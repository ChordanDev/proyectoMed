# #419 Push-to-talk for the learner's voice in the Unreal client

Objective: in an Unreal voice training the learner's audio reaches the voice worker only while a key or an on-screen button is held, and releasing it ends the turn at once.
Branch: `feat/419-push-to-talk` from `develop` (37c96a6). Delivery: ask-on-risk. Runners: `uv run --locked python -m unittest discover` in `voice-worker`; `scripts/run-unreal-tests.sh` (unit specs), voice specs inside `scripts/run-voice-stack.sh`.

## Specs

- S1 Audio reaches the worker only while the key or the on-screen button is held: "que solo mande audio cuando estamos tocando el botón".
- S2 Releasing ends the turn without the multi-second wait: "cuando dejamos de tocar el botón mande el audio". Today the worker waits for Deepgram's end of speech: "el micrófono parece como que no sabe cuándo terminó la oración. Entonces se queda esperando a ver si digo algo más. Y a veces tarda un par de segundos."
- S3 (PO, 2026-10-29) The key is the space bar. While the typed-reply text box has focus, the space bar types and never opens the microphone. iPad: an on-screen button ("con un botón en la pantalla para el caso de iPads").
- S4 (PO, 2026-10-29) While the patient answers, a single press does nothing (neither cuts the patient nor opens the microphone). A tap followed by a held press cuts the patient at the second press and opens the microphone while it is held; releasing sends the turn. The on-screen button uses the same gesture. PO: "si el paciente está hablando, quisiera que ni bien al apretar se corte pero es verdad que puede haber un corte por accidente, por ello, es mejor que toque dos veces la barra espaciadora para cortar y empezar a hablar".
- S5 (PO, 2026-10-29) The hold-to-speak exam button (#364) becomes the exam push-to-talk: holding it opens the microphone with the exam mode armed, releasing sends the request at once. It gets its own shortcut, Shift + space bar, with the same behaviour and the same tap-then-hold rule while the patient answers. Needs #364 (PR #414) in `develop`.
- S6 (PO, 2026-10-29) The always-open microphone is removed from the Unreal client. The web client keeps its always-open microphone.
- S7 The learner token stays without data publishing (#364 S4): the release is signalled by muting the LiveKit microphone track, never by a data message.
- S8 (derived) Worker contract. A learner whose microphone track has been muted is on push-to-talk for that connection: Deepgram's end of speech no longer ends a turn; an unmute is a press and interrupts the patient at once (as a start of speech, #193); a mute is a release: the worker asks Deepgram to finalize and commits the turn once the transcript settles, with a bound. Transcript that arrives after that commit and before the next press belongs to the committed turn and is dropped. Pressing again before the commit continues the same turn. A connection never muted (the web client) keeps Deepgram's end of speech.
- S9 `docs/unreal-setup.md` "Voice trainings" and the README runbook describe push-to-talk.

## Tasks

| ID | Specs | Route | Status | Commit / evidence |
|----|-------|-------|--------|-------------------|
| T1 | S2, S7, S8 | inline | done | RED 6 (no `push_to_talk` module, no fake `flush`, mutes ignored); GREEN worker suite 280/280, ruff, pyright |
| T2 | S1, S6, S7 | inline | pending | |
| T3 | S1, S3, S4, S6 | inline | pending | |
| T4 | S5 | inline, after #414 merges | pending | |
| T5 | S9 | inline | pending | |
| T6 | S1-S5 by eye (human) | human | pending | |

T1: voice worker push-to-talk (mute/unmute → finalize and commit, press barge-in). T2: `FStationVoiceLink` publishes the microphone muted and opens it only on request. T3: push-to-talk gesture (space bar, tap-then-hold while the patient answers), wired into `UStationRunFlow` and the HUD button. T4: exam push-to-talk and Shift + space bar. T5: docs.

## Log

- L1 (2026-10-29, PO, verbatim) "el micrófono parece como que no sabe cuándo terminó la oración. Entonces se queda esperando a ver si digo algo más. Y a veces tarda un par de segundos. Creo que lo mejor que podríamos hacer es que el micrófono sea más mecánico y solo se active cuando se toca una letra que especificamos en el teclado o con un botón en la pantalla para el caso de iPads y que solo mande audio cuando estamos tocando el botón y cuando dejamos de tocar el botón mande el audio."
- L2 (2026-10-29) Decisions S3-S6 asked one at a time and recorded on #419. Exam shortcut Shift + space bar was the example in the chosen option; the PO can change it.
- L3 (2026-10-29) Evidence. Worker: `ENDPOINTING_MS = 500` and the turn commits at `END_OF_SPEECH` (`transcripts.TurnTracker.handle`). The Deepgram plugin (livekit-plugins-deepgram 1.8.3) sends `Finalize` on `stream.flush()` and keeps the socket alive with `KeepAlive` every 5 s while no audio flows. Deepgram does not guarantee a `from_finalize` response (https://developers.deepgram.com/docs/finalize), and the plugin does not expose it, so the commit waits for the transcript to go quiet, with a bound. LiveKit C++ SDK 1.12.3 `LocalAudioTrack::mute()` keeps the track published; Python `rtc.Room` emits `track_muted`/`track_unmuted`. The web client only calls `setMicrophoneEnabled(true)`, so it never mutes.
- L4 (2026-10-29) T1: `voice-worker/push_to_talk.py` wraps the transcription stream in `transcribe()`; `follow_push_to_talk` listens to the learner's microphone `track_muted`/`track_unmuted` and stops on leaving. Release settles after 0.3 s of quiet transcript, at most 1.5 s, both to tune by eye (T6). Risk: item 4 (async ordering of mutes and transcript events).
