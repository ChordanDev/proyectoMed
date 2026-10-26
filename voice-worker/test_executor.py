# pyright: reportMissingImports=false
import unittest

from livekit.agents import JobExecutorType

import worker
from worker import configure_server, job_executor_from_env


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


class ConfigureServerTest(unittest.TestCase):
    def tearDown(self):
        worker.server.update_options(job_executor_type=JobExecutorType.PROCESS)

    def test_default_server_runs_each_job_in_a_process(self):
        server = configure_server({})
        self.assertIs(server, worker.server)
        self.assertIs(server._job_executor_type, JobExecutorType.PROCESS)

    def test_thread_executor_from_the_environment(self):
        server = configure_server({"VOICE_WORKER_EXECUTOR": "thread"})
        self.assertIs(server._job_executor_type, JobExecutorType.THREAD)


if __name__ == "__main__":
    unittest.main()
