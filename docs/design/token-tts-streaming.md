# Token TTS streaming (issue #313)

Parent: #237. The user prefers fluency and asked to try word-by-word streaming of the patient reply to ElevenLabs and to measure how much it lowers the response time.

## What was built

| Piece | Where |
| --- | --- |
| `VOICE_TTS_STREAMING=sentence\|token` (default `sentence`, validated at boot) | `backend/config/runtime.exs`, `SpeechDeltas.mode/0` |
| Word-aligned, stage-direction-free deltas of the reply so far | `Backend.Stations.StationAI.SpeechDeltas` |
| Delta hook with abort (BoundedReply violation, refused/regenerated sentence, failure) | `SentenceStream` `:delta` option |
| `delta` and `abort` NDJSON lines, only for a worker that sends `deltas: true` | `VoiceWorkerController`, `Stations.stream_voice_turn/6` |
| One ElevenLabs streaming-input stream per generation, fed by deltas | `PatientVoice.on_delta`, `SpeechPlayer.speak(feed=...)`, `TextFeed` |
| Per-stage timing marks, the same in both modes | `voice_turn_timing` (Phoenix), `first patient audio ... (mode=... first_text=... first_tts_push=...)` (worker) |
| Scripted comparison | `voice-worker/measure_tts_streaming.py` |

Rules in token mode:

- Deltas start after the `[PACIENTE]` marker is parsed; the marker is never sent. An examiner turn sends nothing.
- Before each delta, `BoundedReply` checks the accumulated text. A violation sends `abort`: the worker stops the audio at once, and the reply so far takes the sentence verification, so the first sentence gets the single regeneration (spoken sentence by sentence) and a later one the refusal path (the verified sentences are stored).
- Sentence lines still flow, for the transcript; the worker does not synthesize them again.
- `PATIENT_VERIFICATION=blocking` keeps sentence mode: deltas would be spoken before any Jev verdict.
- ElevenLabs plugin (livekit-plugins-elevenlabs 1.8.3, read from the installed source): `TTS.stream()` uses the `multi-stream-input` websocket. Its default `auto_mode=True` tokenizes by sentence, so the worker sets `auto_mode=False` (word tokenizer) and `chunk_length_schedule=[50, 90, 120, 160]` (50 is the API minimum). `TTS.synthesize()`, used by sentence mode, ignores both.

## Measurement (2026-10-21, `acute-appendicitis`)

Setup: an own Phoenix on port 4313 (`PATIENT_VERIFICATION=audit`, Claude Haiku 5.5 patient), restarted per mode, and `measure_tts_streaming.py` driving the real worker pipeline (TurnManager, PatientVoice, SpeechPlayer, the real ElevenLabs API, `eleven_flash_v2_5`, `pcm_24000`) with an in-memory room. Three runs of the 10-turn #290 replay per mode, 30 turns each; all committed.

Not a true end-to-end audio measurement: there is no LiveKit room and no Deepgram, so "speech end" is the moment the final transcript is committed (Deepgram's endpointing, 500 ms, and LiveKit transport come on top, equal in both modes), and "first audio" is the first PCM frame ElevenLabs returned, pushed to the room source.

Medians over 30 turns, ms. Phoenix marks are from the start of the Phoenix turn; worker marks from speech end.

| Stage | Sentence | Token |
| --- | --- | --- |
| Phoenix: first model token | 797 | 878 |
| Phoenix: addressee marker parsed | 797 | 878 |
| Phoenix: first text handed to the worker | 919 | 899 |
| Phoenix: first token → first text | 112 | 17 |
| Worker: first text received | 957 | 934 |
| Worker: first text pushed to TTS | 957 | 939 |
| Worker: first TTS push → first audio | 346 | 379 |
| **Worker: speech end → first audio** | **1318** | **1307** |

Per run (speech end → first audio): sentence 1314 / 1382 / 1340, token 1300 / 1636 / 1254.

## Reading

Token mode gains about 10 ms at the median, within run-to-run noise. Two reasons:

1. Haiku produces the whole one- or two-sentence reply about 110 ms after its first token, so waiting for the first full sentence costs little; that 110 ms is the ceiling of what token streaming can save on the Phoenix side, and token mode does remove it (17 ms).
2. ElevenLabs' streaming input then waits for 50 characters before generating, about one short sentence, and its time to first audio over the websocket (≈380 ms) is not better than the HTTP endpoint's (≈350 ms). The Phoenix-side saving is spent there.

The response time is dominated by the model's time to first token (≈800 ms) and ElevenLabs' time to first audio (≈350 ms). Recommendation: keep `VOICE_TTS_STREAMING=sentence` (the default); token mode stays available behind the flag for longer replies or a slower model, where the first sentence takes longer to complete.

## Follow-ups

- The bigger levers are the time to first token (prompt size, model, region) and the TTS first byte; worth a separate issue if fluency is still the goal.
- The README configuration table (outside this issue's edit surface) does not list `VOICE_TTS_STREAMING` yet.
