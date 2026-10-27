# 344 deploy prep: Fly production with drain-safe sessions (repo side)

Objective: prepare everything in the repository to deploy Phoenix and the voice worker to Fly `gru` with a pre-deploy drain gate, `fly-replay` to the owning machine, a concurrent-session cap and a deploy runbook. Branch `feat/344-deploy-prep` from `develop`, one PR to `develop` (`Refs #344`). Test runner: ExUnit (`mix test`, `MIX_TEST_PARTITION=_issue344`), local CI script.

Why: Fly's `kill_timeout` is capped at 300 s, shorter than a 10-minute station (research #328 A3), so a deploy must drain the old node first. Running anything against Fly, Neon or LiveKit Cloud waits for the owner's explicit authorization (scope note 2026-10-25).

Constraints: repo-side only (no `fly`, `flyctl`, `neonctl`, `livekit-cli`, no accounts, secrets or `.env`); Phoenix contexts (`Backend.Stations` is the public interface, `BackendWeb` stays thin); learner-facing copy in pt-BR; conversations stay in memory (no migration).

## Specs

- S1 Release: backend `Dockerfile` + `mix release` (runtime.exs already reads env) with `Backend.Release` migrate/rollback and an admin-provisioning entry point ("eval-able, reads ADMIN_EMAIL/ADMIN_PASSWORD, idempotent, never prints the password").
- S2 `backend/fly.toml` "for app in region gru: http service, health check route, kill_timeout 300, single machine at launch, release_command migrate, [env] for non-secret settings (PHX_HOST placeholder, TRUSTED_CLIENT_IP_HEADER=fly-client-ip, VOICE_PROVIDER=deepgram_cartesia)".
- S3 voice-worker `Dockerfile` + `fly.toml` "(gru, no public http, scales separately)".
- S4 Drain gate: "an authenticated operator action (mix release eval command or admin-only endpoint) that switches the node to 'no new sessions' (POST /sessions returns 503 `draining` with Retry-After), reports active sessions, and a script that waits until zero or a 12-minute ceiling before `fly deploy`; requests for sessions held by the old machine are answered with a `fly-replay: instance=<machine id>` header so they reach the owning machine (use FLY_MACHINE_ID; record the owning machine id on the session)".
- S5 "configurable cap on concurrent active sessions (503 `capacity_exhausted`) with a log/telemetry warning at 80%".
- S6 `docs/operations/deploy.md` runbook: "every secret and env var with its source (Neon URL, Cartesia, Deepgram, Anthropic, TypeSafe, RevenueCat, mailer, LiveKit Cloud), first deploy, routine deploy with the drain script, rollback, admin creation, smoke checks".
- S7 Verify locally: "`docker build` both images if Docker is available (report if not), run the release locally against local Postgres, exercise drain and capacity with tests".

## Tasks

| ID | Specs | Route | Status | Commit / evidence |
|---|---|---|---|---|
| T1 | S1, S7 | inline | done | 2c5cf55; RED 8/9 failing, GREEN 9/9; release built and run locally (migrate, create_admin twice: created then already exists, /health 200 over HTTP, other paths 301); `docker build` backend OK and container served /health |
| T2 | S4 (drain gate, operator action) | inline | done | 37708aa; RED 7/7 failing, GREEN 7/7; `bin/drain status|start|stop` exercised on the local release through rpc |
| T3 | S4 (fly-replay to the owning machine) | inline | done | d8b63b0; RED 9/10 placement+plug, 2/4 runtime config; GREEN 10/10 and 4/4 |
| T4 | S5 | inline | done | ca57efc; RED 4/10 and 2/7 runtime config; GREEN 10/10 and 7/7 |
| T5 | S2, S4 (drain-and-deploy script) | inline | done | 2e47497; deploy script RED 6/6 failing, GREEN 6/6 (stub `fly`); fly.toml test written after the file (no RED) |
| T6 | S3 | inline | done | 9cd65bd; no runnable RED (image config); `docker build` OK, image imports livekit-agents 1.8.3 and runs as uid 10001 |
| T7 | S6 | inline | done | d826c07; passive docs, structural readback |
| T8 | S5 (test isolation) | inline | done | a6f7898; RED 5/6 (`Capacity.admit(10_000)` refused at the default 200 in `:test`), GREEN 6/6; `mix test --seed 205216` 2481/2481; local CI passed |

- T1 `Backend.Release` (`migrate/0`, `rollback/2`, `create_admin/0`), release overlays (`bin/server`, `bin/migrate`, `bin/create_admin`), loopback-only distribution for `bin/backend rpc`, `/health` route outside `force_ssl`, backend `Dockerfile` and `.dockerignore`.
- T2 `Backend.Stations.Drain`: node flag, active-session count, `{:error, :draining}` from `Stations.start_station_session/2`, `503 draining` + `Retry-After`, `Backend.Release.drain/0`, `resume/0`, `drain_status/0` and `bin/drain start|stop|status`.
- T3 Session ids carry the owning machine (`FLY_MACHINE_ID`); `BackendWeb.Plugs.SessionReplay` answers a session owned by another machine with `fly-replay: instance=<id>`.
- T4 `Backend.Stations.Capacity`: `MAX_CONCURRENT_SESSIONS`, `503 capacity_exhausted`, warning log and telemetry at 80%.
- T5 `backend/fly.toml` and `backend/rel/deploy.sh` (drain, wait for zero or 12 min, `fly deploy`, resume on failure), tested with a stub `fly`.
- T6 voice-worker `Dockerfile`, `.dockerignore`, `fly.toml`.
- T7 `docs/operations/deploy.md` and README env rows.

Routing: every task inline (no Writer trigger: one sequential delivery, units depend on each other). Risk: item 5 (delivery/environment: Dockerfiles, fly.toml, deploy script) and item 3 (session ids gain a machine prefix in production).

## Log

- L1 (2026-10-25, user): "dale" (the workflow task: implement the repo-side preparation of #344 as specified above).
- L2 Plan: conversations live only in ETS (`Backend.Stations.Conversation`), so the owning machine is encoded in the session id (`<machine id>.<random>`) instead of a database column; no migration is in scope.
- L3 (2026-10-25) Verification: local CI on the branch: web typecheck, lint, backend format, compile with warnings as errors, Credo strict (no issues), web unit 342/342, ExUnit 2480/2480 passed. The process-level E2E (`stationFlow.test.ts`) failed on the session-expiry scenario with a 14.6 s timeout after a 587 s wall-clock test; reruns failed with "Phoenix failed to start within 25000ms" and a vitest worker fetch timeout. `pmset` shows the host cycling through DarkWake on battery (load average 16), and a manual dev boot of this branch serves `/health` in 4 s, so the failures are environmental timing, not this change (which does not touch `web/` and leaves session ids unchanged without `FLY_MACHINE_ID`).
- L4 Pending live checks (need the owner's authorization): first deploy, a deploy during a running station, `fly machines list --quiet` and `fly ssh console --command` exit status as `rel/deploy.sh` assumes, gru to Neon latency, the voice worker load test (50/100/200 sessions).
- L5 (2026-10-26) E2E diagnosis: `stationFlow.test.ts` Technical Failure (5 s default timeout) passed 3/3 on develop (a22936d) and 3/3 on the branch, ~80 ms in isolation; the CI timeout was host load (load average up to 75 while the suite ran), not this change. A second local CI exposed a real branch defect instead: with seed 205216, 37 `SessionControllerTest`/`SessionRateLimitTest` tests got `503 capacity_exhausted` ("200 of 200 active"), because the Conversation ETS table outlives every test and the suite's leftover sessions reached the default cap. T8 sets no cap in `config/test.exs`; capacity tests set their own. Local CI then passed (ExUnit 2481/2481, E2E 4/4, Dialyzer 0 errors).
