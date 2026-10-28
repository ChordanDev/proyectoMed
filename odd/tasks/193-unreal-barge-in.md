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
| T1 | S1, S1a | inline | done | a3a1aab; RED `test_barge_in_over_a_settled_reply_stops_its_playback` (0 != 1), GREEN 171 OK |
| T2 | S2, S2a, S4, S4a, S5 | inline | done | 0b6b75d; RED 3 unit specs, GREEN `ProyectoMed.StationRun.Unit` 14/14 |
| T3 | S1, S2, S2b, S3, S5 | inline | done | 6f6269e; RED sink spec, GREEN `PatientVoice.Unit+StationRun.Unit` 20/20 |
| T4 | S1-S4 by eye (human) | human | done | L11, user in the editor with real providers |

- T1 Worker: speaking over a settled reply's audio stops it.
- T2 Unreal flow: superseded turns leave the conversation; a newer learner turn is the barge-in signal.
- T3 Unreal patient voice: empty the buffer, rest the mouth, gate late audio; stop the patient when the run ends.
- T4 By-eye check in the editor with the voice stack.

## Log

- L1 (2026-10-25, user): "dale" — answer to "¿Arranco con #193?"; chose "Do it here".
- L2 (2026-10-25): mapped. Worker: `TurnManager.on_speech_event` (voice-worker/transcripts.py:563) cancels only `pending_turn_id`, which clears once Phoenix settles (transcripts.py:797-800). Unreal: `HandleVoiceEvent` commits an unfinished reply when a newer turn starts (StationRunFlow.cpp:638), the opposite of S4a; `FStationPatientAudioSink` queues PCM into a `USoundWaveProcedural` that is never emptied, and `UStationPatientVoice` is never stopped when the run ends (StationPlayerController.cpp:136). Engram mirror pending: the Engram hook reports the host session ended.
- L3 (2026-10-25): T1. `TurnManager.on_barge_in` tells the worker the learner spoke over every turn up to the previous one; `PatientVoice.cancel_turn` stops that playback even when Phoenix already settled it. `test_barge_in_on_the_pending_turn_cancels_playback` asserted the old gap (the reply kept playing while the learner said "segunda") and now asserts it stops. README fencing paragraph updated (it still sent this to #121, closed).
- L4 (2026-10-25): T2. `UStationRunFlow` takes `FStationPatientOutput` (Audio, Silence, Resume) instead of `SetPatientAudio`. A non-empty learner event for a newer turn silences the patient and drops the previous turn when it had no outcome; `PatientText` resumes it; `BeginFinish` silences. An empty learner caption no longer starts a turn.
- L5 (2026-10-25): T3. `FStationPatientAudioSink::Silence` resets the procedural wave, rests the mouth (`FStationMouthState::Rest`) and drops audio until `Resume`. `USoundWaveProcedural::ResetAudio` empties the queue at once but its byte counter only resets on the audio thread, so the spec checks what `GeneratePCMData` plays. The RED for that observable was taken with the byte counter (stub run); the mouth assertions failed on the stubs too.
- L6 (2026-10-25): Risk: item 4 (a gate shared by the LiveKit and game threads under the sink lock; async ordering of barge-in in the worker). Independent verifier at the feature end.
- L7 (2026-10-25): independent verifier (Sonnet): S1, S1a, S2, S2a, S2b, S4, S4a, S5, S6 met; S3 partial. B1: during `Finishing` the room stays until `FinishSession` succeeds, and a later `PatientText` resumed the patient. Advisories: A1 `USoundWaveProcedural::ResetAudio` pops the engine's SPSC queue from the game thread while the audio thread pumps it (data race); A2 the mouth solver's backlog still pushes controls after `Rest`; A3 a few in-flight frames may leak through on resume (data channel vs audio track); A4 a reply whose text event was lost (`text_delivery_failed`) stays silent in Unreal until the next turn; A5 the client silences on learner text, the worker already on `START_OF_SPEECH`; A6 parity with the web on a reply Phoenix stored as the turn went stale; A7 the sink is only detached on `EndPlay`; A8 `Rest` did not assert an empty mouth. Worker probes: an older barge-in never cancels a newer reply; `START_OF_SPEECH` over a settled reply stops it (fails at the baseline). Scratch copies removed.
- L8 (2026-10-25): correction batch. B1: `ResumePatient` only while `Running`; RED `a later sentence stays silent` (1 vs 2), GREEN. A2+A8: `FStationMouthState` ignores solved controls from `Rest` until `NoteSpeech`; RED `a late solved mouth is ignored` (0 vs 1), GREEN. A1: `UStationPatientWave` keeps its own locked buffer (`Push`, `Clear`, `OnGeneratePCMAudio`) instead of the engine queue, so clearing never races the audio thread; no failing-first test (a thread race is not drivable through the interface); covered by the sink specs, now reading what `GeneratePCMData` plays. Needs `AudioExtensions`. A3-A7 left as advisories. `PatientVoice.Unit+StationRun.Unit` 20/20.
- L9 (2026-10-25, user): "Antes de hacer esas pruebas quiero probar el simulador, osea charlando y que me responda". Real providers, Unreal client.
- L10 (2026-10-25, user): "No estoy escuchando la voz, me reconoce lo que estoy diciendo pero no responde". Phoenix log: every voice turn `POST .../transcripts` was followed at once by `POST .../cancel` for the same turn, and the generated reply ended `409`. LiveKit showed the Unreal learner track active about every second at level 0.125 while the learner was silent. Cause: Deepgram `SpeechStarted` (plugin `vad_events`, default on) fires on noise and breath and is not tied to an endpoint; the plugin turns it into `START_OF_SPEECH`, which `TurnManager.on_speech_event` treats as barge-in and so cancels the pending turn. Pre-existing on the baseline; the web client's capture was quieter. Fix: `deepgram.STT(vad_events=False)`, so the plugin starts an utterance on its first transcribed words (`stt.py` "a transcript without a SpeechStarted event"). RED `test_voice_activity_without_words_starts_no_utterance` (None is not False), GREEN worker suite OK.
- L11 (2026-10-28, user): "Funciona bien, ya hice todos los pasos" — by-eye cases 1-6 in the editor (interrupting the patient mid-reply, finishing while it speaks, late replies) pass. develop merged again (d162152, #411 patient prompt, backend only; no Unreal or worker change, no rebuild).
- L12 (2026-10-28): suites on d162152. Worker 249 OK. Scripted Phoenix `StationClient+StationRun.Phoenix+StationRun.Unit` 72/72. Voice stack 37/37 on two reruns; the first run failed `StationVoice.Stack.leaves the room when the run finishes` with "The voice worker did not join within 20 seconds." (worker cold start, the same intermittent failure as on 2026-10-25; it never touches #193 code). Diff vs develop: 529 lines, 50 of them this document; Unreal alone is 410 and #410 is stacked on this branch, so no cohesive split fits 400: one PR, size noted.
