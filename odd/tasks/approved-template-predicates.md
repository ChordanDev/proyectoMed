# ODD feature: approved-template-predicates (#147)

- Issue: #147 (child of #125) — https://github.com/ChordanDev/proyectoMed/issues/147
- Branches: slice 1 `feat/147-template-predicate-contract` (from `feat/125-jev-evaluation`); slice 2 `feat/147-template-predicate-case-state` (from slice 1).
- PR plan (feature-branch-chain, user-approved): PR A slice 1 → `feat/125-jev-evaluation`; PR B slice 2 → slice 1 branch.
- Status: IN PROGRESS.

## Objective

Replace free-form prose `approved_templates[].applicability` (Package v2, #126) with structured, machine-evaluable predicates. A byte-matching candidate whose predicate evaluates `true` against trusted case state bypasses Jev verification (Approved Generic Reply bypass). False, malformed, missing, or unrecognized predicates fail closed and route to Jev per ADR-011 (#123).

## Problem / why

Prose applicability cannot be evaluated deterministically. Today the gate already fails closed on prose (`:unexecutable_prose_applicability` → Jev), so approved templates with prose can never bypass. A structured vocabulary lets authored templates bypass safely while every uncertain case still routes to Jev.

## Scope (from exploration, 2026-09-25)

- Contract: `backend/priv/stations/package.schema.json` (documentation-only; `StationLoader` enforces via `Backend.Stations.StationPackage.validate/1`), `backend/lib/backend/stations/station_package.ex` (`validate_approved_templates/2`).
- Gate: `backend/lib/backend/stations/candidate_gate.ex` (`check_template_applicability/2`, bypass vs `verify_with_jev/5`, recheck at `recheck_candidate_dispatch`).
- Trusted state available today: package data + session message roles (`Conversation.session()` messages: role/modality/text/at). NO persisted revealed-facts state, NO action tracking (Impressos stub), NO stage/turn counter field. Learner message text is untrusted; only role counts are trusted derivations.
- Tests: `backend/test/backend/station_package_test.exs`, `backend/test/backend/stations/candidate_gate_test.exs`, `backend/test/backend/stations/pre_delivery_gate_contract_test.exs`, `backend/test/backend/stations_test.exs`.
- Fixtures: only `backend/priv/stations/fixtures/valid-package-v2.json` declares templates (both prose today).

## Decisions

1. **Strict load-time validation.** Validator admits only structured predicate maps; prose strings, booleans, and missing applicability are load errors. Rationale: AC says the validator "rejects invalid expressions"; `StationLoader` crash-loudly philosophy. Runtime keeps fail-closed handling as defense in depth.
2. **Predicate vocabulary v1** (grounded only in trusted derivable state): `{"type":"unconditional"}`, `{"type":"first_learner_turn"}`, `{"type":"min_learner_turns","count":n}`, `{"type":"max_learner_turns","count":n}` (count integer ≥ 1). No composition (`all_of`/`any_of`) in v1; no `fact_revealed`/`action_requested` (state not persisted). Unknown type at runtime evaluates false → Jev, never raises.
3. **Runtime legacy literals preserved** (`"unconditional"` string, `true`, `{"type"=>"unconditional"}` map) as deterministic defense-in-depth; load-time admits only structured maps. `opts[:predicate_evaluator]` test escape hatch keeps precedence.
4. **Package version stays 2.0.0** — evolve v2 in place on this unreleased parent branch; no v3 bump.
5. **Case state is projected once per turn** by the caller (trusted `%{learner_turns: n}` etc.) and passed via opts, so bypass cannot flip between Jev retry attempts.

## Tasks

- [ ] T1 (delegated, writer trigger — 2+ files): Contract — schema `$defs` structured predicate for `approvedTemplate.applicability`; validator strict structural validation with distinct error messages; update `valid-package-v2.json` (opening template → `min_learner_turns: 1`; safety template → `unconditional`, the only honest deterministic mapping); add invalid fixtures + `station_package_test.exs` positive/negative/schema-shape cases. Verify: `cd backend && mix test test/backend/station_package_test.exs`.
- [ ] T2 (delegated, writer trigger): Evaluator + gate — new internal module `backend/lib/backend/stations/template_applicability.ex` (pure, deterministic, fail-closed, string-key tolerant); rewire `check_template_applicability/2` preserving precedence (`predicate_evaluator` → embedded fn → structured map → legacy literals → fail-closed errors → Jev); extend `candidate_gate_test.exs` for every predicate type true/false + unknown/malformed/missing → Jev. Verify: `cd backend && mix test test/backend/stations/candidate_gate_test.exs`.
- [ ] T3 (slice 2, delegated): Trusted case-state projection — derive `learner_turns` from `session.messages` in `Backend.Stations.build_verify_opts/4` (and `verify_patient_reply/3` path), pass as `case_state:`; tests in `stations_test.exs` + `pre_delivery_gate_contract_test.exs`. Verify: `cd backend && mix test test/backend/stations_test.exs test/backend/stations/pre_delivery_gate_contract_test.exs`.
- [ ] T4 (parent): Docs note + full suite (`cd backend && mix test`, `bash scripts/test.sh`), work-unit commits, slice PRs A/B, issue close evidence.

## Delivery strategy

- Mode: `ask-on-risk` → resolved by user to **feature-branch-chain** (stacked slices).
- Forecast: ~700–1000 authored lines total. Slice A = T1+T2; Slice B = T3+T4.
- Slice boundaries / PR contents: PR A (branch `feat/147-template-predicate-contract`): contract + evaluator/gate commits. PR B (branch `feat/147-template-predicate-case-state`): case-state plumbing + docs, targets PR A branch.

## Checks / TDD

- TDD: off (source: `openspec/config.yaml` `strict_tdd: false`; tests written with implementation, not red-green).
- Runner: `cd backend && mix test`; full gate `bash scripts/test.sh`.
- Extra: `mix format`, `mix credo --strict` if configured (recent history shows Credo strict complexity limits — keep functions small).

## Verification evidence

- (pending T1/T2 worker report)

## Progress log

- 2026-09-25: exploration delegated (gentle-ai-explore) — mapping complete, no edits. Feature doc created; user approved chained-slice delivery. Branch `feat/147-template-predicate-contract` created from `feat/125-jev-evaluation`.
- Engram mirror: PENDING (Engram server down at session time; will mirror on availability).

## Next step

Launch bounded writer for T1+T2 (slice 1) with allowed edit surfaces below; parent commits each work unit.
