import array
import unittest

from loadtest.learner import is_audible, session_offsets
from loadtest.run import max_gap, parse_steps, steady_window, summarize_process
from loadtest.stack import (
    LOOPBACK,
    Ports,
    clean_env,
    livekit_config_body,
    phoenix_env,
    require_loopback,
    worker_env,
)

USER_ENV = {
    "PATH": "/usr/bin",
    "HOME": "/Users/someone",
    "LANG": "en_US.UTF-8",
    "LC_ALL": "en_US.UTF-8",
    "MIX_HOME": "/Users/someone/.mix",
    "HEX_HOME": "/Users/someone/.hex",
    "DEEPGRAM_API_KEY": "real-deepgram",
    "CARTESIA_API_KEY": "real-cartesia",
    "CARTESIA_VOICE_IDS": "patient=abc",
    "ANTHROPIC_API_KEY": "real-anthropic",
    "OPENAI_API_KEY": "real-openai",
    "OPENAI_BASE_URL": "https://api.openai.com/v1",
    "LLM_PROVIDER": "anthropic",
    "JEV_ADAPTER": "typesafe",
    "DATABASE_URL": "ecto://prod@neon.example/db",
    "LIVEKIT_URL": "wss://cloud.livekit.example",
    "VOICE_PROVIDER": "openai",
}
PORTS = Ports()
PAID = {
    "DEEPGRAM_API_KEY",
    "CARTESIA_API_KEY",
    "CARTESIA_VOICE_IDS",
    "ANTHROPIC_API_KEY",
    "LLM_PROVIDER",
    "JEV_ADAPTER",
    "VOICE_PROVIDER",
}


class CleanEnvTest(unittest.TestCase):
    def test_keeps_only_toolchain_variables(self):
        self.assertEqual(
            clean_env(USER_ENV),
            {
                "PATH": "/usr/bin",
                "HOME": "/Users/someone",
                "LANG": "en_US.UTF-8",
                "LC_ALL": "en_US.UTF-8",
                "MIX_HOME": "/Users/someone/.mix",
                "HEX_HOME": "/Users/someone/.hex",
            },
        )


class PortsTest(unittest.TestCase):
    def test_defaults_avoid_the_developer_ports(self):
        used = {
            PORTS.livekit,
            PORTS.livekit_tcp,
            PORTS.livekit_udp,
            PORTS.phoenix,
            PORTS.mock_llm,
        }
        self.assertEqual(PORTS.phoenix, 4159)
        self.assertFalse(used & {4000, 4001, 5173, 7880, 7881, 7882})
        self.assertEqual(len(used), 5)

    def test_livekit_config_uses_the_ports(self):
        body = livekit_config_body(PORTS)
        self.assertIn("port: 7990", body)
        self.assertIn("tcp_port: 7991", body)
        self.assertIn("udp_port: 7992", body)


class PhoenixEnvTest(unittest.TestCase):
    def setUp(self):
        self.env = phoenix_env(USER_ENV, PORTS, "secret-1", "backend_load401")

    def test_points_every_provider_at_local_fakes(self):
        self.assertEqual(self.env["OPENAI_BASE_URL"], "http://127.0.0.1:18866")
        self.assertEqual(self.env["LIVEKIT_URL"], "ws://127.0.0.1:7990")
        self.assertEqual(self.env["JEV_E2E_APPROVING_ADAPTER"], "true")
        self.assertEqual(self.env["VOICE_MODE"], "realtime")
        self.assertEqual(self.env["PORT"], "4159")
        self.assertEqual(self.env["MIX_ENV"], "dev")
        self.assertEqual(self.env["VOICE_WORKER_SECRET"], "secret-1")
        self.assertEqual(self.env["DATABASE_URL"], "ecto://localhost/backend_load401")
        self.assertFalse(PAID & self.env.keys())
        self.assertNotEqual(self.env["OPENAI_API_KEY"], "real-openai")


class WorkerEnvTest(unittest.TestCase):
    def test_fake_providers_on_and_no_provider_key(self):
        env = worker_env(USER_ENV, PORTS, "secret-1")
        self.assertEqual(env["VOICE_WORKER_FAKE_PROVIDERS"], "true")
        self.assertEqual(env["LIVEKIT_URL"], "ws://127.0.0.1:7990")
        self.assertEqual(env["PHOENIX_URL"], "http://127.0.0.1:4159")
        self.assertEqual(env["VOICE_WORKER_SECRET"], "secret-1")
        self.assertFalse(PAID & env.keys())
        self.assertNotIn("OPENAI_API_KEY", env)


class RequireLoopbackTest(unittest.TestCase):
    def test_accepts_loopback(self):
        for url in ("http://127.0.0.1:4159", "ws://localhost:7990", "http://[::1]:1"):
            self.assertEqual(require_loopback(url), url)

    def test_refuses_anything_else(self):
        for url in (
            "wss://cloud.livekit.example",
            "http://127.0.0.1.example.com",
            "http://user@127.0.0.1",
            "",
        ):
            with self.assertRaises(ValueError, msg=url):
                require_loopback(url)

    def test_loopback_set(self):
        self.assertEqual(LOOPBACK, {"127.0.0.1", "localhost", "::1"})


class LearnerTest(unittest.TestCase):
    def test_silence_and_tone(self):
        self.assertFalse(is_audible(array.array("h", [0] * 480)))
        self.assertFalse(is_audible(array.array("h", [40, -40] * 240)))
        self.assertTrue(is_audible(array.array("h", [3000, -3000] * 240)))
        self.assertFalse(is_audible(array.array("h")))

    def test_sessions_start_evenly_over_the_ramp(self):
        self.assertEqual(session_offsets(4, 2.0), [0.0, 0.5, 1.0, 1.5])
        self.assertEqual(session_offsets(1, 10.0), [0.0])
        self.assertEqual(session_offsets(0, 10.0), [])


class RunTest(unittest.TestCase):
    def test_parse_steps(self):
        self.assertEqual(parse_steps("10,25, 50"), [10, 25, 50])
        for bad in ("", "10,x", "0", "25,10"):
            with self.assertRaises(ValueError, msg=bad):
                parse_steps(bad)

    def test_steady_window_is_when_every_session_is_talking(self):
        turns = [
            {"session": 0, "started_at": 10.0, "ended_at": 15.0},
            {"session": 0, "started_at": 20.0, "ended_at": 90.0},
            {"session": 1, "started_at": 30.0, "ended_at": 35.0},
            {"session": 1, "started_at": 40.0, "ended_at": 120.0},
        ]
        self.assertEqual(steady_window(turns), (30.0, 90.0))

    def test_steady_window_ignores_sessions_that_failed_before_a_turn(self):
        turns = [
            {"session": 0, "outcome": "ok", "started_at": 10.0, "ended_at": 20.0},
            {"session": 0, "outcome": "ok", "started_at": 20.0, "ended_at": 30.0},
            {
                "session": 1,
                "outcome": "session_worker_not_joined",
                "started_at": 25.0,
                "ended_at": 25.0,
            },
        ]
        self.assertEqual(steady_window(turns), (10.0, 30.0))

    def test_max_gap_flags_a_stalled_machine(self):
        self.assertEqual(max_gap([1.0, 2.0, 3.1, 20.1, 21.0]), 17.0)
        self.assertEqual(max_gap([5.0]), 0.0)
        self.assertEqual(max_gap([]), 0.0)

    def test_no_overlap_has_no_window(self):
        turns = [
            {"session": 0, "started_at": 10.0, "ended_at": 15.0},
            {"session": 1, "started_at": 30.0, "ended_at": 35.0},
        ]
        self.assertIsNone(steady_window(turns))
        self.assertIsNone(steady_window([]))

    def test_peaks_from_the_whole_step_average_from_the_window(self):
        def row(at, cpu, rss, processes):
            return {"at": at, "cpu_percent": cpu, "rss_mb": rss, "processes": processes}

        rows = [
            row(1.0, 400.0, 3000.0, 12),  # ramp spike, before the window
            row(31.0, 100.0, 2500.0, 20),
            row(60.0, 200.0, 2600.0, 21),
            row(100.0, 50.0, 2000.0, 11),  # drain, after the window
        ]
        summary = summarize_process(rows, (30.0, 90.0))
        self.assertEqual(summary["cpu_avg_percent"], 150.0)
        self.assertEqual(summary["cpu_peak_percent"], 400.0)
        self.assertEqual(summary["rss_peak_mb"], 3000.0)
        self.assertEqual(summary["processes_peak"], 21)

    def test_no_window_averages_the_whole_step(self):
        rows = [
            {"at": 1.0, "cpu_percent": 100.0, "rss_mb": 1.0, "processes": 1},
            {"at": 2.0, "cpu_percent": 300.0, "rss_mb": 2.0, "processes": 2},
        ]
        summary = summarize_process(rows, None)
        self.assertEqual(summary["cpu_avg_percent"], 200.0)
        self.assertEqual(summary["cpu_peak_percent"], 300.0)


if __name__ == "__main__":
    unittest.main()
