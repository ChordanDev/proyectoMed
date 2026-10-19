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

- [x] T1 Deepgram transcription provider behind `:voice_provider` (route: inline, one
  new module + one edited module; tests in `backend/test/backend/transcription_test.exs`).
- [x] T2 ElevenLabs speech provider behind `:voice_provider` (route: inline, one new
  module + one edited module; tests in `backend/test/backend/tts_test.exs`).
- [x] T3 Runtime configuration (`VOICE_PROVIDER`, `DEEPGRAM_*`, `ELEVENLABS_*`) and README
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

- T1 `fdfc8e7` feat(voice): Deepgram transcription. RED: 4 of 19 transcription tests
  failed (request shape, configured model/content types, transcript mapping, empty
  result); the timeout, HTTP error, malformed body and missing key tests already
  passed through the OpenAI path, which maps them to the same outcome. GREEN: 19/19,
  plus 8/8 transcription controller tests.
- T2 `e47d550` feat(voice): ElevenLabs speech. RED: 3 of 19 TTS tests failed (request
  shape, configured model/voice, missing ElevenLabs key or voice id); the failure
  mappings already passed through the OpenAI path. GREEN: 19/19, plus 7/7 TTS
  controller tests.
- T3 runtime configuration and README (config + docs, no runnable RED). Structural
  check: `Config.Reader.read!("config/runtime.exs", env: :dev)` with the variables
  set yields `voice_provider: :deepgram_elevenlabs`, the key and the trimmed voice id;
  a blank variable is ignored; `env: :test` reads none of them.
- Provider docs checked on 2026-10-19: Deepgram `/v1/listen` (`Authorization: Token`,
  `model`, `language`, `smart_format`, `results.channels[].alternatives[].transcript`,
  `metadata.duration`); ElevenLabs `/v1/text-to-speech/{voice_id}` (`xi-api-key`,
  `text`, `model_id`, `output_format` default `mp3_44100_128`). The raw-audio body
  for Deepgram follows the reference branch and Deepgram's documented binary upload
  (the reference page only shows the URL form).
- Local CI (mirror of `.github/workflows/pr-validation.yml`) on `547af81`: LOCAL CI
  PASSED — web unit 213/213 (9 files), backend ExUnit 1200 passed, E2E 4/4, `tsc`,
  ESLint, `mix format --check-formatted`, Credo and Dialyzer clean. GitHub Actions is
  blocked by billing.
- T4 pending: live check needs the maintainer's keys.

## Next step

Maintainer live check (T4) on acute-appendicitis with real Deepgram and ElevenLabs keys.
