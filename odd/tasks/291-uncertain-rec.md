# #291 Write a real recommendation for an uncertain rubric item

Locator: `odd/tasks/291-uncertain-rec.md` · branch `fix/291-uncertain-recommendation` (from `origin/feat/237-clinician-demo-readiness`) · parent tracker #237 · Engram `odd/291-uncertain-rec/tasks`.

## Objective
An uncertain rubric item gets a recommendation written from the transcript evidence (what the learner asked and what is still missing) instead of the bare item title, and shows its evidence when it has any. Evaluated items do not change.

## Why
In the 2026-10-20 rehearsal, item 2 ("Anamnese — caracterização da dor") was uncertain and its RECOMENDAÇÃO block showed only the title. Root cause (three layers):
1. `RubricAssessment.base_result/3` drops the validated sub-actions and evidence of an uncertain criterion (`evidence: []`, `sub_actions: []`).
2. `LearnerFeedback.attach/3` only rewrites `:assessed` criteria, so an uncertain one keeps the authored `practice_recommendation`, which in the appendicitis package is the item title.
3. The web decoder (`decodeEducationalCriterion`) rejects evidence on any non-assessed criterion.

## Scope / constraints
- Allowed surfaces: `backend/lib/backend/stations.ex`, `backend/lib/backend/stations/**`, `backend/test/**`, `web/src/features/station/**`, `README.md`, `docs/**`, `odd/tasks/**`.
- Thin `BackendWeb`; logic inside `Backend.Stations` internals. No new adapters.
- Uncertain criteria stay unscored: no level, no points, estimates unchanged; task order still reads only assessed criteria.
- The uncertain recommendation is deterministic (no provider call), built from authored action descriptions; learner-facing copy in pt-BR.
- `not_observable` and `not_applicable` keep no evidence.

## Tasks
- [ ] T1 Backend assessment: an uncertain criterion whose criterion and sub-action evidence validated keeps its sub-actions and its evidence (criterion evidence plus performed actions' evidence, pool order). Route: inline (2 files: rubric_assessment.ex + its test).
- [ ] T2 Backend recommendation: `LearnerFeedback` writes a deterministic recommendation for an uncertain criterion with sub-actions ("Você investigou: …. Ainda falta investigar: …."), keeps the authored text otherwise; educational result serializes evidence for uncertain items. Route: inline.
- [ ] T3 Web: decoder accepts evidence on uncertain criteria (still rejects it on not_observable/not_applicable); ResultScreen test shows the evidence and the recommendation for an uncertain item. Route: inline.

## Acceptance
- An uncertain item renders a recommendation that is not the bare title (tested in LearnerFeedback and at the HTTP result).
- Item evidence is shown for uncertain items that have evidence (tested backend + web).
- No change for evaluated items (existing tests stay green).

## Checks
- Focused: `mix test test/backend/stations/rubric_assessment_test.exs`, `mix test test/backend/stations/learner_feedback_test.exs`, `npm --prefix web test`.
- Full: local CI script (`LOCAL CI PASSED`).

## Delivery
Forecast ~300 authored changed lines, single PR to `feat/237-clinician-demo-readiness`.

## Progress / evidence
(pending)

## Next
T1.
