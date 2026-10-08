# Ubiquitous Language

## MVP Learning Outcome

The smallest product outcome worth validating: a doctor completes one clinical station through voice or text and receives actionable feedback about performed actions, omissions, and improvements.

This outcome is educational feedback, not certification or a determination that someone is ready for Revalida.

## Content Partner

The project partner who creates and curates every clinical station, rubric, and case outside the application. The MVP application consumes this prepared content; it has no clinician workspace, authoring roles, or in-app content administration.

## Station AI

The case-bound patient or actor that receives learner input during a station. It may use only prepared clinical facts, then compares the completed interaction against the prepared rubric to provide educational feedback. It never creates cases or invents clinical facts.

## Station Input

The MVP station accepts both voice and text from the learner. Voice is transcribed for the station interaction; text is an equal input path and the fallback when voice is unavailable.

## Actionable Feedback

The educational station result identifies actions performed correctly, relevant omissions, why they matter within the station, and what the learner should practice next. It does not state pass/fail or claim Revalida readiness.

## MVP Station

The MVP contains one complete original clinical station authored by the Content Partner. It is the only case needed to validate the end-to-end learner experience before expanding content.

## Original Case

The MVP station is an original case inspired by skills relevant to Revalida. It does not copy or publicly use official Revalida materials.

## Learner-Facing Language

The MVP station instructions, Station AI interaction, voice and text input, and actionable feedback are all in Brazilian Portuguese.

## MVP Runtime

The MVP uses an Elixir/Phoenix backend and a Vite + React + TypeScript web SPA. The system is built as a client/server product, with the SPA running in the browser and communicating with the Phoenix API over HTTP.

## MVP Work Streams

The MVP is planned as four coordinated work streams: API contract and case/rubric model, Phoenix backend, web SPA frontend, and end-to-end integration/testing. Frontend and backend may progress in parallel only against the agreed API contract; integration remains a required final stream.

## Station Timer

The MVP station has a visible ten-minute countdown. It provides Revalida-like time pressure for practice but is not an official examination or certification signal.

## Technical Failure

If connectivity, microphone capture, or transcription fails during a station, that station is invalidated without feedback or penalty. The learner may restart it from the beginning; partial results are not shown.

## Station AI Responses

The Station AI replies with synthesized speech and visible Brazilian Portuguese text. The visible response supports accessibility, review, and continuity when audio is unavailable.

## Rubric-Bound Feedback

The MVP compares the learner transcript against the Content Partner's rubric. Each criterion is reported as met, omitted, or uncertain with supporting evidence. The MVP preserves uncertainty and provides no global readiness grade or certification. The current runtime stops at criterion statuses with no points (ADR-005). The accepted, unimplemented architecture adds assessment statuses, performance levels, and educational point estimates; see Educational Point Estimate (accepted architecture) and `docs/design/jev-prototype.md`. ADR-012 accepted that architecture on 2026-09-21, but runtime implementation and the remaining provider, privacy, legal, zero-data-retention, and clinical qualification gates are still pending.

## MVP Data Retention

The MVP has no learner account, server-side personal history, or retained learner transcript. It shows the current station result and permits a restart. Any non-identifying operational telemetry needs separate definition and justification.

## Pilot Operations

The project owner recruits participants and runs MVP validation outside the application. The MVP has no invitation workflow, participant management, or pilot-administration features.

## Pre-Station Notice

Before a station, the MVP shows a concise Brazilian Portuguese notice: it is an independent educational tool, not an official Revalida-readiness assessment, and learners must not enter real patient data.

## Station Package

The Content Partner supplies the one MVP station as a versioned structured package: clinical context, facts the Station AI may reveal, response rules, expected learner actions, and feedback criteria. This package constrains Station AI behavior without an in-app authoring workspace.

## Station Completion

The learner may finish a station early, or the ten-minute timer ends it automatically. Both paths end the interaction permanently for that run and transition directly to actionable feedback.

## Feedback Evidence Display

The feedback view shows the current session transcript and highlights excerpts that support each rubric criterion. It is session-only and discarded when the learner exits; it does not create personal history or server-side transcript retention.

## Unknown Clinical Facts

When a learner asks for a clinical fact absent from the Station Package, the Station AI responds neutrally in Brazilian Portuguese that it does not have that information. It never fabricates symptoms, history, findings, or results.

## Session Data Lifecycle

The backend holds conversation, transcription, and evaluation data only while it is needed to complete the station. It deletes them when the learner exits the result or after a short safety timeout; no personal history remains.

## MVP Continuation Criterion

The MVP is worth extending when pilot learners can complete the station without assistance and can explain what they did well, omitted, and should practice next because of its feedback. The project owner evaluates this outside the application.

## MVP Platforms

The first MVP release targets desktop and mobile browsers via the Vite + React web SPA. Native mobile apps (iOS/Android) and Expo Go are outside the initial scope; the priority is browser-based voice via `MediaRecorder`/Web Speech API, microphone permissions, and conversational interaction.

## Station Retry Policy

The MVP allows unlimited repetitions of the single station during the pilot. Usage caps, commercial limits, or station rotation are separate decisions for after the pilot.

## Jev (accepted architecture)

Jev is the working name for an independent decision-model family — a vendor candidate behind the backend's shared Phoenix proxy/domain interface, not a measured specialist in clinical pt-BR. It does not generate or replace patient dialogue. Separate adapters may use that shared interface for generation, transcription, text-to-speech, and decision-model calls. Under the architecture accepted on 2026-09-21, Jev verifies candidate Station AI replies and classifies rubric evidence into bounded observations. Selection, credentials, limits, data-processing terms, calibration, and zero-data-retention claims remain pending. This term describes accepted architecture, not shipped capability or an approved provider.

## Approved Generic Reply (accepted architecture)

A Station AI reply that bypasses Jev only when it is the exact text of a package- and version-bound approved template and code can determine that template's applicability from the authored case state. A safe renderer emits the stored template byte-for-byte and rejects prefixes, suffixes, mixed content, or model-declared identity. Shortness, length, language heuristics, or a plausible tone never authorize a reply. "Estou bem" is eligible only when the authored case state makes that exact statement non-contradictory. "Não tenho alergias" is a clinical claim, not a generic reply, and requires an authored revealable fact. An approved zero-clinical-content template may be used as a safety fallback only for the deterministic violation and applicability conditions for which it was explicitly approved; an Approved Generic Reply is not inherently a clinical answer or a universal fallback.

## Jev Gate (accepted architecture)

Every Station AI reply that is not an Approved Generic Reply must pass Jev before it is displayed or sent to text-to-speech; there is no parallel bypass. The gate checks groundedness in allowed facts, contradiction with the case and context, early or excessive disclosure, relevance to the patient role, and treats injected instructions found in learner turns as evidence to report, never as instructions to follow. Semantic refusal or low confidence permits at most one regeneration and complete recheck within the turn deadline; no text is delivered if that path does not pass. Timeout, malformed output, transport error, or provider 5xx is a technical failure that invalidates the attempt under the existing policy; it is not converted to `uncertain` and cannot produce fallback clinical text. Learner input may reach generation as untrusted evidence. Rejected or otherwise unverified patient candidates never enter trusted history or regeneration input, and text-to-speech receives only approved patient text.

## Assessment Status (accepted architecture)

Each rubric criterion carries exactly one of four statuses: assessed, uncertain, not_observable, or not_applicable. Uncertain or unobservable criteria are never silently scored as zero: a numeric level and points exist only for assessed criteria, and a genuine omission on complete, reliable evidence scores the authored zero of its level.

## Performance Level (accepted architecture)

When a criterion is assessed, it receives one authored level — inadequado, parcialmente_adequado, or adequado — and the authored decimal points for that level. Levels, sub-actions, and points follow the Station Package rubric, mirroring the structural shape of the official PEP sheets without reproducing official content.

## Educational Point Estimate (accepted architecture)

A numeric, PEP-shaped estimate computed only from authored rubric points on assessed criteria, using exact decimal arithmetic (supporting 0.125 granularity), with explicit coverage reported when active criteria remain unassessed and no rescaling of partial totals. A numeric total exists only when every active criterion is assessed; otherwise the result shows a scored subtotal, scored versus eligible maxima, and the unresolved items. It is an unofficial AI-generated educational estimate — never an official Revalida grade, pass/fail verdict, or readiness claim — and is labeled as such in pt-BR before and on the result screen.
