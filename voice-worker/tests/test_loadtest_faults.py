import asyncio
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from livekit.agents import JobExecutorType

from loadtest import faults, worker_entry
from loadtest.faults import Fault, claim, fault_from_env, fault_impact
from loadtest.run import build_parser, fault_env

FAKE_ENV = {
    "VOICE_WORKER_FAKE_PROVIDERS": "true",
    "LIVEKIT_URL": "ws://127.0.0.1:7990",
}


class FaultFromEnvTest(unittest.TestCase):
    def test_no_fault_by_default(self):
        self.assertIsNone(fault_from_env({}))
        self.assertIsNone(fault_from_env({"LOADTEST_FAULT": " "}))

    def test_crash_and_hang(self):
        for kind in ("crash", "hang"):
            env = {
                "LOADTEST_FAULT": kind,
                "LOADTEST_FAULT_AFTER_S": "30",
                "LOADTEST_FAULT_MARKER": "/tmp/x/fault.json",
            }
            self.assertEqual(
                fault_from_env(env), Fault(kind, 30.0, Path("/tmp/x/fault.json"))
            )

    def test_after_defaults_to_a_minute(self):
        env = {"LOADTEST_FAULT": "crash", "LOADTEST_FAULT_MARKER": "/m"}
        self.assertEqual(fault_from_env(env).after_s, 60.0)

    def test_refuses_bad_settings(self):
        bad = (
            {"LOADTEST_FAULT": "explode", "LOADTEST_FAULT_MARKER": "/m"},
            {"LOADTEST_FAULT": "crash"},
            {
                "LOADTEST_FAULT": "hang",
                "LOADTEST_FAULT_MARKER": "/m",
                "LOADTEST_FAULT_AFTER_S": "-1",
            },
            {
                "LOADTEST_FAULT": "hang",
                "LOADTEST_FAULT_MARKER": "/m",
                "LOADTEST_FAULT_AFTER_S": "soon",
            },
        )
        for env in bad:
            with self.assertRaises(ValueError, msg=env):
                fault_from_env(env)


class ClaimTest(unittest.TestCase):
    def test_only_the_first_job_claims_the_fault(self):
        with tempfile.TemporaryDirectory() as tmp:
            marker = Path(tmp) / "fault.json"
            self.assertTrue(claim(marker, "station-session-a", at=100.0))
            self.assertFalse(claim(marker, "station-session-b", at=101.0))
            self.assertEqual(
                json.loads(marker.read_text()),
                {"room": "station-session-a", "at": 100.0},
            )


class EntrypointTest(unittest.IsolatedAsyncioTestCase):
    async def test_the_claiming_job_triggers_the_fault_then_runs_the_session(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = {
                "LOADTEST_FAULT": "hang",
                "LOADTEST_FAULT_AFTER_S": "0",
                "LOADTEST_FAULT_MARKER": str(Path(tmp) / "fault.json"),
            }
            triggered = []
            sessions = []

            async def session(ctx):
                sessions.append(ctx.room.name)
                await asyncio.sleep(0.05)

            with (
                patch.dict("os.environ", env),
                patch.object(faults.worker, "entrypoint", session),
                patch.object(faults, "trigger", triggered.append),
            ):
                await faults.entrypoint(SimpleNamespace(room=SimpleNamespace(name="a")))
                await faults.entrypoint(SimpleNamespace(room=SimpleNamespace(name="b")))
            self.assertEqual(sessions, ["a", "b"])
            self.assertEqual(triggered, ["hang"])


class FaultImpactTest(unittest.TestCase):
    def learner(self, index, session_id, outcomes, start=0.0):
        return {
            "index": index,
            "session_id": session_id,
            "failed": None,
            "turns": [
                {
                    "session": index,
                    "outcome": outcome,
                    "started_at": start + 10 * i,
                    "ended_at": start + 10 * i + 5,
                }
                for i, outcome in enumerate(outcomes)
            ],
        }

    def test_counts_other_sessions_failing_after_the_fault(self):
        learners = [
            self.learner(0, "s0", ["ok", "no_audio", "no_audio"]),  # the faulty one
            self.learner(1, "s1", ["ok", "ok", "no_audio"]),  # fails after the fault
            self.learner(2, "s2", ["no_audio", "ok", "ok"]),  # failed before it only
            self.learner(3, "s3", ["ok", "ok", "ok"]),
        ]
        marker = {"room": "station-session-s0", "at": 12.0}
        self.assertEqual(
            fault_impact("crash", marker, learners),
            {
                "kind": "crash",
                "session_id": "s0",
                "at": 12.0,
                "faulty_session_found": True,
                "faulty_session_turns_failed_after": 2,
                "other_sessions": 3,
                "other_sessions_affected": 1,
                "other_turns_failed_after": 1,
            },
        )

    def test_no_marker_means_the_fault_never_fired(self):
        learners = [self.learner(0, "s0", ["ok"])]
        self.assertEqual(
            fault_impact("hang", None, learners),
            {"kind": "hang", "session_id": None, "faulty_session_found": False},
        )


class FaultOptionsTest(unittest.TestCase):
    def test_no_fault_by_default(self):
        args = build_parser().parse_args([])
        self.assertIsNone(args.fault)
        self.assertEqual(fault_env(args, Path("/out")), {})

    def test_fault_environment_for_the_workers(self):
        args = build_parser().parse_args(["--fault", "crash", "--fault-after-s", "45"])
        self.assertEqual(
            fault_env(args, Path("/out")),
            {
                "LOADTEST_FAULT": "crash",
                "LOADTEST_FAULT_AFTER_S": "45.0",
                "LOADTEST_FAULT_MARKER": "/out/fault.json",
            },
        )


class ConfigureFaultTest(unittest.TestCase):
    def tearDown(self):
        server = worker_entry.worker.server
        server._entrypoint_fnc = worker_entry.worker.entrypoint
        server.update_options(job_executor_type=JobExecutorType.PROCESS)

    def test_no_fault_keeps_the_worker_entrypoint(self):
        server = worker_entry.configure(FAKE_ENV)
        self.assertIs(server._entrypoint_fnc, worker_entry.worker.entrypoint)

    def test_a_fault_wraps_the_entrypoint(self):
        env = {**FAKE_ENV, "LOADTEST_FAULT": "crash", "LOADTEST_FAULT_MARKER": "/m"}
        server = worker_entry.configure(env)
        self.assertIs(server._entrypoint_fnc, faults.entrypoint)

    def test_refuses_a_bad_fault(self):
        with self.assertRaisesRegex(SystemExit, "LOADTEST_FAULT"):
            worker_entry.configure({**FAKE_ENV, "LOADTEST_FAULT": "explode"})


if __name__ == "__main__":
    unittest.main()
