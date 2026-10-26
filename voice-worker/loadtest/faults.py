"""Fault injection for the load test (#405): one session crashes or hangs.

With `LOADTEST_FAULT` set, the first job of the run to claim `LOADTEST_FAULT_MARKER`
(an exclusive file create, so one job across every worker process) runs its session
normally and, `LOADTEST_FAULT_AFTER_S` seconds in, either

- `crash`: ends its process at once with `os._exit`, as a native crash (a segfault in
  a C extension) or an out-of-memory kill would; or
- `hang`: blocks its event loop in a busy loop that never returns, as a stuck
  synchronous call or an endless loop would.

The marker records the room and the time the fault fires, so the runner can tell the
faulty session from the others (`fault_impact`). Only the load test worker
(`loadtest.worker_entry`) installs this entrypoint; the production worker never does.
"""

import asyncio
import dataclasses
import json
import math
import os
import time
from pathlib import Path

import worker

KINDS = ("crash", "hang")
DEFAULT_AFTER_S = 60.0
CRASH_EXIT = 70


@dataclasses.dataclass(frozen=True)
class Fault:
    kind: str
    after_s: float
    marker: Path


def fault_from_env(environ) -> Fault | None:
    kind = environ.get("LOADTEST_FAULT", "").strip()
    if not kind:
        return None
    if kind not in KINDS:
        raise ValueError(f"LOADTEST_FAULT must be crash or hang, got {kind!r}")
    marker = environ.get("LOADTEST_FAULT_MARKER", "").strip()
    if not marker:
        raise ValueError("LOADTEST_FAULT needs LOADTEST_FAULT_MARKER")
    raw = environ.get("LOADTEST_FAULT_AFTER_S", "").strip()
    try:
        after = float(raw) if raw else DEFAULT_AFTER_S
    except ValueError:
        after = math.nan
    if not math.isfinite(after) or after < 0:
        raise ValueError(f"LOADTEST_FAULT_AFTER_S must be seconds >= 0, got {raw!r}")
    return Fault(kind, after, Path(marker))


def claim(marker: Path, room: str, at: float) -> bool:
    """Whether this job is the one that faults: only the first to create the marker."""
    try:
        fd = os.open(marker, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        return False
    with os.fdopen(fd, "w") as file:
        json.dump({"room": room, "at": at}, file)
    return True


def trigger(kind: str) -> None:
    if kind == "crash":
        os._exit(CRASH_EXIT)
    while True:  # hang: never yields to the event loop again
        pass


async def entrypoint(ctx) -> None:
    fault = fault_from_env(os.environ)
    if fault is not None and claim(
        fault.marker, ctx.room.name, time.time() + fault.after_s
    ):
        asyncio.get_running_loop().call_later(fault.after_s, trigger, fault.kind)
    await worker.entrypoint(ctx)


def fault_impact(kind: str, marker: dict | None, learners) -> dict:
    """How many sessions other than the faulty one failed a turn after the fault."""
    if marker is None:
        return {"kind": kind, "session_id": None, "faulty_session_found": False}
    session_id = marker["room"].removeprefix(worker.ROOM_PREFIX)
    at = marker["at"]

    def failed_after(learner) -> int:
        return sum(
            1
            for turn in learner["turns"]
            if turn["outcome"] != "ok" and turn["ended_at"] >= at
        )

    faulty = [lr for lr in learners if lr.get("session_id") == session_id]
    others = [lr for lr in learners if lr.get("session_id") != session_id]
    return {
        "kind": kind,
        "session_id": session_id,
        "at": at,
        "faulty_session_found": bool(faulty),
        "faulty_session_turns_failed_after": sum(map(failed_after, faulty)),
        "other_sessions": len(others),
        "other_sessions_affected": sum(1 for lr in others if failed_after(lr)),
        "other_turns_failed_after": sum(map(failed_after, others)),
    }
