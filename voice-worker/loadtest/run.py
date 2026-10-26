"""Voice worker load test (#401): N simulated learners against one local worker.

Starts the local stack (`loadtest.stack`), then for each N in `--steps` runs N
learners (`loadtest.learner`) split into shard processes, samples the worker,
Phoenix and LiveKit process trees once a second, and writes `results.json` and
`table.md` to `--out`. Stops at the first step that fails badly (most turns failed)
or when the machine runs low on memory, then stops everything it started.

Run it with `scripts/load/run-worker-load-test.sh` (see docs/research/voice-worker-capacity.md).
"""

import argparse
import asyncio
import json
import multiprocessing
import platform
import queue
import tempfile
import time
from dataclasses import asdict
from pathlib import Path

import psutil

from loadtest.learner import Script, run_learners, session_offsets
from loadtest.metrics import (
    ProcessTreeSampler,
    degradation_point,
    render_table,
    summarize_samples,
    summarize_step,
)
from loadtest.stack import LIVEKIT_KEY, LIVEKIT_SECRET, Ports, Stack, phoenix_url

ABORT_ERROR_RATE = 0.5


def parse_steps(text: str) -> list[int]:
    try:
        steps = [int(part) for part in text.split(",")]
    except ValueError:
        raise ValueError(f"steps must be comma-separated integers: {text!r}") from None
    if not steps or steps[0] < 1 or steps != sorted(set(steps)):
        raise ValueError(f"steps must be positive and increasing: {text!r}")
    return steps


def steady_window(turns) -> tuple[float, float] | None:
    """From the last session's first turn to the first session's last turn, or None."""
    first: dict[int, float] = {}
    last: dict[int, float] = {}
    for turn in turns:
        s = turn["session"]
        first[s] = min(first.get(s, turn["started_at"]), turn["started_at"])
        last[s] = max(last.get(s, turn["ended_at"]), turn["ended_at"])
    if not first:
        return None
    start, end = max(first.values()), min(last.values())
    return (start, end) if start < end else None


def _shard(indexes, offsets, phoenix, script, results) -> None:
    results.put(
        json.dumps(asyncio.run(run_learners(indexes, offsets, phoenix, script)))
    )


async def _delete_rooms(ports: Ports) -> int:
    from livekit import api

    lk = api.LiveKitAPI(
        f"http://127.0.0.1:{ports.livekit}", LIVEKIT_KEY, LIVEKIT_SECRET
    )
    try:
        rooms = (await lk.room.list_rooms(api.ListRoomsRequest())).rooms
        for room in rooms:
            await lk.room.delete_room(api.DeleteRoomRequest(room=room.name))
        return len(rooms)
    finally:
        await lk.aclose()


def run_step(n: int, stack: Stack, args, script: Script, idle: dict) -> dict:
    ctx = multiprocessing.get_context("spawn")
    results = ctx.Queue()
    offsets = session_offsets(n, n * args.ramp_per_session)
    shards = []
    for start in range(0, n, args.sessions_per_shard):
        idx = list(range(start, min(n, start + args.sessions_per_shard)))
        proc = ctx.Process(
            target=_shard,
            args=(
                idx,
                [offsets[i] for i in idx],
                phoenix_url(stack.ports),
                script,
                results,
            ),
            daemon=True,
        )
        proc.start()
        shards.append(proc)
    samplers = {
        name: ProcessTreeSampler(stack.procs[name].pid)
        for name in ("worker", "phoenix", "livekit")
    }
    samples: dict[str, list] = {name: [] for name in samplers}
    learners: list[dict] = []
    aborted = None
    min_available = psutil.virtual_memory().available
    reported = 0
    while reported < len(shards) and aborted is None:
        now = time.time()
        for name, sampler in samplers.items():
            samples[name].append({"at": now, **sampler.sample()})
        min_available = min(min_available, psutil.virtual_memory().available)
        if min_available < args.memory_guard_mb * 2**20:
            aborted = f"available memory under {args.memory_guard_mb} MB"
        try:
            learners += json.loads(results.get(timeout=1.0))
            reported += 1
        except queue.Empty:
            if not any(proc.is_alive() for proc in shards):
                try:  # a shard's last results may still be in the pipe
                    learners += json.loads(results.get(timeout=5))
                    reported += 1
                except queue.Empty:
                    aborted = "a load shard exited without results"
    for proc in shards:
        if aborted:
            proc.kill()
        proc.join(timeout=60)
    turns = [t for lr in learners for t in lr["turns"]]
    window = steady_window(turns)

    def steady(rows):
        inside = [r for r in rows if window and window[0] <= r["at"] <= window[1]]
        return inside or rows

    step = summarize_step(
        n,
        turns,
        sessions_started=n,
        sessions_failed=n - sum(1 for lr in learners if not lr["failed"]),
        worker=steady(samples["worker"]),
        phoenix=steady(samples["phoenix"]),
    )
    # Peaks come from the whole step, ramp included; averages from the steady window.
    for name in ("worker", "phoenix"):
        step[name]["rss_peak_mb"] = summarize_samples(samples[name])["rss_peak_mb"]
        step[name]["processes_peak"] = summarize_samples(samples[name])[
            "processes_peak"
        ]
    # Memory each session adds over the idle worker (main process, no jobs).
    step["worker_rss_per_session_mb"] = (
        (step["worker"]["rss_peak_mb"] or 0) - idle["rss_mb"]
    ) / n
    step["livekit"] = summarize_samples(steady(samples["livekit"]))
    step["steady_window_s"] = window[1] - window[0] if window else None
    step["min_available_mb"] = min_available / 2**20
    step["session_failures"] = sorted({lr["failed"] for lr in learners if lr["failed"]})
    step["aborted"] = aborted
    return step


def drain(stack: Stack, baseline: int, seconds: float = 120) -> None:
    asyncio.run(_delete_rooms(stack.ports))
    sampler = ProcessTreeSampler(stack.procs["worker"].pid)
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline and sampler.sample()["processes"] > baseline:
        time.sleep(2)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--steps", default="10,25,50,100,200", type=parse_steps)
    parser.add_argument("--turns", type=int, default=Script.turns)
    parser.add_argument("--turn-interval", type=float, default=Script.turn_interval_s)
    parser.add_argument("--ramp-per-session", type=float, default=0.25)
    parser.add_argument("--sessions-per-shard", type=int, default=25)
    parser.add_argument("--memory-guard-mb", type=int, default=1024)
    parser.add_argument("--p95-limit-ms", type=float, default=1500)
    parser.add_argument("--error-limit", type=float, default=0.01)
    parser.add_argument("--database", default="backend_load401")
    parser.add_argument("--out", type=Path, default=None)
    args = parser.parse_args(argv)
    script = Script(turns=args.turns, turn_interval_s=args.turn_interval)
    out = args.out or Path(tempfile.mkdtemp(prefix="voice-load-"))
    out.mkdir(parents=True, exist_ok=True)
    stack = Stack(Ports(), args.database, out)
    steps: list[dict] = []
    idle: dict = {}
    try:
        stack.start()
        time.sleep(3)
        idle = ProcessTreeSampler(stack.procs["worker"].pid).sample()
        baseline = idle["processes"]
        for n in args.steps:
            print(f"load test: N={n} ({script.turns} turns each)", flush=True)
            step = run_step(n, stack, args, script, idle)
            steps.append(step)
            print(render_table([step]).splitlines()[-1], flush=True)
            _write(out, args, script, steps, idle)
            drain(stack, baseline)
            if step["aborted"] or step["error_rate"] > ABORT_ERROR_RATE:
                print(f"load test: stopping after N={n}", flush=True)
                break
    finally:
        stack.stop()
    _write(out, args, script, steps, idle)
    print(f"load test: results in {out}", flush=True)
    return 0 if steps else 1


def _write(out: Path, args, script: Script, steps, idle) -> None:
    result = {
        "machine": {
            "platform": platform.platform(),
            "processor": platform.processor(),
            "cpus": psutil.cpu_count(),
            "memory_mb": psutil.virtual_memory().total / 2**20,
        },
        "script": asdict(script),
        "worker_idle": idle,
        "ramp_per_session_s": args.ramp_per_session,
        "degradation": degradation_point(steps, args.p95_limit_ms, args.error_limit),
        "limits": {"p95_ms": args.p95_limit_ms, "error_rate": args.error_limit},
        "steps": steps,
    }
    (out / "results.json").write_text(json.dumps(result, indent=2))
    (out / "table.md").write_text(render_table(steps) + "\n")


if __name__ == "__main__":
    raise SystemExit(main())
