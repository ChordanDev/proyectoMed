# Jev Decision Adapter and Patient Gate (#127)

Parent: #125; base `feat/125-jev-evaluation`; child `feat/127-jev-decision-gate`; intended PR target `feat/125-jev-evaluation`.
Issue: https://github.com/ChordanDev/proyectoMed/issues/127

## Objective and constraints

Expose a validated, typed Jev decision seam for patient verification and closed-set rubric questions. No patient text or TTS release before approval; deterministic deny precedes an exact applicable-template bypass; all other candidates need verification. Never trust learner input or rejected text as provider instructions/history. One semantic regeneration maximum, with a full recheck inside the deadline; technical errors invalidate the attempt. Provider credentials, privacy qualification and live activation remain blocked until a human reviews terms, ZDR, data minimization, logging and retention. #119–#121 own scheduling, delivery fencing, cancellation and media; #128 owns deterministic evaluation rules. Backend.Stations remains the sole public domain interface.

## Checks, routing and delivery

- TDD: off, from `openspec/config.yaml` (`strict_tdd: false`); focused backend runner `cd backend && mix test`, full runner `bash scripts/test.sh`. Tests remain required.
- RDD switch: off (session). No native review start while disabled; risk assessment determines separate verifier after delegated writes.
- Forecast: approximately 850 authored lines for #127 before integration; review budget risk high (>400). Delivery strategy: single-pr; user explicitly accepted an over-400-line exception on this child PR. Record `size:exception` in the PR and keep cohesive tests with each work unit, not code-golf for size.
- Engram mirror topic: `odd/jev-decision-gate/tasks` (pending: local Engram server incompatible with client); local file is current recovery copy.

## Tasks

- [x] T1 — Reconcile #135 into the #125 parent branch, preserving #126 package v2, then update the child branch from that parent. Route: delegated writer for conflict and test reconciliation, independent verifier after unassessable native risk (untracked task file); parent completed merge and fast-forward. Evidence: merge `582600c8a66690e78dc72585ba85407023a6e302` (first parent `2bbfe1b`, second `73ff898`); 197 backend tests passed, format and cached diff checks passed, parent spot-check 14 package tests passed. Rollback boundary: revert merge with `-m 1` on parent (without rewriting #126); child can return to branch point `2bbfe1b` only under explicit destructive-operation authorization. No push yet.
- [ ] T2 — Implement the external decision adapter contract, disabled/test-double configuration, typed and validated patient/rubric requests and outcomes, bounded context and deadlines; unit/contract tests. Route: delegated writer (multiple production/test files). Check focused tests, invalid output, timeout/5xx and privacy-safe logging.
- [ ] T3 — Implement deny-first, exact package/version/template applicability bypass and all-other-candidate verification with one bounded semantic retry, full recheck and no fabricated fallback; focused tests. Route: delegated writer (production/test files). Check groundedness, contradiction, premature disclosure, role and injection cases.
- [ ] T4 — Wire the verified/rejected/technical-failure boundary through Backend.Stations and thin HTTP boundary; contract-test no unapproved text/history/TTS and stale/cancelled decisions without taking #119–#121 scheduling/media ownership. Route: delegated writer (production/test files). Check focused and full backend/web runner, explicit runtime scenario and rollback boundary.
- [ ] T5 — Prepare delivery: inspect reviewable diff, verification evidence, parent/child PR ancestry and scope; publish PR targeting feat/125-jev-evaluation when checks pass, with no live activation claim. Route: parent coordination and delegated verification as assessed.

## Progress and evidence

- Branch created from `feat/125-jev-evaluation` at `2bbfe1be779da9dd32c3eb83e5d14ea4a15782a9`.
- User approved synchronizing the parent branch with develop to import merged #135 before implementation.
- Local `backend/priv/plts/` is pre-existing, untracked Dialyzer cache and must not be staged/deleted.
- Parent `feat/125-jev-evaluation` now integrates remote develop `73ff8985dc020be83b005ba2412bb8c67d7f5d61` in merge `582600c8a66690e78dc72585ba85407023a6e302`; child fast-forwarded to the same commit. Canonical `Backend.Stations.StationPackage` retains v2 and the legacy module delegates `migrate/1`. Three stale v1 version assertions in new #135 tests were corrected after user authorization; independent verifier observed 197 passing backend tests, format and diff checks. The #125 remote has not been updated.

## Next step

T1 is complete locally. Implement T2 (validated, disabled-by-default Jev decision seam); keep the single-PR size exception, and publish the synchronized #125 parent before opening the #127 child PR.
