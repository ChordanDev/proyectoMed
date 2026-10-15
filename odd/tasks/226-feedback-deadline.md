# Issue 226: Give learner feedback generation enough time to finish

- Issue: #226 (child of #215)
- Worktree: `../proyectoMed-226`, branch `feat/226-feedback-deadline` from `origin/develop` (`da56a8a`)
- PR target: `develop` (`Closes #226`)
- Engram mirror: `odd/226-feedback-deadline/tasks`

## Objective

Learner feedback (#215) gets up to 60 s to finish so the result shows generated recommendations instead of the authored fallback, and the web waits for it with a visible waiting message.

## Problem and why

#215 live check (2026-10-15): every assessed criterion fell back to the authored title; backend logged `Learner feedback unavailable (timeout)` with the 3 s deadline. Resolver took 5648 ms; result endpoint 9368 ms. The web client aborts every request at 15 s (`web/src/features/station/api/client.ts:473`), so a longer backend deadline also needs a longer result-request timeout.

## Decisions (maintainer, 2026-10-15)

- Feedback quality matters more than latency; waiting up to one minute is acceptable.
- Default feedback deadline 60 000 ms; `LEARNER_FEEDBACK_DEADLINE_MS` overrides it (positive integer only), mirroring `RUBRIC_RESOLVER_DEADLINE_MS`.
- Only the educational result request gets a longer web timeout (about 80 s); every other request keeps 15 s.
- The result screen shows a pt-BR waiting message while the result loads.
- Fallback behavior from #215 is unchanged.

## Constraints

- Backend modular monolith; no Mox, hand-written doubles with `Application.put_env` in `async: false` tests.
- Frontend feature-first (`web/src/features/station`).
- Never touch `.env*` files.

## Forecast and delivery

- Forecast: about 250 authored changed lines (T1 ~120, T2 ~110, T3 ~20). Under the 400-line budget: single PR to `develop`.
- RDD: off (clone-local); ordinary checks only.

## Tasks

- [x] **T1** Backend: 60 s default feedback deadline (`config/config.exs`, `@default_deadline_ms` in `LearnerFeedback.OpenAIAdapter`), `LEARNER_FEEDBACK_DEADLINE_MS` override in `config/runtime.exs`, latency log per feedback call; tests for slow-but-in-deadline provider and latency log. Route: delegated direct (writer trigger: 2+ non-trivial files).
- [x] **T2** Web: longer timeout for the educational result request only; waiting message on the result screen; tests. Route: delegated direct.
- [x] **T3** Docs: `docs/educational-result-api.md` notes the first result fetch may take up to about a minute; this record. Route: delegated direct (same writer as T1/T2), separate commit.
- [ ] **T4** Live check by the user on acute-appendicitis. Route: run by the user.

## Progress

- 2026-10-15: worktree created, design settled with the maintainer. Next: T1.
- 2026-10-15: T1 done in `f50a236` (`fix(stations): give learner feedback up to a minute to finish`). Route: delegated direct.
  - RED: 7 new tests failed before the change (adapter receive timeout default 59 750 ms, default deadline 60 000 ms, provider slower than 3 s without a configured deadline, success/failure/timeout latency logs, `LEARNER_FEEDBACK_DEADLINE_MS` override via `Config.Reader` on `config/runtime.exs`).
  - GREEN: `mix test` on both feedback test files 43 passed. The failure log stays at warning level (with latency); the success log is info level, so its test raises this module's level to `:info` (`config/test.exs` logs at `:warning`).
  - `RUBRIC_RESOLVER_DEADLINE_MS` had no runtime test; the new override is tested in the style of the TypeSafe runtime tests (`Config.Reader.read!/2`, `:dev` and `:test` only, since `:prod` needs `SECRET_KEY_BASE`).
- 2026-10-15: T2 done in `45ca5af` (`fix(web): wait for generated learner feedback on the result screen`). Route: delegated direct.
  - RED: 2 new tests failed (`fetchResult` aborted at 15 s instead of 80 s; finishing state lacked the one-minute message).
  - GREEN: `EDUCATIONAL_RESULT_TIMEOUT_MS = 80_000` for `fetchResult` only; `getActiveStation`, `getSession` and `fetchLegacyResult` (which does not generate feedback) keep 15 s. The existing finishing state keeps `loadingResult` and adds the note `loadingResultFeedbackWait`.
- 2026-10-15: T3 done in the docs commit that carries this entry (`docs(stations): note learner feedback wait on first result fetch`). Route: delegated direct.
- Verification (after T2): `mix format --check-formatted` ok; `mix compile --warnings-as-errors --force` ok; `mix credo --strict` no issues; `mix test` 1051 passed; `npm --prefix web run typecheck` ok; `npm --prefix web run lint` ok; `npm --prefix web test` 187 passed (8 files).
- Next: T4 live check by the user on acute-appendicitis, then PR to `develop` (`Closes #226`).
