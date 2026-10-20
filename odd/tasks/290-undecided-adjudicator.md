# #290 Adjudicate undecided Jev verdicts with a small Claude model

Parent: #237. Branch `feat/290-undecided-adjudicator` (from `origin/feat/237-clinician-demo-readiness`, 6f84232).
Design source: the 2026-10-20 decision comment on #290 (supersedes the options in the body). ADR-011 (#123) is amended; the proposed amendment text is drafted outside the repository and recorded in `docs/design/undecided-adjudicator.md`.

## Objective
A `low_confidence` Jev verdict (any undecided label) is no longer an automatic refusal: one call to a small Claude model (`ANTHROPIC_ADJUDICATOR_MODEL`, default `claude-haiku-5-5`) decides `deliver`, `regenerate` (with withheld fact ids) or `refuse`, with Jev's scores as evidence. Clear verdicts stay deterministic.

## Why
"Toma algum remédio?" was refused twice in the 2026-10-20 rehearsal (`undecided_other`): a broad question matches several narrow negative facts and Jev cannot tell whether it "asks" each one. Hand-tuning facts per station does not scale.

## Constraints (hard limits)
- BoundedReply deterministic checks run first; the adjudicator never delivers a candidate they reject.
- The adjudicator never delivers a fact whose Jev `fact_asked` label is a clear no (its `deliver` becomes `regenerate` withholding those facts).
- The adjudicator is a separate model call from the patient generator; Jev stays mandatory and independent for clear outcomes.
- Learner text is untrusted data inside the prompt. Structured output (JSON schema); malformed output, timeout or error = `refuse`, which is today's behaviour.
- The call runs inside the existing bounded verification deadline (3 s shared by Jev, the single regeneration and its recheck), capped by its own configurable deadline.
- Logs carry only the outcome and latency, never text or fact ids.

## Tasks
- [x] T1 Jev verdict carries the undecided labels with their scores and the clear-no "asked" facts; `JevDecision` passes them through (RED→GREEN) — `45b3618`
  - RED: 9 failing in `jev_decision_test.exs` + `typesafe_adapter_test.exs` (163 run). GREEN: 163 passed; full `mix test` 1607 passed.
- [x] T2 `PatientAdjudicator` seam: behaviour, disabled and Anthropic adapters, output validation, deadline, logging; `AnthropicClient` Haiku 5.5 support; configuration (RED→GREEN) — `4bc040c`
  - RED: 25 of 46 failing (module undefined, Haiku body/header, runtime config). GREEN: 46 passed; `mix compile --warnings-as-errors` and `mix credo --strict` clean.
  - Haiku 5.5 facts (claude-api skill): no server-side fallback (omit `fallbacks` and the beta), `thinking: disabled` accepted at effort `high` or below, effort default `medium` (we send `low`), 512-token cache minimum (the system prompt may sit below it and then silently does not cache).
- [x] T3 `CandidateGate` routes `low_confidence` through the adjudicator under the hard limits (first candidate and recheck; text and voice share the path) (RED→GREEN) — `46a7a98`
  - RED: 4 of 9 failing in `candidate_gate_adjudication_test.exs` (the 5 passing ones assert today's path is kept). GREEN: 9 passed; full `mix test` 1642 passed; warnings-as-errors and `credo --strict` clean.
- [x] T4 Design doc in `docs/design/`, README configuration rows, ADR-011 amendment draft, live check — this commit
  - No runnable RED for docs; the measured latency changed the default deadline from 1500 ms to 2000 ms (tests re-run green).
  - Live check: two runs of the 10-turn replay. Run 2 (2000 ms): turns 1-8 and 10 answered; turn 9 "Toma algum remédio?" refused (adjudicator `deliver` in 1.0 s, hard limit `not_asked` on `pergunta-explicita-02` (`fact_asked` 0.19) turned it into `regenerate`; the recheck had about 0.2 s and timed out). Run 1 (1500 ms): turn 1 also refused after an adjudication timeout.

- [x] T5 Prevention (PR #299 follow-up): the patient prompt lists the facts that require an explicit question, derived from package data (RED→GREEN) — `608c9c7`
  - `StationAI.explicit_question_fact?/1`: authored `requires_explicit_question` boolean, else topic "perguntar explicitamente"/"pergunta explícita", else id prefix `pergunta-explicita`. New stable section "FATOS QUE SÓ PODEM SER DITOS COM PERGUNTA EXPLÍCITA" (absent without such facts).
  - RED: 3 failing in `station_ai_test.exs`. GREEN: 15 passed.
- [x] T6 Adjudicator never withholds asked facts; extended budget only after a `regenerate` adjudication; config (RED→GREEN) — `d2a6fe8`
  - `asked_fact_ids` (clear-yes `fact_asked`) on low-confidence verdicts, validated in `JevDecision`; dropped from `withheld_fact_ids`; prompt rule "never list a fact that answers the latest learner message"; per-fact `requires_explicit_question` in the request.
  - `PATIENT_ADJUDICATOR_REGENERATION_EXTENSION_MS` (default 1500, non-negative integer, else default) extends the deadline on the `{:regenerate, ids}` path only.
  - RED: 15 of 224 failing across the 7 touched test files (3 of them T5). GREEN: 224 passed; full `mix test` 1652 passed; `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict` clean.
- [x] T7 Live check after T5/T6 and docs — this commit
  - Runs 3 and 4: turns 1-8 and 10 answered (1.6-5.0 s); turn 9 "Toma algum remédio?" refused both times (6.9 s, 6.2 s). The patient no longer volunteers antibiotics; the candidate is a generic "Não tomo remédio regularmente". Jev keeps `fact_stated(pergunta-explicita-02)` 0.31-0.32 with a clear-no `fact_asked`, so the unchanged hard limit converts Haiku's `deliver` into `regenerate`; the recheck's adjudication timed out (1140 ms, 1823 ms). In run 4 the recheck had no not-asked fact, so only the adjudication latency blocked it.

- [x] T8 Product decision (PR #299): the not-asked hard limit applies only when `fact_stated` is a clear yes; Haiku reads per-fact scores (RED→GREEN) — `0bb89be`
  - TypesafeAdapter adds `stated_not_asked_fact_ids` (stated clear yes, asked clear no) and `fact_scores` (stated/asked per fact not clearly unstated); `JevDecision` validates both (unknown ids are invalid; malformed scores are dropped). `PatientAdjudicator` blocks only `stated_not_asked_fact_ids`; BoundedReply still re-checks every deliver.
  - RED: 8 of 201 failing across the 5 touched test files: (a) stated 0.31 + asked 0.19 + deliver → delivered, at both the adjudicator and the gate; (b) stated 0.9 + asked 0.19 + deliver → regenerate already passed, which is the unchanged behaviour. GREEN: 201 passed; full `mix test` 1656 passed; format, warnings-as-errors and `credo --strict` clean.
  - Live runs 5 and 6: turn 9 answered both times (4307 ms, 3799 ms; Haiku deliver 1326/1862 ms; `pergunta-explicita-02` stated 0.30/0.33, asked 0.14/0.17). Turn 10 answered (2745, 2231 ms). Run 6 turn 1 refused (out-of-role 0.67, Haiku refuse, then the 3 s budget ran out on the regeneration).

## Routing
All tasks: delegated direct (this worker is the single bounded writer). Mapping done in-session with CodeGraph-free targeted reads (codegraph index initialised for the worktree).

## Checks
- Runner: `cd backend && mix test <file>` per task; `mix test` and the local CI script at closure.
- Local CI: `local_ci.sh <worktree>` must print `LOCAL CI PASSED` (GitHub Actions blocked by billing).

## Progress
- Feature document created.
- T1 done: `TypesafeAdapter.put_adjudication_evidence/5` adds `undecided_labels` (question, fact_id or rule, score rounded to 3 decimals) and `not_asked_fact_ids` to low-confidence verdicts only; `JevDecision` validates them (malformed labels dropped, unknown not-asked ids are an invalid response like the other id lists).
- T2 done: `Backend.Stations.PatientAdjudicator` (+ `DisabledAdapter`, `AnthropicAdapter`), `AnthropicClient` `:adjudicator_model` and Haiku handling, `config.exs` defaults, `runtime.exs` `ANTHROPIC_ADJUDICATOR_MODEL`, `PATIENT_ADJUDICATOR=off`, `PATIENT_ADJUDICATOR_DEADLINE_MS`.

- T3 done: `CandidateGate` sends each `:low_confidence` decision (first candidate and recheck) to `PatientAdjudicator`; deliver delivers, regenerate uses the single regeneration with the adjudicator's ids, anything else keeps today's path. Voice sentences go through the same `verify_candidate/3`, so index > 0 (`can_retry?: false`) can only deliver or refuse.

- T4 done: `docs/design/undecided-adjudicator.md` (decision, limits, latency table, live check, trade-offs, follow-ups, proposed ADR-011 amendment), README rows, amendment draft outside the repository.

## Open concerns
- Resolved by T8: "Toma algum remédio?" is answered live (runs 5 and 6).
- An adjudicator `refuse` keeps the plain 3 s budget, so its regeneration seldom fits (run 6 turn 1, out-of-role 0.67). Extending it too would need a product decision.
- Even with 4.5 s, the recheck's adjudication (Haiku 1.0-1.9 s) can time out after Jev + adjudication + regeneration + recheck (about 2.6-3.3 s).
- The voice worker's default transcript timeout (35 s) has 2 s of headroom over a 3 s verification budget; the 1.5 s extension uses most of it in the worst case (voice-worker is outside this change).

- T5-T7 done (PR #299 follow-up): prevention in the patient prompt, asked facts never withheld, extended regeneration budget, live runs 3 and 4 recorded in the design doc.

- T8 done: amended hard limit, per-fact scores for Haiku, live runs 5 and 6.

## Next step
Review of PR #299; product decision on whether an adjudicator `refuse` also gets the extended budget.
