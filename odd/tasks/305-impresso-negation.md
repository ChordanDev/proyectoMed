# 305 — Do not release an impresso the learner names only to decline it

Issue: #305 (parent #237). Branch: `fix/305-impresso-negation` from `feat/237-clinician-demo-readiness`.

## Objective

`Impressos.match/2` ignores a keyword occurrence governed by a Portuguese negation
cue in the same clause, so "não preciso do ECG" neither releases the ECG impresso
(modal or examiner turn) nor records an impresso event the rubric would credit.

## Why

Since #302 an examiner-addressed turn releases every impresso whose keyword appears
in the learner text. A declined exam ("sem necessidade de tomografia") was released
and credited by the rubric.

## Constraints

- Deterministic, no LLM (ADR-008 and its #302 amendment).
- Accent/case-insensitive, word-start anchored matching unchanged.
- Non-negated matching across authored packages unchanged.
- Edit surface: `backend/lib/backend/stations/impressos.ex`, `backend/test/**`, `docs/design/**`.

## Checklist

- [x] T1 — Negation-aware clause matching in `Impressos.match/2` with unit tests for
  every issue example; examiner voice turn "não preciso do ECG" records nothing and the
  rubric does not credit it; design doc note. Route: inline (one source file, one
  understood change). Checks: `mix test` (focused, then full via local CI).

## Checks

- Focused: `mix test test/backend/stations/impressos_test.exs test/backend/stations/turn_addressee_test.exs test/backend/stations/impresso_phrasings_test.exs`
- Full: local CI script (mirrors `.github/workflows/pr-validation.yml`).

## Progress

- Worktree and feature document created.
- T1 done (commit b295a1a).
  - RED: 8 new tests failed (6 in `impressos_test.exs`, 2 in `turn_addressee_test.exs`).
  - GREEN: focused 91 passed (impressos, turn addressee, phrasings);
    `mix compile --force --warnings-as-errors` clean.
  - Local CI passed: backend 1692 passed; web 337 passed (16 files); 4 passed (1 file).

## Next step

Open the PR to `feat/237-clinician-demo-readiness`.
