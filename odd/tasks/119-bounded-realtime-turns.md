# #119 Bounded real-time station turns

## Objective and problem
A final Deepgram utterance already commits one learner voice message through the authenticated worker API (#118), but does not generate or deliver a safe patient reply. Make that turn idempotent and ordered, attach a session-scoped generation identity, and reject late results after cancellation, supersession, completion, or expiry. The role-labelled ephemeral transcript must remain the evaluator's input and follow the existing lifecycle.

## Scope and constraints
- Base: `origin/feat/116-realtime-voice` at `80c4353`; feature branch `feat/119-bounded-realtime-turns`, worktree `../proyectoMed-119`. Child PR, if requested, targets `feat/116-realtime-voice`.
- Keep `Backend.Stations` the only public context entry for BackendWeb and worker-facing HTTP. Reuse StationAI, BoundedReply, the package safety rules, and the existing verification seam; fail closed on unsafe or stale results. Do not send unverified text to synthesis.
- Do not persist/log audio, raw provider payloads, or transcript content in the worker. No new UI, TTS provider, or speculative context.
- Preserve existing #118 duplicate-final response compatibility where possible; every response with a patient reply must be generation-bound and safe.
- Tests and technical artifacts in English. No push/PR without user decision.

## Acceptance and checks
- Final `(session, turn_id)` accepted at most once in monotonic turn order; transcript remains ephemeral and evaluator-visible.
- Generation identities and cancellation/supersession prevent late replies from being appended or delivered.
- Voice delivery verifies bounded reply and authorized facts/refusal through existing StationAI boundary; no patient content on failure.
- Integration tests cover duplicate finals, ordering, unknown facts, cancellation races, completion, expiry, and evaluator input; worker/controller only use public context.
- Focused ExUnit and Python unit tests, backend precommit, applicable full suite; record exact results.

## Test mode and delivery
- Effective strict TDD: off from `openspec/config.yaml`; ordinary behavior-focused tests required. Backend runner: `cd backend && mix test`; Python worker runner: `cd voice-worker && uv run python -m unittest`; full project runner: `bash scripts/test.sh`. #118's historical task stated strict TDD on locally, but current project configuration is off.
- RDD: clone-local off, observed with `gentle-ai review mode status`. Run native read-only assessment after delegated writers and follow its verification plan; no START when off.
- Initial forecast ~500–750 authored lines; actual work units were larger because of deterministic cancellation and integration tests. Delivery strategy `ask-on-risk`; user selected `stacked-to-main`. User subsequently accepted documented `size:exception` for four honest cohesive review slices before publication; no code golf or artificial splits. The repository has no `size:exception` label, so record the exception in every PR body.

## Tasks
- [x] T1 — Establish monotonic voice turn/generation state and atomic cancellation/supersession in Conversation, preserving duplicate and lifecycle behavior. Route: delegated writer (multi-file code and tests). Evidence: `f5e5cc1`; 35 focused Conversation/controller tests passed in writer, verifier, and parent spot check; formatting passed. Rollback boundary: conversation generation APIs and their tests.
- [x] T2 — Expose verified patient reply orchestration through Backend.Stations. Route: delegated writer (multi-file code and tests). Evidence: `5671692`; 86 focused backend tests passed by verifier and parent, formatting clean. Fail closed to canonical refusal unless reply is an exact authorized package fact. Rollback boundary: Stations voice orchestration and its tests.
- [x] T3 — Expose authenticated verified replies and turn-scoped cancellation through Backend.Stations; consume Deepgram events without waiting for Phoenix; reject stale generations locally and on server. Route: delegated writers (backend, then Python), independent verifier. Evidence: backend `48360b3` (766 authored lines), worker `0779310` (1433 authored lines); backend precommit 291, Python unittest 45, web Vitest 52 + backend ExUnit 291 via root harness all passed. Runtime boundary: mocked Phoenix HTTP + async STT stream tests; live Deepgram/LiveKit skipped because external credentials/services unavailable. Rollback boundaries: revert worker commit, then backend commit. No TTS (#120).

## Progress and evidence
- Parent #118 closed; PR #155 merged to parent branch. Current #134 work remains isolated in its own worktree.
- T1 delivered as `f5e5cc1` (629 authored diff lines: 615 additions + 14 deletions, coherent code/tests). Both writer and independent verifier observed 35 focused tests passing and formatting clean; parent reran 35 focused tests. Initial and committed native assessments were unassessable due to untracked task file; independent verifier used. Runtime boundary: Conversation GenServer tested via ExUnit; rollback only `f5e5cc1`.
- T2 delivered as `5671692` (531 authored diff lines). Native assessment was unassessable (schema-incompatible), so independent verifier ran; 86 focused tests passed both there and in parent spot check. No live provider or audio harness for this unit; rollback only `5671692`.
- Review slices: S1 `80c4353..f5e5cc1` (629); S2 `f5e5cc1..5671692` (567, includes initial task doc); S3 `5671692..48360b3` (766); S4 `48360b3..7627348` (1446, includes worker and task update). User chose to defer publication until #119 was complete, then accepted a documented size exception for all four slices. No push/PR yet.
- T3 retry resumed a functioning worker. Independent verification caught cancellation and background-task races; writer corrected them. Backend precommit 291 tests and formatting/compile checks passed; Python 45 tests passed; root harness passed web 52 and backend 291. Parent spot check reran Python 45; `git diff --check` clean. Native risk assessment was unassessable (`schema-incompatible`), so separate verifier ran.
- Known follow-ups: a lost HTTP success response retried as duplicate intentionally returns no clinical text (safe but no speech synthesis for that turn); no live provider E2E. #120 owns actual TTS/audio delivery acknowledgement. The ephemeral transcript currently records a verified patient reply once Phoenix resolves it, even if a later barge-in prevents hearing it; do not claim audible-turn fidelity until #120 defines delivery semantics.

## Next step
Implementation verified and documented size exception accepted. Push four stacked branches and open PRs: S1 targets `feat/116-realtime-voice`, each subsequent PR targets the immediately preceding slice branch. Use `Refs #119`, exactly one `type:feature` label, and explicit review boundary/risk in each; do not merge automatically.
