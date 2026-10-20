# 269 — Real-time voice path follows the demo branch rules

Issue: #269 (parent #237). Branch `fix/269-voice-path-rules` from `origin/feat/237-clinician-demo-readiness` (5954453), worktree `../proyectoMed-worktrees/issue-269`. PR target `feat/237-clinician-demo-readiness`, `Refs #269`.

## Objective

Make the real-time voice path (`Stations.process_voice_turn/3`, `VoiceWorkerController`, `voice-worker/`) follow the rules the text path got this week: refusals keep the learner turn (#235, #256), verification runs on an explicit deadline budget, stage directions are never spoken (#257), and the worker waits long enough for a refusal plus one regeneration.

## Why

Today a refused voice reply fails the generation as `station_ai_unavailable` (503). The worker retries, gets the same 503, and stops the whole voice job; the patient may read `*(curvado…)*` aloud, and a 5 s worker timeout can cut a refusal-then-regeneration turn short so the learner hears nothing.

## Scope and constraints

- Reuse the text kept-turn semantics (`:keep_learner_turn`); do not duplicate it.
- A technical failure with no refusal keeps today's fail-closed behavior (`fail_generation`).
- Reuse `Backend.Stations.TTS.StageDirections` for the voice `reply_text`; the transcript keeps the full verified reply, as on the text path.
- Keep `candidate_gate.ex` untouched if possible (#273 changes it in parallel).
- Never log transcripts, patient text or audio (Elixir or Python).
- Web transcript wiring of voice events is #270, not here.
- ~400 changed lines per task is a planning heuristic only.

## Tasks

- [x] T1 — Feature document. Route: inline.
- [ ] T2 — Phoenix: a refused voice reply (and a refused-then-timed-out regeneration) keeps the learner turn, stores no patient text and returns a kept-turn result; the controller answers `201 {status: "kept"}` without text. Route: inline (single writer).
- [ ] T3 — Phoenix: verification for voice and text turns receives one explicit, shared deadline budget. Route: inline.
- [ ] T4 — Phoenix: the voice `reply_text` has no stage directions; a reply with nothing speakable keeps the learner turn. Route: inline.
- [ ] T5 — Worker: a `kept` reply is accepted, speaks nothing, and publishes an examiner acknowledgement (not a failure) on the data channel. Route: inline.
- [ ] T6 — Worker: the transcript POST timeout covers the server budget and is configurable; only a connection failure is retried. Docs. Route: inline.
- [ ] T7 — Local CI, worker unittest, push, PR. Route: inline.

## Acceptance criteria

- A refused voice reply keeps the learner turn and emits a kept-turn event (Phoenix and worker tests).
- A refused-then-timed-out regeneration behaves the same (tested).
- `reply_text` sent to the worker has no stage directions (tested).
- The worker timeout covers the server budget (tested and documented).
- Live check (pending, no keys): a spoken exam finding produces "Anotado.", and the patient never reads stage directions aloud.

## Checks

- `cd backend && mix test <files>` per task (RED then GREEN).
- `cd voice-worker && uv sync && uv run python -m unittest`.
- `local_ci.sh <worktree>` prints `LOCAL CI PASSED`.

## Progress

- (none yet)

## Next step

T2.
