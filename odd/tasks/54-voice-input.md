# Voice Input and Text Fallback (#54)

## Goal
Add opt-in voice input through Phoenix-proxied transcription (`POST /api/stations/active/sessions/:id/transcribe`) while preserving a usable text fallback for the rest of the session.

## Acceptance Criteria
- Voice input is unavailable until audio consent is granted in NoticeScreen.
- Audio is sent to the Phoenix transcription endpoint, which proxies OpenAI STT.
- When transcription is unavailable (permission denied, 5xx, network error), the learner can continue with text input and an inline notice "Voz indisponível — usando texto." is displayed without crashing.
- On success, the transcribed message is added to the transcript and sent to `POST /messages` with `modality: "voice"`.
- `bash scripts/test.sh` exits 0.

## Tasks
- [x] Task 1: Add `transcribeAudio` to `api/client.ts` and unit tests in `api/client.test.ts`
- [x] Task 2: Add `transcribe` to `hooks/useStation.ts` and unit tests in `hooks/useStation.test.ts`
- [x] Task 3: Add voice recording UI and fallback logic to `screens/StationScreen.tsx`, `screens/StationScreen.css`, and `i18n/pt-BR.json`
- [x] Task 4: Connect voice input and consent in `App.tsx` and update `App.test.tsx`
- [x] Task 5: Add comprehensive tests in `screens/StationScreen.test.tsx` for mic recording, permission denial, API failure, and text fallback
- [x] Task 6: Full verification across web and backend (`npm --prefix web test`, `npm --prefix web run build`, `npm --prefix web run lint`, `bash scripts/test.sh`)

## Surfaces
- `web/src/features/station/api/client.ts`
- `web/src/features/station/api/client.test.ts`
- `web/src/features/station/hooks/useStation.ts`
- `web/src/features/station/hooks/useStation.test.ts`
- `web/src/features/station/screens/StationScreen.tsx`
- `web/src/features/station/screens/StationScreen.css`
- `web/src/features/station/screens/StationScreen.test.tsx`
- `web/src/features/station/i18n/pt-BR.json`
- `web/src/features/station/index.ts`
- `web/src/App.tsx`
- `web/src/App.test.tsx`

## Verification evidence
- `npm --prefix web test`: 71 tests passed (was 61; +10 voice/fallback tests).
- `npm --prefix web run build`: typecheck + Vite build OK.
- `npm --prefix web run lint`: 0 errors.
- `bash scripts/test.sh`: 71 web Vitest + 157 backend ExUnit passed, exit 0.
