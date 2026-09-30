# ODD feature: approved-template-predicates (#147)

- Issue: #147 (child of #125) — https://github.com/ChordanDev/proyectoMed/issues/147
- Branches (refined after actual slice-1 counts): `feat/147-predicate-vocabulary` → `feat/147-predicate-contract` → `feat/147-predicate-gate` (chain from `feat/125-jev-evaluation`); slice 2 `feat/147-predicate-case-state` from the gate branch.
- PR plan (feature-branch-chain, user-approved): PR A vocabulary (373/400) → `feat/125-jev-evaluation`; PR B contract (215/400) → PR A branch; PR C gate + docs (333/400) → PR B branch; slice 2 PR D → PR C branch. Parent Draft PR #142 remains the integration tracker.
- Status: SLICE 1 DELIVERED (T1+T2 complete, verified); slice 2 (T3+T4) pending.

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

- [x] T1 (delegated, writer trigger — 2+ files): Contract — DONE. Commits `fca257a` (module) + `39f13de` (contract). Evidence: `mix test test/backend/station_package_test.exs` 17 passed.
- [x] T2 (delegated, writer trigger): Evaluator + gate — DONE. Commits `fca257a`/`67ac417`. Evidence: `mix test test/backend/stations/candidate_gate_test.exs` 63 passed; `template_applicability_test.exs` 11 passed.
- [ ] T3 (slice 2, delegated): Trusted case-state projection — derive `learner_turns` from `session.messages` in `Backend.Stations.build_verify_opts/4` (and `verify_patient_reply/3` path), pass as `case_state:`; tests in `stations_test.exs` + `pre_delivery_gate_contract_test.exs`. Verify: `cd backend && mix test test/backend/stations_test.exs test/backend/stations/pre_delivery_gate_contract_test.exs`.
- [ ] T4 (parent): Docs note + full suite (`cd backend && mix test`, `bash scripts/test.sh`), work-unit commits, slice PRs A/B, issue close evidence.

## Delivery strategy

- Mode: `ask-on-risk` → resolved by user to **feature-branch-chain** (stacked slices).
- Forecast was ~700–1000; actual slice 1 = 921 authored lines (838 code + docs), so slice 1 was resliced into three sub-400 PRs at work-unit boundaries: PR A vocabulary+unit tests (373), PR B contract (215), PR C gate+tests+docs (333). Slice 2 (T3+T4) follows from the gate branch.
- Slice boundaries / PR contents: PR A = `fca257a`; PR B = `39f13de`; PR C = `67ac417` + docs commits.

## Checks / TDD

- TDD: off (source: `openspec/config.yaml` `strict_tdd: false`; tests written with implementation, not red-green).
- Runner: `cd backend && mix test`; full gate `bash scripts/test.sh`.
- Extra: `mix format`, `mix credo --strict` if configured (recent history shows Credo strict complexity limits — keep functions small).

## Verification evidence

Slice 1 (T1+T2), branch `feat/147-predicate-gate` @ `847ebcf`:

- Writer (gentle-ai-worker, self-verification): all green — station_package_test 17 passed; candidate_gate_test 63 passed; template_applicability_test 11 passed; full `mix test` 339 passed; `mix format --check-formatted` exit 0; `mix credo --strict` no issues.
- Parent spot check: candidate_gate_test re-run 63 passed; format + station_package/candidate_gate suites re-run after external reformat: 80 passed.
- Native assess: UNAVAILABLE (`unassessable`, native error) → per contract treated as high → independent verifier mandatory.
- Independent verifier (gentle-ai-verify): zero findings. `mix test` 339 passed; `mix format --check-formatted` exit 0; `mix credo --strict` no issues; `bash scripts/test.sh` exit 0 (web + backend). Code-read confirmations: fail-closed semantics (classify/1 total, no raising path), case_state-only isolation, validator/evaluator single-sourcing via shared classifier, determinism across Jev retries, negative tests pin exact error strings.
- Dialyzer (parent, CI parity): `mix dialyzer --format short` — 0 errors.
- Per-task review tier record: T1/T2 assess unavailable → treated high → outcome: independent verifier ran, zero findings.

## Progress log

- 2026-09-25: exploration delegated (gentle-ai-explore) — mapping complete, no edits. Feature doc created; user approved chained-slice delivery.
- 2026-09-25: T1+T2 delegated to gentle-ai-worker → all green (339 tests, format, credo strict). Work-unit commits `fca257a`, `39f13de`, `67ac417`; ODD doc `847ebcf`. Assess unassessable → high → gentle-ai-verify zero findings; Dialyzer 0 errors. Slice 1 resliced into 3 PRs (373/215/333 lines) and published to origin.
- Engram mirror: PENDING (Engram server down at session time; will mirror on availability).

## Next step

Slice 2 (T3): branch `feat/147-predicate-case-state` from `feat/147-predicate-gate`; delegate trusted case-state projection (`learner_turns` from `session.messages`) in `Backend.Stations.build_verify_opts/4` + `verify_patient_reply/3`, tests in `stations_test.exs` + `pre_delivery_gate_contract_test.exs`; then T4 full suite + PR D.
