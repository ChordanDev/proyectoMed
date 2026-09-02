## Problem Statement

A doctor trained abroad needs a safe, focused, low-cost way to rehearse one clinical station for Brazil's Revalida. Today the product has only a scaffolded Phoenix API and an Expo runtime placeholder; there is no station, no conversation, no rubric-bound feedback, and no validation of the learner experience. The user must be able to open the app, complete the station in Portuguese using voice and text under a ten-minute countdown, and immediately understand what they did well, what they missed, and what to practice next — without accounts, subscriptions, or stored personal history.

## Solution

Deliver a single Expo app for iOS and Android distributed internally through Expo Go, backed by a Phoenix API that loads one original clinical Station Package authored outside the repo by the Content Partner. The learner starts a session, talks to the Station AI by voice or text, ends the station manually or at the timer, and sees rubric-bound feedback with highlighted transcript excerpts. All session data is ephemeral. No clinician workspace, no accounts, no server-side personal history. The Content Partner prepares the station as a versioned structured package; the system executes the experience.

## User Stories

1. As a learner, I want the app to show a short notice in pt-BR explaining that it is an independent educational tool and not an official Revalida-readiness assessment, so that I understand the limit of the result before I start.
2. As a learner, I want to confirm I am not entering real patient data and proceed, so that the practice reflects the intended scenario without mixing clinical data.
3. As a learner, I want the app to start a ten-minute countdown when I begin the station, so that I practice under Revalida-like time pressure.
4. As a learner, I want to speak to the Station AI in pt-BR and see its response in text at the same time, so that I can practice the oral station with a readable transcript.
5. As a learner, I want to type instead of speaking when my microphone or connectivity is unavailable, so that the experience continues.
6. As a learner, I want the Station AI to use only the facts prepared for the station, so that I cannot be misled by invented clinical information.
7. As a learner, I want to end the station manually before the timer runs out, so that I can move on when I believe I have finished.
8. As a learner, I want the timer to end the station automatically at zero, so that I never stay past the intended practice window.
9. As a learner, I want the feedback screen to show each rubric criterion as met, omitted, or uncertain, so that I understand my performance per skill rather than as a single grade.
10. As a learner, I want the feedback screen to highlight the transcript excerpts that justify each criterion, so that I can verify the feedback against what I said.
11. As a learner, I want a short recommendation on what to practice next, so that I can keep improving between sessions.
12. As a learner, I want to restart the station at any time during the pilot, so that repetition is always available.
13. As a learner, I want any technical failure during the station to invalidate that attempt without partial feedback or penalty, so that a broken session is treated fairly.
14. As a learner, I want my session data to disappear when I leave the result screen, so that no personal history is retained.
15. As a learner, I do not want to see pass/fail language or any claim that I am ready for Revalida, so that I keep realistic expectations about the result.
16. As a Content Partner, I want to author the one station as a versioned structured package outside the app, so that clinical content stays under my control and the system never invents cases.
17. As a Content Partner, I want my package to constrain the Station AI to approved facts and response rules, so that the simulated patient behaves consistently with the case.
18. As a Content Partner, I want my package to declare the rubric criteria, so that the system can evaluate the learner against my intent.
19. As a project owner, I want to recruit pilot learners and measure outcomes outside the app, so that the application stays focused on the learner experience.
20. As a project owner, I want the MVP Continuation Criterion to be answerable from the feedback screen only, so that I do not need to instrument the application to validate the prototype.

## Implementation Decisions

### Architecture and runtime

- The MVP runtime stays an Elixir/Phoenix backend and a React Native Expo frontend targeting iOS and Android distributed via Expo Go.
- The Phoenix API is the only public surface for the MVP. It loads exactly one Station Package at boot from `priv/stations/<id>/package.json` (no database, no admin endpoints).
- All session state lives in an in-memory ETS table keyed by session id with a short safety timeout; the table is wiped on shutdown or expiry.
- The Expo app speaks to the backend over HTTP. It does not persist anything beyond the current view.
- `scripts/test.sh` is the only test command. New tests are wired into the existing Jest (Expo) and ExUnit (Phoenix) suites.

### Station Package format (seam: external file, loaded at boot)

The package is a single JSON file at `priv/stations/<id>/package.json`. It defines exactly:

- `station_id`, `version`, `language` (pt-BR), `display_title`.
- `patient_profile`: persona, age, presenting context, tone.
- `revealable_facts`: a list of facts keyed by topic. The Station AI may only answer using facts present in this list.
- `response_rules`: rules the Station AI must follow (politeness, length cap, refusal to invent facts, refusal to roleplay non-clinical scenarios).
- `expected_actions`: ordered or unordered list of clinician actions the learner should demonstrate during the station.
- `rubric`: list of feedback criteria. Each criterion has `id`, `description`, `weight` (informational, no global score), `evidence_questions` (questions the evaluator asks the transcript to decide met/omitted/uncertain), and `practice_recommendation` (free text used when the criterion is omitted or uncertain).
- The package is loaded once at boot. A different `package.json` requires an app restart. No hot reload, no admin UI.

### API contract (seam: Phoenix REST under `/api/stations`)

- `GET /api/stations/active` → `{ station_id, version, display_title, language }`.
- `POST /api/stations/active/sessions` → creates a session, returns `{ session_id, started_at, expires_at, server_now }`.
- `POST /api/stations/active/sessions/:id/messages` with `{ role: "learner", modality: "voice" | "text", text }` → `{ reply_text, reply_audio_url?, server_now }`. The endpoint accepts text; voice is transcribed on-device before the call.
- `POST /api/stations/active/sessions/:id/finish` with optional `{ reason: "user" | "timer" }` → `{ session_id, completed_at }`.
- `GET /api/stations/active/sessions/:id/result` → `{ session_id, status, criteria: [{ id, status: "met" | "omitted" | "uncertain", evidence: [transcript_excerpts], recommendation }] }`.
- All errors return JSON `{ "error": "code", "message": "human-readable pt-BR" }`. Invalid session ids return 404; expired sessions return 410.
- A session that is not accessed for the safety timeout becomes invalid; the next request returns 410 and the backend deletes its record.

### Backend modules

- `Backend.StationLoader` — reads and validates the package at boot. Crashes loudly if the package is missing or malformed.
- `Backend.Conversation` — owns the in-memory session state. Functions: `start/0`, `append_message/2`, `complete/2`, `fetch/1`.
- `Backend.StationAI` — given the package and conversation so far, returns the next reply constrained to `revealable_facts` and `response_rules`. Implementation choice between a thin wrapper around an LLM provider and a rule engine is left for the implementation issue.
- `Backend.Evaluator` — given the package and final transcript, produces the criterion-level result. Returns `met`, `omitted`, or `uncertain` per criterion with evidence excerpts. No global score.
- `BackendWeb.StationController` — implements the JSON contract. Validates input shapes and returns the error codes listed above.
- The router gains a `scope "/api/stations", BackendWeb do ... end` block; existing `HealthController` and root route stay untouched.

### Frontend modules

- `mobile/src/api/client.ts` — typed HTTP client for the API. Exposes `getActiveStation`, `startSession`, `sendMessage`, `finishSession`, `fetchResult`. Throws typed errors.
- `mobile/src/hooks/useStation.ts` — React hook that owns the session lifecycle and timer state.
- `mobile/src/screens/NoticeScreen.tsx` — pt-BR educational-use notice with a single "Entendi" button.
- `mobile/src/screens/StationScreen.tsx` — voice + text input, transcript list, Station AI replies with synthesized speech (when voice is enabled) and visible text, ten-minute countdown, "Finalizar estação" button.
- `mobile/src/screens/ResultScreen.tsx` — per-criterion status list with highlighted transcript excerpts and practice recommendations.
- `mobile/src/i18n/pt-BR.json` — all learner-facing strings.
- Voice capture uses `expo-av`; transcription happens on-device before posting the message to the backend. Text is always available as a fallback input.

### Failure policy

- A 5xx, network timeout, or missing session id invalidates the station: the client shows a short pt-BR notice ("a estação não pôde ser concluída; você pode reiniciar") and offers "Reiniciar estação". No partial feedback, no penalty.
- A microphone permission denial or STT failure surfaces a pt-BR notice and switches the input to text-only for that session. The station can still be completed.
- A timer-driven completion fires the same `finish` endpoint with `reason: "timer"`.

### Testing

- Good tests assert the external behavior of each module: HTTP responses, returned criteria, error codes, transcript excerpts selected for evidence.
- Backend coverage with ExUnit:
  - `Backend.StationLoaderTest` — happy path, malformed package, missing file.
  - `Backend.ConversationTest` — start, append, complete, expiry.
  - `Backend.StationAITest` — never invents facts; respects revealable facts list; uses response_rules.
  - `Backend.EvaluatorTest` — produces met/omitted/uncertain per criterion; selects transcript excerpts; returns no global score.
  - `BackendWeb.StationControllerTest` — every endpoint, every error code, the 410 on expired sessions.
- Frontend coverage with Jest + React Native Testing Library:
  - `client.test.ts` — typed errors, retry semantics, audio/text input mapping.
  - `useStation.test.ts` — countdown, manual finish, timer finish, technical failure path.
  - `ResultScreen.test.tsx` — criterion list with evidence highlights; no pass/fail language.
  - `NoticeScreen.test.tsx` — required notice text in pt-BR.
- Integration coverage: `scripts/test.sh` continues to be the only command. A new integration test boots the Phoenix endpoint from Jest and asserts the full learner loop (start → messages → finish → result).
- `strict_tdd: false` per the OpenSpec config; tests run after implementation. Coverage targets are per-file conventions, not a numeric threshold.

### Out of scope

- Clinician workspace, account management, subscription, billing, or any in-app authoring.
- Server-side personal history or retained learner transcript beyond the active session.
- Official Revalida material, public or internal; the case is original and inspired by Revalida skills.
- Web platform, multi-station library, station rotation, station editor.
- Patient avatars, 3D, video, or image capture.
- Store publication (App Store, Play Store, TestFlight). Distribution is Expo Go.
- Analytics, telemetry, or instrumentation inside the app. The project owner measures outcomes externally.
- Translation to languages other than pt-BR.
- Multi-leaderboard, sharing, or social features.

## Further Notes

- The implementation of `Backend.StationAI` is a single decision left to the implementation issue: a deterministic rule engine is enough for the MVP if it can satisfy the rubric; otherwise the issue may introduce one external LLM provider behind a thin adapter. The choice is documented in the implementation PR, not here.
- The single station package is provided by the Content Partner. Until the partner delivers the file, the implementation may ship a placeholder package clearly marked `placeholder: true` and `display_title: "Estação de demonstração"`. The placeholder must still pass the StationLoader validation and must not be promoted to the pilot.
- The session data lifecycle and safety timeout are listed as implementation details in the API contract; the actual timeout value (proposal: 30 minutes) is decided in the API contract issue, not here.
- After this spec is approved, the work streams are: API contract and Station Package format (seam 1), Phoenix backend (seam 2), Expo frontend (seam 3), integration and verification (seam 4). Each becomes its own implementation issue via `to-tickets`.
