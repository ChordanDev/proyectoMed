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

## Authored rule semantics (T5, resolved 2026-10-06)

The v2 schema authored `actions`, `order`, `count_cap`, `first_n` and `veto` as bare fields with no semantics. The product owner decided to define them inside #128, extending the schema and the Jev batch contract where needed. The structural reference is the official booklet ADR-012 cites, `2023_1_PEP_publicacao.pdf` (INEP, https://download.inep.gov.br/revalida/provas_e_gabaritos/2023_1_PEP_publicacao.pdf). It is a reference for the shape of the rules only; rubric content stays original. The copies under `docs/` are byte-corrupted in the committed blob (`0d27786`) and cannot be read.

What the booklet states:

- Count to level: "Adequado: pergunta quatro OU cinco itens. Parcialmente adequado: pergunta dois OU três itens. Inadequado: pergunta apenas um item" (p. 10).
- Mandatory action: "investiga três ou mais achados, incluindo obrigatoriamente o item 3 ... Inadequado: não investiga o item 3" (p. 4). A missing mandatory action scores the item at zero.
- First N: "Só serão pontuados os DEZ primeiros exames laboratoriais citados" (pp. 10-11).
- Order: a dedicated binary item, "Execução das tarefas na ordem determinada" (pp. 5, 11).
- Veto: "Caso o(a) participante indique a vacina do rotavírus, AVALIAR COMO INADEQUADO" (p. 15). It is local to the item, not to the station.
- Annulment: "(ITEM ANULADO)" (p. 46), already covered by `exclusion`.

Decisions:

10. **Schema additions are optional**, so every existing v2 package stays valid and the version does not change: `levels[].min_actions` (integer >= 0), `actions[].role` (`counted` default, `mandatory`, `forbidden`), and `rule` on a criterion (`null` default, `task_order`). `count_cap` and `first_n` must be >= 1 when set. Action IDs are unique within a criterion. If any level of a criterion sets `min_actions`, every level does, the zero-point level has 0, and thresholds do not decrease as points increase. A criterion with a `forbidden` action must set `veto: true`; `veto: true` without one has no effect. Added after independent verification of T5a: when thresholds are authored, every level with points above zero has `min_actions` >= 1, and the highest `min_actions` is reachable, so it is at most the number of non-`forbidden` actions (which requires at least one such action) and at most `count_cap` when `count_cap` is set. Otherwise a level could be earned with no action, or count in the station maximum without being earnable.
11. **Per-criterion rules**, applied in code to a criterion Jev assessed. One principle (owner decision, 2026-10-06, replacing the earlier rule 1): an unresolved action makes the criterion `uncertain` only when resolving it could change the result. In this order:
    1. A `performed` action without validated learner evidence is unresolved: it is treated like an action classified `uncertain` and keeps its own reason.
    2. A `forbidden` action that was performed, with evidence, scores the criterion at its zero-point level.
    3. A `mandatory` action that was `not_performed` scores the criterion at its zero-point level.
    4. Otherwise the criterion is `uncertain` when an unresolved action could change the level: any unresolved `forbidden` or `mandatory` action; and, when thresholds are authored, the unresolved countable (non-`forbidden`) actions only if the level computed with all of them counted as performed differs from the level computed with none of them counted, both after `count_cap`.
    5. When thresholds are authored, the level is the highest one whose `min_actions` is at most the number of performed non-forbidden actions, capped by `count_cap`. The count decides the level; Jev's criterion-level class does not.
    6. Without thresholds, Jev's level stands.

    The zeros of rules 2 and 3 are certain whatever else is unresolved, with or without thresholds. The reported reason is the first unresolved action, in authored order, among those that could change the result: `{:uncertain_sub_action, action_id}` or `{:unsupported_sub_action, action_id}`. A counted action on a criterion without thresholds never makes it `uncertain`.
12. **`first_n`**: only the learner's first N answers to the criterion are eligible, including answers that match no authored action. This needs Jev to report answer positions in the batch contract; code validates them against evidence order.
13. **Task order**: a criterion with `rule: "task_order"` is assessed in code, not by Jev, from the `order` ranks of the other criteria and the position of their earliest evidence. It is never sent to the classifier, and the batch validation still requires exactly the criteria that were asked.
    - Ranked criteria are the other active (not excluded) criteria with a non-null `order`. Equal ranks are unordered among themselves.
    - A ranked criterion is *performed* when it is assessed above its zero-point level; its position is the pool position of its earliest evidence item. Ranked criteria assessed at zero are skipped: order is judged among the steps the learner actually did.
    - The order holds when, for every pair of performed ranked criteria with rank a < rank b, the position of a is at most the position of b (one turn may back both).
    - Result: if the resolved performed criteria already show a violation, the zero-point level. Otherwise, if any ranked criterion is `uncertain` or `not_observable`, the order criterion is `uncertain` with reason `{:unresolved_ranked_criterion, criterion_id}` (the first one in rubric order). Otherwise, with at least two performed ranked criteria in order, the top level; with fewer than two, the zero-point level.
    - Its evidence is the earliest evidence item of each compared criterion, in pool order, so credit is grounded like any other criterion. With fewer than two performed criteria nothing is compared and the evidence is empty.
    - `exclusion` and `modality_requirement` on the order criterion keep their existing meaning. Totals and the legacy projection treat it like any other criterion.
    - Loader: at most one `task_order` criterion per rubric; it has no actions, no thresholds, `order: null`, `count_cap`/`first_n` null, `veto: false`, and a zero-point level; a rubric that has one needs at least two other criteria with a non-null `order`. Each violation has its own error message. `assess/3` invalidates the attempt (`:missing_zero_point_level`) for a package that skipped the loader and authors no zero-point level on it.

    Implementation notes (T5a/T5b, open to being overruled):
    - A criterion with thresholds, a `mandatory` action or a `forbidden` action must author a zero-point level. The loader rejects it otherwise, and `assess/3` invalidates the attempt (`:missing_zero_point_level`, `:inconsistent_thresholds`) for a package that skipped the loader.
    - A level earned by count still needs criterion-level evidence: sub-action evidence is not merged into the criterion evidence, so a positive level with no criterion evidence stays `:unsupported_credit`.
    - The role decides the veto in code; `veto: true` is a loader requirement only.
14. **Not implemented**: pairwise "only what was said before X counts" gates (booklet pp. 10 and 20) and verbalization requirements (p. 20). They need their own authoring fields and are recorded as a follow-up.

## Tasks

- [x] **T1 Exact points and coverage-aware estimates.** `RubricAssessment.Points` (eighths) and `RubricAssessment.Estimates`. Route: delegated (2 non-trivial files + tests).
  - Accept: 0.125 arithmetic is exact; non-multiples are rejected; `total` is `nil` with any unresolved active criterion; subtotal / scored max / eligible max reconcile with the #126 reconciliation fixture (0.25 / 0.25 / 1.25 / nil); excluded criteria are outside both maxima.
- [x] **T2 Evidence pool and validation.** `RubricAssessment.Evidence`. Route: delegated.
  - Accept: ordered role-labelled pool with stable IDs from a session map; one learner turn may back several criteria; patient turns, unknown IDs, wrong channel and wrong-version events are rejected with distinct reasons; event provenance covered.
- [x] **T3 Batched Jev rubric decision.** `JevDecision.decide_rubric_batch/2` plus adapter callback and disabled-adapter clause. Route: delegated.
  - Accept: one call for N questions sharing one evidence pool; class and criterion-ID structure validated; technical-failure taxonomy reused; optional per-action classifications carried.
- [x] **T4 Assessment orchestration and context entry point.** `RubricAssessment.assess/3`, `Backend.Stations.assess_session/1`, `to_legacy/1`. Route: delegated.
  - Accept: statuses per decision 6; fail-closed evidence; technical failure invalidates the attempt; capacity split recorded; omission, uncertainty/missing modality and exclusion each covered by its own fixture test; legacy projection tested.
- [x] **T5a Schema and loader for authored rules.** `package.schema.json`, `StationPackage` validation, fixtures. Route: delegated.
  - Accept: decision 10 enforced by the loader with a distinct error per violation; existing v2 packages and the v1 migration stay valid; one valid fixture exercises every new field.
- [x] **T5b Per-criterion rules.** `apply_authored_rules/2`. Route: delegated.
  - Accept: decision 11 in its stated order, each rule covered by its own test; a criterion without the new fields behaves exactly as before.
  - Reopened and closed again on 2026-10-06: decision 11 was rewritten around one principle (doubt matters only when it can change the outcome), with the precedence cases the independent verification found missing.
- [x] **T5c Task-order criterion.** `RubricAssessment.TaskOrder` plus the station-level pass in `rubric_assessment.ex`. Route: delegated.
  - Accept: decision 13; the criterion is never sent to Jev; unresolved ranked criteria make it `uncertain`.
- [ ] **T5d First-N answers.** Batch contract extension plus the rule. Route: delegated.
  - Accept: decision 12; positions that contradict evidence order fail closed.
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
| T5a | delegated (one writer for T5a and T5b) | `3a4f47a` | not assessed by the writer | RED 3 failed / 34 passed of 37 in `station_package_test.exs` (4 of the 7 new tests are acceptance cases that already passed) -> GREEN 37/37; `mix test` 613 passed; format, compile `--force --warnings-as-errors`, Credo strict clean. One valid fixture (`valid-package-v2-authored-rules.json`); violations are inline cases. 477 lines incl. this document. |
| T5b | delegated (same writer) | `5e242ba` | not assessed by the writer | RED 37 failed / 33 passed of 70 (module missing; one integration test already passed because sub-action evidence was validated since T4) -> GREEN 70/70; `mix test` 651 passed; format, compile, Credo strict and Dialyzer clean. New internal module `RubricAssessment.AuthoredRules`; the seam now returns `{:ok, draft} | {:uncertain, reason}` and needs no pool. No existing test changed. |
| T5a fix | delegated (bounded writer; correction from independent verification) | this commit (`fix(stations): reject unreachable authored rubric thresholds`) | not assessed by the writer | RED 2 failed / 38 passed of 40 in `station_package_test.exs` (the acceptance case for a top threshold equal to the countable actions already passed) -> GREEN 40/40; `mix test` 654 passed; format, compile `--force --warnings-as-errors`, Credo strict and Dialyzer clean. The loader rejects a positive-point level with `min_actions: 0`, a top threshold above the non-forbidden actions or above `count_cap`, and thresholds with no countable action, each with its own message. A negative `min_actions` no longer also trips the value checks. No fixture changed. `first_n` is not part of the reachability check. |
| T5b rework | delegated (one bounded writer for the T5b rework and T5c) | `56f831d` | not assessed by the writer | RED 8 failed / 73 passed of 81 in the two focused files (the six precedence and decisiveness unit cases and two integration cases) -> GREEN 81/81; `mix test` 665 passed; format, compile `--force --warnings-as-errors`, Credo strict clean. Decision 11 rewritten around one principle. Tests from `5e242ba` for the old rule 1 were updated; the vacuous "forbidden action not performed is not counted" test was deleted because a forbidden action never reaches the count observably. No test that predates `cbbfc1d` changed. |
| T5c | delegated (same writer) | this commit (`feat(stations): assess the task-order rubric criterion in code`) | not assessed by the writer | RED 18 failed / 86 passed of 104 in `station_package_test.exs` and `rubric_assessment_test.exs` (no order pass, no loader rule, no schema rule) -> GREEN 104/104; `mix test` 687 passed; format, compile `--force --warnings-as-errors`, Credo strict and Dialyzer clean. New internal module `RubricAssessment.TaskOrder`; no `jev_decision*` file changed, because the order criterion is simply never a question. The existing fixture already carried a valid task-order criterion, so no fixture changed. |

## Next step

T5d and T6. Before the first PR: confirm the chain strategy (four linear work-unit commits so far, each above 400 lines because of test matrices).

Engram mirror `odd/rubric-assessments/tasks`: pending. The last successful save predates T1; the update after T4 was refused because several runtime sessions were active on this project. Resynchronize from this file.
