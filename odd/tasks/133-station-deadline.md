# #133 Authoritative ten-minute station deadline

Locator: `odd/tasks/133-station-deadline.md` · branch `feat/133-station-deadline` (from `origin/feat/30-expo-screens` + merged `origin/develop` for #135) · Engram `odd/133-station-deadline/tasks`.

## Objective
One server-authoritative 10-minute deadline (`deadline_at = started_at + 10 min`), independent of the 30-min ETS `expires_at` TTL, a countdown derived from server time, and exactly-once timer completion.

## Constraints
- Thin `BackendWeb`; logic in `Backend.Stations` (AGENTS.md). No new abstractions without ADR.
- Errors keep `%{error, message}` shape. Duplicate finish stays idempotent (first writer wins).
- TDD: enabled (source: global session config "Strict TDD Mode: enabled"; repo `openspec/config.yaml` says `strict_tdd: false` — session setting applied). Runners: `mix test`, `npm --prefix web test`; full gate `bash scripts/test.sh`.
- Delivery: forecast ~500–700 authored lines → strategy `ask-on-risk`; chain decision asked before any PR.

## Tasks
- [x] T1 (delegated writer; trigger: 3+ non-trivial backend files) Backend: `deadline_at` + `server_now` on create; time-based `check_session_deadline`; late turn → `station_time_elapsed`; accepted pending turn resolves within bounded grace before completion; timer finish exactly once, distinguishable from manual; restart/race tests.
- [ ] T2 (delegated writer) Web: decode `deadline_at`/`server_now`; skew-corrected countdown in StationScreen; at zero disable input and finish once with `reason: "timer"`; handle `station_time_elapsed`; survive refresh/rerender; fake-timer tests.
- [ ] T3 Manual smoke steps for the user (no browser automation).

## Acceptance
Per issue #133; `bash scripts/test.sh` exits 0.

## Progress / evidence

### T1 (done)
- Design: `Backend.Stations.Conversation` gains `deadline_at` (station_duration_ms, default 10 min) alongside the existing 30-min `expires_at`. A `Process.send_after` deadline timer auto-completes with reason `:timer`. Accepted-before-deadline turns are tracked via `begin_turn/2` + `resolve_turn/3` (a `make_ref/0` token); while a turn is pending, `complete/2` (manual or timer) is deferred and answered via `GenServer.reply/2` once the turn resolves, or after a bounded `turn_grace_ms` (default 30s) elapses, which rolls back the pending learner message and force-completes. A stale/late `resolve_turn` (post-grace) returns `{:error, :station_time_elapsed}` and does not append.
- `Backend.Stations.create_message/2` now goes through `begin_turn`/`resolve_turn` instead of `append_message`/`pop_last_message`; late turns are rejected before touching the transcript. `complete_session/2` rejects an early `reason: :timer` finish arriving more than 2s before `deadline_at` with `{:error, :deadline_not_reached}`.
- `check_session_deadline/1` is now genuinely time-based (compares against `deadline_at`), not delegated to `status`.
- Controller: `create_session` adds `deadline_at`; `create_message` maps `station_time_elapsed` → 409; `finish_session` adds `completion_reason`/`deadline_at`/`server_now` and maps `deadline_not_reached` → 409; new `GET /api/stations/active/sessions/:id` (`show_session`) returns the session contract + `status`/`completion_reason` (thin controller, serialization only).
- Config keys: `:station_duration_ms` (default `:timer.minutes(10)`), `:turn_grace_ms` (default `:timer.seconds(30)`).
- Two pre-existing race tests (station_controller_test.exs, stations_test.exs) were rewritten: under the old model a racing manual `complete` won and silently dropped the in-flight reply; under the new authoritative-deadline model an accepted-before-deadline turn is protected, so the reply is appended and the completion finalizes afterward. Both were restructured to run the racing `complete` call from a separate process (avoids a same-process deadlock against the deferred `GenServer.reply`).
- Evidence: `cd backend && mix format` (clean) → `mix format --check-formatted` (exit 0) → `mix test` (204 passed) → `mix credo` (no issues) → `bash scripts/test.sh` from worktree root (web 71 tests passed [pre-existing `node_modules` was installed to unblock the gate, no web/ source touched] + backend 204 passed, exit 0). TDD observed RED→GREEN per behavior during implementation (turn/grace/timer paths verified against a debug script before landing the `finalize_deferred_completion` return-value fix).
- Deviation: none from the required decisions; `resolve_turn`'s own return value was corrected mid-implementation to reflect the just-finalized completed session (not the pre-completion session) — a bug caught by the new grace-window test, not a scope deviation.

## Next
T2.
