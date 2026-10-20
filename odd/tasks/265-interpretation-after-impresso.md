# 265 - Interpretation evidence only after the impresso was released

Issue: #265 (parent #237). Branch: `fix/265-interpretation-after-impresso`, based on
`feat/237-clinician-demo-readiness`.

## Objective

A learner cannot interpret an exam before receiving it. Interpretation actions accept
as evidence only learner turns sent after the impresso they interpret was released in
the session.

## Why

In the 2026-10-19 rehearsal (9.6/10), item 7 (lab interpretation) was graded at the
right level but cited the opener "O que o trouxe aqui hoje? Onde começou a dor?" and the
exam-authorization turn, both sent before any lab impresso was released. #243 restricted
the resolver's citations to the items Jev left open; a TypeSafe Jev "yes" on an
unrelated turn is not filtered, and this run shows Jev is the source.

## Scope and constraints

- Rubric actions declare the impressos they interpret with an optional
  `interprets_impresso_ids` list, in the `impresso_ids` style from #228, validated
  against the authored impressos.
- The rule is deterministic, with no extra model call, applied at the shared evidence
  boundary in `RubricAssessment` (per-action citations after the resolver merged its
  answers), so it covers Jev's and the resolver's citations alike.
- Ordering comes from the evidence pool, which is already built in session order
  (`at`, turns before events on a tie). No new wall-clock comparison.
- A citation that fails the rule is dropped. A performed action left with no citation
  is `not_performed`; the level comes from the authored rules as today. An earlier turn
  never raises a level.
- Keep the #228 evidence-only grading contract and the #243 rule.
- `acute-appendicitis/package.json`: touch only the rubric section (#264 edits
  `revealable_facts` in parallel).
- No live calls; the live check stays pending.

## Checklist

- [ ] T1 - Package contract: `actions[].interprets_impresso_ids` in the schema and
  `StationPackage` validation (non-empty list of authored impresso ids; not together
  with `impresso_ids` on one action), with the authoring guide row.
- [ ] T2 - Assessment rule: `RubricAssessment.InterpretationEvidence` drops citations
  that are not learner turns after a release of a declared impresso, applied in
  `RubricAssessment` sub-action validation; docs in `educational-result-api.md`.
- [ ] T3 - Authoring and regression: declare the dependencies on items 5, 7 and 8 of
  acute-appendicitis, document them (package mapping D22, checklist), and extend the
  #243 regression harness with the second rehearsal evidence for item 7.

## Routing

- All tasks: delegated direct (this writer is the delegated worker); inline inside it.

## Checks

- Focused: `mix test` on the touched test files per task (RED then GREEN).
- Closure: local CI script (mirrors `.github/workflows/pr-validation.yml`).
- Live rehearsal re-run: pending (no live calls in this task).

## Progress

(updated per task)

## Next step

T1.
