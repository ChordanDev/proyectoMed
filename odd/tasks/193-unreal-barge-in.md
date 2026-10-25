# #193 Interrupt the patient: barge-in and stale replies in the Unreal client

Objective: the learner can speak over the patient in the Unreal client; the patient stops at once and never speaks, animates or shows a superseded reply.
Branch: `feat/193-barge-in` from `develop` (80ebe70). Delivery: ask-on-risk. Runners: `cd voice-worker && uv run python -m unittest -q`; `scripts/run-unreal-tests.sh` (unit specs), voice specs inside `scripts/run-voice-stack.sh`.

## Specs

Acceptance criteria of #193, verbatim:

- S1 "Speaking over the patient stops both the voice and the facial animation promptly."
- S2 "A reply for an interrupted or superseded turn is never played or animated, even if it arrives late."
- S3 "Ending the station while the patient is speaking silences and stops the patient."
- S4 "Visible text never shows a reply that was discarded."
- S5 "Automated tests cover interruption and late-arriving stale replies at the station client module."
- S6 "The Unreal client relies on the generation fencing delivered by the real-time voice work rather than inventing its own."

Derived technical decisions (parent, 2026-10-25):

- S1a The worker stops the patient's audio when the learner starts speaking over it, including the tail of a reply Phoenix already settled. Today it stops only the pending turn's audio (`TurnManager.on_speech_event`), so speaking over the last sentence of a settled reply does not stop it. The settled reply's text stays: Phoenix stored it.
- S2a The client's barge-in signal is the first learner event with text for a newer turn: the worker cancels the pending turn on that same speech (`START_OF_SPEECH` or non-empty transcript), and the room's reliable data channel keeps events in order.
- S2b On that signal the client empties its local patient audio buffer, rests the mouth, and drops patient audio until the patient text of a newer turn arrives (the worker publishes a sentence's text before its audio).
- S4a A spoken turn still without an outcome (no end event, no whole reply, no examiner note, no kept receipt) when a newer turn starts was superseded: its partial patient text and its learner line leave the conversation, as in the web client (`dropSupersededVoiceTurns`, `placeOutcome` in `web/src/features/station/screens/voiceTranscript.ts`).

## Tasks

| ID | Specs | Route | Status | Commit / evidence |
|----|-------|-------|--------|-------------------|
| T1 | S1, S1a | inline | open | |
| T2 | S2, S2a, S4, S4a, S5 | inline | open | |
| T3 | S1, S2, S2b, S3, S5 | inline | open | |
| T4 | S1-S4 by eye (human) | human | open | |

- T1 Worker: speaking over a settled reply's audio stops it.
- T2 Unreal flow: superseded turns leave the conversation; a newer learner turn is the barge-in signal.
- T3 Unreal patient voice: empty the buffer, rest the mouth, gate late audio; stop the patient when the run ends.
- T4 By-eye check in the editor with the voice stack.

## Log

- L1 (2026-10-25, user): "dale" — answer to "¿Arranco con #193?"; chose "Do it here".
- L2 (2026-10-25): mapped. Worker: `TurnManager.on_speech_event` (voice-worker/transcripts.py:563) cancels only `pending_turn_id`, which clears once Phoenix settles (transcripts.py:797-800). Unreal: `HandleVoiceEvent` commits an unfinished reply when a newer turn starts (StationRunFlow.cpp:638), the opposite of S4a; `FStationPatientAudioSink` queues PCM into a `USoundWaveProcedural` that is never emptied, and `UStationPatientVoice` is never stopped when the run ends (StationPlayerController.cpp:136). Engram mirror pending: the Engram hook reports the host session ended.
