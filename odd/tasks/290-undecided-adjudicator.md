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
- [x] T3 `CandidateGate` routes `low_confidence` through the adjudicator under the hard limits (first candidate and recheck; text and voice share the path) (RED→GREEN) — commit recorded in T4
  - RED: 4 of 9 failing in `candidate_gate_adjudication_test.exs` (the 5 passing ones assert today's path is kept). GREEN: 9 passed; full `mix test` 1642 passed; warnings-as-errors and `credo --strict` clean.
- [ ] T4 Design doc in `docs/design/`, README configuration rows, ADR-011 amendment draft, live check

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

## Next step
T4.
