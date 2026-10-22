## Problem Statement

A doctor trained abroad needs a safe, focused, low-cost way to rehearse one clinical station for Brazil's Revalida. The user must be able to open the app, complete the station in Portuguese using voice and text under a ten-minute countdown, and understand what they did well, what they missed, and what to practice next — without accounts, subscriptions, or stored personal history.

Implementation baseline: `7fac4a2`. Station sessions, a pre-delivery verification gate, rubric assessment, and a versioned educational-result API and UI exist. The Jev decision adapter is disabled by default. An opt-in TypeSafe adapter verifies patient replies only, and its live use awaits the human privacy and legal gate (#183); no decision provider or clinical accuracy is validated. User stories below describe the intended learner outcome, not evidence of pilot readiness. The distinction between #128's internal assessment and subsequent HTTP/UI integration is detailed below.

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
9. As a learner, I want criterion-level feedback that distinguishes assessed performance, uncertainty, unavailable observation, and exclusions, so that I understand my performance per skill rather than as a single grade.
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

- The repository runtime is an Elixir/Phoenix backend and a Vite + React + TypeScript web SPA in `web/`.
- Accepted ADR-013 (#209) makes a native Unreal Engine 5.8 + MetaHuman client for macOS and Windows the learner station client and freezes the web SPA as an internal desktop-browser test harness that receives no new features. No Unreal client code is in this repository; both clients use the same Phoenix HTTP API.
- The Phoenix API is the only public surface for the MVP. It loads exactly one Station Package at boot from `priv/stations/<id>/package.json` (no database, no admin endpoints).
- Backend session state lives in an in-memory ETS table keyed by session id; records are removed on discard or expiry, and the table is lost on shutdown.
- The SPA speaks to the backend over HTTP from the browser. It does not persist anything beyond the current view.
- `bash scripts/test.sh` is the root test orchestrator: web unit tests, backend ExUnit, then process-level E2E scenarios. Individual suite commands also exist; tests use Vitest and ExUnit.

### Station Package format (seam: external file, loaded at boot)

The active package is loaded from `backend/priv/stations/chest-pain-initial-assessment/package.json`. The v2 contract is documented in `backend/priv/stations/package.schema.json` and validated by `Backend.Stations.StationPackage`. Its principal fields are:

- `station_id`, `version` (`2.0.0`), `language` (`pt-BR`), `display_title`, and `placeholder`.
- `patient_profile`: persona, age, presenting context, tone.
- `revealable_facts`: facts with `id`, `topic`, `content`, and `disclosure_condition`. These author the allowed facts; the fields alone are not proof of a clinically qualified verifier.
- `response_rules`: rules the Station AI must follow (politeness, length cap, refusal to invent facts, refusal to roleplay non-clinical scenarios).
- `expected_actions`: ordered or unordered list of clinician actions the learner should demonstrate during the station.
- `rubric`: criteria with `id`, `description`, `evidence_questions`, `practice_recommendation`, `levels`, `actions`, `order`, `count_cap`, `first_n`, `veto`, `exclusion`, and `modality_requirement`. Levels have `label`, `description`, and `points`; labels are `inadequado`, `parcialmente_adequado`, or `adequado`. Points are nonnegative multiples of 0.025. Optional `levels[].min_actions`, `actions[].role` (`counted`, `mandatory`, `forbidden`), and `rule: "task_order"` drive deterministic rules. Cross-field validation rejects inconsistent authoring. The old informational `weight` is not the v2 scoring contract. `StationPackage.migrate/1` explicitly upgrades v1 maps before validation; boot loading does not automatically migrate them.
- Optional `approved_templates` bind exact text to structured applicability predicates; optional `impressos` author releasable examination material.
- The package is loaded once at boot. A different `package.json` requires an app restart. No hot reload, no admin UI.

### API contracts (Phoenix REST, legacy and v2)

- `GET /api/stations/active` → `{ station_id, version, display_title, language }`.
- `POST /api/stations/active/sessions` requires `{ audio_consent: boolean }` and returns `{ session_id, station_id, station_version, audio_consent, started_at, expires_at, deadline_at, server_now }`.
- `POST /api/stations/active/sessions/:id/messages` with `{ role: "learner", modality: "voice" | "text", text }` → `{ reply_text, reply_audio_url?, server_now }`. Learner text longer than 2,000 characters (default of `:learner_message_max_characters`) returns 422 `message_too_long` before it enters the conversation or reaches Jev; it is never truncated. A reply after the station deadline returns 409 `station_time_elapsed`; verification timeout returns 504, and gate rejection or an unavailable Station AI returns 502. The text contract remains current; ADR-009 (#114) assigns prototype voice transport/transcription to LiveKit/WebRTC and Deepgram, with endpoint evolution owned by Ticket 13 (#116).
- `POST /api/stations/active/sessions/:id/finish` with optional `{ reason: "user" | "timer" }` returns session id, completed status/time, completion reason, deadline, and server time. Premature timer completion returns 409.
- `GET /api/stations/active/sessions/:id/result` retains the legacy `{ session_id, status, criteria: [{ id, status: "met" | "omitted" | "uncertain", evidence: [transcript_excerpts], recommendation }] }` shape. It calls `Evaluator`, not `RubricAssessment.to_legacy/1`, and has no points.
- `GET /api/v2/stations/active/sessions/:id/result` calls `get_educational_result/2` → `assess_session/2` → `RubricAssessment.assess/3`. The web client's `fetchResult` uses this route. Success has `schema_version: "2"`, session id, completed status, `placeholder`, four-state criteria, coverage counts, and estimates. Points and maxima are exact decimal **strings**; unresolved totals are `null`. Only assessed criteria have a level and points. Provider diagnostics and internal call records are not serialized. Responses are `Cache-Control: no-store`; an invalid assessment returns 502 `invalid_attempt`, with no partial criteria or fallback to the legacy evaluator.
- Session routes also expose retrieval, explicit discard, Impressos requests/listing, transcription, and speech synthesis; `backend/lib/backend_web/router.ex` is the complete route inventory. Impressos request text shares the 2,000-character learner limit (422 `message_too_long`). The current transcription and speech-synthesis routes call OpenAI audio APIs, not the ADR-009 voice stack.
- Controller errors use JSON `{ "error": "code", "message": "human-readable pt-BR" }`. Missing session ids return 404; an expired record encountered before purging returns 410 and is deleted. Already-purged records return 404.
- The safety timeout is a fixed TTL from creation, not an inactivity timeout. It defaults to 30 minutes, independently of the ten-minute station deadline; reads do not renew it. Explicit discard and periodic expiry cleanup remove ephemeral records.

### Backend modules

`Backend.Stations` is the implemented public context (`backend/lib/backend/stations.ex`). `BackendWeb` delegates domain work through it. Implementation modules live under `backend/lib/backend/stations/`:

- `Backend.Stations.StationLoader` and `StationPackage` load and validate the package at boot, failing startup for missing or invalid content.
- `Backend.Stations.Conversation` owns ephemeral ETS sessions, turn settlement, deadlines, completion, and discard.
- `Backend.Stations.StationAI` and its generation adapters are distinct from `Backend.Stations.CandidateGate` and `JevDecision`. `Stations.create_message/2` generates a candidate, verifies it, and only then commits patient text; failure rolls back the pending turn rather than storing rejected text.
- `Backend.Stations.JevDecision` is the decision seam. `DisabledAdapter` is the default; `TypesafeAdapter` (TypeSafe System One, selected only by `JEV_ADAPTER=typesafe`) serves patient decisions and returns `rubric_decision_unsupported` for rubric decisions. The seam never truncates: text over its caps (24,000 characters for patient requests, 120,000 for the rubric evidence pool by default) fails closed with `context_limit_exceeded` before any adapter call.
- `Backend.Stations.Evaluator` still provides the legacy three-state, no-point result.
- `Backend.Stations.RubricAssessment` implements evidence validation, authored rules, four-state assessment, and exact estimates. `EducationalResult` serializes that assessment for the v2 route.
- `Backend.Stations.Qualification` runs fictional qualification cases; a harness and scripted tests are not clinical qualification.
- `BackendWeb.StationController` validates HTTP input, delegates to the context, and serializes responses. The router has both legacy and v2 scopes and retains the root health route.

Some historical top-level compatibility delegates/configuration keys and test module names remain. They do not change the public context boundary or imply that the implementation still lives in top-level domain modules.

### Frontend modules

- `web/src/features/station/api/client.ts` — typed HTTP client, including v2 educational-result decoding and typed `ApiError` responses; uses `import.meta.env.VITE_API_URL`.
- `web/src/features/station/hooks/useStation.ts` — session lifecycle and concurrency state.
- `web/src/features/station/screens/NoticeScreen.tsx` — pt-BR notice, educational-estimate disclaimer, and audio consent.
- `web/src/features/station/screens/StationScreen.tsx` — voice/text input, transcript, timer, and completion controls.
- `web/src/features/station/result/ResultScreen.tsx` — four-state criteria, evidence, recommendations, coverage-aware estimates, fictional-data labels, and the educational disclaimer.
- `web/src/features/station/i18n/pt-BR.json` — shared learner-facing copy.
- The accepted prototype voice plan uses LiveKit/WebRTC with Deepgram transcription and Cartesia speech synthesis (ADR-009, #114; ElevenLabs was replaced by Cartesia for real-time speech in #360). Text input remains an equal fallback path. Ticket 13 (#116) and children #117–#121 own the corresponding media and orchestration migration.

### Intended failure policy and current boundary

- A 5xx, network timeout, or missing session id invalidates the station: the client shows a short pt-BR notice ("a estação não pôde ser concluída; você pode reiniciar") and offers "Reiniciar estação". No partial feedback, no penalty.
- A microphone permission denial or STT failure surfaces a pt-BR notice and switches the input to text-only for that session. The station can still be completed.
- A timer-driven completion fires the same `finish` endpoint with `reason: "timer"`.

The gate returns typed failures and the context rolls back a failed pending turn; that is not a persisted backend-wide invalid-attempt status. Assessment technical failures return no criteria. Default Jev-dependent requests fail closed because the decision adapter is disabled. With the opt-in TypeSafe adapter, assessments that need a decision call still return `invalid_attempt`, because it does not serve rubric decisions. Successful scripted tests do not imply a live qualified service.

### Testing

- Good tests assert the external behavior of each module: HTTP responses, returned criteria, error codes, transcript excerpts selected for evidence.
- Backend coverage lives in `backend/test/backend/` and `backend/test/backend_web/controllers/`. Historical files such as `station_ai_test.exs` and `evaluator_test.exs` retain top-level **test** module names and call compatibility delegates to `Backend.Stations.*` internals. New suites include `Backend.Stations.AssessSessionTest`, `Backend.Stations.RubricAssessmentTest`, rule/evidence/point tests, gate tests, `Backend.Stations.JevDecision.TypesafeAdapterTest` (provider stubbed with `Req.Test`), and `BackendWeb.EducationalResultTest`.
- Frontend coverage is colocated under `web/src/features/station/`: API decoding, lifecycle, notice, station controls, and result presentation. Scripted classifications verify deterministic mechanics, not freedom from clinical hallucination or clinical scoring accuracy.
- `bash scripts/test.sh` runs `npm --prefix web run test:unit`, `mix test` in `backend/`, then `npm --prefix web run test:e2e`. The E2E harness compiles the dev backend, starts a local mock OpenAI server and Phoenix process, and selects the dev-only approving Jev adapter. It does not qualify a live provider.

### Out of scope

- Clinician workspace, account management, subscription, billing, or any in-app authoring.
- Server-side personal history or retained learner transcript beyond the active session.
- Reproducing official Revalida cases in the learner experience; original cases are required. Public PEP booklets are structural design references, not replacement clinical content.
- Native mobile apps (iOS/Android), Expo Go distribution.
- Multi-station library, station rotation, station editor.
- Patient avatars, 3D, video, or image capture.
- Store publication (App Store, Play Store). Distribution is via browser URL.
- Analytics, telemetry, or instrumentation inside the app. The project owner measures outcomes externally.
- Translation to languages other than pt-BR.
- Multi-leaderboard, sharing, or social features.

## Dialogue Verification and PEP-Style Estimates: Implementation and Limits

The governing design is `docs/design/jev-prototype.md`, under accepted ADR-011 (#123) and ADR-012 (#124). #128 implemented the assessment engine internally; the current baseline also contains the v2 HTTP/UI integration. Implementation is not live-provider qualification, pilot/production authorization, acceptance of privacy/ZDR/legal terms, or evidence of clinical pt-BR accuracy.

- Implemented dialogue gate: deterministic deny checks run first and immediately reject violations without fallback text. Exact package/version-bound templates with deterministic applicability may bypass Jev; all other candidates require the decision seam. A violation-specific approved fallback is an architectural allowance, not implemented routing.
- The only ordinary bypass is an exact Approved Generic Reply with deterministic applicability. Shortness or length never authorizes text. "Estou bem" is eligible only when the authored case state makes it non-contradictory; "Não tenho alergias" is a clinical claim and is not generic.
- The message path permits at most one semantic regeneration and full recheck within a monotonic deadline. Technical errors return without fallback clinical text; rejected candidates do not enter committed history or regeneration input. The accepted voice architecture requires only approved text to reach TTS; the LiveKit/Deepgram/Cartesia migration remains separate work, not proof supplied by this gate.
- Jev is a decision-model seam, not the generation model. One shared Phoenix proxy/domain interface may host distinct generation, transcription, text-to-speech, and decision-model adapters.
- Implemented assessment builds shared, ordered, role-labelled evidence from transcript turns and Impressos events. Questions are batched once unless `max_questions_per_call` requires capacity chunks; task-order dependencies are computed in code. The batch contract takes classifications and code-supplied evidence IDs, not probability-weighted scores. Code validates IDs, learner role, provenance, and channel. Bad citations make a criterion uncertain; structural/provider failures invalidate the assessment without partial criteria. Span alignment for providers unable to cite supplied IDs is not implemented.
- Deterministic code applies counts, required sub-actions, order, veto, and cancellation rules and maps authored levels to exact decimal points. Patient-role words never earn learner credit. Impressos events from #105–#108 are required only for criteria that depend on those events.
- Assessment statuses are `assessed`, `uncertain`, `not_observable`, and `not_applicable`; only assessed criteria carry levels and points. Points are integer fortieths internally (multiples of 0.025), serialized as exact decimal strings in v2. A numeric total exists only when at least one criterion is active and every active criterion is assessed; otherwise it is null alongside the scored subtotal, scored and eligible maxima, and unresolved items. No rescaling or probability-weighted points.
- Results show a conspicuous pt-BR disclaimer before and on the result screen; no pass/fail, certification, readiness, or published-score claim. Example scores are explicitly fictitious fixtures.
- Transient session state does not establish vendor privacy or zero-data-retention compliance. Provider retention/legal terms and clinical calibration remain unverified; no end-to-end no-logging guarantee is asserted here.

Remaining limits: no qualified live decision adapter (the TypeSafe adapter is opt-in, serves patient decisions only, uses uncalibrated `0.8`/`0.2` thresholds, and awaits #183); no measured clinical accuracy; no implemented time-window, pairwise "before X", or explicit verbalization rules. First-N completeness and within-turn answer order depend on classifier output. Task order skips steps scored zero even when attempted. `RubricAssessment.to_legacy/1` exists, but the legacy HTTP endpoint still invokes its original evaluator. The default disabled adapter makes assessments requiring a decision call invalid; a rubric with no questions can complete deterministically without calling it.

### Architecture and tracker boundaries

- ADR-009 (#114) is **Accepted** and defines the prototype voice stack: LiveKit/WebRTC, Deepgram, and Cartesia (amended in #360; originally ElevenLabs). Ticket 13 (#116) has children #117–#121.
- The accepted Jev architecture integrates with, but does not duplicate, #119 (no patient response exits Phoenix before the safety boundary), #120 (only Phoenix-approved text reaches the TTS provider), or #121 (cancellation, stale generation, failure recovery, and realism; not media, UI, or orchestration ownership).
- ADR-010 (#115), Proposed and V3-only, is superseded by accepted ADR-013 (#209). Neither is part of this Jev prototype.
- The #105–#108 Impressos DAG is unchanged. Closed #27 and #44 remain prior evaluator and bounded-reply seams.
- ADR-011 (#123) extends the ADR-002 safety contract; ADR-012 (#124) supersedes ADR-005's no-score rule only for Educational Point Estimates, never certification, pass/fail, or readiness claims. The legacy endpoint remains score-free; v2 exposes educational estimates without conferring clinical validation.
- Ticket 14 (#125) separates package/schema (#126), decision gate/provider qualification (#127), deterministic assessment (#128), result contract/disclaimer (#129), and clinical authoring/qualification (#130). The baseline contains mechanisms from these work streams; issue ownership is not a claim that human qualification gates have passed. See the design's Ticket 14 table for code evidence rather than historical readiness-label or blocker snapshots.

## Further Notes

- Patient-response generation defaults to the OpenAI adapter behind the Phoenix context. Jev is a separate implemented decision seam with a disabled default adapter and an opt-in, patient-only TypeSafe adapter; it is not a replacement generation model or a qualified live provider.
- The single station package is provided by the Content Partner. Until the partner delivers the file, the implementation may ship a placeholder package clearly marked `placeholder: true` and `display_title: "Estação de demonstração"`. The placeholder must still pass StationLoader validation and must not be promoted to the pilot.
- The session TTL defaults to 30 minutes and can be configured; the station deadline defaults to ten minutes.
- Remaining Jev work includes rubric decisions through a live provider, the human privacy/legal gate before live use (#183), threshold calibration, and ZDR and clinical qualification. Existing voice and Impressos ownership is unchanged; implemented assessment and HTTP/UI paths do not authorize deployment or clinical claims.
- ADR-010 (#115) is superseded by ADR-013 (#209).
