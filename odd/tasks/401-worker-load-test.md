# 401 worker load test

Objective: measure how many concurrent voice sessions one voice-worker machine sustains, with fake STT/TTS only, and turn it into Fly gru sizing and cost for #344.
Branch: `test/401-worker-load-test` from `develop`; PR to `develop` with `Refs #401`. Delivery: single PR. Test runner: `cd voice-worker && uv run python -m unittest`.

## Specs

- S1: "A repeatable load harness (script in the repo) that starts N simulated learner sessions against a local Phoenix + local LiveKit (`livekit-server --dev` on a non-default port) + one voice worker process, each session speaking scripted utterances at human pace for a 10-minute-equivalent run (time-compressed is fine if documented)."
- S2: "Report per N (10, 25, 50, 100, 200 or until failure): worker CPU and memory, Phoenix CPU and memory, turn latency percentiles (end of speech → first audio with fake providers), dropped or failed turns, and the N where latency or errors degrade."
- S3: "Translate the result into machine sizing and a monthly cost estimate for Fly gru (current public prices, cited), and note which limits are provider-side (Cartesia 15 concurrent on Scale, Deepgram 150) rather than worker-side."
- S4: "The harness runs with one documented command and never contacts a paid provider."
- S5: "A report in docs/research/ with the table per N and the sizing/cost recommendation."
- S6: "#344 is updated with the measured sessions per machine."
- Constraints (task handoff): fake providers only, never read any `.env`; own LiveKit on a non-default port and own Phoenix on `PORT=4159`; never touch ports 4000/4001/5173/7880 or the user's processes; stop everything started. If real WebRTC participants at N=200 are impossible on this machine, state exactly what was measured.

## Tasks

| ID | Specs | Route | Status | Commit / evidence |
|----|-------|-------|--------|-------------------|
| T1 | S2 | inline | done | `8988ed0` metrics; RED: `tests.test_loadtest_metrics` import error (module missing); GREEN: 15 tests OK |
| T2 | S1, S4 | inline | done | `8f69bf8` harness; RED: `tests.test_loadtest_harness` import error (modules missing); GREEN: 13 tests OK; smoke run N=2 × 3 turns: 6/6 turns ok, p50 650 ms, all ports freed |
| T3 | S2, S3, S5 | inline | done | report `docs/research/voice-worker-capacity.md` + raw JSON; harness fix `5244630` (RED: worker_entry import error, then OwnTreeLoad missing; GREEN: 5 tests) and `max_gap` (RED: import error; GREEN) |
| T4 | S6 | inline | pending | comment measured sessions per machine on #344 |

## Log

- L1 (2026-10-25, user request relayed by the workflow): "dale" — implement issue #401 "Measure voice worker capacity with a local load test" as a bounded writer.
- L2: Exploration. The worker runs one process per job (`livekit-agents` 1.8.3, `JobExecutorType.PROCESS`, spawn), so memory per session is a process. `dev` mode has no load cap (`load_threshold=inf`), `start` caps at 0.7 machine CPU. `scripts/run-voice-stack.sh` pins LiveKit to 7880 and Phoenix to the dev DB, so the load harness starts its own stack (LiveKit 7990/7991/7992 UDP, Phoenix 4159, separate `backend_load401` database). Machine: Apple M3, 8 cores, 16 GB.
- L3: T1 and T2 done. Worker suite `uv run python -m unittest`: 208 tests OK. Smoke run proved the stack starts, learners are real WebRTC participants (Python `livekit.rtc`), and teardown frees 4159/7990/7991/18866.
- L4: First full run invalid: the laptop slept during N=25/N=50 (pmset log, uptime jumps). It also showed two harness defects: `dev`'s 0 warm processes made LiveKit drop dispatches ("no servers available") after ~13 cold jobs, and the machine-wide CPU of the shared laptop marked the worker full. Fixed with `loadtest/worker_entry.py` (8 warm processes, own process-tree load), SIGTERM cleanup and `caffeinate`. Orphans of the killed run were stopped by PID after checking their cwd was this worktree.
- L5: Second full run (2026-10-26 08:40-09:08, no sleep in pmset log): N=10 400/400 p95 636 ms; N=25 1000/1000 p95 1,099 ms; N=50 degraded (p95 1,862 ms, 64.5% failed turns, 4.3 GB swap). Stopped after N=50 by the harness. Per session: ~360 MB RSS, 6.4% of an M3 core. Fly prices from https://fly.io/pricing (2026-10-26): perf-4x $132.01, perf-8x $264.01, RAM $6/GB, gru x1.615. Recommendation: performance-4x 12 GB at 20 sessions, 11 machines, ~$2,772/month.
