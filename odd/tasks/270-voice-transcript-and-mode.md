# 270 — Real-time voice in the station transcript, and VOICE_MODE

Issue: #270 (parent #237). Branch: `feat/270-voice-transcript-and-mode` from
`feat/237-clinician-demo-readiness`.

## Objective

Spoken turns of the real-time (LiveKit) voice session appear in the `StationScreen`
transcript, in order, and the deployment chooses exactly one voice experience with
`VOICE_MODE=realtime|turn|off`.

## Why

`useVoiceSession` handles no `DataReceived` events, so the learner never sees what
was transcribed, the verified patient reply, or the examiner acknowledgement of a
kept turn. The app also offers two voice stacks at once (LiveKit panel and the
turn-based record/play buttons).

## Constraints

- Worker event schema (topic `transcript`, sender identity `voice-worker`, checked in
  `voice-worker/worker.py` and `voice-worker/transcripts.py`):
  - learner: `{session_id, turn_id, final, text}` (interim when `final` is false);
  - patient: `{session_id, turn_id, generation_id, role: "patient", text}` where `text`
    is the reply **without stage directions** (speech text, #269);
  - kept: `{session_id, turn_id, generation_id, role: "examiner", status: "kept"}`;
  - turn failure: `{session_id, turn_id, generation_id, failure}`;
  - fatal: `{session_id, error}`.
  `turn_id` is present on every turn event, so no worker change is needed.
- The patient entry must show the stored (full verified) text, like the text path:
  the web refetches the session messages after a patient event and uses the stored
  reply that follows the learner turn; the event text is only a fallback.
- Interim transcripts are a live caption only, never stored in the transcript.
- No double rendering: voice entries are keyed by turn id; duplicate events are
  ignored.
- Never log transcripts or patient text.
- Frontend feature-first; backend web layer stays thin.

## Decisions

- `VOICE_MODE` is resolved in `backend/config/runtime.exs` (not in `:test`) and served
  as `voice_mode` on `GET /api/stations/active`. Unset or unknown: `realtime` when
  `LIVEKIT_URL`, `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` are all set, otherwise
  `turn`. The web treats a missing field as `turn`.
- `realtime`: the voice panel is part of the station screen; no record or
  "Ouvir resposta" buttons. `turn`: today's turn-based buttons, no panel. `off`: no
  audio consent and no voice controls.
- A learner voice turn left without an outcome is dropped when a later turn
  resolves (it was superseded by barge-in and Phoenix cancelled it).
- `StationSession.tsx` is removed (it is no longer in the app flow).

## Tasks

Route: delegated direct (this bounded writer). Planning heuristic ~400 changed lines
per task; not a cap.

- [ ] T1 — Backend `VOICE_MODE` config and `voice_mode` on the active station; web
  client decodes it (default `turn`).
- [ ] T2 — `useVoiceSession` parses `transcript` data events from the worker and
  hands typed events to a callback.
- [ ] T3 — Transcript merge (pure) + `StationScreen` hosts the real-time voice panel,
  renders learner/patient/examiner entries, live caption and failure notices, and
  uses the stored patient reply.
- [ ] T4 — App wiring by voice mode; voice session after the brief, ended on finish,
  deadline and leave; remove `StationSession`.
- [ ] T5 — README demo runbook and `.env.example`.
- [ ] T6 — Screenshots with `VOICE_MODE=realtime` (no live LiveKit session).

## Checks

- `npm --prefix web test`, `npm --prefix web run lint`, typecheck/build.
- `cd backend && mix test`, `mix format --check-formatted`.
- Local CI script (`LOCAL CI PASSED`).

## Progress

(updated per task)

## Next step

T1.
