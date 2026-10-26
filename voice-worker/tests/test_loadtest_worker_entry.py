import unittest

from livekit.agents import JobExecutorType

from loadtest import worker_entry
from loadtest.worker_entry import WARM_PROCESSES, configure

FAKE_ENV = {
    "VOICE_WORKER_FAKE_PROVIDERS": "true",
    "LIVEKIT_URL": "ws://127.0.0.1:7990",
}


class ConfigureTest(unittest.TestCase):
    def setUp(self):
        self.threshold = worker_entry.worker.server._load_threshold

    def tearDown(self):
        worker_entry.worker.server.update_options(
            job_executor_type=JobExecutorType.PROCESS,
            load_threshold=self.threshold,
        )

    def test_runs_each_job_in_a_process_by_default(self):
        server = configure(FAKE_ENV)
        self.assertIs(server._job_executor_type, JobExecutorType.PROCESS)

    def test_takes_the_executor_from_the_environment(self):
        server = configure({**FAKE_ENV, "VOICE_WORKER_EXECUTOR": "thread"})
        self.assertIs(server._job_executor_type, JobExecutorType.THREAD)

    def test_no_job_cap_by_default(self):
        threshold = worker_entry.worker.server._load_threshold
        server = configure(FAKE_ENV)
        self.assertIsInstance(server.load_fnc, worker_entry.OwnTreeLoad)
        self.assertIs(server._load_threshold, threshold)

    def test_a_job_cap_wraps_its_own_load_and_refuses_jobs_at_the_cap(self):
        server = configure({**FAKE_ENV, "VOICE_WORKER_JOBS_PER_PROCESS": "6"})
        self.assertIsInstance(server.load_fnc, worker_entry.worker.JobCapLoad)
        self.assertIsInstance(server.load_fnc.base, worker_entry.OwnTreeLoad)
        self.assertEqual(server.load_fnc.cap, 6)
        self.assertEqual(server._load_threshold, 1.0)

    def test_refuses_an_unknown_executor(self):
        with self.assertRaisesRegex(SystemExit, "VOICE_WORKER_EXECUTOR"):
            configure({**FAKE_ENV, "VOICE_WORKER_EXECUTOR": "hybrid"})

    def test_keeps_the_production_number_of_warm_processes(self):
        server = configure(FAKE_ENV)
        self.assertIs(server, worker_entry.worker.server)
        self.assertEqual(WARM_PROCESSES, 8)
        self.assertEqual(server._num_idle_processes, WARM_PROCESSES)

    def test_reports_the_load_of_its_own_processes_only(self):
        server = configure(FAKE_ENV)
        self.assertIsInstance(server.load_fnc, worker_entry.OwnTreeLoad)
        load = server.load_fnc()
        self.assertGreaterEqual(load, 0.0)
        self.assertLessEqual(load, 1.0)

    def test_own_tree_load_is_a_share_of_the_machine(self):
        load = worker_entry.OwnTreeLoad(cpus=4)
        load._sampler.sample = lambda: {
            "cpu_percent": 200.0,
            "rss_mb": 1,
            "processes": 3,
        }
        self.assertEqual(load(), 0.5)
        load._sampler.sample = lambda: {
            "cpu_percent": 900.0,
            "rss_mb": 1,
            "processes": 3,
        }
        self.assertEqual(load(), 1.0)

    def test_refuses_to_run_without_fake_providers(self):
        with self.assertRaisesRegex(SystemExit, "fake speech providers"):
            configure({"LIVEKIT_URL": "ws://127.0.0.1:7990"})

    def test_refuses_fake_providers_on_a_remote_livekit(self):
        env = {**FAKE_ENV, "LIVEKIT_URL": "wss://cloud.livekit.example"}
        with self.assertRaisesRegex(SystemExit, "loopback"):
            configure(env)


if __name__ == "__main__":
    unittest.main()
