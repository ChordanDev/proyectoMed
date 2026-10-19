# Deepgram transcription and ElevenLabs patient voice (#253)

Parent: #237 (clinician demo readiness). Branch `feat/253-deepgram-elevenlabs-voice`
from `feat/237-clinician-demo-readiness`; PR targets the parent branch with `Refs #253`.

## Objective

Let the turn-based web voice ("Usar voz" / "Ouvir resposta") run without OpenAI:
speech-to-text through Deepgram's pre-recorded API (pt-BR) and text-to-speech through
ElevenLabs, selected by one setting. Without that setting the OpenAI path is unchanged.

## Why

The maintainer decided on 2026-10-19 to run the clinician demo without OpenAI. Deepgram
and ElevenLabs keys already exist from the real-time voice prototype (#116).

## Constraints

- Keep `Transcription.transcribe/4` and `TTS.synthesize/4` contracts: formats, size and
  text limits, consent and session checks, error atoms, the JSON shape of
  `/transcribe` and the `audio/mpeg` (mp3) body of `/synthesize`. The web is unchanged.
- Provider failures keep mapping to the existing `:openai_unavailable` outcome (502 in
  the controllers), so the web fallback behaves exactly as today.
- Never log audio, transcripts or synthesized text. Missing keys make voice
  unavailable exactly as a missing OpenAI key does today.
- Reference choices from `feat/116-realtime-voice`: Deepgram `nova-3`, `pt-BR`;
  ElevenLabs `eleven_flash_v2_5` (low latency, pt-BR) with a configured voice id.
- `runtime.exs` and `README.md` are edited in parallel by #252: additions live in their
  own clearly separated blocks.
- No live calls in tests (stubbed `Req`). The live check stays pending until the
  maintainer runs it with real keys.

## Tasks

- [ ] T1 Deepgram transcription provider behind `:voice_provider` (route: inline, one
  new module + one edited module; tests in `backend/test/backend/transcription_test.exs`).
- [ ] T2 ElevenLabs speech provider behind `:voice_provider` (route: inline, one new
  module + one edited module; tests in `backend/test/backend/tts_test.exs`).
- [ ] T3 Runtime configuration (`VOICE_PROVIDER`, `DEEPGRAM_*`, `ELEVENLABS_*`) and README
  documentation (route: inline, config + docs only).
- [ ] T4 Live check on acute-appendicitis with real keys (maintainer; pending).

## Acceptance criteria

- With the provider setting and a stubbed HTTP client, transcription sends a well-formed
  Deepgram request and maps a transcript, an empty result, a timeout and an HTTP error
  to the existing outcomes.
- Speech sends a well-formed ElevenLabs request and returns playable mp3 audio, or maps
  a failure to the existing outcomes.
- Without the setting, the OpenAI voice path is unchanged.
- README documents the variables.

## Checks

- `cd backend && mix test test/backend/transcription_test.exs test/backend/tts_test.exs`
- Local CI script (mirrors `.github/workflows/pr-validation.yml`).

## Progress

(updated per task)

## Next step

T1.
