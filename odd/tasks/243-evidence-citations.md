# Issue 243: Keep rubric evidence citations related to the criterion they support

- Issue: #243 (parent tracker #237)
- Worktree: `../proyectoMed-worktrees/issue-243`, branch `fix/243-evidence-citations` from `origin/feat/237-clinician-demo-readiness` (`7f23f9d`)
- PR: child of #237, targets `feat/237-clinician-demo-readiness`, body `Refs #243`
- Engram mirror: `odd/243-evidence-citations/tasks`

## Objective

A rubric criterion only cites learner items that support the action they are cited for. In the 2026-10-19 live result (acute-appendicitis, 9.6/10) items 7 (lab interpretation) and 10 (antibiotic and surgical referral) both cited the opener "O que o trouxe aqui hoje? Onde começou a dor?". A level is never raised by an unrelated citation alone.

## Why

A clinician reading a result that cites the opener for lab interpretation distrusts the whole grading.

## Diagnosis

Two stages can cite an item for an action:

1. **Jev (TypeSafe batch)** asks one noul question per action and learner item and cites every item answered yes (`typesafe_adapter.ex` `action_decision/3`). The citation is tied to the item it was asked about, so a yes for the opener would be a per-item false positive of the provider.
2. **The resolver** (gpt-4o-mini behind `Resolver.OpenAIAdapter`) decides only the actions Jev left uncertain and may cite any id of the learner pool. `Resolver.apply_decision/4` checks the ids with `Evidence.validate/3`, which checks existence, role, provenance and channel, never relevance. Nothing ties a resolver citation to Jev's per-item answers, so it can cite an item Jev clearly answered "no" for that action.

The live provider logs for the 2026-10-19 run are not available (no keys in this environment), so the stage cannot be proven. Only the resolver path is unconstrained by construction; the fix closes it at the shared boundary (the resolver merge). A Jev per-item yes for the opener cannot be ruled out deterministically and would need the live noul answers.

## Constraints

- Keep the #228 evidence-only grading contract: credit only with validated learner evidence; resolver `not_performed` never grounds a zero alone.
- Allowed edit surfaces: `rubric_assessment.ex`, `rubric_assessment/**`, `jev_decision/typesafe_adapter.ex`, `backend/test/**`, `docs/**`, this file. `RubricBatch` (which normalizes action decisions to `id`, `classification`, `evidence_ids`) is out of scope, so the candidate items travel in the existing `evidence_ids` field of an uncertain action.
- No Mox; `Req.Test` stubs and recorded doubles.

## Design

- TypeSafe: an `uncertain` action carries in `evidence_ids` the items Jev left undecided for it (never the items it answered no). `performed` and `not_performed` are unchanged.
- Resolver merge: a `performed` decision keeps only the cited ids that the uncertain action offered as candidates (when it offered any); unrelated citations are dropped, and an action left with no supported citation stays `uncertain`. An uncertain action with no candidates (other adapters) keeps the previous behaviour.
- Candidate ids are consumed by the resolver and never reported: every action still `uncertain` after the resolver step carries no evidence.

## Tasks

- [x] **T1** Resolver citations must be among the items Jev left undecided for that action; TypeSafe exposes them; candidates never reported. Unit tests (adapter, resolver). Route: inline (parent context already holds the three modules; writer trigger is about delegating parent work, this agent is the bounded writer).
- [ ] **T2** Regression case from the 2026-10-19 transcript in the #228-style harness: items 7 and 10 do not cite the opener and keep `adequado`; a resolver citing only the opener does not raise a level. Docs (`docs/educational-result-api.md`). Route: inline.

## Checks

- Focused: `mix test test/backend/stations/rubric_assessment test/backend/stations/jev_decision`.
- Closure: local CI script (`LOCAL CI PASSED`), mirrors `.github/workflows/pr-validation.yml`.

## Progress

- 2026-10-19: issue read, diagnosis recorded above. Next: T1 (RED first).
- 2026-10-19: T1 done (route: inline). TypeSafe `action_decision/3` gives an uncertain action its undecided items as `evidence_ids`; `Resolver.apply_decision/4` keeps only cited ids among those candidates (all valid ids when there are none) and leaves the action uncertain when none remain; `Resolver.resolve/4` clears the evidence of every action still uncertain, also on a resolver failure. Test-first: RED 5 failing of 57 in `resolver_test.exs` + `typesafe_adapter_rubric_batch_test.exs`, GREEN 57/57. `mix test test/backend/stations` 798 passed; `mix format`, `mix compile --warnings-as-errors`, `mix credo --strict` clean. Commit: see T2 entry (SHA recorded after commit). Next: T2.
