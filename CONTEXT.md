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

The MVP compares the learner transcript against the Content Partner's rubric. Each criterion is reported as met, omitted, or uncertain with supporting evidence. The MVP preserves uncertainty and provides no global readiness grade or certification.

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
