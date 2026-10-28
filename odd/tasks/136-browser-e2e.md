# 136 — Verify the complete learner journey in a real browser

Issue: #136 (tracking parent #22). Branch: `feat/136-browser-e2e`, cut from `develop` at `6f82902`. Target of the pull request: `develop`. Test runner: Playwright (`npm --prefix web run test:browser`), plus ExUnit for the backend switch.

## Specs

- **S1** "The suite launches the supported SPA and Phoenix runtime in a real browser and drives the UI from notice through session start, interaction, finish, result, and discard."
- **S2** "Automated scenarios cover the authoritative countdown, manual and timer completion, text input, microphone permission granted/denied, voice-to-text fallback, patient-text rendering, playback failure, technical invalidation, expiry, restart, and cleanup."
- **S3** "Browser media tests use deterministic fake media and provider doubles; no production credential is required for the automated suite."
- **S4** "A documented HITL smoke checkpoint covers one real microphone path, patient-audio playback, interruption-to-silence behavior, keyboard navigation, screen-reader-relevant semantics, and supported-browser permission behavior."
- **S5** "The suite proves that no stale patient output or result appears after cancellation, technical invalidation, expiry, or explicit discard."
- **S6** "Browser E2E results are reported separately from Vitest, ExUnit, and the HTTP/API integration harness, with reproducible diagnostics and non-zero failure status."
- **S7** "The standard verification documentation names prerequisites and the exact runner command; existing `bash scripts/test.sh` remains green."

## Decisions

- **One Phoenix and one Vite per spec file.** A worker-scoped Playwright fixture boots the existing E2E harness (`web/src/integration/harness.ts`) with the file's provider doubles, then a Vite dev server whose `/api` proxy points at that Phoenix. One worker runs the files in turn.
- **Provider doubles in the shared harness.** The mock OpenAI server now also answers `POST /v1/audio/transcriptions` (fixed text) and `POST /v1/audio/speech` (a generated silent MP3), each with an optional failure status. The HTTP/API suite's defaults are unchanged.
- **Timer completion needs a short station.** `E2E_STATION_DURATION_MS`, honored only under `:dev` like the other E2E switches, sets `station_duration_ms`.
- **Microphone permission.** Headless Chromium has no prompt: without `--use-fake-ui-for-media-stream` every `getUserMedia` fails with `NotSupportedError`, whatever the context permissions. The project grants with that switch; the denied spec uses `--use-fake-ui-for-media-stream=deny`, which rejects with `NotAllowedError`.
- **Technical invalidation** follows SPEC_MVP ("A 5xx, network timeout, or missing session id invalidates the station"): a network failure on a turn, and a session the server no longer has. **Cancellation** is leaving the page mid-station (the pagehide keepalive discard).
- **Separate report.** `test:browser` stays out of `scripts/test.sh`; CI runs it in its own `browser-e2e` job that is not a required check.

## Tasks

- [x] **T1 — Backend switch `E2E_STATION_DURATION_MS`.** S2. Route: inline. RED: `e2e_station_duration_config_test.exs`, 1 of 4 failed before the `runtime.exs` change; GREEN after.
- [x] **T2 — Harness doubles for transcription and speech.** S3. Route: inline. Existing `npm run test:e2e`: 4 passed after the change.
- [x] **T3 — Playwright suite.** S1, S2, S3, S5. Route: inline. 11 scenarios in 6 spec files: 11 passed locally (38.8 s). `bash scripts/test.sh`: exit 0 (342 web unit, 2500 ExUnit, 4 HTTP E2E); one earlier run timed out the HTTP "Technical Failure" scenario at Vitest's 5 s default under heavy machine load, and three reruns passed. Mutation check: computing the countdown from `Date.now()` instead of the anchored server clock makes the device-clock scenario fail.
- [x] **T4 — HITL checkpoint, README, CI job.** S4, S6, S7. Route: inline. `docs/operations/browser-e2e-smoke.md`, README "Browser E2E (Playwright)", `browser-e2e` job in `pr-validation.yml`.

## Log

- **L1** (2026-10-28) Implement issue #136 of ChordanDev/proyectoMed: "Ticket 17: Verify the complete learner journey in a real browser". Add a Playwright browser E2E suite (new web/e2e/ folder, playwright.config.ts, a new `test:browser` npm script) that boots Phoenix (reusing the E2E harness approach, JEV_E2E_APPROVING_ADAPTER, mocked provider replies) plus the Vite SPA and drives notice -> start -> interact -> finish -> result -> discard with Chromium fake-media flags. Add a documented HITL smoke checkpoint and a README Test section naming prerequisites and the runner command, keeping `bash scripts/test.sh` green and reporting browser results separately (optionally a separate non-blocking CI job).
- **L2** (2026-10-28) The first denied-microphone scenario passed for the wrong reason (`NotSupportedError` from the missing prompt switch, not a denial); fixed by the explicit grant/deny switches above.
