# Issue 212: Serve rubric decisions from the live TypeSafe Jev adapter

- Issue: #212 (follow-ups #214 LLM resolves undecided actions, #215 LLM writes learner feedback)
- Worktree: `../proyectoMed-212`, branch `feat/212-jev-rubric-batch` from `origin/develop` (`d9adc8b`)
- PR target: `develop` (`Closes #212`)
- Engram mirror: `odd/212-jev-rubric-batch/tasks`

## Objective

`TypesafeAdapter` implements `decide_rubric_batch`, so rubric cases graded with the live adapter return real outcomes instead of `{:technical_failure, :rubric_batch_unsupported}`.

## Problem and why

The adapter serves only patient decisions. The rubric batch contract needs class labels, per-action classifications and evidence ids taken from the code-supplied pool. TypeSafe answers only with probabilities, and it cannot author identifiers. Positive credit requires a valid learner citation (`rubric_assessment.ex` around 449-455; a `performed` action without evidence is unresolved, `authored_rules.ex` around 276). So a mapping that has no citations could never grant credit.

## Decisions (maintainer, 2026-10-14)

- **Noul fan-out:** one yes/no question per (authored action, citable learner evidence item): "Does this learner item perform this action?". Probabilities are thresholded in code with the adapter's existing thresholds (yes >= 0.8, no <= 0.2).
- **Per-action classification:**
  - `performed` when at least one item is yes; every yes item is cited.
  - `not_performed` when every item is no.
  - `uncertain` otherwise.
  - An action with no citable items is `not_performed`.
- **Criterion classification:** the criterion class is always `"uncertain"` with no criterion-level evidence. Authored rules (`min_actions`) decide the level from the action outcomes. A criterion without deciding rules stays uncertain (`:classifier_uncertain`) and never receives credit.
- **Request shape:** one request carries every question, with the full citable conversation as state. When the estimated payload exceeds the provider budget (64k tokens per request), the request is split into groups of actions; every group keeps the full conversation. Groups run concurrently under the single batch deadline. Splitting per message is rejected, because the probe showed it changes answers.
- **Enumeration:** a question with `enumerate_answers: true` has no mapping. The batch fails closed with a typed technical failure; no real package uses it.
- **Failure policy:** any transport error, timeout, invalid probability or missing answer fails the whole batch closed. A technical problem never becomes a credited action or level.
- **Design doc:** `docs/design/jev-prototype.md` (around line 155) is amended. The rubric TypeSafe mapping thresholds probabilities in code, and every cited id still comes from the code-supplied pool.
- **Follow-ups:** the LLM that resolves undecided actions (#214) and the LLM that writes learner feedback (#215) are out of scope.

## Evidence: live probe (2026-10-14, one run, `jev-1.13.0`, 48 actions x 10 pt-BR messages = 480 questions)

| Shape | Wall time | yes / no / undecided |
|---|---|---|
| Single request | 790 ms | 24 / 446 / 10 |
| 48 per-action requests | 1025 ms | 24 / 446 / 10 |
| 10 per-message requests | 604 ms | 23 / 442 / 15 |

Every shape fit the 2850 ms budget (3 s deadline minus the 150 ms margin), with 0 failures. The single request is about 32k estimated tokens.

## Constraints

- Backend modular monolith: `Backend.Stations` is the public interface, and there are no new behaviours or speculative abstractions (`.agents/skills/backend-phoenix-contexts/SKILL.md`).
- Reuse the adapter's existing config, credential, threshold, budget, request and parse helpers.
- No automatic retries. The 150 ms deadline margin is kept.
- Never touch `.env*` files.

## Tasks

- [x] **T1** `decide_rubric_batch` in `TypesafeAdapter`, test-first, with stubbed HTTP. Route: delegated direct (writer trigger: adapter plus tests are 2+ non-trivial files; preparation trigger). Tests cover:
  - performed with citations, not_performed and uncertain;
  - a criterion always classed "uncertain";
  - no citable items, so no network call;
  - enumeration fails closed;
  - action-group split above the size budget, with every group keeping the full conversation;
  - timeout, zero budget, transport error, HTTP error, missing or invalid answer: each fails closed;
  - patient turns are never offered as citable items.
- [x] **T2** Amend `docs/design/jev-prototype.md` for the rubric probability mapping. Route: same writer, separate commit.
- [x] **T3** Live check. The user runs `mix stations.qualify acute-appendicitis` with the key, and the rubric cases report real outcomes within the deadline. Route: run by the user; the agent never reads the key.
- [x] **T4** (TR-1) Contain crashes in TypeSafe rubric group requests: a raise, exit or throw inside a group task returns `{:error, {:technical_failure, _}}` and the caller of `JevDecision.decide_rubric_batch` stays alive. Reason: Jorge advisory review of PR #217, 2026-10-14. Route: delegated direct.
- [x] **T5** (CD-1) Cite only admissible evidence in rubric decisions: citations to real pool items that `Evidence` rejects for channel or modality reasons are dropped per action before rules apply, so they no longer turn a criterion into `{:invalid_evidence, _}`; bogus ids keep failing closed. Reason: Jorge advisory review of PR #217, 2026-10-14. Route: delegated direct.

## Acceptance criteria

- The rubric batch returns validated decisions for acute-appendicitis through `Backend.Stations.JevDecision.decide_rubric_batch`.
- Every failure path is covered by a stubbed test and fails closed.
- `mix test` and `mix compile --warnings-as-errors` pass in `backend/`.
- The qualification run reports real rubric outcomes.

## Checks

- `cd backend && mix test`
- `cd backend && mix compile --warnings-as-errors`
- `cd backend && mix format --check-formatted`

## Delivery

- Strategy `ask-on-risk`; forecast about 400-600 authored lines (adapter plus tests plus doc).
- Receipt-driven development is off for this clone (clone-local), so delivery follows ordinary repository policy.

## Progress

- 2026-10-14: exploration, decisions and live probe done; T1 starting.
- 2026-10-14: T1 done, commit `98bdb62` (`feat(stations): serve rubric batches from the TypeSafe Jev adapter`), route delegated direct. Test-first: new `backend/test/backend/stations/jev_decision/typesafe_adapter_rubric_batch_test.exs` (24 tests) plus the export test flipped in `typesafe_adapter_test.exs`. RED: `mix test test/backend/stations/jev_decision` 143/168 passed, 25 failed. GREEN: 168/168. 3 files, +764/-12 lines (527 of them tests).
- 2026-10-14: T2 done, commit `e05363c` (`docs(design): describe the TypeSafe rubric batch mapping`), route delegated direct. Amended the status line, the "TypeSafe outputs and evidence identity" section and the "No live adapter" limit; +16/-3 lines.
- Verification (backend/): `mix compile --warnings-as-errors` clean; `mix format --check-formatted` clean; `mix test test/backend/stations/jev_decision` 168 passed; `mix test` 937 passed, 0 failures.
- Implementation notes: citable items are pool items with role `learner`/`student` (atom or string), matching `Evidence`'s learner roles; the state is `learner_items` (`item` position plus text) and holds only those items; question ids are `performs:<question>.<action>:<item>`; a single action whose request alone exceeds the budget fails closed with `{:technical_failure, :rubric_request_too_large}`; `:max_request_tokens` (default 64000) is read from call options or the adapter's application env, not from `config/runtime.exs`.
- Follow-up outside the writer's surface: the parent fixed the stale TypeSafe rubric statement in `README.md` (around line 230) in commit `375d36c`.
- 2026-10-14: T3 done. The user's live run `JEV_ADAPTER=typesafe mix stations.qualify acute-appendicitis` (adapter `TypesafeAdapter`) returned no technical failure on any rubric case except `technical-failure-02`, which is designed to fail.
  - Rubric outcomes: `action:performed` 2, `action:not_performed` 2, `action:uncertain` 4, `uncertain` 5, `assessed:inadequado` 3.
  - Before this change, all 14 rubric cases reported `technical_failure`.
  - No case is adjudicated (0 of 33), so correctness is not established. No criterion reached a positive level in this run.
- 2026-10-14: merged `origin/develop` (`7fac4a2`, #213). After the merge, `mix test` passed 958 with 0 failures, and compile and format are clean. Pushed the branch and opened PR #217 to `develop` (`Closes #212`).
- 2026-10-14: Jorge advisory review of PR #217 confirmed TR-1 and CD-1; added T4 and T5.
- 2026-10-14: T4 done, commit `1f4dc9a` (`fix(stations): contain crashes in TypeSafe rubric group requests`), route delegated direct. Each group task body is wrapped (rescue, catch exit, catch throw) and returns `{:technical_failure, :adapter_crashed | :task_exit | :adapter_threw}`, the atoms the seam already uses. RED: two seam tests with a raising and an exiting `Req.Test` stub, run from a non-trapping `spawn_monitor` caller: 24/26 passed, both `{:caller_died, _}`. GREEN: `mix test test/backend/stations/jev_decision` 174 passed.
- 2026-10-14: T5 done, commit `dc03282` (`fix(stations): cite only admissible evidence in rubric decisions`), route delegated direct. `RubricAssessment` drops each sub-action citation that `Evidence.validate` rejects with `:wrong_channel` before validating the rest; `:nonexistent_evidence_id`, `:wrong_role` and `:wrong_provenance` still fail the criterion closed. Criterion-level and first-N answer citations are unchanged. A performed action left without citations follows the existing evidence-less path (`{:unsupported_sub_action, id}` for the mandatory action in the test). RED: `mix test test/backend/stations/rubric_assessment_test.exs` 99/101 passed (`{:invalid_evidence, :wrong_channel, "impresso-req-none"}` in both). GREEN: 232 passed with `test/backend/stations/rubric_assessment`.
- Verification (backend/): `mix compile --warnings-as-errors` clean; `mix format --check-formatted` clean; `mix test test/backend/stations/jev_decision` 174 passed; `mix test` 962 passed, 0 failures.
- Next: push the fixes and reply on #217 per the review feedback loop. The follow-ups are #214 and #215.
