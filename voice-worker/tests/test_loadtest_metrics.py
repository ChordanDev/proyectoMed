import subprocess
import sys
import unittest

import psutil

from loadtest.metrics import (
    ProcessTreeSampler,
    degradation_point,
    percentile,
    render_table,
    summarize_samples,
    summarize_step,
)


def turns(latencies, failed=0, outcome="no_audio"):
    ok = [{"session": 0, "outcome": "ok", "latency_ms": ms} for ms in latencies]
    return ok + [{"session": 0, "outcome": outcome, "latency_ms": None}] * failed


class PercentileTest(unittest.TestCase):
    def test_interpolates_between_ranks(self):
        values = [10, 20, 30, 40]
        self.assertEqual(percentile(values, 0), 10)
        self.assertEqual(percentile(values, 50), 25)
        self.assertEqual(percentile(values, 100), 40)
        self.assertAlmostEqual(percentile(values, 95), 38.5)

    def test_unordered_input_and_single_value(self):
        self.assertEqual(percentile([30, 10, 20], 50), 20)
        self.assertEqual(percentile([7], 99), 7)

    def test_empty_input_has_no_percentile(self):
        self.assertIsNone(percentile([], 50))


class SummarizeSamplesTest(unittest.TestCase):
    def test_average_and_peak_cpu_and_peak_memory(self):
        samples = [
            {"cpu_percent": 50.0, "rss_mb": 100.0, "processes": 2},
            {"cpu_percent": 150.0, "rss_mb": 300.0, "processes": 4},
        ]
        self.assertEqual(
            summarize_samples(samples),
            {
                "cpu_avg_percent": 100.0,
                "cpu_peak_percent": 150.0,
                "rss_peak_mb": 300.0,
                "processes_peak": 4,
            },
        )

    def test_no_samples(self):
        self.assertEqual(
            summarize_samples([]),
            {
                "cpu_avg_percent": None,
                "cpu_peak_percent": None,
                "rss_peak_mb": None,
                "processes_peak": 0,
            },
        )


class SummarizeStepTest(unittest.TestCase):
    def test_counts_latency_percentiles_and_failures(self):
        step = summarize_step(
            10,
            turns(list(range(100, 1100, 10)), failed=2) + turns([], 1, "no_reply"),
            sessions_started=10,
            sessions_failed=1,
            worker=[{"cpu_percent": 80.0, "rss_mb": 900.0, "processes": 11}],
            phoenix=[{"cpu_percent": 20.0, "rss_mb": 200.0, "processes": 1}],
        )
        self.assertEqual(step["n"], 10)
        self.assertEqual(step["turns_total"], 103)
        self.assertEqual(step["turns_ok"], 100)
        self.assertEqual(step["turns_failed"], 3)
        self.assertEqual(step["failures"], {"no_audio": 2, "no_reply": 1})
        self.assertAlmostEqual(step["error_rate"], 3 / 103)
        self.assertAlmostEqual(step["latency_p50_ms"], 595.0)
        self.assertAlmostEqual(step["latency_p95_ms"], 1040.5)
        self.assertEqual(step["latency_max_ms"], 1090)
        self.assertEqual(step["sessions_started"], 10)
        self.assertEqual(step["sessions_failed"], 1)
        self.assertEqual(step["worker"]["rss_peak_mb"], 900.0)
        self.assertEqual(step["worker_rss_per_session_mb"], 90.0)
        self.assertEqual(step["worker_cpu_per_session_percent"], 8.0)
        self.assertEqual(step["phoenix"]["cpu_avg_percent"], 20.0)

    def test_step_without_turns(self):
        step = summarize_step(5, [], 0, 5, worker=[], phoenix=[])
        self.assertEqual(step["turns_total"], 0)
        self.assertEqual(step["error_rate"], 1.0)
        self.assertIsNone(step["latency_p95_ms"])
        self.assertIsNone(step["worker_rss_per_session_mb"])


class DegradationPointTest(unittest.TestCase):
    def step(self, n, p95, error_rate):
        return {"n": n, "latency_p95_ms": p95, "error_rate": error_rate}

    def test_first_step_over_the_latency_limit(self):
        steps = [self.step(10, 800, 0), self.step(25, 900, 0), self.step(50, 2100, 0)]
        self.assertEqual(
            degradation_point(steps, p95_limit_ms=1500, error_limit=0.01),
            {"n": 50, "reason": "latency_p95_ms 2100 > 1500"},
        )

    def test_first_step_over_the_error_limit(self):
        steps = [self.step(10, 800, 0), self.step(25, 900, 0.05)]
        self.assertEqual(
            degradation_point(steps, p95_limit_ms=1500, error_limit=0.01),
            {"n": 25, "reason": "error_rate 5.0% > 1.0%"},
        )

    def test_step_without_latency_is_degraded(self):
        steps = [self.step(10, None, 1.0)]
        self.assertEqual(degradation_point(steps, 1500, 0.01)["n"], 10)

    def test_no_degradation(self):
        steps = [self.step(10, 800, 0), self.step(25, 900, 0.005)]
        self.assertIsNone(degradation_point(steps, 1500, 0.01))


class RenderTableTest(unittest.TestCase):
    def test_one_row_per_step(self):
        step = summarize_step(
            10,
            turns([500, 700]),
            10,
            0,
            worker=[{"cpu_percent": 80.0, "rss_mb": 900.0, "processes": 11}],
            phoenix=[{"cpu_percent": 20.0, "rss_mb": 200.0, "processes": 1}],
        )
        lines = render_table([step]).splitlines()
        self.assertEqual(len(lines), 3)
        self.assertTrue(lines[0].startswith("| N |"))
        self.assertIn("| 10 |", lines[2])
        self.assertIn("2/2", lines[2])
        self.assertIn("900", lines[2])

    def test_missing_values_render_as_dash(self):
        step = summarize_step(5, [], 0, 5, worker=[], phoenix=[])
        self.assertIn("| - |", render_table([step]))


class ProcessTreeSamplerTest(unittest.TestCase):
    def test_counts_the_process_and_its_children(self):
        child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"])
        try:
            sampler = ProcessTreeSampler(psutil.Process().pid)
            sampler.sample()  # the first cpu_percent of a process is always 0
            sample = sampler.sample()
            self.assertGreaterEqual(sample["processes"], 2)
            self.assertGreater(sample["rss_mb"], 1)
            self.assertGreaterEqual(sample["cpu_percent"], 0)
        finally:
            child.kill()
            child.wait()

    def test_a_gone_process_samples_empty(self):
        child = subprocess.Popen([sys.executable, "-c", "pass"])
        child.wait()
        sample = ProcessTreeSampler(child.pid).sample()
        self.assertEqual(sample, {"cpu_percent": 0.0, "rss_mb": 0.0, "processes": 0})


if __name__ == "__main__":
    unittest.main()
