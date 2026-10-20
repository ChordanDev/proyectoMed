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

- [x] T1 - Package contract: `actions[].interprets_impresso_ids` in the schema and
  `StationPackage` validation (non-empty list of authored impresso ids; not together
  with `impresso_ids` on one action), with the authoring guide row.
- [x] T2 - Assessment rule: `RubricAssessment.InterpretationEvidence` drops citations
  that are not learner turns after a release of a declared impresso, applied in
  `RubricAssessment` sub-action validation; docs in `educational-result-api.md`.
- [x] T3 - Authoring and regression: declare the dependencies on items 5, 7 and 8 of
  acute-appendicitis, document them (package mapping D23, checklist), and extend the
  #243 regression harness with the second rehearsal evidence for item 7.

## Routing

- All tasks: delegated direct (this writer is the delegated worker); inline inside it.

## Checks

- Focused: `mix test` on the touched test files per task (RED then GREEN).
- Closure: local CI script (mirrors `.github/workflows/pr-validation.yml`).
- Live rehearsal re-run: pending (no live calls in this task).

## Progress

| Task | Commit | RED | GREEN |
|---|---|---|---|
| T1 | `1dccb80` | 4/66 failing (schema field, invalid values, no impressos, both fields) | 71 passed (with the #228 `impresso_ids` tests) |
| T2 | `656c740` | 8/9 failing (module undefined; the "unaffected" test passed as expected) | 9 passed; `test/backend/stations` 842 passed |
| T3 | `6af5571` | package unauthored: 2/16 failing (package test, #265 harness case) | 16 passed; full backend 1268 passed |
| Refactor | `4cc721d` | credo `--strict`: 3 nesting findings in new test helpers | credo clean |

Decisions:

- Field name `interprets_impresso_ids`; any listed impresso's first verified release
  opens the window. An action authors at most one of `impresso_ids` and
  `interprets_impresso_ids`.
- Only learner turns count after the release; the request event itself is not
  interpretation evidence. Ties (`at` equal) sort turns before events, so a turn at the
  release instant does not count.
- A performed action whose citations are all dropped becomes `not_performed` (the
  issue's wording), not "performed without evidence".
- Criterion-level citations are not filtered (no action dependency to apply; TypeSafe
  sends none).
- Authored on item 5 `criterio-2`-`4`, item 7 `criterio-1`-`4`, item 8 `criterio-2`-`4`
  (including the mandatory hypothesis, per the issue). Flagged for clinical review in
  checklist row D23.

Checks: local CI passed (web 229 + 4 tests, backend 1271 tests, typecheck, lint,
format, compile with warnings as errors, credo strict, dialyzer 0 errors). Live
rehearsal re-run: pending.

## Next step

Push and open the PR to `feat/237-clinician-demo-readiness`; live re-run of the
rehearsal transcript stays pending.
