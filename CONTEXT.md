# Ubiquitous Language

## MVP Learning Outcome

The smallest product outcome worth validating: a doctor completes one clinical station through voice or text and receives actionable feedback about performed actions, omissions, and improvements.

This outcome is educational feedback, not certification or a determination that someone is ready for Revalida.

## Content Partner

The project partner who created and curated the MVP clinical station, rubric, and case outside the application, such as the hand-tuned acute-appendicitis Station Package. For the production launch (#326, ADR-012 amendment on #124) the Content Partner is no longer the source of cases: the n8n pipeline generates each Case, and Admins review it in the admin case panel before publication. The term remains only for the hand-authored MVP content.

## Case (decided for launch)

A numbered, generated clinical case in the tagged Markdown format, stored by the Content context with its area, theme, status, and revisions (ADR-007 amendment on #92). The n8n pipeline inserts it as `pending`; an Admin moves it to `approved` or `disapproved`. It is generated from public material as inspiration, never reproduced verbatim. A deterministic case format parser turns it into a Station Package or a list of located format errors; a Case with format errors cannot be approved.

## Admin (decided for launch)

A paid doctor with the `admin` role who reviews Cases in the Phoenix LiveView admin case panel (ADR-015, #347): reads, fixes small errors in place, and approves or disapproves. Doctor review is the clinical qualification gate of each Case.

## Station Version (decided for launch)

The immutable Station Package published when an Admin approves a Case. Editing an approved Case publishes a new Station Version. A session pins one Station Version, so its result stays explainable after later edits.

## Station AI

The case-bound patient or actor that receives learner input during a station. It may use only prepared clinical facts, then compares the completed interaction against the prepared rubric to provide educational feedback. It never creates cases or invents clinical facts.

## Station Input

The MVP station accepts both voice and text from the learner. Voice is transcribed for the station interaction; text is an equal input path and the fallback when voice is unavailable.

## Actionable Feedback

The educational station result identifies actions performed correctly, relevant omissions, why they matter within the station, and what the learner should practice next. It does not state pass/fail or claim Revalida readiness.

## MVP Station

The MVP contains one complete original clinical station authored by the Content Partner. It is the only case needed to validate the end-to-end learner experience before expanding content. The production launch (#326) replaces it with a catalog of at least 400 approved Station Versions; the acute-appendicitis case is rewritten in the tagged Markdown format as the reference Case.

## Original Case

Every station is an original case inspired by skills relevant to Revalida. Public material, including official INEP cases, may inspire a generated Case, but no official case or item content is reproduced verbatim (ADR-012 amendment on #124).

## Learner-Facing Language

The MVP station instructions, Station AI interaction, voice and text input, and actionable feedback are all in Brazilian Portuguese.

## MVP Runtime

The MVP uses an Elixir/Phoenix backend and a native Unreal Engine 5.8 station client with a MetaHuman patient (accepted architecture, ADR-013). The learner performs the station in the Unreal client, whose code is not in this repository yet; Phoenix remains the only authority, and the client holds no clinical rules. The Vite + React + TypeScript web SPA is frozen as an internal test harness: it receives no new features and keeps working unchanged until the Unreal client reaches parity. Both clients communicate with the Phoenix API over HTTP. For the production launch, account, billing, device-login confirmation, and the admin case panel are Phoenix LiveView screens (ADR-015, #347), not SPA features.

## MVP Work Streams

The MVP is planned as four coordinated work streams: API contract and case/rubric model, Phoenix backend, web SPA frontend, and end-to-end integration/testing. Frontend and backend may progress in parallel only against the agreed API contract; integration remains a required final stream.

## Station Timer

The MVP station has a visible ten-minute countdown. It is not an official examination or certification signal. In a real test (#318) it provides Revalida-like time pressure and ends the run at zero. In a training (decided 2026-10-23, built in #323) it marks the expected time and does not end the run: at zero the client shows that the expected time is over and then counts the overtime up, until a hard cap 20 minutes after start. A session without a mode is a training.

## Technical Failure

If connectivity, microphone capture, or transcription fails during a station, that station is invalidated without feedback or penalty. The learner may restart it from the beginning; partial results are not shown.

## Station AI Responses

The Station AI replies with synthesized speech and visible Brazilian Portuguese text. The visible response supports accessibility, review, and continuity when audio is unavailable.

## Rubric-Bound Feedback

The MVP compares the learner transcript against the Station Package rubric. The legacy result endpoint reports each criterion as met, omitted, or uncertain with supporting evidence and no points (ADR-005). The MVP preserves uncertainty and provides no global readiness grade or certification. The architecture ADR-012 accepted on 2026-09-21 adds assessment statuses, performance levels, and educational point estimates. Issue #128 implemented that assessment in the backend, and #129 exposed it through the versioned `/api/v2/stations/active/sessions/:id/result` endpoint, which the web client uses. The default decision adapter is disabled, so under it an assessment that needs a decision call is an invalid attempt. The opt-in TypeSafe adapter (#212) serves rubric batches. The provider, privacy, legal, zero-data-retention and clinical qualification gates are still pending. See Rubric Assessment and `docs/design/jev-prototype.md`.

## MVP Data Retention

ADR-014 (#346) supersedes the MVP's no-database stance (ADR-001, #34) for the production launch. Phoenix stores Learner Accounts, Subscription Entitlement, content-free per-session usage, and one Educational Result per finished session in the Results History. It never stores raw audio or a full transcript: the only transcript fragments kept are the learner phrases cited in an Educational Result. Account deletion erases the account, its entitlement, and its Educational Results and revokes every token; usage records keep no user reference. Retention periods are configuration set together with the legal documents. Until the launch work ships, the running MVP still has no database.

## Learner Account (decided for launch)

A learner's account, created on the LiveView web with email and password and acceptance of the terms of use and privacy policy. The Unreal client logs in through a browser Device Login and holds a short-lived, refreshable, revocable token; a password change or account deletion logs the learner out everywhere (ADR-013 amendment on #209).

## Subscription Entitlement (decided for launch)

The plan and entitlement state of a learner, received from a signed RevenueCat webhook by the Billing context. Phoenix checks it, and the plan's Daily Quota, when a session is created. Usage counts only sessions that reach a graded result; a Technical Failure consumes no quota.

## Results History (decided for launch)

The learner's past Educational Results, listed by date and filterable by area, each with its criteria, cited learner phrases, and recommendations. It has no aggregate across sessions, no pass/fail verdict, and no readiness score.

## Pilot Operations

The project owner recruits participants and runs MVP validation outside the application. The MVP has no invitation workflow, participant management, or pilot-administration features.

## Pre-Station Notice

Before a station, the MVP shows a concise Brazilian Portuguese notice: it is an independent educational tool, not an official Revalida-readiness assessment, and learners must not enter real patient data.

## Station Package

A versioned structured package: clinical context, facts the Station AI may reveal, response rules, expected learner actions, and feedback criteria. It constrains Station AI behavior. The Content Partner hand-authored the MVP package; for the launch, the case format parser produces it from an approved Case and it is published as a Station Version. It declares its actors (the patient and, when the case has one, a companion), each with a profile and a voice; facts and mandatory final questions belong to an actor.

## Station Completion

The learner may finish a station at any time. In a real test, the ten-minute timer also ends it automatically. In a training, the run ends when the learner finishes or, at the latest, at the 20-minute cap, which Phoenix applies with its own completion reason (decided 2026-10-23, built in #323). Every path ends the interaction permanently for that run and transitions directly to actionable feedback.

## Feedback Evidence Display

The feedback view shows the current session transcript and highlights excerpts that support each rubric criterion. The full transcript is session-only and discarded when the learner exits; it is never retained server-side. The Results History keeps only the cited learner phrases of each Educational Result (ADR-014, #346).

## Unknown Clinical Facts

When a learner asks for a clinical fact absent from the Station Package, the Station AI responds neutrally in Brazilian Portuguese that it does not have that information. It never fabricates symptoms, history, findings, or results.

## Session Data Lifecycle

The backend holds conversation, transcription, and evaluation data in memory only while it is needed to complete the station. It deletes them when the learner exits the result or after a short safety timeout. Under ADR-014 (#346), the only thing that outlives the session is its Educational Result, stored in the Results History of a Learner Account, and only when the session reached a graded result. A planned deploy drains running sessions instead of dropping them.

## MVP Continuation Criterion

The MVP is worth extending when pilot learners can complete the station without assistance and can explain what they did well, omitted, and should practice next because of its feedback. The project owner evaluates this outside the application.

## MVP Platforms

The station client targets macOS and Windows desktops through the native Unreal Engine 5.8 client (accepted architecture, ADR-013). The frozen web harness runs in desktop browsers for internal validation only. Native mobile apps (iOS/Android), Expo Go, and mobile, console, or browser-streamed builds of the Unreal client are outside the initial scope.

## Station Retry Policy

The MVP allows unlimited repetitions of the single station during the pilot. For the production launch (#326), a learner picks a station from the catalog or draws a random one, optionally within an area, within the Daily Quota of their plan; quota numbers are set after cost measurement.

## Jev (accepted architecture)

Jev is the working name for an independent decision-model family — a vendor candidate behind the backend's shared Phoenix proxy/domain interface, not a measured specialist in clinical pt-BR. It does not generate or replace patient dialogue. Separate adapters may use that shared interface for generation, transcription, text-to-speech, and decision-model calls. Under the architecture accepted on 2026-09-21, Jev verifies candidate Station AI replies and classifies rubric evidence into bounded observations; since #307 it audits patient replies after delivery by default (see Jev Gate). The decision seam is implemented as `Backend.Stations.JevDecision`: its default adapter is disabled, and an opt-in TypeSafe adapter (`JEV_ADAPTER=typesafe`, #206) serves patient decisions only and returns `rubric_decision_unsupported` for rubric decisions. The seam never truncates: text over its caps (24,000 characters per patient request, 120,000 per rubric evidence pool by default) fails closed before any adapter call. Live use awaits the human privacy and legal gate (#183); provider approval, data-processing terms, threshold calibration, and zero-data-retention claims remain pending. This term does not describe a qualified live service or an approved provider.

## Approved Generic Reply (accepted architecture)

A Station AI reply that bypasses Jev only when it is the exact text of a package- and version-bound approved template and code can determine that template's applicability from the authored case state. A safe renderer emits the stored template byte-for-byte and rejects prefixes, suffixes, mixed content, or model-declared identity. Shortness, length, language heuristics, or a plausible tone never authorize a reply. "Estou bem" is eligible only when the authored case state makes that exact statement non-contradictory. "Não tenho alergias" is a clinical claim, not a generic reply, and requires an authored revealable fact. An approved zero-clinical-content template may be used as a safety fallback only for the deterministic violation and applicability conditions for which it was explicitly approved; an Approved Generic Reply is not inherently a clinical answer or a universal fallback.

## Jev Gate (accepted architecture)

`PATIENT_VERIFICATION` selects how Jev checks patient replies (ADR-011 amendment for #307 on #123). In the default `audit` mode the deterministic `BoundedReply` check is the only pre-delivery gate: a reply is delivered once it passes, and Jev judges the delivered reply afterwards, for audit and measurement only, never delaying, blocking, or rewriting it. `off` makes no patient-side Jev call. The rest of this entry describes the `blocking` mode, kept as a fallback. In `blocking` mode, every Station AI reply that is not an Approved Generic Reply must pass Jev before it is displayed or sent to text-to-speech; there is no parallel bypass. The gate checks groundedness in allowed facts, contradiction with the case and context, early or excessive disclosure, relevance to the patient role, and treats injected instructions found in learner turns as evidence to report, never as instructions to follow. Semantic refusal or low confidence permits at most one regeneration and complete recheck within the turn deadline; no text is delivered if that path does not pass. Timeout, malformed output, transport error, or provider 5xx is a technical failure that invalidates the attempt under the existing policy; it is not converted to `uncertain` and cannot produce fallback clinical text. Learner input may reach generation as untrusted evidence. Rejected or otherwise unverified patient candidates never enter trusted history or regeneration input, and text-to-speech receives only approved patient text. `Backend.Stations.CandidateGate` implements the deny checks, exact-template bypass, decision call, and single semantic retry before patient text is committed; known violations currently return an error without the optional approved fallback.

## Rubric Assessment (implemented)

The backend capability that assesses a completed station against the Station Package rubric: Jev classifies each criterion and its authored actions in one batched call, and code validates the cited evidence, applies the Authored Rubric Rules, and computes the Educational Point Estimate. Its public entry point is `Backend.Stations.assess_session/2`; `Backend.Stations.get_educational_result/2` serves it over HTTP through the versioned result contract of #129 (`/api/v2/stations/active/sessions/:id/result`, which answers an invalid attempt with 502 `invalid_attempt`). It has no live rubric decision adapter: the default adapter is disabled and the opt-in TypeSafe adapter does not serve rubric decisions, so an assessment that needs a decision call is an invalid attempt, while a rubric with no questions can complete without one. Its clinical accuracy is unmeasured and belongs to #130. A technical failure of the decision call, a structurally invalid response, or a rubric that cannot be assessed exactly invalidates the whole attempt: no partial criteria are returned and nothing is converted to `uncertain`.

## Evidence Pool (implemented)

The ordered, role-labelled evidence of one completed session, shared by every rubric question. Its identifiers are derived at evaluation time and are not stored: `turn-N` for the N-th message of the transcript (1-based) and `impresso-<request_id>` for an Impressos request event. A turn's channel is its modality and its provenance is the transcript; an event's channel is Impressos, and it is verified evidence only when it was recorded for the package's version and released only authored impressos. Code looks up every identifier Jev cites and rejects one that does not exist, is not the learner's, is an unverified event, or does not satisfy the criterion's modality requirement. A rejected citation fails that criterion closed: it becomes uncertain with a machine-readable reason, and nothing is repaired, substituted, or aligned by text. Patient-role words never earn learner credit.

## Assessment Status (implemented)

Each rubric criterion carries exactly one of four statuses. Assessed: a level was decided and, when it is above zero, grounded in validated learner evidence. Uncertain: Jev could not classify the criterion, its cited evidence failed validation, or an unresolved action could still change the level. Not_observable: the criterion requires a modality the station cannot provide in this session, so it is not sent to Jev. Not_applicable: the author excluded the criterion, so it is not sent to Jev and stays outside every maximum. Uncertain or unobservable criteria are never silently scored as zero: a level and points exist only for assessed criteria, and a genuine omission scores the authored zero-point level.

## Performance Level (implemented)

When a criterion is assessed, it receives one authored level — inadequado, parcialmente_adequado, or adequado — and the authored points for that level. Levels, actions, and points follow the Station Package rubric, mirroring the structural shape of the official PEP sheets without reproducing official content.

## Authored Rubric Rules (implemented)

Optional rubric fields of the Station Package that code, not Jev, applies after classification. Count thresholds (`min_actions`) pick the level from the number of performed actions, capped by `count_cap`. An action's role is counted, mandatory, or forbidden: a missing mandatory action or a performed forbidden one scores the criterion at zero, and that veto is local to the criterion. `first_n` scores only the learner's first N answers to a criterion, including answers that match no authored action, so that listing everything is not rewarded; it requires count thresholds on a criterion with actions. Jev enumerates the answers and code checks the list against the order of the evidence and against each action's own evidence, and leaves the criterion uncertain when an unresolved action could push a listed answer beyond the first N. The rule still rests on Jev listing every answer and ordering the answers within one turn, which code cannot verify. A forbidden action is not excused by coming after the first N. `order` ranks criteria as steps, and the single `task_order` criterion is assessed in code from those ranks and the position of each step's earliest evidence. An unresolved action leaves its criterion uncertain only when resolving it could change the level. Time windows, "only what was said before X counts" gates, and verbalization requirements are not implemented.

## Educational Point Estimate (implemented)

A numeric, PEP-shaped estimate computed only from authored rubric points on assessed criteria. Points are multiples of 0.025 held as integer fortieths, so sums are exact (widened on 2026-10-07 from multiples of 0.125 to follow PEP 2025/2 tenths, amending ADR-012, #124); no probability multiplies points and no partial total is rescaled. The estimate reports the scored subtotal and scored maximum over assessed criteria (`scored_subtotal`, `scored_max`) and the eligible maximum over every criterion that is not excluded (`eligible_max`). A numeric `total` exists only when at least one such criterion exists and every one is assessed; otherwise it is null, and the unresolved criteria are listed. The v2 result serializes points as exact decimal strings. It is an unofficial AI-generated educational estimate — never an official Revalida grade, pass/fail verdict, or readiness claim. #129 shows it to learners in the web client, with the pt-BR disclaimer on the Pre-Station Notice and on the result screen; this exposure is not clinical validation. Overtime never changes this estimate. A training result adds a separate training score (decided 2026-10-23, built in #323): the `total` minus 0.25 points per started minute of overtime, at most 2.5, floored at zero, and null when `total` is null. Real tests have no overtime penalty.
