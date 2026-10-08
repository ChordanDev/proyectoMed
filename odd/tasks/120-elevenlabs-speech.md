# #120 Stream verified patient speech through ElevenLabs

## Objective
The voice worker speaks each Phoenix-approved patient reply: it sends only the
`reply_text` returned by the worker API to ElevenLabs streaming TTS and publishes the
resulting audio as a patient track in the active LiveKit room, frame by frame, fenced by
the turn's generation identity.

## Problem
#119 returns an approved `reply_text` and `generation_id` to the worker, but nothing
consumes it: `transcribe(...)` is called without `on_reply` (`voice-worker/worker.py`),
no audio is published into the room, and the learner receives neither patient text nor
patient audio on the voice path.

## Why this approach
- ADR-009 (#114) places provider media streaming, cancellation and generation races in
  the voice worker. #118 already integrated Deepgram there; Phoenix has no LiveKit media
  SDK. ElevenLabs follows the same seam: a provider object injected into the worker
  (`tts=`), replaced by a double in tests.
- Phoenix stays the only text authority. The worker never composes, edits or retries
  text: the only input to synthesis is an accepted `VoiceTurnReply` from
  `POST /api/internal/voice/sessions/:id/transcripts`.
- The reply is a complete short bounded string, so one synthesis request per generation
  with streamed audio output is enough; no input-streaming session is needed.

## Scope
- `voice-worker/speech.py`: provider-neutral speech player owning one audio source and
  published track per room; `speak(reply)` streams frames as they arrive; idempotent
  `cancel(generation_id)`; `aclose()` cleanup.
- Worker wiring: consume accepted replies, publish the approved text event before
  synthesis starts, cancel playback when the generation is superseded, cancelled, or the
  learner disconnects, and release ElevenLabs/LiveKit resources on cleanup.
- Typed non-fatal failure `synthesis_failed`, published content-free to the room and
  documented in the README.
- Config: `ELEVENLABS_API_KEY` (worker env only), `ELEVENLABS_VOICE_ID`,
  `ELEVENLABS_MODEL`; `.env.example` and README updated.

## Out of scope
- Learner-facing rendering of the patient text/failure events and barge-in detection
  integrated in the station UI: #121.
- Jev verification (#127): merged to `develop`, not yet in `feat/116-realtime-voice`.
  On this branch the effective gate is `Backend.Stations.admit_voice_reply/2` (canonical
  refusal or an exact package fact). The worker speaks only what Phoenix returns, so it
  inherits Jev when the parent branch takes `develop`.
- New Phoenix endpoints, delivery acknowledgement, and the legacy OpenAI
  `/synthesize` batch baseline.
- Adding worker tests to `scripts/test.sh` / CI.

## Constraints
- ElevenLabs receives only text from an accepted, non-stale `VoiceTurnReply`.
- First audio frame is published before synthesis of the utterance completes.
- After `cancel(generation_id)` or a newer generation, no further frame of the old
  generation is pushed, including frames already buffered or arriving late.
- A synthesis or publication failure never removes or delays the visible text event and
  never stops the worker job.
- Reply text, audio, provider payloads and provider error messages are never logged or
  persisted; logs carry session id, turn id, generation id and failure kind only.
- Credentials stay in the worker process environment; nothing is sent to the browser.

## TDD
Strict test-first. Runner: `cd voice-worker && uv run python -m unittest`
(baseline on `9111ba4`: 73 passed). No production credentials: TTS, audio source and
room are doubles.

## Tasks
- [ ] T1 Speech player (`speech.py` + `test_speech.py`): streaming, generation fencing,
  idempotent cancel, stale/late chunks, provider failure and disconnect mapping to
  `synthesis_failed`, cleanup. Route: delegated (writer trigger: 2+ non-trivial files
  across T1/T2, preparation reading of the worker).
- [ ] T2 Worker wiring + config + docs: `on_reply` consumer, text event before
  synthesis, cancel on supersede/barge-in/disconnect/cleanup, failure event, text
  fallback, ElevenLabs dependency, `.env.example`, README. Route: delegated (same writer).

## Acceptance
See issue #120.

## Checks
- `cd voice-worker && uv run python -m unittest`
- `bash scripts/test.sh` (unchanged backend/web must stay green)

## Delivery
- Branch `feat/120-elevenlabs-speech` from `feat/116-realtime-voice` (`9111ba4`);
  PRs target `feat/116-realtime-voice` with `Refs #120`.
- Forecast: about 900 authored changed lines (tests included), above the 400-line
  budget. Strategy: feature-branch chain, one PR per work unit (T1, then T2), following
  the #119 precedent (PR #163-#166). Push and PR creation are the user's decision.
- RDD: off for this clone (`clone_local`); ordinary checks only.

## Progress / evidence
- Worktree `../proyectoMed-120`, baseline worker tests 73 passed.

## Next step
T1.
