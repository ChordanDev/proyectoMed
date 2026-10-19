# 229 — Generate learner feedback once per session under concurrent fetches

Issue: #229 (parent tracker #215). Branch `fix/229-feedback-single-flight` from `origin/develop` 7bfb4cd (worktree `../proyectoMed-worktrees/issue-229`). PR target `develop`, `Closes #229`.

## Objective

Concurrent result fetches for the same session make at most one learner feedback provider call, and a failed generation is not retried on every fetch.

## Why

`LearnerFeedback.attach/3` reads the session cache, calls the provider and writes the cache only on success. Concurrent fetches (StrictMode double effect, reload during the wait, retry after the client's 80 s abort) each run a full call bounded at 60 s, and a failure is never cached, so every later fetch calls the provider again. This is a cost and load issue (Jorge review of PR #227, SP-1 / TR-1).

## Scope

- Per-session single-flight: while one fetch generates feedback for a session, other fetches for the same session wait for it, then read the cache.
- Short negative cache (cooldown) after a failed generation: within it, fetches return the authored text without a provider call; after it, generation is attempted again.

## Constraints

- Keep #215/#226: authored fallback on any failure; cache bound to the graded outcome fingerprint; feedback never changes levels, statuses or points; 60 s default deadline.
- Cache, cooldown and in-flight state live with the session (`Conversation`), so they die with discard and expiry.
- Cooldown configurable (`:learner_feedback_cooldown_ms`); tests use controllable slow adapters and short cooldowns, no long sleeps.
- `BackendWeb` untouched; `Backend.Stations` stays the public interface.

## Tasks

- [x] T1 — Single-flight. `Conversation.claim_learner_feedback/2` and `settle_learner_feedback/2`: the first claimer generates; later claimers for the same session wait (bounded by the deadline) until it settles, then re-read the cache; a crashed or exited owner releases its waiters (monitor); discard releases waiters. Tests: two concurrent `Stations.get_educational_result/2` calls with a slow gated adapter make one adapter call and return the same recommendations; a waiter whose owner fails, times out or crashes gets the authored text within the deadline. Route: inline (two coupled files, already mapped; one writer).
- [x] T2 — Failure cooldown. Failed or invalid criteria are stored as `%{fingerprint, retry_after}` entries; within the cooldown they keep the authored text without a call, after it they are retried; changed outcome still regenerates only that criterion. Config `:learner_feedback_cooldown_ms` (30 s default, 0 in test env, tests override). Docs in `docs/educational-result-api.md`. Route: inline.

## Acceptance criteria

- Two concurrent `Stations.get_educational_result/2` calls for the same completed session with a slow adapter make exactly one adapter call and return the same recommendations.
- After a failed generation, a fetch within the cooldown makes no adapter call and returns the authored text; a fetch after the cooldown calls the adapter again.
- A waiter whose generation fails or times out still gets the authored fallback within the deadline.
- A changed graded outcome regenerates only the affected criteria (existing #215 tests keep passing).

## Checks

- Focused: `cd backend && mix test test/backend/stations/learner_feedback_test.exs test/backend_web/controllers/educational_result_test.exs`.
- Closure: local CI script (mirrors `.github/workflows/pr-validation.yml`; GitHub Actions is blocked by billing) must print `LOCAL CI PASSED`.

## Progress

- Exploration done: `learner_feedback.ex` (attach/cache/generate), `conversation.ex` (ETS session store + GenServer state), existing tests in `learner_feedback_test.exs` and `educational_result_test.exs`.

- T1 (route: inline; two coupled files already mapped, no delegation trigger fired): RED observed first — 6 of 46 focused tests failing (`concurrent result fetches ... single feedback call`, and 5 `single-flight` tests: concurrent wait, waiter on failure, waiter on timeout, owner killed, discard releases waiters); `different sessions generate independently` passed before and after, as expected. GREEN: 46/46, stable over 5 repeated runs. `mix compile --warnings-as-errors --force` clean; `mix credo --strict` no issues. The only test warning (`unused require Logger` in `learner_feedback_test.exs`) is pre-existing on `develop`.

- T1 commit: `069cabb`.
- T2 (route: inline): RED observed first — 6 of 45 `learner_feedback_test.exs` tests failing (default/test cooldown config, within-cooldown no call, timeout cools down, invalid criterion cools down, changed outcome regenerates only the cooling criterion, waiter reads the cooldown). `a fetch after the cooldown calls the provider again` and `discarding the session drops its cooldown` passed before and after, as expected (they pin retry behavior). The two existing retry tests now set the cooldown to 0 explicitly. GREEN: 54/54 focused tests.
- Closure: local CI script printed `LOCAL CI PASSED` — web unit 192/192 (7 files), backend ExUnit 1101 passed, process-level E2E 4/4, typecheck, lint, format, compile (`--warnings-as-errors`), credo strict and dialyzer clean. GitHub Actions is blocked by billing.

## Next step

Open the PR to `develop` (`Closes #229`); merge is a human decision.
