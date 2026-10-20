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

- [x] T1 — Backend `VOICE_MODE` config and `voice_mode` on the active station; web
  client decodes it (default `turn`). Commit `01ea78b`.
  RED: backend 6 failed of 68 (controller + runtime config tests); web client 6 failed
  of 40. GREEN: 68/68 and 40/40.
- [x] T2 — `useVoiceSession` parses `transcript` data events from the worker and
  hands typed events to a callback. Commit `03a628f`.
  RED: parser suite failed to load (module missing) and the hook delivery test
  failed. GREEN: 34/34.
- [x] T3 — Transcript merge (pure) + `StationScreen` hosts the real-time voice panel,
  renders learner/patient/examiner entries, live caption and failure notices, and
  uses the stored patient reply. Commit `edea389`.
  RED: merge suite failed to load; StationScreen voice tests 7/7 failed. A further
  RED (kept turn 2 resolving before turn 1's stored reply dropped turn 1) added the
  pending-turn guard and its test. GREEN: screens 114/114.
- [x] T4 — App wiring by voice mode; voice session after the brief, ended on finish,
  deadline and leave (LiveKit `disconnectOnPageLeave`); remove `StationSession`.
  Commit `f2f2791`. RED: 5 failed of 73 (App modes, `fetchTranscript`). GREEN: web
  unit 302/302.
- [x] T5 — README demo runbook and `.env.example`. Commit `354efa6`. Passive
  documentation: no runnable RED; structural readback.
- [x] T6 — Screenshots with `VOICE_MODE=realtime` (no live LiveKit session): desktop
  and mobile station with the panel under the header and no turn-based buttons, and
  the `voice_unavailable` panel state. A spoken exchange could not be captured
  (no LiveKit, Deepgram or ElevenLabs session available); transcript rendering is
  covered by component tests with mocked LiveKit data events.

## Checks

- `npm --prefix web test`, `npm --prefix web run lint`, typecheck/build.
- `cd backend && mix test`, `mix format --check-formatted`.
- Local CI script (`LOCAL CI PASSED`).

## Progress

All tasks done. Local CI passed on `354efa6`: web unit 302/302 (16 files), backend 1484/1484, E2E 4/4, typecheck, lint, Dialyzer.

## Follow-ups

- Live check of a full spoken consultation with the transcript visible (needs
  LiveKit, Deepgram, ElevenLabs and Jev credentials).
- On a 390 px viewport the station input row overflows (the "Exame Físico / Exames"
  and "Enviar" buttons are cut); pre-existing, outside this issue.
- The worker publishes the speech text; the web reads the stored reply from
  `GET /sessions/:id`. Publishing the stored text from the worker would save that
  read, but needs a Phoenix voice API change.

## Next step

Open the PR to `feat/237-clinician-demo-readiness`.
