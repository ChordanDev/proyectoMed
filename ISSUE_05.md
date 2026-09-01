## Parent

Part of #22

## What to build

A `Backend.Evaluator` module that, given the Station Package and the final transcript, produces the per-criterion feedback. Each criterion is reported as `met`, `omitted`, or `uncertain` with the transcript excerpts that justify the decision. There is no global readiness score and no pass/fail language.

## Acceptance criteria

- [ ] `Backend.Evaluator.evaluate/2` returns `%{criteria: [%{id, status, evidence: [excerpts], recommendation}]}`.
- [ ] `evidence` is a list of transcript excerpts (role, text) that grounded the decision. Empty for `omitted` criteria.
- [ ] `uncertain` is used when the evidence is ambiguous; the `recommendation` field still offers what to practice next.
- [ ] No global score, no readiness verdict, no Revalida-readiness claim appears anywhere in the output.
- [ ] ExUnit coverage: `Backend.EvaluatorTest` covers a fully-met station, a partially-omitted station, an uncertain criterion, and a transcript with no evidence for a criterion.
- [ ] `bash scripts/test.sh` exits 0.

## Blocked by

- #25 (Conversation ETS)
