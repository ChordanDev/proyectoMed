# pyright: reportMissingImports=false
import unittest
from types import SimpleNamespace

from livekit.agents import JobExecutorType

import worker
from worker import (
    JobCapLoad,
    configure_server,
    job_executor_from_env,
    jobs_per_process_from_env,
)


class JobExecutorFromEnvTest(unittest.TestCase):
    def test_process_per_job_by_default(self):
        self.assertIs(job_executor_from_env({}), JobExecutorType.PROCESS)
        self.assertIs(
            job_executor_from_env({"VOICE_WORKER_EXECUTOR": "  "}),
            JobExecutorType.PROCESS,
        )

    def test_process_and_thread(self):
        self.assertIs(
            job_executor_from_env({"VOICE_WORKER_EXECUTOR": "process"}),
            JobExecutorType.PROCESS,
        )
        self.assertIs(
            job_executor_from_env({"VOICE_WORKER_EXECUTOR": " Thread "}),
            JobExecutorType.THREAD,
        )

    def test_refuses_anything_else(self):
        for value in ("threads", "hybrid", "1"):
            with self.assertRaisesRegex(
                ValueError, "VOICE_WORKER_EXECUTOR must be process or thread", msg=value
            ):
                job_executor_from_env({"VOICE_WORKER_EXECUTOR": value})


class JobsPerProcessFromEnvTest(unittest.TestCase):
    def test_no_cap_by_default(self):
        self.assertIsNone(jobs_per_process_from_env({}))
        self.assertIsNone(
            jobs_per_process_from_env({"VOICE_WORKER_JOBS_PER_PROCESS": " "})
        )

    def test_a_positive_cap(self):
        self.assertEqual(
            jobs_per_process_from_env({"VOICE_WORKER_JOBS_PER_PROCESS": " 12 "}), 12
        )

    def test_refuses_anything_else(self):
        for value in ("0", "-3", "ten", "1.5", "²"):
            with self.assertRaisesRegex(
                ValueError,
                "VOICE_WORKER_JOBS_PER_PROCESS must be a positive integer",
                msg=value,
            ):
                jobs_per_process_from_env({"VOICE_WORKER_JOBS_PER_PROCESS": value})


def running(jobs: int):
    return SimpleNamespace(active_jobs=[object()] * jobs)


class JobCapLoadTest(unittest.TestCase):
    def test_base_load_below_the_cap(self):
        load = JobCapLoad(3, lambda server: 0.25)
        self.assertEqual(load(running(0)), 0.25)
        self.assertEqual(load(running(2)), 0.25)

    def test_full_at_the_cap(self):
        load = JobCapLoad(3, lambda server: 0.25)
        self.assertEqual(load(running(3)), 1.0)
        self.assertEqual(load(running(4)), 1.0)

    def test_base_load_without_the_server_argument(self):
        load = JobCapLoad(2, lambda: 0.5)
        self.assertEqual(load(running(1)), 0.5)


class ConfigureServerTest(unittest.TestCase):
    def setUp(self):
        self.load_fnc = worker.server.load_fnc

    def tearDown(self):
        worker.server.update_options(job_executor_type=JobExecutorType.PROCESS)
        worker.server.load_fnc = self.load_fnc

    def test_default_server_keeps_the_livekit_load(self):
        server = configure_server({})
        self.assertIs(server.load_fnc, self.load_fnc)

    def test_a_cap_wraps_the_livekit_cpu_load(self):
        server = configure_server({"VOICE_WORKER_JOBS_PER_PROCESS": "8"})
        self.assertIsInstance(server.load_fnc, JobCapLoad)
        self.assertEqual(server.load_fnc.cap, 8)

    def test_a_cap_wraps_a_given_base_load(self):
        def base():
            return 0.1

        server = configure_server({"VOICE_WORKER_JOBS_PER_PROCESS": "2"}, base)
        self.assertIs(server.load_fnc.base, base)

    def test_a_base_load_without_a_cap(self):
        def base():
            return 0.1

        server = configure_server({}, base)
        self.assertIs(server.load_fnc, base)

    def test_default_server_runs_each_job_in_a_process(self):
        server = configure_server({})
        self.assertIs(server, worker.server)
        self.assertIs(server._job_executor_type, JobExecutorType.PROCESS)

    def test_thread_executor_from_the_environment(self):
        server = configure_server({"VOICE_WORKER_EXECUTOR": "thread"})
        self.assertIs(server._job_executor_type, JobExecutorType.THREAD)


if __name__ == "__main__":
    unittest.main()
