## Problem Statement

A doctor trained abroad needs a safe, focused, low-cost way to rehearse one clinical station for Brazil's Revalida. Today the product has only a scaffolded Phoenix API and a Vite web SPA runtime placeholder; there is no station, no conversation, no rubric-bound feedback, and no validation of the learner experience. The user must be able to open the app, complete the station in Portuguese using voice and text under a ten-minute countdown, and immediately understand what they did well, what they missed, and what to practice next — without accounts, subscriptions, or stored personal history.

## Solution

Deliver a Vite + React + TypeScript web SPA for desktop and mobile browsers, backed by a Phoenix API that loads one original clinical Station Package authored outside the repo by the Content Partner. The learner starts a session, talks to the Station AI by voice or text, ends the station manually or at the timer, and sees rubric-bound feedback with highlighted transcript excerpts. All session data is ephemeral. No clinician workspace, no accounts, no server-side personal history. The Content Partner prepares the station as a versioned structured package; the system executes the experience.

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

- The MVP runtime is an Elixir/Phoenix backend and a Vite + React + TypeScript web SPA targeting desktop and mobile browsers.
- The Phoenix API is the only public surface for the MVP. It loads exactly one Station Package at boot from `priv/stations/<id>/package.json` (no database, no admin endpoints).
- All session state lives in an in-memory ETS table keyed by session id with a short safety timeout; the table is wiped on shutdown or expiry.
- The SPA speaks to the backend over HTTP from the browser. It does not persist anything beyond the current view.
- `scripts/test.sh` is the only test command. New tests are wired into the existing Vitest (web) and ExUnit (Phoenix) suites.

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
- `POST /api/stations/active/sessions/:id/messages` with `{ role: "learner", modality: "voice" | "text", text }` → `{ reply_text, reply_audio_url?, server_now }`. The text contract remains current; ADR-009 (#114) assigns prototype voice transport/transcription to LiveKit/WebRTC and Deepgram, with endpoint evolution owned by Ticket 13 (#116).
- `POST /api/stations/active/sessions/:id/finish` with optional `{ reason: "user" | "timer" }` → `{ session_id, completed_at }`.
- `GET /api/stations/active/sessions/:id/result` → `{ session_id, status, criteria: [{ id, status: "met" | "omitted" | "uncertain", evidence: [transcript_excerpts], recommendation }] }`.
- All errors return JSON `{ "error": "code", "message": "human-readable pt-BR" }`. Invalid session ids return 404; expired sessions return 410.
- A session that is not accessed for the safety timeout becomes invalid; the next request returns 410 and the backend deletes its record.

### Backend modules

The current code uses the following top-level modules. There is no `Backend.Stations` module in the current source; that context remains an accepted-but-unimplemented governance migration.

- `Backend.StationLoader` — reads and validates the package at boot. Crashes loudly if the package is missing or malformed.
- `Backend.Conversation` — owns the in-memory session state. Functions: `start/0`, `append_message/2`, `complete/2`, `fetch/1`.
- `Backend.StationAI` — given the package and conversation so far, returns the next reply constrained to `revealable_facts` and `response_rules`. Generation remains a distinct capability; a Jev decision-model adapter does not replace it.
- `Backend.Evaluator` — given the package and final transcript, produces the criterion-level result. Returns `met`, `omitted`, or `uncertain` per criterion with evidence excerpts. No global score under the current ADR-005 contract.
- `BackendWeb.StationController` — implements the JSON contract. Validates input shapes and returns the error codes listed above.
- The router gains a `scope "/api/stations", BackendWeb do ... end` block; existing `HealthController` and root route stay untouched.

The accepted architecture target exposes station operations through one `Backend.Stations` public context and keeps internals under `backend/lib/backend/stations/`. One shared Phoenix proxy/domain interface may host separate generation, transcription, text-to-speech, and decision-model adapters. This governance migration was accepted architecturally on 2026-09-21 but is not implemented and does not describe current module placement.

### Frontend modules

- `web/src/api/client.ts` — typed HTTP client for the API. Exposes `getActiveStation`, `startSession`, `sendMessage`, `finishSession`, `fetchResult`. Throws typed `ApiError`. Uses `import.meta.env.VITE_API_URL`.
- `web/src/hooks/useStation.ts` — React hook that owns the session lifecycle and concurrency state.
- `web/src/screens/NoticeScreen.tsx` — pt-BR educational-use notice with audio consent checkbox and a single "Entendi" button. Rendered with semantic HTML elements.
- `web/src/screens/StationScreen.tsx` — voice + text input, transcript list, Station AI replies, ten-minute countdown, "Finalizar estação" button.
- `web/src/screens/ResultScreen.tsx` — per-criterion status list with highlighted transcript excerpts and practice recommendations.
- `web/src/i18n/pt-BR.json` — all learner-facing strings.
- The accepted prototype voice plan uses LiveKit/WebRTC with Deepgram transcription and ElevenLabs speech synthesis (ADR-009, #114). Text input remains an equal fallback path. Ticket 13 (#116) and children #117–#121 own the corresponding media and orchestration migration.

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
- Frontend coverage with Vitest + @testing-library/react:
  - `web/src/api/client.test.ts` — typed errors, request decoding, timeout behavior, all API methods.
  - `web/src/hooks/useStation.test.ts` — full lifecycle, concurrency, manual and timer finish, failure paths (7 tests).
  - `web/src/screens/NoticeScreen.test.tsx` — required pt-BR notice text, checkbox consent gate, voice/text mode (13 tests).
  - `web/src/screens/ResultScreen.test.tsx` — criterion list with evidence highlights; no pass/fail language.
- Integration coverage: `scripts/test.sh` continues to be the only command.
- `strict_tdd: false` per the OpenSpec config; tests run after implementation. Coverage targets are per-file conventions, not a numeric threshold.

### Out of scope

- Clinician workspace, account management, subscription, billing, or any in-app authoring.
- Server-side personal history or retained learner transcript beyond the active session.
- Official Revalida material, public or internal; the case is original and inspired by Revalida skills.
- Native mobile apps (iOS/Android), Expo Go distribution.
- Multi-station library, station rotation, station editor.
- Patient avatars, 3D, video, or image capture.
- Store publication (App Store, Play Store). Distribution is via browser URL.
- Analytics, telemetry, or instrumentation inside the app. The project owner measures outcomes externally.
- Translation to languages other than pt-BR.
- Multi-leaderboard, sharing, or social features.

## Accepted Architecture: Dialogue Verification and PEP-Style Estimates (not implemented)

Everything in this section is accepted architecture, not implemented behavior. The governing design is `docs/design/jev-prototype.md`. [ADR-011 (#123)](https://github.com/ChordanDev/proyectoMed/issues/123) and [ADR-012 (#124)](https://github.com/ChordanDev/proyectoMed/issues/124) were accepted on 2026-09-21; [Ticket 14 (#125)](https://github.com/ChordanDev/proyectoMed/issues/125) and its children #126–#130 remain the implementation graph. Acceptance authorizes architecture only: it does not implement runtime behavior, activate a pilot or production deployment, select or approve a provider, accept privacy/ZDR/legal terms, establish clinical accuracy, authorize certification/pass-fail/readiness claims, or complete clinical pt-BR qualification.

- Deterministic deny rules run first and are deny-only. A known violation may route to a zero-clinical-content fallback only when the emitted text is the exact package/version-bound approved template and its applicability is deterministic; otherwise the candidate is blocked and the attempt follows the contract's invalidation path.
- The only ordinary bypass is an exact Approved Generic Reply with deterministic applicability. Shortness or length never authorizes text. "Estou bem" is eligible only when the authored case state makes it non-contradictory; "Não tenho alergias" is a clinical claim and is not generic.
- All other replies pass Jev before display or text-to-speech. Semantic refusal or low confidence permits at most one regeneration and full recheck within the total turn deadline. Jev timeout, malformed output, transport error, or provider 5xx is a technical failure: invalidate the attempt under the existing policy, with no fallback clinical text and no conversion to `uncertain`. Learner input may reach generation as untrusted evidence. Rejected or otherwise unverified patient candidates never enter trusted history or regeneration input, and text-to-speech receives only approved patient text.
- Jev is a decision-model seam, not the generation model. One shared Phoenix proxy/domain interface may host distinct generation, transcription, text-to-speech, and decision-model adapters.
- Evaluation consumes the full ordered, role-labelled session evidence. Independent questions over the same state are batched once; another call is allowed only for a real dependency or provider capacity limit. TypeSafe Choice/Noul-style outputs are constrained classifications or probabilities, not trusted evidence identifiers. Code selects and validates existing evidence IDs. If a provider cannot return IDs, deterministic span alignment is a separate implementation that must be specified and tested rather than invented by the model.
- Deterministic code applies counts, required sub-actions, order, veto, and cancellation rules and maps authored levels to exact decimal points. Patient-role words never earn learner credit. Impressos events from #105–#108 are required only for criteria that depend on those events.
- A numeric total exists only when every active criterion is assessed; otherwise the result shows a scored subtotal, scored and eligible maxima, and unresolved items. No rescaling or probability-weighted points.
- Results show a conspicuous pt-BR disclaimer before and on the result screen; no pass/fail, certification, readiness, or published-score claim. Example scores are explicitly fictitious fixtures.
- Privacy remains pending vendor validation: transient session state, zero default logging, no retained transcripts, with zero-data-retention terms and calibration still unverified.

### Architecture and tracker boundaries

- ADR-009 (#114) is **Accepted** and defines the prototype voice stack: LiveKit/WebRTC, Deepgram, and ElevenLabs. Ticket 13 (#116) has children #117–#121.
- The accepted Jev architecture integrates with, but does not duplicate, #119 (no patient response exits Phoenix before the safety boundary), #120 (only Phoenix-approved text reaches ElevenLabs), or #121 (cancellation, stale generation, failure recovery, and realism; not media, UI, or orchestration ownership).
- ADR-010 (#115) is **Proposed** and V3-only. It is not part of this prototype.
- The #105–#108 Impressos DAG is unchanged. Closed #27 and #44 remain prior evaluator and bounded-reply seams.
- [ADR-011 (#123)](https://github.com/ChordanDev/proyectoMed/issues/123), accepted on 2026-09-21, architecturally extends or supersedes the relevant ADR-002 safety contract with the Jev gate. [ADR-012 (#124)](https://github.com/ChordanDev/proyectoMed/issues/124), accepted on the same date, architecturally supersedes #38's no-score rule only for Educational Point Estimates; it preserves the prohibition on certification, pass/fail, and readiness claims. Neither decision describes implemented runtime behavior.
- [Ticket 14 (#125)](https://github.com/ChordanDev/proyectoMed/issues/125) is open with no labels and has exactly five native subissues. The architecture acceptance gate is resolved, and [#126](https://github.com/ChordanDev/proyectoMed/issues/126) has no native blockers. [#127](https://github.com/ChordanDev/proyectoMed/issues/127) owns the Jev adapter/gate and provider qualification (HITL; blocked by #126). [#128](https://github.com/ChordanDev/proyectoMed/issues/128) owns deterministic evaluation and estimates (AFK; blocked by #126 and #127; Impressos applies only to event-based criteria). [#129](https://github.com/ChordanDev/proyectoMed/issues/129) owns the result contract and disclaimer (HITL; blocked by #128). [#130](https://github.com/ChordanDev/proyectoMed/issues/130) owns clinical authoring and qualification (HITL; blocked by #126, #127, #128, and #129).
- The blocker sets above are the complete published native graph and are unchanged by acceptance. Voice issues #119–#121 remain integration references, not blanket blockers, and their media/orchestration ownership is unchanged. Ticket 14 and #126–#130 have no readiness labels. Provider/legal/privacy/ZDR review and clinical qualification remain human gates; architecture acceptance is not implementation approval or ready-for-agent approval.

## Further Notes

- Patient-response generation currently uses OpenAI through the generation provider adapter behind the Phoenix proxy. This is a generation capability, not an agent tooling profile. Jev is a separate accepted-but-unimplemented decision-model architecture and does not replace generation.
- The single station package is provided by the Content Partner. Until the partner delivers the file, the implementation may ship a placeholder package clearly marked `placeholder: true` and `display_title: "Estação de demonstração"`. The placeholder must still pass StationLoader validation and must not be promoted to the pilot.
- The session data lifecycle and safety timeout are listed as implementation details in the API contract; the actual timeout value (proposal: 30 minutes) remains an implementation decision.
- Jev and estimate work follows accepted ADR-011 (#123), accepted ADR-012 (#124), and the unchanged Ticket 14 (#125–#130) graph above. Existing Ticket 13 voice work and the #105–#108 Impressos graph retain their ownership. Remaining work consists of the provider/privacy/ZDR/legal and clinical qualification gates, followed by separately authorized runtime planning—not another architecture decision or automatic implementation.
- ADR-010 (#115) remains Proposed and V3-only.
