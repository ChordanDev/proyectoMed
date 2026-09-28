# #118 Stream learner speech through Deepgram (Python LiveKit Agents worker)

## Objective
A Python LiveKit Agents worker joins each `station-session-*` room, streams only the
learner's microphone to Deepgram (pt-BR, nova-3, server-side keyterms), publishes interim
transcripts to the room, and POSTs each final transcript to Phoenix with a monotonic
`turn_id`. Phoenix stays the transcript authority and commits each turn at most once.

## Why this approach
The previous Egress→WebSocket attempt was dropped (local branch
`backup/118-deepgram-egress-attempt`). LiveKit Agents already solves room joining, track
subscription and the Deepgram streaming client; the worker only moves voice.

## Scope
- Backend: internal worker API behind a shared bearer secret (`VOICE_WORKER_SECRET`).
  - `GET  /api/internal/voice/sessions/:id` → `{session_id, language, keyterms, last_turn_id}`
  - `POST /api/internal/voice/sessions/:id/transcripts` `{turn_id, text}` →
    201 `committed` | 200 `duplicate` (turn_id <= last) | 403/404/410/422
  - Keyterms come from optional `stt_keyterms` in the station package.
  - The committed turn is appended as a learner `:voice` message; no patient reply (#119).
- Worker: `voice-worker/` (uv, Python >= 3.12).
- Out of scope: patient reply (#119), TTS (#120), barge-in/VAD and web transcript UI (#121).

## Constraints
- Transcript text, audio and provider payloads are never logged or persisted by the worker.
- Worker failures are typed (`auth`, `timeout`, `disconnected`, `malformed`, `session_inactive`).

## TDD
Strict TDD on. Runners: `mix test` (backend), `uv run python -m unittest` (voice-worker).

## Tasks
- [x] T1 Backend internal voice API + idempotent turn commit (route: inline, 3 files + tests)
- [x] T2 Python worker + unit tests for normalization/turn tracking (route: inline)
- [x] T3 README manual test for the worker path

## Acceptance
See issue #118.

## Progress / evidence
- T1 `5306d42`: RED 9/9 failing → GREEN; `mix test` 244 passed, `mix precommit` green.
- T2 `cc40fb7`: RED (import error) → GREEN; `uv run python -m unittest` 11 passed. `worker.py`
  glue (LiveKit/Deepgram) is not unit tested; covered by the README manual test.
- T3 `70fbf20`: README "Voice transcription (Deepgram worker) — manual test".
- RDD: not run (review mode not triggered in this session).

## Next step
User runs the README manual test with a real Deepgram key. Open risk: whether
`AudioStream.from_participant` ends when the learner disconnects (checklist step 6).
Then push + PR `feat/118-deepgram-worker` → `feat/116-realtime-voice` (user decision).
Worker tests are not wired into `scripts/test.sh` / CI yet.
