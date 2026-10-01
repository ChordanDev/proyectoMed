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
- Forecast: approximately 500–750 authored diff lines across three work units (T1 alone is ~500 with tests). Delivery strategy `ask-on-risk`; user selected `stacked-to-main` chain strategy before first commit. Keep coherent work-unit commits and split PR review slices along their boundaries; do not compress code or tests to fit.

## Tasks
- [x] T1 — Establish monotonic voice turn/generation state and atomic cancellation/supersession in Conversation, preserving duplicate and lifecycle behavior. Route: delegated writer (multi-file code and tests). Evidence: `f5e5cc1`; 35 focused Conversation/controller tests passed in writer, verifier, and parent spot check; formatting passed. Rollback boundary: conversation generation APIs and their tests.
- [ ] T2 — IN PROGRESS. Expose verified patient reply orchestration only via Backend.Stations, using current transcript and rejecting stale generation before append/return; tests for safety and evaluator. Route: delegated writer (multi-file code and tests). Check: focused Stations tests; commit pending.
- [ ] T3 — Wire worker-facing delivery and cancellation to public context, update Python worker integration and controller tests without leaking unverified text; verify backend/Python/full suite. Route: delegated writer (multi-file code and tests). Check: focused and full suites; commit pending.

## Progress and evidence
- Parent #118 closed; PR #155 merged to parent branch. Current #134 work remains isolated in its own worktree.
- T1 delivered as `f5e5cc1` (615 authored diff lines, coherent code/tests). Both writer and independent verifier observed 35 focused tests passing and formatting clean; parent reran 35 focused tests. Initial and committed native assessments were unassessable due to untracked task file; independent verifier used. Runtime boundary: Conversation GenServer tested via ExUnit; rollback only `f5e5cc1`.
- Review slice S1: `f5e5cc1` alone; future S2 starts from S1 and holds T2 work unit. No push/PR requested.

## Next step
Implement T2 against `Conversation.begin_voice_turn/3`, `resolve_patient_reply/3`, and `cancel_generation/2`, preserving old #118 worker route until T3.
