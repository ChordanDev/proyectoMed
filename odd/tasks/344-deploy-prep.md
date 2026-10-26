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
| T1 | S1, S7 | inline | pending | |
| T2 | S4 (drain gate, operator action) | inline | pending | |
| T3 | S4 (fly-replay to the owning machine) | inline | pending | |
| T4 | S5 | inline | pending | |
| T5 | S2, S4 (drain-and-deploy script) | inline | pending | |
| T6 | S3 | inline | pending | |
| T7 | S6 | inline | pending | |

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
