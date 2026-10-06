# #128 Grounded rubric assessments and exact educational point estimates

Issue: https://github.com/ChordanDev/proyectoMed/issues/128 (parent #125, ADR-012 #124).
Branch: `feat/128-rubric-assessments`, stacked on PR #167 (`chore/125-sync-develop` -> `feat/125-jev-evaluation`, merge commit `fb1285f`). Branch point / first review boundary: `fb1285f`.
Engram mirror: `odd/rubric-assessments/tasks`.

## Objective and problem

`Backend.Stations.Evaluator` (#27) is a keyword heuristic that returns `met | omitted | uncertain` with flattened text evidence. It never calls Jev, ignores every v2 rubric field (`levels`, `points`, `actions`, `order`, `count_cap`, `first_n`, `veto`, `exclusion`, `modality_requirement`) and has no failure channel. #128 adds the Jev-backed evaluator that grounds each criterion in validated transcript/event evidence, applies authored rules in code, and produces exact, coverage-aware point estimates.

## Why

ADR-012 requires PEP-shaped educational estimates with explicit uncertainty: a learner must never get a number that hides unresolved criteria, float drift, or credit earned by patient text.

## Scope

In: evidence pool with stable IDs; evidence validation (existence, learner role, channel, provenance); batched Jev rubric questions; status vocabulary; deterministic post-processing; exact arithmetic; totals; technical-failure invalidation; an internal context entry point; an explicit projection to the legacy result shape.

Out (owned elsewhere): versioned HTTP result contract, web decoder and pt-BR disclaimer (#129); clinical authoring and thresholds (#130); dialogue generation, turn orchestration and `Conversation` semantics; any change to the Impressos event contract (#105-#108); a live Jev adapter.

## Constraints

- `Backend.Stations` stays the only public context interface; new modules live under `backend/lib/backend/stations/`.
- `GET .../result` keeps returning the legacy `met | omitted | uncertain` shape until #129.
- No new dependencies. Points use scaled integers in eighths.
- CI: `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`, `mix dialyzer --format short`, `bash scripts/test.sh`.
- Test-first where a deterministic test exists (all tasks below).

## Design decisions

1. **Evidence IDs are derived at evaluation time** from the completed (immutable) session, not stored: `turn-N` (1-based index in `messages`) and `impresso-<request_id>` for `impresso_requests`. `Conversation` is not changed. The pool is ordered by `at`, with message order and event `order` as tie-breakers.
2. **Channel and provenance.** A turn's channel is its `modality` (`text | voice`); an event's channel is `impressos`. Provenance is `transcript` or `impressos`; an event is valid evidence only when its `station_version` matches the package and its released IDs are authored in the package (same rule the legacy evaluator applies).
3. **Fail closed per criterion.** A nonexistent, non-learner, wrong-channel or wrong-provenance evidence ID never earns credit: the criterion becomes `uncertain` with a machine-readable reason. No evidence is substituted or aligned by text.
4. **Structural problems invalidate the attempt.** Timeout, transport error, 5xx, malformed output, a class outside the allowed set, or missing/duplicate/unknown criterion IDs in a batch return `{:error, {:invalid_attempt, reason}}`. No partial feedback.
5. **Exact points.** Authored points are multiples of 0.125 and are converted once to integer eighths (lossless: multiples of 1/8 are exact in binary floats; the conversion still rejects anything else). All sums are integers. Rendering to a decimal string is a pure function; the wire format is #129's choice.
6. **Statuses.** `assessed | uncertain | not_observable | not_applicable`. Only `assessed` carries `level` and `points`.
   - `not_applicable`: authored `exclusion: true`. Excluded from both maxima. No Jev question.
   - `not_observable`: the criterion's `modality_requirement` names a modality the station cannot provide in this session (for an Impressos category or `impressos`: the package authors no matching impresso). No Jev question. Counts toward `eligible_max` and `unresolved`.
   - `uncertain`: Jev answered `uncertain`, or evidence failed validation.
   - A modality the station does provide but the learner never used is a genuine omission: it is assessed at the authored zero-point level when Jev classifies it so.
7. **Totals.** `scored_subtotal` and `scored_max` cover assessed criteria; `eligible_max` covers every active (non-excluded) criterion; `total` equals the subtotal only when every active criterion is assessed, else `nil`. Nothing is rescaled; probability never multiplies points.
8. **Batching.** One Jev call carries every active question with the full shared evidence pool. A second call happens only for a provider capacity limit (`:max_questions_per_call`) and each call records its justification in the result.
9. **Legacy compatibility.** The legacy evaluator and endpoint are untouched. `RubricAssessment.to_legacy/1` is the explicit, tested migration projection (`assessed` at the zero level -> `omitted`, `assessed` above zero -> `met`, everything else -> `uncertain`; `not_applicable` criteria are dropped).

## Open decision (blocks T5 only)

The v2 schema authors `actions`, `order`, `count_cap`, `first_n` and `veto` as bare fields with no semantics: no count-to-level thresholds, no mandatory flag on actions, no veto effect, no meaning for `order` across criteria. T5 needs the product owner to confirm the semantics before any code is written.

## Tasks

- [x] **T1 Exact points and coverage-aware estimates.** `RubricAssessment.Points` (eighths) and `RubricAssessment.Estimates`. Route: delegated (2 non-trivial files + tests).
  - Accept: 0.125 arithmetic is exact; non-multiples are rejected; `total` is `nil` with any unresolved active criterion; subtotal / scored max / eligible max reconcile with the #126 reconciliation fixture (0.25 / 0.25 / 1.25 / nil); excluded criteria are outside both maxima.
- [x] **T2 Evidence pool and validation.** `RubricAssessment.Evidence`. Route: delegated.
  - Accept: ordered role-labelled pool with stable IDs from a session map; one learner turn may back several criteria; patient turns, unknown IDs, wrong channel and wrong-version events are rejected with distinct reasons; event provenance covered.
- [x] **T3 Batched Jev rubric decision.** `JevDecision.decide_rubric_batch/2` plus adapter callback and disabled-adapter clause. Route: delegated.
  - Accept: one call for N questions sharing one evidence pool; class and criterion-ID structure validated; technical-failure taxonomy reused; optional per-action classifications carried.
- [x] **T4 Assessment orchestration and context entry point.** `RubricAssessment.assess/3`, `Backend.Stations.assess_session/1`, `to_legacy/1`. Route: delegated.
  - Accept: statuses per decision 6; fail-closed evidence; technical failure invalidates the attempt; capacity split recorded; omission, uncertainty/missing modality and exclusion each covered by its own fixture test; legacy projection tested.
- [ ] **T5 Authored rules.** Counts and thresholds, mandatory sub-actions, chronology, first-N caps, veto. Blocked on the open decision.
- [ ] **T6 Docs.** Update `docs/design/jev-prototype.md` and `CONTEXT.md` with the implemented contract and the evidence-ID scheme.

## Checks

Per task: focused `mix test <file>`, then `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`, `mix test`. At closure: `mix dialyzer --format short` and `bash scripts/test.sh`.

## Delivery

Forecast: about 1,500 authored changed lines, over the 400-line budget. Commits are linear work units, so they can be sliced into stacked PRs against `feat/125-jev-evaluation` without rework. Chain strategy to be confirmed with the user before the first PR. RDD is off for this clone (`clone_local`); each commit is assessed with `gentle-ai review assess` and verified under ordinary policy.

## Progress

| Task | Route | Commit | Tier / review | Evidence |
|------|-------|--------|---------------|----------|
| T1 | delegated (writer trigger: 2 non-trivial modules + tests) | `43bce67` | medium, `slice_budget_reached`; RDD off, writer self-verification + parent spot check | RED 0/32 (modules missing) -> GREEN 32/32; `mix test` 473 passed; format, compile `--warnings-as-errors`, Credo strict, Dialyzer clean. Empty/all-excluded rubric yields `total: nil`. Running count: 621 lines incl. this document. |
| T2 | delegated (reading prepares the write; non-trivial module + tests) | `97f59b0` | medium, `slice_budget_reached`; RDD off, writer self-verification + parent spot check | RED 0/39 (module missing) -> GREEN 39/39; `mix test` 512 passed; format, compile, Credo strict, Dialyzer clean. An event that released nothing never counts as evidence (legacy rule); invalid events stay in the pool as `:unverified`. 770 lines: the rejection/providability matrix is 39 tests. Running count: 1,391. |
| T3 | delegated (writer trigger: 4 lib files + tests) | `8506231` | medium, `slice_budget_reached`; RDD off, writer self-verification + parent spot check (277 station tests re-run; diff to existing lib files is additive, 106+/1-) | RED 0/57 (function undefined) -> GREEN 57/57 plus 48 untouched `jev_decision_test.exs`; `mix test` 569 passed; format, compile, Credo strict, Dialyzer clean. `technical_failure?/1` already treats `{:invalid_request, _}` and `{:invalid_response, _}` as technical. Running count: 2,571 (forecast of 1,500 exceeded; test matrices dominate). |
| T4 | delegated (writer trigger: new module + context function + 2 test files) | `9ad867e` | medium, `slice_budget_reached`; RDD off, writer self-verification + parent spot check (`mix test` 606 passed re-run, format clean, `stations.ex` diff additive +35) | RED 0/37 (functions undefined) -> GREEN 37/37; Credo strict and Dialyzer clean. T5 seam: private `apply_authored_rules/2` in `rubric_assessment.ex`, identity for now, runs before the credit-grounding check. `to_legacy/1` emits impresso evidence with role `:learner` and the event text, not the legacy `:impresso` marker string. Running count: 3,947. |

## Next step

T5 waits for the product decision on rule semantics; T6 follows T5. Before the first PR: confirm the chain strategy (four linear work-unit commits so far, each above 400 lines because of test matrices).
