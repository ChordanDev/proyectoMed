# 268 — Bring the real-time voice prototype (#151) onto the clinician demo branch

Issue: #268 (parent #237). Branch `feat/268-realtime-voice-on-demo` from `origin/feat/237-clinician-demo-readiness` (c2e4210), worktree `../proyectoMed-worktrees/issue-268`. PR target `feat/237-clinician-demo-readiness`, `Refs #268`.

## Objective

Merge `origin/feat/116-realtime-voice` (draft PR #151, 93 commits) into the demo branch with a merge commit, resolve conflicts without dropping either side's behavior, and bring local CI back to green.

## Scope and constraints

- Integration base only. No porting of voice to today's rules (refusal keep-turn, stage directions, worker timeout, web transcript): those are #269 / #270.
- Fix only what breaks compilation or existing tests.
- Text station must behave as on `feat/237-clinician-demo-readiness`.

## Tasks

- [ ] T1 — Feature document. Route: inline.
- [ ] T2 — `git merge --no-ff origin/feat/116-realtime-voice`; resolve `.gitignore`, `web/src/features/station/index.ts`, `web/src/features/station/api/client.test.ts`, `backend/lib/backend/stations/conversation.ex`. Route: inline (bounded writer for this issue).
- [ ] T3 — Review auto-merged semantic-risk files; record notes for #269/#270. Route: inline.
- [ ] T4 — Local CI (mirrors `pr-validation.yml`) and voice-worker Python tests. Route: inline.
- [ ] T5 — Push and open PR. Route: inline.

## Acceptance criteria

- Branch contains both histories; local CI passes.
- Text station tests from the demo branch still pass.
- PR describes every conflict and its resolution.

## Checks

- `local_ci.sh <worktree>` prints `LOCAL CI PASSED`.
- `cd voice-worker && uv sync && uv run pytest -q` (if available).

## Progress

## Notes for #269 / #270
