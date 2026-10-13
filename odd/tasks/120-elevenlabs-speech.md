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
- [x] T1 Speech player (`speech.py` + `test_speech.py`): streaming, generation fencing,
  idempotent cancel, stale/late chunks, provider failure and disconnect mapping to
  `synthesis_failed`, cleanup. Route: delegated (writer trigger: 2+ non-trivial files
  across T1/T2, preparation reading of the worker).
- [x] T2 Worker wiring + config + docs: `on_reply` consumer, text event before
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
- T1 `efe114b`: RED `ModuleNotFoundError: No module named 'speech'` (74 run, 1 error) →
  GREEN `uv run python -m unittest` 93 passed. 758 changed lines (tests 452, this
  document 93).
- T2 `acdbf33`: RED 4 errors (3 `process_speech_stream() got an unexpected keyword
  argument 'on_cancel'`, 1 `ImportError: cannot import name 'PatientVoice'`) → GREEN 111
  passed, three consecutive runs. The playout-tail test was added mid-task; its RED was
  a hang on the missing `wait_for_playout` call. 776 changed lines (tests 505, README 78,
  lockfile 16). `bash scripts/test.sh`: web 52 passed, backend 311 passed.
- Dependency: `livekit-plugins-elevenlabs` 1.8.3, the same release as the locked
  `livekit-agents` 1.8.3; `uv lock` added only that package. The non-streaming-input
  `synthesize()` path is used (HTTP `/text-to-speech/{voice}/stream`, `pcm_24000`,
  `eleven_flash_v2_5`, one attempt per generation).
- Room events (topic `transcript`): patient text
  `{session_id, turn_id, generation_id, role: "patient", text}`; non-fatal failure
  `{session_id, turn_id, generation_id, failure: "synthesis_failed"}`.
- Route: delegated writer, both tasks. RDD off; ordinary checks only.
- Manual test 2026-10-13 (local `livekit-server --dev`, Safari, real Deepgram, OpenAI
  and ElevenLabs keys, default voice): the learner turn is transcribed and committed,
  the worker job token has `canPublish` and publishes the `patient-voice` track, and the
  approved reply is heard as synthesized audio. Every voice turn returned the canonical
  refusal (five different questions through the worker API), while the text path
  answers the same question: `admit_voice_reply/2` admits only the refusal or an exact
  package fact, and the adapter paraphrases. README prerequisites added from this run.
- Not measured: audible latency. Manual steps 3-6 (supersede, disconnect mid-answer,
  wrong key, log scan): result pending confirmation from the tester.

## Known follow-ups
- Learner speech over a reply that is already playing does not stop it until the next
  reply is accepted: `TurnManager` only detects barge-in on a turn still pending in
  Phoenix. Detection during playback belongs to #121.
- ElevenLabs keeps request history by default (`enable_logging=true`); zero-retention
  mode is enterprise-only. Decide before real patient-like content is used.
- `livekit-agents` records the synthesized text as a span attribute; no trace exporter
  is configured in this worker. Re-check if telemetry is enabled.
- A lost commit response retried as `duplicate` still yields no text and no speech for
  that turn (inherited from #119).

- The voice path cannot give a non-refusal answer until `develop` (Jev, #127) is merged
  into `feat/116-realtime-voice`.

## Next step
Confirm manual steps 3-6, then push and open the T1 and T2 PRs against
`feat/116-realtime-voice` (user decision).
