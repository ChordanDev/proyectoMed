"""Measurements of the voice worker load test (#401).

Turn records come from the simulated learners: one dict per spoken turn with its
`outcome` (`ok`, or the failure kind) and `latency_ms`, the time from the end of the
learner's speech to the first audible frame of the patient's reply. Process samples
come from `ProcessTreeSampler`: CPU (percent of one core) and resident memory of a
process and all its children, which for the worker includes one process per job.
"""

import math

import psutil


def percentile(values, p: float) -> float | None:
    """The p-th percentile with linear interpolation between ranks, None when empty."""
    if not values:
        return None
    ordered = sorted(values)
    rank = (len(ordered) - 1) * p / 100
    low, high = math.floor(rank), math.ceil(rank)
    return ordered[low] + (ordered[high] - ordered[low]) * (rank - low)


def summarize_samples(samples) -> dict:
    cpu = [s["cpu_percent"] for s in samples]
    return {
        "cpu_avg_percent": sum(cpu) / len(cpu) if cpu else None,
        "cpu_peak_percent": max(cpu) if cpu else None,
        "rss_peak_mb": max(s["rss_mb"] for s in samples) if samples else None,
        "processes_peak": max((s["processes"] for s in samples), default=0),
    }


def summarize_step(
    n: int, turns, sessions_started: int, sessions_failed: int, *, worker, phoenix
) -> dict:
    """One row of the report: the turns and process samples of N concurrent sessions."""
    latencies = [t["latency_ms"] for t in turns if t["outcome"] == "ok"]
    failures: dict[str, int] = {}
    for turn in turns:
        if turn["outcome"] != "ok":
            failures[turn["outcome"]] = failures.get(turn["outcome"], 0) + 1
    failed = sum(failures.values())
    worker_summary = summarize_samples(worker)
    return {
        "n": n,
        "sessions_started": sessions_started,
        "sessions_failed": sessions_failed,
        "turns_total": len(turns),
        "turns_ok": len(latencies),
        "turns_failed": failed,
        "failures": failures,
        "error_rate": failed / len(turns) if turns else 1.0,
        "latency_p50_ms": percentile(latencies, 50),
        "latency_p95_ms": percentile(latencies, 95),
        "latency_p99_ms": percentile(latencies, 99),
        "latency_max_ms": max(latencies) if latencies else None,
        "worker": worker_summary,
        "phoenix": summarize_samples(phoenix),
        "worker_rss_per_session_mb": _per(worker_summary["rss_peak_mb"], n),
        "worker_cpu_per_session_percent": _per(worker_summary["cpu_avg_percent"], n),
    }


def _per(total, n):
    return total / n if total is not None and n else None


def degradation_point(steps, p95_limit_ms: float, error_limit: float) -> dict | None:
    """The first step whose p95 latency or error rate is over its limit, or None."""
    for step in steps:
        p95 = step["latency_p95_ms"]
        if p95 is None or p95 > p95_limit_ms:
            shown = "none" if p95 is None else f"{p95:.0f}"
            return {
                "n": step["n"],
                "reason": f"latency_p95_ms {shown} > {p95_limit_ms:.0f}",
            }
        if step["error_rate"] > error_limit:
            return {
                "n": step["n"],
                "reason": f"error_rate {step['error_rate']:.1%} > {error_limit:.1%}",
            }
    return None


COLUMNS = (
    "N",
    "sessions ok",
    "turns ok",
    "p50 ms",
    "p95 ms",
    "p99 ms",
    "worker CPU avg/peak %",
    "worker RSS peak MB",
    "worker processes",
    "Phoenix CPU avg/peak %",
    "Phoenix RSS peak MB",
)


def _num(value) -> str:
    return "-" if value is None else f"{value:.0f}"


def render_table(steps) -> str:
    """A Markdown table with one row per step."""
    rows = ["| " + " | ".join(COLUMNS) + " |", "|" + "---|" * len(COLUMNS)]
    for s in steps:
        w, p = s["worker"], s["phoenix"]
        cells = (
            str(s["n"]),
            f"{s['sessions_started'] - s['sessions_failed']}/{s['sessions_started']}",
            f"{s['turns_ok']}/{s['turns_total']}",
            _num(s["latency_p50_ms"]),
            _num(s["latency_p95_ms"]),
            _num(s["latency_p99_ms"]),
            f"{_num(w['cpu_avg_percent'])}/{_num(w['cpu_peak_percent'])}",
            _num(w["rss_peak_mb"]),
            str(w["processes_peak"]),
            f"{_num(p['cpu_avg_percent'])}/{_num(p['cpu_peak_percent'])}",
            _num(p["rss_peak_mb"]),
        )
        rows.append("| " + " | ".join(cells) + " |")
    return "\n".join(rows)


class ProcessTreeSampler:
    """CPU and memory of a process and every descendant, sampled on demand.

    CPU is the percent of one core since the previous sample, so 200 means two busy
    cores. The first sample of each process reads 0, as `psutil` measures CPU between
    calls. A process that is gone, or one this user may not inspect, is skipped.
    """

    def __init__(self, pid: int):
        self._pid = pid
        self._seen: dict[int, psutil.Process] = {}

    def sample(self) -> dict:
        try:
            root = psutil.Process(self._pid)
            tree = [root, *root.children(recursive=True)]
        except psutil.Error:
            return {"cpu_percent": 0.0, "rss_mb": 0.0, "processes": 0}
        cpu = rss = 0.0
        count = 0
        alive: dict[int, psutil.Process] = {}
        for proc in tree:
            known = self._seen.get(proc.pid, proc)
            try:
                with known.oneshot():
                    cpu += known.cpu_percent(None)
                    rss += known.memory_info().rss
            except psutil.Error:
                continue
            alive[proc.pid] = known
            count += 1
        self._seen = alive
        return {"cpu_percent": cpu, "rss_mb": rss / 2**20, "processes": count}
