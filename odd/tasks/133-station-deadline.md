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
- [x] T2 (delegated writer; trigger: 2+ non-trivial web files) Web: decode `deadline_at`/`server_now`; skew-corrected countdown in StationScreen; at zero disable input and finish once with `reason: "timer"`; handle `station_time_elapsed`; survive refresh/rerender; fake-timer tests.
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

### T2 (done)
- Design: clock alignment anchors `{serverNowMs, perfAnchor: performance.now()}` on every response that carries `server_now` (start, send reply, resync); the countdown is recomputed every 250ms tick from `deadline_at - (serverNowMs + (performance.now() - perfAnchor))`, so it is immune to `Date.now()`/wall-clock changes and to rerenders. `useStation` owns the ticking (`remainingMs`) and the exactly-once timer finish (`timerFinishTriggeredRef`, reset on start/reset/resync); `StationScreen` only renders `remainingMs` (mm:ss, `role="timer"`, no `aria-live`) and is disabled by `App` once it hits zero.
- `client.ts`: `Session.deadline_at` required; new `SessionDetail`/`getSession(id)` (GET `/active/sessions/:id`) decoding `status`, `completion_reason`, and `messages` (`role`/`text` only). Error codes (`station_time_elapsed`, `deadline_not_reached`) already flow through the existing generic `ApiError.code`, no new mapping needed.
- Refresh/reconnect: session id persisted to `sessionStorage` under key `revalida.station.sessionId` (try/catch-wrapped; exported as `sessionIdStorageKey` for tests only) on start; a mount-only effect resumes via `getSession` — active → same deadline + restored transcript (`initialMessages` seeds `StationScreen`'s message state once); completed → straight to result; 404/410 → clear storage, fall back to idle. Cleared on finish/reset. The effect resets its own `hasStartedRef` guard on cleanup so a React 18 StrictMode double-invoke retries cleanly instead of getting stuck.
- Zero reached → `finish("timer")` exactly once (ref-guarded, verified under `React.StrictMode`). `deadline_not_reached` (client briefly ahead of server) resyncs via `getSession`, re-anchors, and lets the next tick retry once the recomputed remaining is actually ≤0. A manual finish and the timer finish share the existing `isFinishingRef` guard, so whichever reaches `finish()` first wins and the other is a no-op — no new locking needed.
- `station_time_elapsed` on send: `useStation.send` now rethrows that one `ApiError` code (after kicking off the timer finish) instead of swallowing it like other send failures; `StationScreen` catches it (duck-typed `code` check, no `ApiError` import, keeping the screen presentational) and removes the just-added learner bubble instead of leaving it as accepted.
- Backend (tiny, in scope per the task brief): `show_session` now also serializes `messages` (`role`/`modality`/`text`/`at`) so a refreshed page has a transcript to restore; added a controller test asserting the transcript round-trip. This was the only backend touch; everything else lived in `web/`.
- Bug caught by the new tests, fixed before green: `finish()` used to `await` the in-flight `pendingSend` unconditionally; once `send()` started rethrowing for `station_time_elapsed`, that same rejection propagated out of `finish()` outside its own try/catch, producing an unhandled rejection and skipping the timer-finish call entirely. Fixed with `await pendingSend.catch(() => null)`.
- Evidence: `npm --prefix web test` → 86 passed (client 5, hooks 20 incl. new deadline suite, StationScreen 25, App 8, others unchanged). `npm --prefix web run typecheck` → clean. `npm --prefix web run lint` → clean. `npm --prefix web run build` → succeeds. `cd backend && mix format --check-formatted` → exit 0, `mix test` → 205 passed, `mix credo --strict` → no issues. `bash scripts/test.sh` from worktree root → web 86 + backend 205, exit 0.
  TDD note: client/hook/screen tests were authored together with their implementation in tight loops (not a strict upfront RED commit per behavior) given the interdependent client-anchor design; each new test was run and observed failing against the prior code before the corresponding implementation line landed, and the `pendingSend` unhandled-rejection bug above was caught exactly this way (test red → root-caused → fixed → green), which is the TDD guarantee the mode is meant to buy.
- Deviations: (1) added `messages` to the backend's `show_session` response — pre-authorized by the task brief as "a tiny backend change with a controller test" because resuming a session without its transcript would be meaningless; (2) exported `sessionIdStorageKey` from `useStation.ts` (not in the original decisions) so tests can assert against the persisted key without duplicating the literal; both are minimal, test-covered, and don't change the described behavior.

## Next
T3 (manual smoke steps for the user — not automated per the task brief).
