# Production deploy on Fly (runbook)

How to run proyectoMed in production on Fly.io São Paulo (`gru`) (#344).
Two Fly apps, both built from this repository:

| App | Source | What it runs | Public |
|---|---|---|---|
| `proyectomed` | `backend/` (`backend/fly.toml`, `backend/Dockerfile`) | Phoenix: the JSON API, the LiveView pages, the RevenueCat webhook | HTTPS through Fly's proxy |
| `proyectomed-voice` | `voice-worker/` (`voice-worker/fly.toml`, `voice-worker/Dockerfile`) | The LiveKit voice worker, self-hosted and connected to LiveKit Cloud as an agent | No service |

The app names and `PHX_HOST` in both `fly.toml` files are placeholders: replace
them before the first deploy. Postgres is Neon (ADR-014 #346). LiveKit Cloud
carries only the media (SFU and TURN); LiveKit-hosted agents are not used
(decision of 2026-10-22 on #344).

Nothing in this runbook has been run against Fly, Neon or LiveKit Cloud yet:
the repository side is ready, and the first run waits for the owner's
authorization. See "Pending live checks" at the end.

## Why deploys drain first

Conversations live in the memory of the machine that started them. A station
lasts 10 minutes, and Fly stops a machine at most 300 s after the stop signal
(`kill_timeout`, research #328 A3). A plain `fly deploy` would cut running
stations, so every routine deploy goes through `backend/rel/deploy.sh`:

1. **Drain.** It runs `/app/bin/drain start` on every running machine. From
   then on `POST /sessions` answers `503` with `{"error": "draining"}` and a
   `Retry-After: 30` header. Running sessions continue.
2. **Wait.** It polls `/app/bin/drain status` every 15 s until no machine has
   an active session, or 12 minutes have passed (a 10-minute station plus
   margin). At the ceiling it deploys anyway and says how many sessions were
   still running.
3. **Deploy.** It runs `fly deploy`. The strategy is `bluegreen`: the new
   machine boots next to the old one and takes traffic once `/health` passes,
   so new sessions start on the new machine.
4. **Replay.** Until the old machine is gone, a request for one of its
   sessions that reaches the new machine is answered with
   `fly-replay: instance=<old machine id>`, and Fly's proxy replays it to the
   old machine. A session id names its machine: `<FLY_MACHINE_ID>.<random>`.

If the machine list cannot be read, the script stops before draining or
deploying. If the drain status cannot be read, `fly deploy` fails, or the
script is interrupted (Ctrl-C, a closed terminal, a cancelled job), it runs
`/app/bin/drain stop` on every machine it drained and exits non-zero.

Each machine's LiveKit orphan sweep only deletes rooms of its own sessions, so
the new machine never ends the old machine's voice rooms during the overlap.
A room whose machine is gone is closed by LiveKit's empty-room timeout.

With one machine, new sessions are refused for the length of the drain (up to
12 minutes): learners see "O simulador está sendo atualizado" and can retry.
Deploy at a quiet hour.

## Secrets and environment

Secrets are set with `fly secrets set NAME=value --app <app>` and never written
to the repository or to `fly.toml`. The non-secret settings are in the
`[env]` of each `fly.toml`.

### Phoenix (`proyectomed`)

Secrets:

| Variable | Source |
|---|---|
| `DATABASE_URL` | Neon console, project in `aws-sa-east-1`, the pooled connection string written as `ecto://USER:PASS@HOST/DATABASE`. No `ssl` query parameter (TLS comes from `DATABASE_SSL`). |
| `SECRET_KEY_BASE` | Generate once: `mix phx.gen.secret`. |
| `ANTHROPIC_API_KEY` | Anthropic Console, API keys. |
| `TYPESAFE_API_KEY` | TypeSafe dashboard. Live Jev use requires the privacy and legal acceptance of #183. |
| `DEEPGRAM_API_KEY` | Deepgram console, API keys (turn-based voice). |
| `CARTESIA_API_KEY` | Cartesia dashboard, API keys (turn-based voice). |
| `CARTESIA_VOICE_ID` | Cartesia voice library: the patient's voice id. |
| `LIVEKIT_URL` | LiveKit Cloud project settings (`wss://<project>.livekit.cloud`). |
| `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` | LiveKit Cloud project, API keys. |
| `VOICE_WORKER_SECRET` | Generate once (`openssl rand -hex 32`); the same value in the voice worker. |
| `REVENUECAT_WEBHOOK_AUTHORIZATION`, `REVENUECAT_WEBHOOK_SECRET` | RevenueCat dashboard, webhook settings (`docs/operations/revenuecat.md`). |
| `REVENUECAT_CARD_PURCHASE_LINK`, `REVENUECAT_PIX_PURCHASE_LINK` | RevenueCat Web Purchase Links (`https://pay.rev.cat/<token>`). |
| `MAILER_PROVIDER`, `MAILER_API_KEY`, `MAILER_FROM_EMAIL` (and `MAILER_DOMAIN` for mailgun) | The chosen email provider's dashboard, with a verified sending domain. Production refuses to boot without `MAILER_PROVIDER`. |

Set in `backend/fly.toml` `[env]`:

| Variable | Value | Meaning |
|---|---|---|
| `PHX_HOST` | placeholder `proyectomed.fly.dev` | The public host of the URLs Phoenix builds. Set the real domain. |
| `PHX_SERVER`, `PORT` | `true`, `8080` | Serve HTTP on the port of `[http_service]`. |
| `TRUSTED_CLIENT_IP_HEADER` | `fly-client-ip` | Rate limits key on the client IP Fly's proxy sets. |
| `VOICE_MODE` | `realtime` | The LiveKit voice panel. |
| `VOICE_PROVIDER` | `deepgram_cartesia` | Deepgram and Cartesia for the turn-based voice endpoints. |
| `LLM_PROVIDER` | `anthropic` | Claude serves the patient, the rubric resolver and learner feedback. |
| `JEV_ADAPTER` | `typesafe` | Live Jev verification. |
| `DATABASE_SSL`, `POOL_SIZE` | `true`, `10` | TLS to Neon with peer verification; the pool size. |
| `MAX_CONCURRENT_SESSIONS` | `200` | The concurrent-session cap of one machine (see below). |

Set by Fly on every machine, never by hand: `FLY_MACHINE_ID` (names the owner of
each session; a value that is not lowercase letters and digits refuses to
boot), `FLY_APP_NAME`, `FLY_REGION`.

Every other variable keeps its default; the README tables describe them all
(rate limits, model names, deadlines, prices with `USAGE_PRICES_JSON`).
`ACTIVE_STATION_ID` refuses to boot in production: stations come only from the
database.

### Voice worker (`proyectomed-voice`)

Secrets: `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` (the same
LiveKit Cloud project as Phoenix), `VOICE_WORKER_SECRET` (the same value as
Phoenix), `DEEPGRAM_API_KEY`, `CARTESIA_API_KEY`, `CARTESIA_VOICE_ID`, and
optionally `CARTESIA_VOICE_IDS` for companion stations.

Set in `voice-worker/fly.toml` `[env]`: `PHOENIX_URL` (placeholder
`https://proyectomed.fly.dev`; it must go through Fly's proxy, not
`.internal`, so `fly-replay` reaches the machine that owns a session) and
`CARTESIA_MODEL`. Never set `VOICE_WORKER_FAKE_PROVIDERS` in production.

## First deploy

Run from a checkout of the release commit, with `flyctl` logged in to the
organization.

1. Create the Neon project in `aws-sa-east-1` and copy its connection string.
2. Create both apps without deploying, in `gru`:
   `fly apps create <phoenix app>` and `fly apps create <voice app>`. Put the
   names in both `fly.toml` files and the real host in `PHX_HOST` and
   `PHOENIX_URL`.
3. Set every secret of both tables above with `fly secrets set ... --app <app>`.
4. Deploy Phoenix: `cd backend && fly deploy`. With no machine yet there is
   nothing to drain. The `release_command` (`/app/bin/migrate`) migrates the
   Neon database on a temporary machine first, and the release migrates again
   on boot (a no-op).
5. Keep one Phoenix machine: `fly scale count 1 --app <phoenix app>`.
6. Create the first admin (below).
7. Deploy the voice worker: `cd voice-worker && fly deploy`, then size it with
   `fly scale count <n> --app <voice app>` from the load test.
8. Point the RevenueCat webhook at `https://<host>/webhooks/revenuecat`.
9. Run the smoke checks.

## Routine deploy

```sh
cd backend
rel/deploy.sh            # drains, waits, then runs `fly deploy`
```

Arguments after the script go to `fly deploy`, for example
`rel/deploy.sh --image-label v1.2.0`. `FLY_APP` overrides the app in
`fly.toml`; `DRAIN_CEILING_S` (default `720`) and `DRAIN_POLL_S` (default `15`)
tune the wait.

Deploy the voice worker in the same quiet window, right after the Phoenix
drain, when no station is running: on `SIGTERM` the agent server stops taking
jobs and finishes the running ones, but Fly waits at most 300 s.

```sh
cd voice-worker && fly deploy
```

Manual drain controls, from inside a machine:

```sh
fly ssh console --app <phoenix app> --machine <id> --command "/app/bin/drain status"
# draining=false active_sessions=3
fly ssh console --app <phoenix app> --machine <id> --command "/app/bin/drain start"
fly ssh console --app <phoenix app> --machine <id> --command "/app/bin/drain stop"
```

`bin/drain` reaches the running node through `bin/backend rpc`. Erlang
distribution listens on the loopback interface only (`rel/env.sh.eex`), so the
command works only inside the machine, behind Fly's SSH authentication.

## Concurrent-session cap

One machine admits at most `MAX_CONCURRENT_SESSIONS` running sessions (default
200, research #328 A2). At the cap `POST /sessions` answers `503` with
`{"error": "capacity_exhausted"}` and `Retry-After: 60`. From 80% of the cap
every admitted session logs a warning, for example
`concurrent sessions near the cap: 160 of 200`, and a refusal logs
`concurrent-session cap reached: 200 of 200 active, new session refused`. The
telemetry events `[:backend, :stations, :capacity, :warning]` and
`[:backend, :stations, :capacity, :exhausted]` carry `active` and `limit`.
Alert on those log lines in Fly's log drain.

## Rollback

- **Code:** redeploy the previous image with the drain: find its image
  reference in `fly releases --app <phoenix app>` (or the dashboard), then
  `rel/deploy.sh --image <previous image>`.
- **Database:** migrations only add (expand first). To undo one, run inside a
  machine `/app/bin/backend eval "Backend.Release.rollback(Backend.Repo, <version>)"`,
  where `<version>` is the timestamp of the last migration to keep, then deploy
  the code that matches it. Neon's point-in-time restore (a branch from a
  timestamp) is the last resort for lost data.

## Admin creation

Admins never sign up through a public page (#331). Inside a Phoenix machine:

```sh
fly ssh console --app <phoenix app> --command \
  "env ADMIN_EMAIL=medica@example.com ADMIN_PASSWORD='at least 12 characters' /app/bin/create_admin"
```

It prints `admin <email> created`, or `already exists, left unchanged` (it is
idempotent), and exits 0. If the email belongs to a non-admin account it
leaves that account unchanged, says so, and exits 1; so do a missing variable,
a rejected password and an unreachable database. It never prints the password. The password reaches the remote
shell's command line: change it at `/users/settings` after the first login.

## Smoke checks

After every deploy:

1. `curl -fsS https://<host>/health` answers `{"status":"ok"}`.
2. `fly ssh console --app <phoenix app> --command "/app/bin/drain status"` on the
   new machine prints `draining=false`.
3. `/users/log-in` loads, and the admin reaches `/admin`.
4. `GET /stations` with a device access token lists the published stations.
5. A learner with a subscription starts a station (`POST /sessions` answers
   `201`), exchanges a text turn and, with voice, joins the LiveKit panel; the
   voice worker's log shows the job.
6. `fly logs --app <phoenix app>` shows no transcript, generated text, audio,
   token or provider payload.

## Pending live checks

These need the accounts and the owner's authorization:

- The first deploy itself, and a deploy during a running station (drain,
  bluegreen and `fly-replay` end to end).
- What Fly's proxy answers for `fly-replay: instance=<id>` once that machine
  is gone, and for a replayed request body above 1 MB (a large `/transcribe`
  upload to an old machine's session).
- That `fly machines list --quiet` lists only machine ids and that
  `fly ssh console --command` returns the command's exit status, as
  `rel/deploy.sh` assumes.
- Latency from `gru` to Neon `aws-sa-east-1`.
- The voice worker load test (50, 100 and 200 simulated sessions): sessions per
  machine and monthly cost.
- Whether self-hosted agents are exempt from LiveKit Cloud's agent session
  limit.
