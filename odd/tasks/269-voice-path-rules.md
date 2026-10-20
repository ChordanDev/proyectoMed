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
- [x] T2 — Phoenix: a refused voice reply (and a refused-then-timed-out regeneration) keeps the learner turn, stores no patient text and returns a kept-turn result; the controller answers `201 {status: "kept"}` without text. Route: inline (single writer).
- [x] T3 — Phoenix: verification for voice and text turns receives one explicit, shared deadline budget. Route: inline.
- [x] T4 — Phoenix: the voice `reply_text` has no stage directions; a reply with nothing speakable keeps the learner turn. Route: inline.
- [x] T5 — Worker: a `kept` reply is accepted, speaks nothing, and publishes an examiner acknowledgement (not a failure) on the data channel. Route: inline.
- [x] T6 — Worker: the transcript POST timeout covers the server budget and is configurable; only a connection failure is retried. Docs. Route: inline.
- [x] T7 — Local CI, worker unittest, push, PR. Route: inline.

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

- T1: 7e428a2 feature document.
- T2: 47e8ba9. `Conversation.resolve_patient_reply/3` accepts `:keep_learner_turn` (same atom as the text path's `resolve_turn/3`) and settles the generation without a patient message; `process_voice_turn/3` returns `{:ok, {:kept, %{turn_id, generation_id, refusal}}}`; the controller answers `201 {status: "kept"}`. RED: 5 failures (4 Stations, 1 controller); GREEN: 133/133 in the two files, then 1009 across stations/controllers.
- T3: a04bd0d. One explicit verification budget (`JevDecision.default_deadline_ms/0`) passed to text and voice. RED not observable: both paths already fell back to the same default, so the new test passed before the change (characterization). GREEN: 229 tests.
- T4: 3539f01. Voice `reply_text` is `TTS.StageDirections.strip/1` of the verified reply; the transcript keeps the full reply; a gesture-only reply is kept with reason `:unspeakable`. RED: 3 failures; GREEN: 232 tests.
- T5: 5a7fa16. Worker accepts a generation-bound `kept` receipt, speaks nothing, publishes `{role: "examiner", status: "kept"}` and releases cancel ownership. RED: 2 failures + 1 error; GREEN: worker 124 tests OK.
- T6: bc9a486. Transcript POST waits `DEFAULT_TURN_TIMEOUT_S` = 15 + 3 + 15 + 2 = 35 s (configurable `PHOENIX_TURN_TIMEOUT_S`, `PHOENIX_TURN_RETRIES`); context/cancel keep 5 s; EOF wait = timeout x attempts + 5 s. README updated. RED: 3 import/attribute errors; GREEN: worker 130 tests OK.
- T7: local CI PASSED — web 259 + e2e 4, backend 1457 ExUnit, typecheck, lint, format, credo (no issues), dialyzer 0 errors. Worker `uv run python -m unittest`: 130 OK.
- Review round 1 (Jorge C1, merged TR-2/SP-1): `phoenix_turn_settings` crashed on a non-ASCII digit such as `PHOENIX_TURN_RETRIES=²` (`isdigit()` true, `int()` raises). Guarded with `isascii()`; it now keeps the default and logs the warning. Caps and defaults unchanged. RED: 1 error (ValueError); GREEN: worker 130 tests OK.

## Pending / follow-ups

- Live check (no LiveKit/Deepgram/ElevenLabs/Claude keys here): spoken exam finding produces "Anotado.", and no stage direction is spoken. Pending.
- The web does not render voice room events yet (#270): the kept-turn event must be shown as "Anotado." there.
- A retry of a kept turn returns `duplicate` (no replay of the kept outcome); with the 35 s budget a retry only follows a transport failure.
- A transcript POST that still times out after all attempts ends the voice job (unchanged behavior).

## Next step

Push and open the PR to `feat/237-clinician-demo-readiness`.
