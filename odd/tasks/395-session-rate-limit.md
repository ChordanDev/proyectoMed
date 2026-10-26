# #395 Rate-limit paid provider calls inside a learner session

Parent: #326. Branch `feat/395-session-rate-limit` from `origin/feat/326-production-launch` (b584ad1).
Delivery: one PR to `feat/326-production-launch`. Test runner: `cd backend && MIX_TEST_PARTITION=_issue395 mix test`.

## Specs

- S1 "Add per-session (and per-learner) throttling on the learner session routes that call paid providers, reusing `BackendWeb.RateLimit` from #380, with a `429 rate_limited` JSON error and limits that never affect a normal 10-minute station (one turn every few seconds, a handful of impresso requests)."
- S2 "Requests beyond the configured per-session limit on each paid route return 429 `rate_limited` with Retry-After (tested)."
- S3 "A scripted normal station (turns at human pace, impresso requests, finish, result) is never throttled (tested)."
- S4 "Limits are configurable and documented in the README and docs/unreal-station-client.md."
- S5 (orchestrator) Key by session id and by learner id; voice-worker internal routes are worker-authenticated and must not be throttled per learner in a way that drops a spoken turn: decide and document whether the worker path is limited (prefer the learner-facing entry points). Limits use the existing `RATE_LIMIT_<ACTION>_<KIND>` scheme.

## Why

The daily quota (#340) bounds how many sessions a learner starts, not how often the paid routes are called inside one session; a client bug or an abusive learner can multiply Claude, Jev, OpenAI and LiveKit cost.

## Decisions

- New actions in `BackendWeb.RateLimit`, keys `:session` (the route's `:id`) and `:learner` (the device-token user id; `nil` on the unauthenticated dev/test legacy routes, so skipped):
  `session_message` (`POST .../messages`), `session_transcribe`, `session_synthesize`, `session_voice` (LiveKit credential), `session_impresso` (`POST .../impressos/request`), `session_exam_mode` (`POST`/`DELETE .../exam-mode`), `session_result` (`GET .../result`, legacy v1 and v2 too).
- One plug, `BackendWeb.Plugs.SessionRateLimit`, applied per route through router pipelines on the `/sessions/:id/...` routes and their deprecated `/api/stations/active/...` aliases. Same 429 body and `retry-after` header as `BackendWeb.Plugs.RateLimit`.
- The voice-worker routes (`/api/internal/voice/...`) are not throttled: a refused transcript would drop a spoken turn. Their cost is bounded at the learner-facing entry points: the LiveKit credential (`session_voice`, plus the existing per-session MediaSession limit), the exam-mode arming (`session_exam_mode`), and the station deadline that ends the voice session.
- Defaults are fixed windows sized well above a human-paced station (one turn every ~3 s at most): see README.
- A test-only `:clock_offset_ms` config lets a test advance the limiter's clock to script a 10-minute station without waiting.

## Tasks

- [x] T1 S1 S2 S4 S5: session/learner limits, plug, router wiring, runtime env vars, docs. Route: inline (no writer reason). RED: 11/12 new tests failed (no 429; the worker guard passed). GREEN: 12/12; full suite 2419 passed. Commit: see L3.
- [ ] T2 S3: scripted normal 10-minute station never throttled at the default limits (limiter clock offset). Route: inline. Commit: pending.

## Log

- L1 (2026-10-25, issue #395 body) "The daily quota (#340) limits how many sessions a learner starts, but inside one session nothing limits how often the paid routes are called. Every `POST /sessions/:id/messages`, voice turn, `POST /sessions/:id/impressos/request` (Jev classification since #357) and result fetch can trigger Claude or Jev calls, and the learner session routes have no `BackendWeb.RateLimit` (found in the #357 review). A client bug or an abusive learner can multiply provider cost within a session."
- L2 Explored `BackendWeb.RateLimit`, `Plugs.RateLimit`, `Plugs.ClientIP`, router `:learner_api`, the voice controllers and `MediaSession` (existing 5/min per-session LiveKit token limit). Phoenix 1.8 sets the controller action only after pipelines, so per-route pipelines carry the action.
- L3 T1 done: `BackendWeb.Plugs.SessionRateLimit`, seven `session_*` actions with defaults in `BackendWeb.RateLimit`, per-route pipelines on `/sessions/:id/...` and the legacy aliases (shared counters), `RATE_LIMIT_SESSION_*_{SESSION,LEARNER}` in `config/runtime.exs` (checked with `mix run` in dev: `3/30` parsed, `abc` refuses to boot), README and `docs/unreal-station-client.md`. Voice-worker routes stay unthrottled (tested).
