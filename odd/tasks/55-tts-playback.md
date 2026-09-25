# TTS Playback and Fallback (#55)

## Goal
Add opt-in speech playback of patient replies through the Phoenix synthesis endpoint
(`POST /api/stations/active/sessions/:id/synthesize`) with a non-audio fallback: the reply
text always stays available to the learner.

## Scope
- Web only (`web/src/features/station` + `web/src/App.tsx`). Backend `/synthesize` already exists (#33).
- Branch `feat/55-tts-playback` from parent `feat/30-expo-screens`; child PR targets the parent with `Refs #55`.

## Constraints
- No direct provider call from the browser; audio comes only from Phoenix.
- Timestamp: playback does not need one, so `x-synthesized-at` is intentionally not read (acceptance allows omitting it).
- Playback is opt-in: requires audio consent and an explicit per-message play action.
- On synthesis or playback failure: keep the text, hide the play button for that message, never retry automatically (parent #30).
- Push-to-interrupt (issue comment): starting a recording or sending a new turn stops any playing audio.

## Acceptance Criteria
- Playback uses the Phoenix synthesis endpoint rather than a direct provider call.
- The response uses `synthesized_at` when a timestamp is needed, or omits an unnecessary timestamp.
- A synthesis or playback failure leaves the text reply available to the learner.

## TDD
- Mode: strict, source: global orchestrator config (`Strict TDD Mode: enabled`).
- Runner: `npm --prefix web test` (Vitest + RTL, jsdom).

## Tasks
- [x] T1 (delegated writer — writer trigger: 5+ non-trivial files): `synthesizeSpeech` in `api/client.ts`, `synthesize` in `hooks/useStation.ts`, per-message play button + fallback + interrupt in `screens/StationScreen.tsx`/`.css`, i18n strings, wiring in `App.tsx`, tests for each layer.
- [x] T2 (inline): real smoke through Vite proxy → Phoenix → fake OpenAI-compatible server, full checks.

## Checks
- `npm --prefix web test`
- `npm --prefix web run build`
- `npm --prefix web run lint`
- `bash scripts/test.sh`

## Delivery
- Strategy: `ask-on-risk`. Forecast ~300–400 authored lines.

## Progress / Evidence
- T1: writer RED observed per layer (client `synthesizeSpeech is not a function`, hook `synthesize is not a function`, screen missing `play-button`) → GREEN. Parent refactor: folded the duplicated `requestBlob` into `request` via a `readBody` reader + `decodeAudio`.
- T2 real smoke (fake OpenAI-compatible server on :4010, `OPENAI_BASE_URL` → Phoenix :4000 → Vite proxy :5173, headless Google Chrome via playwright-core):
  - `curl` `/synthesize` through the Vite proxy returns the exact audio bytes; a provider 500 maps to 502 `openai_unavailable`.
  - Chrome: reply rendered, "Ouvir resposta" → audio really plays (`currentTime` 0.32s of 2.96s, not paused), label switches to "Parar áudio".
  - Push-to-interrupt: sending a new turn paused playback.
  - Synthesis failure: reply text stays, play button hidden for that message only, exactly 1 synth request (no retry); earlier message stays playable.
  - No request to a provider host from the browser.
- Checks: `npm --prefix web test` 86/86; `npm --prefix web run build` OK; `npm --prefix web run lint` 0 errors; `bash scripts/test.sh` 86 web + 157 backend passed.
- Commit: `feat(web): TTS playback with text fallback (Refs #55)`. RDD: off (global) → no native review; `review assess` tier medium (`slice_budget_reached`, 644 lines — one coherent client→hook→screen→wiring slice with tests, not split).

## Next
- Child PR `feat/55-tts-playback` → `feat/30-expo-screens` with `Refs #55` (push/PR on user approval).
