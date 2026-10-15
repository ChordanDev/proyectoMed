# Issue 228: Make rubric grades match what the learner actually did

- Issue: #228 (parent #128, HITL)
- Worktree: `../proyectoMed-228`, branch `fix/228-rubric-grades-match-transcript` from `origin/develop` (`a8134ca`)
- Engram mirror: `odd/228-rubric-grades-match-transcript/tasks`

## Objective

Rubric grades follow what the learner actually did. Fewer criteria end uncertain because grading gets better context and deterministic rules, and a criterion never ends at a confident zero without proof: it stays "Incerto" instead.

## Problem and why

Two live acute-appendicitis runs (2026-10-15) graded items 2, 5, 6 and 7 against the transcript. Generated feedback (#215/#226) now explains those wrong grades to the learner. Diagnosis (read-only explorer, 2026-10-15):

1. TypeSafe rubric questions carry only the action fragment (e.g. "PCR"), without the criterion description (`jev_decision/typesafe_adapter.ex:737-779`). Middle noul values send many actions to the LLM resolver.
2. The resolver accepts `not_performed` with no evidence (`rubric_assessment/resolver.ex:281-283`) and runs gpt-4o-mini without `temperature` (`rubric_assessment/resolver/openai_adapter.ex:126-141`), so identical input flips between runs.
3. Zero-point levels need no evidence (`rubric_assessment.ex:467-473`), and the `min_actions` range collapse (`authored_rules.ex:213-219`) turns unresolved actions into a confident 0 with no cited evidence.
4. To confirm in the live check: learner turns rolled back after a patient-reply refusal (`stations.ex:274-278`) never reach grading.

No truncation of the rubric input was found (#208 caps fail closed; the 10-turn window is the patient gate only).

## Decisions (maintainer, 2026-10-15)

- Lever 1: give Jev context. Each rubric question carries the criterion description with the action.
- Lever 2: deterministic rules where no interpretation is needed. An action authored with the impresso ids it requests is `performed` when a verified impresso request in the session released one of them, citing that request, with no provider call.
- No confident zero without proof: when a criterion's only reachable level is worth 0 points and any of its `not_performed` actions came from the LLM resolver (not from Jev's all-items-low signal or a deterministic rule), the criterion is `uncertain`, not assessed. The resolver runs at `temperature: 0`.
- Forcing every action to a decision (no "uncertain" at all) was rejected: it produces confident wrong grades.

## Constraints

- Backend modular monolith (`.agents/skills/backend-phoenix-contexts/SKILL.md`); `Backend.Stations` stays the public interface.
- Station package contract changes (new optional action field) stay backward compatible and validated by the package loader.
- No Mox; hand-written doubles and `Req.Test` stubs. Never touch `.env*`.
- Generated feedback, levels-to-points mapping and Jev thresholds are out of scope.

## Forecast and delivery

- Forecast: about 850 authored changed lines (T1 ~250, T2 ~150, T3 ~300, T4 ~150). Above the 400-line budget: strategy `ask-on-risk`.
- **Delivery:** chain strategy `feature-branch-chain`, chosen by the maintainer (2026-10-15). Parent/tracker branch `fix/228-rubric-grades-match-transcript` (draft PR to `develop`, `Closes #228`). Children, each branched from the previous and PR-ed into it: `fix/228-1-regression-harness` (T1, PR to the parent), `fix/228-2-question-context` (T2), `fix/228-3-impresso-actions` (T3), `fix/228-4-no-zero-without-proof` (T4 and T5 docs).
- RDD: off (clone-local); ordinary checks only.

## Tasks

- [x] **T1** Deterministic regression harness: a fixture transcript of the run (learner turns plus impresso requests) graded through `RubricAssessment.assess` with recorded TypeSafe noul answers (`Req.Test`) and recorded resolver decisions; assertions for items 2, 5, 6 and 7 that encode today's wrong grades as the RED baseline for T2-T4. Route: delegated direct.
- [ ] **T2** Lever 1: rubric questions include the criterion description with the action description; tests on the question text and the batch cap. Route: delegated direct.
- [ ] **T3** Lever 2: optional `impresso_ids` on rubric actions (package schema, loader validation, acute-appendicitis lab and imaging actions authored), deterministic `performed` from verified releasing impresso events before any provider call; tests. Route: delegated direct.
- [ ] **T4** No confident zero without proof: resolver-only `not_performed` cannot collapse a criterion to an assessed zero-point level (it becomes `uncertain`); resolver `temperature: 0`; tests. Route: delegated direct.
- [ ] **T5** Docs and live check by the maintainer on acute-appendicitis; record rollback evidence for cause 4. Route: run by the user.

## Progress

- 2026-10-15: diagnosis done, decisions settled with the maintainer. Chain strategy chosen: feature-branch-chain. Next: T1.
- 2026-10-15: T1 done (route: delegated direct, one writer; trigger: 2+ non-trivial test files plus fixture). Commit on `fix/228-1-regression-harness`: `test(stations): reproduce issue 228 rubric grades with recorded provider answers` (SHA in git log; the document is part of that commit). Harness: `backend/test/backend/stations/rubric_assessment/issue_228_regression_test.exs` with `fixtures/issue_228_session.json` (fictional acute-appendicitis transcript, 3 releasing Impressos requests, recorded TypeSafe noul answers keyed by criterion/action/turn key, recorded resolver decisions). It runs the real `TypesafeAdapter` behind a `Req.Test` stub and a recorded resolver adapter; `Qualification.session/2` was made public (visibility only) to build the session as a live attempt would. Evidence: on unchanged grading code the baseline assertions pass, so the harness reproduces the bug: items 2, 5, 6 and 7 are assessed `inadequado` (0 points) with no evidence, resting on resolver `not_performed` without evidence plus one unanswered action each (range collapse), while the learner performed those actions in the transcript. Input completeness: every learner turn and releasing Impressos request reaches the evidence pool and the TypeSafe `learner_items`. Checks: `mix format --check-formatted` ok; `mix compile --warnings-as-errors` ok; `mix credo --strict` no issues; `mix test` 1055 passed. Next: T2 (if the question instruction shape changes, update `stub_typesafe/3`, which matches the question's `action` text exactly).
