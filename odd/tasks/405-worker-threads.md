# 405 - Voice worker sessions as threads instead of processes

Objective: measure process-per-job, thread-per-job and a hybrid executor of the voice worker with the #401 load harness and fake providers, make the executor configurable (default unchanged), and recommend one setup.
Branch: `test/405-worker-threads` from `origin/develop`. Delivery: one PR to `develop` (`Refs #405`). Test runner: `uv run --locked python -m unittest discover` in `voice-worker/`, plus ruff and pyright.

## Specs

- S1 (issue #405): "Measure, with the existing load harness and fake providers only, three executor setups of LiveKit Agents: 1. process per job (today, the baseline); 2. thread per job in one process (`JobExecutorType.THREAD`); 3. a hybrid: a few processes, each running several jobs as threads, if LiveKit Agents supports it (otherwise several worker processes in thread mode on one machine)."
- S2 (issue #405): "For each: memory per session, sessions per machine before degradation, turn latency percentiles, CPU, and fault isolation (inject a crash or a hang in one session and record how many other sessions fail). Translate to machines and monthly cost for 200 sessions, and recommend one setup."
- S3 (issue #405): "Make the chosen executor configurable through an env var with today's behaviour as the default; do not change the default without the owner's decision."
- S4 (acceptance): "A report in docs/research/ with the three setups compared on memory, capacity, latency, CPU, fault isolation and cost."
- S5 (acceptance): "The executor type (and threads per process if applicable) is configurable; the default stays process per job (tested)."
- S6 (acceptance): "The harness run is reproducible with one documented command; no paid provider is contacted."

Constraints: fake providers only, never read `.env`, never use ports 4000/4001/5173/7880-7882, one setup at a time, stop everything started.

## Tasks

| ID | Specs | Route | Status | Commit / evidence |
|---|---|---|---|---|
| T1 | S3, S5 | inline | done | 5348620; RED: test_executor import error (configure_server missing); GREEN: 252 tests OK |
| T2 | S1, S6 | inline | done | fd05465; RED: 2 import errors + 2 failures; GREEN: 264 tests OK; smoke run N=2, thread, 2 workers: 6/6 turns |
| T3 | S2 | inline | done | this commit; RED: test_loadtest_faults import error (no loadtest.faults); GREEN: 277 tests OK; smoke N=3 thread crash at 12 s: 2/2 other sessions affected |
| T4 | S1, S2, S4, S6 | inline | pending | |

- T1: `VOICE_WORKER_EXECUTOR` (`process` default, `thread`) in `worker.py`, refused when invalid; README row; tests for default, thread and refusal.
- T2: harness options `--executor` and `--workers K` (K worker processes on one machine, the hybrid), worker CPU/RSS summed over all worker trees; tests.
- T3: harness fault injection `--fault crash|hang` in one session; report how many other sessions fail; tests.
- T4: run the three setups, write `docs/research/voice-worker-threads.md` with results JSON, cost for 200 sessions and the recommendation.

Route evidence: one bounded writer (this session) owns the whole issue; each task is inline in it. No parallel units.

## Log

- L1 (2026-10-26, user request relayed): "abrí la issue para probar el voice worker en hilos. En cuanto a lo de producción. No sería más barato hacer todo en una VPS?"
- L2: livekit-agents 1.8.3 (installed `.venv`) has `JobExecutorType.PROCESS` and `JobExecutorType.THREAD` only (`livekit/agents/job.py:130`); `ProcPool` builds one `ThreadJobExecutor` or one `ProcJobExecutor` per job (`ipc/proc_pool.py:207-240`). There is no option for several jobs per child process, so the hybrid is several worker processes in thread mode on one machine, as the issue allows. A thread job cannot be killed (`ipc/job_thread_executor.py`, `aclose`), and `job_memory_limit_mb` applies to processes only.
- L3: T1 done. `VOICE_WORKER_EXECUTOR` refuses anything but `process`/`thread` at start (`exit 1` with the message, smoke-checked with `env -i`).
- L4: T2 smoke run (N=2, 3 turns, `--executor thread --workers 2`): both jobs went to `worker-0`; idle thread workers hold 368 MB for 2 workers with 8 warm job threads each. Job distribution across several workers needs checking at a real N.
- L5: T3 done. `--fault crash|hang` and `--fault-after-s`; the first job to create `fault.json` in the run directory faults, the step reports `fault` (other sessions affected after the fault time).
