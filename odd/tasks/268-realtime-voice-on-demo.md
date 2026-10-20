# 268 — Bring the real-time voice prototype (#151) onto the clinician demo branch

Issue: #268 (parent #237). Branch `feat/268-realtime-voice-on-demo` from `origin/feat/237-clinician-demo-readiness` (c2e4210), worktree `../proyectoMed-worktrees/issue-268`. PR target `feat/237-clinician-demo-readiness`, `Refs #268`.

## Objective

Merge `origin/feat/116-realtime-voice` (draft PR #151, 93 commits) into the demo branch with a merge commit, resolve conflicts without dropping either side's behavior, and bring local CI back to green.

## Scope and constraints

- Integration base only. No porting of voice to today's rules (refusal keep-turn, stage directions, worker timeout, web transcript): those are #269 / #270.
- Fix only what breaks compilation or existing tests.
- Text station must behave as on `feat/237-clinician-demo-readiness`.

## Tasks

- [x] T1 — Feature document. Route: inline.
- [x] T2 — `git merge --no-ff origin/feat/116-realtime-voice`; resolve `.gitignore`, `web/src/features/station/index.ts`, `web/src/features/station/api/client.test.ts`, `backend/lib/backend/stations/conversation.ex`. Route: inline (bounded writer for this issue).
- [x] T3 — Review auto-merged semantic-risk files; record notes for #269/#270. Route: inline.
- [x] T4 — Local CI (mirrors `pr-validation.yml`) and voice-worker Python tests. Route: inline.
- [ ] T5 — Push and open PR. Route: inline.

## Acceptance criteria

- Branch contains both histories; local CI passes.
- Text station tests from the demo branch still pass.
- PR describes every conflict and its resolution.

## Checks

- `local_ci.sh <worktree>` prints `LOCAL CI PASSED`.
- `cd voice-worker && uv sync && uv run python -m unittest` (pytest is not a worker dependency; the tests are `unittest`).

## Progress

- T1: feature document committed.
- T2: merge commit 8073ace. Conflicts: `.gitignore` (demo secrets block kept; #151 only added `.env`), `index.ts` (both export sets), `client.test.ts` (both test blocks), `conversation.ex` (typespec union; no textual conflict in turn logic — demo `begin_turn`/`resolve_turn`/`:keep_learner_turn` and #151 voice generation ids/cancellation/voice grace both present).
- T3: auto-merged files reviewed; no fix was needed for compilation or tests.
- T4: local CI passed — web 259 + 4 e2e, backend 1450 ExUnit, typecheck, lint, format, compile, credo, dialyzer 0 errors. Worker: 120 `unittest` tests OK (Python 3.14.6 via uv).

## Notes for #269 / #270

- Voice refusal: `Stations.process_voice_turn/3` fails closed on denied/refused replies as `:station_ai_unavailable` and commits no patient content; the text path now keeps the learner turn (`:keep_learner_turn`, #235). Voice has no keep-turn equivalent yet (#269).
- `Conversation.do_rollback_pending_message/3` now finds the pending learner message by identity (a voice turn may follow it); text rollback behavior is unchanged when it is the tail.
- Voice replies are not yet subject to the demo's stage-direction rules or worker timeout; the worker's only timeout is `cleanup_timeout` (#269).
- Web: `App.tsx` renders `VoicePanel` when `station.audioConsent`; `useStation` now exposes `sessionId`. Voice turns are not shown in the web transcript (#270).
- `config.exs` adds `:filter_parameters` including `"text"` and `"token"`; `runtime.exs` reads `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `VOICE_WORKER_SECRET`; `chest-pain-initial-assessment/package.json` gains `stt_keyterms`.
- `voice-worker` declares no pytest dependency; run tests with `uv run python -m unittest`.
