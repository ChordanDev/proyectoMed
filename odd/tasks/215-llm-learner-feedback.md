# Issue 215: Write learner feedback with an LLM from the graded result

- Issue: #215 (depends on #212, merged as #217; #214 runs concurrently in `../proyectoMed-214`)
- Worktree: `../proyectoMed-215`, branch `feat/215-llm-learner-feedback` from `origin/develop` (`62e3c90`)
- PR target: `develop` (`Closes #215`)
- Engram mirror: `odd/215-llm-learner-feedback/tasks`

## Objective

After rubric grading, an LLM writes the per-criterion `recommendation` shown to the learner in the v2 educational result. The feedback explains the graded outcome, never changes a level, status or points, and falls back to the authored `practice_recommendation` on any failure.

## Problem and why

Today `recommendation` is the static authored `practice_recommendation` (`backend/lib/backend/stations/rubric_assessment.ex:553`); for acute-appendicitis it is only the item title. ADR-005 (#38) requires per-criterion feedback that explains the result. The result is recomputed lazily on every `GET /api/v2/stations/active/sessions/:id/result` (`Stations.get_educational_result/2`, `backend/lib/backend/stations.ex:372`) with no persistence.

## Decisions (maintainer, 2026-10-14)

- **Generated once and stored:** feedback is generated on the first result fetch and kept in memory with the session. Each cached entry is bound to the exact graded outcome of its criterion (id, status, level, points, cited evidence ids). If a later recomputation changes that outcome, only that criterion is regenerated. Stale feedback never contradicts a new grade.
- **Input is the graded record only:** per criterion the provider receives the description, the obtained level and its description, the next level's description, performed and missing actions, and the cited learner evidence text. The full conversation is never sent. This keeps the request small and within the #208 caps, and the feedback cannot re-grade.
- **Language:** the station package `language` (pt-BR for every current package).
- **Length:** 1 to 3 sentences per criterion, hard cap 400 characters. Longer output falls back to the authored text for that criterion.
- **Provider:** OpenAI, reusing the patient configuration (`OPENAI_API_KEY`, `OPENAI_BASE_URL`, `OPENAI_MODEL`, default `gpt-4o-mini`). One request for all eligible criteria, with a 3 s deadline (`Task.yield || Task.shutdown(:brutal_kill)`, as in `JevDecision.run_with_deadline`). No retries.
- **Eligibility:** only `:assessed` criteria get generated feedback. `:uncertain`, `:not_observable` and `:not_applicable` keep the authored text.
- **Fallback:** any error, timeout, crash, malformed output, missing criterion, over-length text, or text containing a global score or pass/fail/readiness language keeps the authored `practice_recommendation` for that criterion. Feedback generation never blocks, delays past the deadline, or alters grading.
- **Seam:** a behaviour with an OpenAI adapter and a disabled default for tests; it is a real external-provider seam. `Backend.Stations` stays the public interface; `RubricAssessment` is not touched (keeps #214 conflict-free).

## Constraints

- ADR-005: per-criterion only, no pass/fail, readiness or certification language. Educational point estimates (ADR-012, #124) stay as they are.
- Backend modular monolith (`.agents/skills/backend-phoenix-contexts/SKILL.md`). No Mox; tests use hand-written doubles swapped with `Application.put_env` in `async: false` tests.
- `recommendation` stays a string, so the web client does not change.
- Never touch `.env*` files.

## Forecast and delivery

- Forecast: about 650 authored changed lines (T1 ~350, T2 ~250, T3 ~50). Above the 400-line budget, so strategy `ask-on-risk` applies; chain strategy chosen below.
- **Delivery:** chain strategy `feature-branch-chain`, chosen by the maintainer. Parent/tracker branch `feat/215-llm-learner-feedback` (draft PR to `develop`, `Closes #215`); child 1 `feat/215-1-feedback-step` (T1, PR to the parent); child 2 `feat/215-2-openai-feedback-adapter` (T2 and T3, PR to child 1).

## Tasks

- [x] **T1** `Backend.Stations.LearnerFeedback` post-assessment step, test-first: behaviour, disabled default adapter, deadline, per-criterion fallback and output policing, cache bound to the graded outcome in the session, wired into `Stations.get_educational_result/2`. Route: delegated direct (writer trigger: 2+ non-trivial files). Tests cover:
  - feedback attached per assessed criterion; non-assessed criteria keep authored text;
  - levels, statuses, points and estimates identical with and without feedback generation;
  - error, timeout, crash, malformed output, missing criterion, over-length and pass/fail/score text each fall back;
  - second fetch reuses the cache (one provider call); a changed graded outcome regenerates only that criterion.
- [x] **T2** OpenAI adapter for learner feedback (Req, `retry: false`, stubbed HTTP tests, structured JSON output parsed per criterion id), config wiring. Route: delegated direct.
- [x] **T3** Docs: `docs/educational-result-api.md:23` (recommendation may be generated, with authored fallback) and this design record. Route: same writer, separate commit.
- [ ] **T4** Live check by the user against OpenAI on acute-appendicitis. Route: run by the user; the agent never reads keys.

## Progress

- 2026-10-14: design points settled with the maintainer (above). Next: T1.
- 2026-10-14: T1 done in `be02235` (`feat(stations): write learner feedback from the graded result with authored fallback`), route delegated direct. Test-first: RED observed with 18/25 failing in `learner_feedback_test.exs` and `educational_result_test.exs` (module undefined, no feedback request), then GREEN. Verification from `backend/`: `mix format --check-formatted` clean; `mix compile --warnings-as-errors --force` clean; `mix credo --strict` no issues; `mix test` 980 passed, 0 failures. Design notes: the cache lives in the session map under `:learner_feedback` (`Conversation.learner_feedback/1`, `put_learner_feedback/2`), so it dies with discard and expiry; the fingerprint is the tuple `{id, status, level, points, sorted evidence_ids}` compared by equality; `missing_actions` are sub-actions classified `not_performed` (uncertain ones are not sent); the next level is the authored level with the smallest points above the obtained points; the `:disabled` default is not logged, other failures log only an atom kind. Next: T2 (OpenAI adapter).
- 2026-10-14: T2 done in `f294e69` (`feat(stations): write learner feedback through OpenAI`) on `feat/215-2-openai-feedback-adapter`, route delegated direct. Test-first: RED observed with 0/11 passing in `test/backend/stations/learner_feedback/openai_adapter_test.exs` (module undefined), then GREEN 11/11. Design notes: `Backend.Stations.LearnerFeedback.OpenAIAdapter` reuses the patient adapter's config, credential check and normalized `POST /v1/chat/completions` (`retry: false`) through a minimal extraction (`config/1`, `validate_credentials/1`, `post_chat_completion/2`, all `@doc false`); `receive_timeout` is the feedback deadline minus 250 ms (at least 500 ms); output is requested with `response_format: json_object` and parsed from `{"feedback": {...}}`, any other shape is `:malformed_response`; values pass through as-is and `LearnerFeedback` polices them. `config/config.exs` now defaults `:learner_feedback_adapter` to the OpenAI adapter; `config/test.exs` keeps the disabled adapter; a missing key yields `:missing_credentials`, which keeps the authored text.
- 2026-10-14: T3 done (`docs(stations): document generated learner feedback recommendation`): `docs/educational-result-api.md` describes the generated `recommendation` and its authored fallback; this record updated with the delivery chain. Verification from `backend/` after T2 and T3: `mix format --check-formatted` clean; `mix compile --warnings-as-errors --force` clean; `mix credo --strict` no issues; `mix test` 991 passed, 0 failures. Next: T4 (live check by the user against OpenAI on acute-appendicitis).
