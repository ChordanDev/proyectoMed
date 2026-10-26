# Voice worker capacity (#401)

How many concurrent voice sessions one voice-worker machine holds, measured locally
with the fake speech providers (#191), and what that means for the Fly `gru` worker
fleet of #344. Measured 2026-10-26 on `develop` at `9192ab7`.

## Result

| Question | Answer |
|---|---|
| Sessions on the test laptop (M3, 8 cores, 16 GB, whole stack on one machine) | **25 clean, degraded at 50** |
| What breaks first | **Memory**: one process per job at about **360 MB** each (RSS) |
| Worker CPU per session | **6.4 % of one M3 core** on average (N=25) |
| Turn latency, end of speech to first patient audio (fakes) | p50 618-674 ms, p95 636-1,099 ms up to N=25. 500 ms of it is the endpointing silence |
| Phoenix | Not a limit: 14 % of one core and 245 MB at N=25 (dev mode) |
| Recommended worker machine (Fly `gru`) | **performance-4x with 12 GB, planned at 20 sessions** |
| 200 sessions | **11 machines (10 + 1 for drains), about $2,772/month** |

The CPU figure for Fly is an assumption (see [Sizing](#sizing-for-fly-gru)): verify it on
one Fly machine before #344 fixes the fleet.

## What was measured

`scripts/load/run-worker-load-test.sh` (one command; options in `--help`):

- starts its own `livekit-server --dev` on ports 7990/7991 (UDP 7992), the voice-stack
  mock OpenAI on 18866, Phoenix in dev on 4159 with its own database
  (`backend_load401`, the approving Jev adapter) and **one voice worker** with
  `VOICE_WORKER_FAKE_PROVIDERS=true`;
- gives every process an allow-list environment (`voice-worker/loadtest/stack.py`), so
  no provider key or URL from the shell reaches it, never reads `.env`, and refuses a
  non-loopback URL; the worker entry refuses to start without the fake providers;
- runs **N real WebRTC learners** (Python `livekit.rtc`, 25 per shard process). Each
  starts a consented session on Phoenix, joins its room with Phoenix's credential and
  publishes a microphone track for the whole run, silence included;
- each learner speaks **40 turns**: a 1.2 s tone the fake STT hears as one utterance,
  then waits for the patient's reply, one turn every 7.5 s;
- latency runs from the moment the last speech sample plays out to the first audible
  frame of the patient's track;
- samples the CPU and resident memory of the worker, Phoenix and LiveKit process trees
  once a second. Averages come from the window when every session is talking; peaks
  from the whole step;
- stops at the first step where most turns fail or available memory drops under the
  guard, and stops everything it started.

**Time compression.** A 10-minute station has about 40 learner turns, one every 15 s.
The harness plays those 40 turns in 5 minutes, at twice the human turn rate. Audio
streaming runs at the real rate; turn processing runs at twice it, so CPU per session
is an overestimate.

**What the fakes leave out.** No Deepgram or Cartesia WebSocket, TLS or network time,
and the mock LLM answers at once. The fake STT computes the energy of every frame in
pure Python, which costs CPU a real Deepgram stream does not. Latency is the worker and
Phoenix pipeline only: add the provider times to it.

**How the worker ran.** `voice-worker/loadtest/worker_entry.py` runs `worker.py` in
`dev` mode (no CPU-load cap, so degradation shows as latency and errors instead of
refused jobs) with two changes:

- the production number of **8 warm job processes**. With `dev`'s 0, a burst of jobs
  waited for cold processes (about 2.4 s of imports, at most 4 at a time) and LiveKit
  dropped dispatches (`no servers available`) after about 13 jobs;
- the worker reports the **CPU of its own process tree** as its load. With the
  machine-wide CPU of the shared laptop, LiveKit stopped dispatching to it. On a
  dedicated worker machine the two are the same.

Learners arrive one per second (N=50 ramps over 50 s).

## Results per N

Raw data: [`voice-worker-capacity-results.json`](voice-worker-capacity-results.json).
CPU is the percent of one core, so 160 means 1.6 cores.

| N | sessions ok | turns ok | p50 ms | p95 ms | p99 ms | worker CPU avg/peak % | worker RSS peak MB | worker processes | Phoenix CPU avg/peak % | Phoenix RSS peak MB |
|---|---|---|---|---|---|---|---|---|---|---|
| 10 | 10/10 | 400/400 | 618 | 636 | 641 | 51/187 | 6519 | 21 | 6/12 | 297 |
| 25 | 25/25 | 1000/1000 | 674 | 1099 | 1318 | 160/252 | 5922 | 36 | 14/46 | 245 |
| 50 | 35/50 | 711/2000 | 944 | 1862 | 10213 | 185/555 | 7082 | 44 | 17/85 | 220 |

- **Idle worker**: 11 processes and 2,920 MB (the main process and 8 warm job processes,
  about 290 MB each).
- **N=10** ran with 5 GB still available: (6,519 − 2,920) / 10 ≈ **360 MB per session**.
  Each job takes a warm process and the pool starts a replacement, so every session adds
  one process.
- **N=25** is the last clean step: every turn answered, p95 1.1 s. The worker RSS is lower
  than at N=10 because macOS was already compressing memory (2.8 GB available at the
  lowest), so the N=10 figure is the per-session one.
- **N=50 degraded** (the first step over the p95 limit of 1,500 ms; 64.5 % of the turns
  failed). The laptop had 4.3 GB of swap in use after the step: job processes started slowly, 15 learners gave
  up waiting 60 s for the worker (`worker_not_joined`), and the rest lost replies
  (`no_audio` 586, `no_reply_end` 78; 25 turns ran past the 10-minute station deadline).
  N=100 and N=200 were not run: the harness stops after a failed step.
- LiveKit used 14 % of one core at N=25. The learners, LiveKit and Phoenix share the
  laptop with the worker, so this is a **floor**: a dedicated machine holds more.

## Sizing for Fly gru

Assumptions, not measurements:

- A Fly performance vCPU does **half the work of an M3 performance core**, so one session
  takes about 12.8 % of a Fly vCPU.
- In production (`start`), the worker stops taking jobs at a CPU load of 0.7.
- Per-machine memory is the main process plus 8 warm processes (about 2.6 GB) plus
  360 MB per session. On Linux, RSS counts the shared library pages of each process, as
  on macOS, so this is conservative.

Prices: Ashburn performance-4x (8 GB) $132.01/month, performance-8x (16 GB)
$264.01/month, extra RAM $6.00 per GB per month, and `gru` costs 1.615 times Ashburn
(<https://fly.io/pricing>, read 2026-10-26). One spare machine is added so a deploy can
drain one.

| Machine (gru) | $/month | CPU limit | Memory limit | Sessions | Machines for 200 | $/month for 200 |
|---|---|---|---|---|---|---|
| performance-4x · 8 GB | 213.20 | 21 | 15 | 15 | 14 + 1 | 3,198 |
| **performance-4x · 12 GB** | **251.96** | **21** | **26** | **21** | **10 + 1** | **2,772** |
| performance-8x · 16 GB | 426.38 | 43 | 38 | 38 | 6 + 1 | 2,985 |
| performance-8x · 20 GB | 465.14 | 43 | 49 | 43 | 5 + 1 | 2,791 |

**Recommendation:** performance-4x with 12 GB, planned at **20 sessions per machine**,
11 machines for 200 sessions, about **$2,772/month** in `gru`. The default 8 GB
performance-4x is memory-bound at about 15 sessions. This replaces the 8 to 20 machines
($1,706 to $4,264/month) that `production-infrastructure.md` (A11) estimated from an
assumed 10 to 25 sessions per machine.

## Provider-side limits

These come before any worker limit and the fakes cannot measure them
(`production-infrastructure.md`, A13 and A14):

- **Deepgram Pay As You Go: 150 concurrent streams.** Each session holds one stream, so
  200 sessions need Growth or Enterprise whatever the worker fleet.
- **Cartesia Scale: 15 concurrent contexts.** It covers the average reply load of
  200 sessions with almost no burst headroom; Enterprise above about 100 sessions.

## Follow-ups

- Run the harness once on a Fly performance-4x machine in `gru` to replace the CPU
  assumption with a measurement.
- Fewer warm processes (for example 3) would free about 1.5 GB per machine; whether
  bursts still dispatch then is untested.
- The thread job executor (`JobExecutorType.THREAD`) would share one interpreter per
  machine and cut memory sharply, at the cost of job isolation. Untested.
