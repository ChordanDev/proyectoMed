# #325 Speak and lip-sync the patient reply to a typed turn in the Unreal client

Objective: in a run with patient voice, the approved reply to a typed turn is also spoken on the `patient-voice` track and lip-synced; the typed-turn HTTP response stays text-only.
Branch: `feat/325-speak-typed-reply` from `develop` (6f82902). Delivery: ask-on-risk. Runners: backend `mix test`; `cd voice-worker && uv run python -m unittest -q`; `scripts/run-unreal-tests.sh` (unit specs), voice specs inside `scripts/run-voice-stack.sh`.

## Specs

Acceptance criteria of #325, verbatim:

- S1 "In a run with patient voice, a typed turn's approved reply is heard and lip-synced, and matches the text shown."
- S2 "A run without audio consent keeps text-only replies."
- S3 "Only text Phoenix approved is spoken; an interrupted or superseded reply is never spoken (with #193)."
- S4 "Automated tests cover it at the station client module against local Phoenix and a local LiveKit development server."

Technical decision (triage, 2026-10-25), verbatim:

- S5 "The voice worker speaks the typed reply, because it already owns the `patient-voice` track and the TTS provider. Unreal adds no TTS of its own, and the typed-turn HTTP response stays text-only."
- S6 "After Phoenix approves a typed turn in a session that has a voice room, it sends that reply to the worker through the LiveKit server API (`Backend.Stations.LiveKit.RoomService`). The payload carries the session, turn id, generation id and approved text."
- S7 "The worker speaks only a reply whose generation is still current. It uses the same fencing as spoken turns, so with #193 an interrupted or superseded reply is never spoken."

Derived technical decisions (this session, 2026-10-28):

- S6a A typed turn takes the next generation id when it begins (`Conversation.begin_turn`), and its turn id is the voice-turn floor at that moment (`max(last_voice_turn_id, cancelled_voice_turn_id)`): the last spoken turn it follows. Neither moves the voice cursors.
- S6b Phoenix sends with LiveKit `SendData`, reliable, topic `typed-reply`, only to the `voice-worker` identity, under a server token whose only grant is `roomAdmin` for that one room. Best effort: a LiveKit failure is logged without content and never fails the typed turn. Only sessions with audio consent and LiveKit configured send.
- S7a The worker takes typed replies only from the server (a packet with no participant). It speaks one only while its generation is newer than any it accepted and the learner has not spoken in a turn after the typed turn's turn id; it publishes no text event (the client already shows the HTTP reply). Speaking over it stops it, as for a spoken reply (#193).
- S3a Unreal resumes the patient voice (#193 gate) when the typed turn's reply arrives, unless the learner spoke a newer turn since sending it.

## Tasks

| ID | Specs | Route | Status | Commit / evidence |
|----|-------|-------|--------|-------------------|
| T1 | S2, S6, S6a, S6b | inline | todo | |
| T2 | S3, S5, S7, S7a | inline | todo | |
| T3 | S1, S3, S3a, S4 | inline | todo | |

- T1 Phoenix: typed-turn fence, `RoomService.send_data`, send after approval.
- T2 Worker: receive, fence and speak typed replies.
- T3 Unreal: resume on typed reply; stack spec hearing the typed reply; docs.

Route evidence: one understood change per component, no writer reason (no parallel launch, context under backstop); all inline.

## Log

- L1 (2026-10-28, parent session brief) "Implement issue #325 of ChordanDev/proyectoMed: \"Speak and lip-sync the patient reply to a typed turn in the Unreal client\". [...] after Phoenix approves a typed turn in a session with a voice room, it sends the approved reply (session, turn id, generation id, text) to the voice worker through the LiveKit server API (`Backend.Stations.LiveKit.RoomService`); the worker speaks it on the existing `patient-voice` track with the same generation fencing as spoken turns; the typed-turn HTTP response stays text-only; Unreal adds no TTS. [...] Check that a spoken typed reply's events resume the patient and are not dropped as a superseded or older turn; pin it with a spec. [...] Keep Unreal edits there minimal."
- L2 Analysis: typed turns today have no turn or generation id; the worker's player speaks only the tracker's active generation, and barge-in cancels playback of turns up to `tracker.turn_id - 1`. Hence S6a (begin-time generation, floor turn id) and S7a (generation + "no newer learner speech" fence). Unreal's #193 gate stays closed after a spoken turn without a patient reply, so a typed reply's voice would be dropped there: S3a.
