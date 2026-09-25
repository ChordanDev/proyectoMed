# Jev Decision Adapter and Patient Gate (#127)

Parent: #125; base `feat/125-jev-evaluation`; child `feat/127-jev-decision-gate`; intended PR target `feat/125-jev-evaluation`.
Issue: https://github.com/ChordanDev/proyectoMed/issues/127

## Objective and constraints

Expose a validated, typed Jev decision seam for patient verification and closed-set rubric questions. No patient text or TTS release before approval; deterministic deny precedes an exact applicable-template bypass; all other candidates need verification. Never trust learner input or rejected text as provider instructions/history. One semantic regeneration maximum, with a full recheck inside the deadline; technical errors invalidate the attempt. Provider credentials, privacy qualification and live activation remain blocked until a human reviews terms, ZDR, data minimization, logging and retention. #119–#121 own scheduling, delivery fencing, cancellation and media; #128 owns deterministic evaluation rules. Backend.Stations remains the sole public domain interface.

## Checks, routing and delivery

- TDD: off, from `openspec/config.yaml` (`strict_tdd: false`); focused backend runner `cd backend && mix test`, full runner `bash scripts/test.sh`. Tests remain required.
- RDD switch: off (session). No native review start while disabled; risk assessment determines separate verifier after delegated writes.
- Running authored lines from work-unit commits: 4,385 additions + deletions (T2: 1,931; T3: 1,448; T4: 1,006). Recorded `size:exception` on single PR.
- Child PR opened: #148 (feat/127-jev-decision-gate -> feat/125-jev-evaluation).
- Parent draft PR #142 (feat/125-jev-evaluation -> develop) is now conflict-free and mergeable.
- Follow-up issue created: #147 (`Implement structured deterministic package/state predicates for Approved Generic Reply bypass`).
- Engram mirror topic: `odd/jev-decision-gate/tasks` (pending: local Engram server incompatible with client); local file is current recovery copy.

## Tasks

- [x] T1 — Reconcile #135 into the #125 parent branch, preserving #126 package v2, then update the child branch from that parent. Route: delegated writer for conflict and test reconciliation, independent verifier after unassessable native risk (untracked task file); parent completed merge and fast-forward. Evidence: merge `582600c8a66690e78dc72585ba85407023a6e302` (first parent `2bbfe1b`, second `73ff898`); 197 backend tests passed, format and cached diff checks passed, parent spot-check 14 package tests passed. Rollback boundary: revert merge with `-m 1` on parent (without rewriting #126); child can return to branch point `2bbfe1b` only under explicit destructive-operation authorization. No push yet.
- [x] T2 — Implement the external decision adapter contract, disabled/test-double configuration, typed and validated patient/rubric requests and outcomes, bounded context and deadlines; unit/contract tests. Route: delegated writer, one independent high-consequence assumption challenge and correction, independent verifier (risk assessment unassessable, RDD off). Commit `25d15a01557dccf61bc3d415193763c032288362` (1,931 authored lines); 47 focused / 244 backend tests passed, format and cached diff checks passed, parent spot-check 47 focused tests passed. Runtime harness N/A because the adapter is disabled and no live provider may be invoked; rollback boundary is the five changed files in this work-unit commit.
- [x] T3 — Implement deny-first, exact package/version/template applicability check (failing closed on unexecutable prose applicability by routing through Jev per Option B; positive structured predicate bypass tracked in #147) and all-other-candidate verification with one bounded semantic retry, full recheck and no fabricated fallback; focused tests. Route: delegated writer, independent verifier. Commit `887dbb675fdeb15bc55c08f72f78ba5240eb28a6` (1,448 authored lines); 53 focused / 297 backend tests passed, format and diff checks passed, parent spot-check 53 focused tests passed. Option B implemented: prose applicability never bypasses Jev; positive structured predicate bypass deferred to follow-up issue #147. Rollback boundary: the three changed files in commit `887dbb6`.
- [x] T4 — Wire the verified/rejected/technical-failure boundary through Backend.Stations and thin HTTP boundary; contract-test no unapproved text/history/TTS and stale/cancelled decisions without taking #119–#121 scheduling/media ownership. Route: delegated writer, independent verifier. Commit `dbfcfa1fd729d539bc15b8359cd2016ebd41a0e8` (1,006 authored lines); 15 pre-delivery contract / 312 backend / 23 web tests passed, format and diff checks passed, parent spot-check 15 contract tests passed. Rollback boundary: the five changed files in commit `dbfcfa1`.
- [x] T5 — Prepare delivery: inspect reviewable diff, verification evidence, parent/child PR ancestry and scope; publish PR targeting feat/125-jev-evaluation when checks pass, with no live activation claim. Route: parent coordination and delegated verification as assessed. Evidence: parent `feat/125-jev-evaluation` updated and pushed to origin (resolving conflicts on draft PR #142 to develop); child `feat/127-jev-decision-gate` pushed and PR #148 opened targeting `feat/125-jev-evaluation` (Refs #127). All 312 backend and 23 web tests pass. Single PR `size:exception` documented.
- [x] T6 — Address review findings from Jorge el Curioso: resolve stale used_facts retention on candidate regeneration in CandidateGate and Backend.Stations, catch :throw in JevDecision.run_with_deadline, and add regression tests. Route: surgical fix under ODD discipline, independent verifier. Commit `bf0ff1018c6ea317fc1e2337d1cf4ce10e828e35` (117 authored lines); 129 focused / 316 backend / 23 web tests passed, compile and format checks clean. Rollback boundary: the 6 changed code/test files.

## Progress and evidence

- Branch created from `feat/125-jev-evaluation` at `2bbfe1be779da9dd32c3eb83e5d14ea4a15782a9`.
- User approved synchronizing the parent branch with develop to import merged #135 before implementation.
- Local `backend/priv/plts/` is pre-existing, untracked Dialyzer cache and must not be staged/deleted.
- Parent `feat/125-jev-evaluation` now integrates remote develop `73ff8985dc020be83b005ba2412bb8c67d7f5d61` in merge `582600c8a66690e78dc72585ba85407023a6e302`; child fast-forwarded to the same commit. Canonical `Backend.Stations.StationPackage` retains v2 and the legacy module delegates `migrate/1`. Three stale v1 version assertions in new #135 tests were corrected after user authorization; independent verifier observed 197 passing backend tests, format and diff checks. The #125 remote has not been updated.

## Next step

Create work-unit commit on `feat/127-jev-decision-gate`, push if authorized, and comment on PR #148 with the finding reference, commit SHA, solution summary, and verification evidence per review feedback protocol.
