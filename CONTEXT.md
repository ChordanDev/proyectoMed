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

The MVP uses an Elixir/Phoenix backend and a native Unreal Engine 5.8 station client with a MetaHuman patient (accepted architecture, ADR-013). The learner performs the station in the Unreal client; Phoenix remains the only authority, and the client holds no clinical rules. The Vite + React + TypeScript web SPA is frozen as an internal test harness: it receives no new features and keeps working unchanged until the Unreal client reaches parity. Both clients communicate with the Phoenix API over HTTP.

## MVP Work Streams

The MVP is planned as four coordinated work streams: API contract and case/rubric model, Phoenix backend, web SPA frontend, and end-to-end integration/testing. Frontend and backend may progress in parallel only against the agreed API contract; integration remains a required final stream.

## Station Timer

The MVP station has a visible ten-minute countdown. It provides Revalida-like time pressure for practice but is not an official examination or certification signal.

## Technical Failure

If connectivity, microphone capture, or transcription fails during a station, that station is invalidated without feedback or penalty. The learner may restart it from the beginning; partial results are not shown.

## Station AI Responses

The Station AI replies with synthesized speech and visible Brazilian Portuguese text. The visible response supports accessibility, review, and continuity when audio is unavailable.

## Rubric-Bound Feedback

The MVP compares the learner transcript against the Content Partner's rubric. Each criterion is reported as met, omitted, or uncertain with supporting evidence. The MVP preserves uncertainty and provides no global readiness grade or certification. The learner-visible runtime stops at criterion statuses with no points (ADR-005). The architecture ADR-012 accepted on 2026-09-21 adds assessment statuses, performance levels, and educational point estimates. Issue #128 implemented that assessment inside the backend, but it is not exposed: the result endpoint and the web client still use the three statuses above, no live decision adapter exists, and the remaining provider, privacy, legal, zero-data-retention, and clinical qualification gates are still pending. See Rubric Assessment and `docs/design/jev-prototype.md`.

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

The station client targets macOS and Windows desktops through the native Unreal Engine 5.8 client (accepted architecture, ADR-013). The frozen web harness runs in desktop browsers for internal validation only. Native mobile apps (iOS/Android), Expo Go, and mobile, console, or browser-streamed builds of the Unreal client are outside the initial scope.

## Station Retry Policy

The MVP allows unlimited repetitions of the single station during the pilot. Usage caps, commercial limits, or station rotation are separate decisions for after the pilot.

## Jev (accepted architecture)

Jev is the working name for an independent decision-model family — a vendor candidate behind the backend's shared Phoenix proxy/domain interface, not a measured specialist in clinical pt-BR. It does not generate or replace patient dialogue. Separate adapters may use that shared interface for generation, transcription, text-to-speech, and decision-model calls. Under the architecture accepted on 2026-09-21, Jev verifies candidate Station AI replies and classifies rubric evidence into bounded observations. Selection, credentials, limits, data-processing terms, calibration, and zero-data-retention claims remain pending. This term describes accepted architecture, not shipped capability or an approved provider.

## Approved Generic Reply (accepted architecture)

A Station AI reply that bypasses Jev only when it is the exact text of a package- and version-bound approved template and code can determine that template's applicability from the authored case state. A safe renderer emits the stored template byte-for-byte and rejects prefixes, suffixes, mixed content, or model-declared identity. Shortness, length, language heuristics, or a plausible tone never authorize a reply. "Estou bem" is eligible only when the authored case state makes that exact statement non-contradictory. "Não tenho alergias" is a clinical claim, not a generic reply, and requires an authored revealable fact. An approved zero-clinical-content template may be used as a safety fallback only for the deterministic violation and applicability conditions for which it was explicitly approved; an Approved Generic Reply is not inherently a clinical answer or a universal fallback.

## Jev Gate (accepted architecture)

Every Station AI reply that is not an Approved Generic Reply must pass Jev before it is displayed or sent to text-to-speech; there is no parallel bypass. The gate checks groundedness in allowed facts, contradiction with the case and context, early or excessive disclosure, relevance to the patient role, and treats injected instructions found in learner turns as evidence to report, never as instructions to follow. Semantic refusal or low confidence permits at most one regeneration and complete recheck within the turn deadline; no text is delivered if that path does not pass. Timeout, malformed output, transport error, or provider 5xx is a technical failure that invalidates the attempt under the existing policy; it is not converted to `uncertain` and cannot produce fallback clinical text. Learner input may reach generation as untrusted evidence. Rejected or otherwise unverified patient candidates never enter trusted history or regeneration input, and text-to-speech receives only approved patient text.

## Rubric Assessment (implemented internally, not exposed)

The backend capability that assesses a completed station against the Station Package rubric: Jev classifies each criterion and its authored actions in one batched call, and code validates the cited evidence, applies the Authored Rubric Rules, and computes the Educational Point Estimate. It is reachable only through `Backend.Stations.assess_session/2`. It is not served over HTTP until the versioned result contract of #129, it has no live decision adapter (the configured adapter is disabled, so every assessment is an invalid attempt), and its clinical accuracy is unmeasured and belongs to #130. A technical failure of the decision call, a structurally invalid response, or a rubric that cannot be assessed exactly invalidates the whole attempt: no partial criteria are returned and nothing is converted to `uncertain`.

## Evidence Pool (implemented internally, not exposed)

The ordered, role-labelled evidence of one completed session, shared by every rubric question. Its identifiers are derived at evaluation time and are not stored: `turn-N` for the N-th message of the transcript (1-based) and `impresso-<request_id>` for an Impressos request event. A turn's channel is its modality and its provenance is the transcript; an event's channel is Impressos, and it is verified evidence only when it was recorded for the package's version and released only authored impressos. Code looks up every identifier Jev cites and rejects one that does not exist, is not the learner's, is an unverified event, or does not satisfy the criterion's modality requirement. A rejected citation fails that criterion closed: it becomes uncertain with a machine-readable reason, and nothing is repaired, substituted, or aligned by text. Patient-role words never earn learner credit.

## Assessment Status (implemented internally, not exposed)

Each rubric criterion carries exactly one of four statuses. Assessed: a level was decided and, when it is above zero, grounded in validated learner evidence. Uncertain: Jev could not classify the criterion, its cited evidence failed validation, or an unresolved action could still change the level. Not_observable: the criterion requires a modality the station cannot provide in this session, so it is not sent to Jev. Not_applicable: the author excluded the criterion, so it is not sent to Jev and stays outside every maximum. Uncertain or unobservable criteria are never silently scored as zero: a level and points exist only for assessed criteria, and a genuine omission scores the authored zero-point level.

## Performance Level (implemented internally, not exposed)

When a criterion is assessed, it receives one authored level — inadequado, parcialmente_adequado, or adequado — and the authored points for that level. Levels, actions, and points follow the Station Package rubric, mirroring the structural shape of the official PEP sheets without reproducing official content.

## Authored Rubric Rules (implemented internally, not exposed)

Optional rubric fields of the Station Package that code, not Jev, applies after classification. Count thresholds (`min_actions`) pick the level from the number of performed actions, capped by `count_cap`. An action's role is counted, mandatory, or forbidden: a missing mandatory action or a performed forbidden one scores the criterion at zero, and that veto is local to the criterion. `first_n` scores only the learner's first N answers to a criterion, including answers that match no authored action, so that listing everything is not rewarded; it requires count thresholds on a criterion with actions. Jev enumerates the answers and code checks the list against the order of the evidence and against each action's own evidence, and leaves the criterion uncertain when an unresolved action could push a listed answer beyond the first N. The rule still rests on Jev listing every answer and ordering the answers within one turn, which code cannot verify. A forbidden action is not excused by coming after the first N. `order` ranks criteria as steps, and the single `task_order` criterion is assessed in code from those ranks and the position of each step's earliest evidence. An unresolved action leaves its criterion uncertain only when resolving it could change the level. Time windows, "only what was said before X counts" gates, and verbalization requirements are not implemented.

## Educational Point Estimate (implemented internally, not exposed)

A numeric, PEP-shaped estimate computed only from authored rubric points on assessed criteria. Points are multiples of 0.025 held as integer fortieths, so sums are exact (widened on 2026-10-07 from multiples of 0.125 to follow PEP 2025/2 tenths, amending ADR-012, #124); no probability multiplies points and no partial total is rescaled. The estimate reports the scored subtotal and scored maximum over assessed criteria (`scored_subtotal`, `scored_max`) and the eligible maximum over every criterion that is not excluded (`eligible_max`). A numeric `total` exists only when every such criterion is assessed; while anything is unresolved it is null and the unresolved criteria are listed. It is an unofficial AI-generated educational estimate — never an official Revalida grade, pass/fail verdict, or readiness claim. Showing it to learners, with the pt-BR label before and on the result screen, is accepted architecture that #129 has not implemented.
