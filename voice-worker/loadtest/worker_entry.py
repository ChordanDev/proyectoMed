"""The voice worker as the load test runs it (#401): `worker.py` with warm processes.

`worker.py dev` keeps no idle job process, so under a burst of sessions every job
waits for a cold process (about 2 s of imports, at most 4 at a time) and LiveKit
gives up on dispatching some rooms ("no servers available"). A production worker
(`start`) keeps 8 warm processes. This entry runs the same worker in `dev`, which has
no CPU-load cap so degradation shows instead of refused jobs, with the production
number of warm processes. It also reports as its load the CPU of its own process
tree, not of the whole machine: on the laptop the learners, LiveKit and Phoenix share
the CPU, and LiveKit stops dispatching to a worker whose reported load reaches 1,
while on a dedicated worker machine the two are the same. It refuses to start unless
the fake speech providers are on and LiveKit is on a loopback address.

Usage (from voice-worker/): python -m loadtest.worker_entry dev --no-reload
"""

# pyright: reportMissingImports=false
import os

import psutil
from livekit.agents import cli

import worker
from fake_providers import fake_providers_from_env
from loadtest.metrics import ProcessTreeSampler

WARM_PROCESSES = 8  # livekit-agents' production default of num_idle_processes


class OwnTreeLoad:
    """The worker's load: CPU of this process and its job processes, 0 to 1 of the machine."""

    def __init__(self, cpus: int | None = None):
        self._cpus = cpus or psutil.cpu_count() or 1
        self._sampler = ProcessTreeSampler(os.getpid())

    def __call__(self) -> float:
        share = self._sampler.sample()["cpu_percent"] / 100 / self._cpus
        return min(max(share, 0.0), 1.0)


def configure(environ):
    try:
        transcript = fake_providers_from_env(environ)
    except ValueError as error:
        raise SystemExit(str(error)) from None
    if transcript is None:
        raise SystemExit("the load test worker runs only with fake speech providers")
    worker.server.update_options(num_idle_processes=WARM_PROCESSES)
    worker.server.load_fnc = OwnTreeLoad()
    return worker.server


if __name__ == "__main__":
    cli.run_app(configure(os.environ))
