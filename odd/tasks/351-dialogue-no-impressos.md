# 351 - Dialogue turns release no impressos and flag exam requests

Issue: #351 (tracker #326). Branch: `feat/351-dialogue-no-impressos` (base `feat/326-production-launch`).
Delivery: single PR to the launch branch. Test runner: `mix test` in `backend/` (local Postgres, `MIX_TEST_PARTITION=_issue351`).

## Objective

A learner turn sent through the dialogue (text, voice, streamed voice) releases no impresso
and records no `impresso_requests` event; only `POST /sessions/:id/impressos/request`
releases. An examiner-addressed response carries a display-only boolean `exam_request`
so a client can point to the exam button (#194 decision, confirmed 2026-10-25).

## Why

The owner decided exams are requested only through the button, superseding the voice
release of #302/#305. Phoenix must enforce it and tell the client when to show the hint.

## Constraints

- Keep the #309 shortcut (a turn naming an authored impresso is examiner-addressed without
  a generation) and the #305 matcher/negation logic for the impresso route and the flag.
- Keep the companion actor (#341) behaviour.
- `request_impresso/2` (including its `unavailable` branch, owned by sibling #357) is untouched.
- No extra model call; the marker set gains `[EXAMINADOR:EXAME]`.
- `exam_request` is additive; every existing response field stays.
- Web harness is frozen and outside this worker's edit surface (see Log L5).

## Specs

- S1 "A dialogue turn (text, voice or streamed voice) that names an authored impresso is still examiner-addressed without a generation (the #309 shortcut stays). It is recorded as a learner turn and answered with `outcome: "examiner_acknowledged"`, `reply_text: null` and `newly_released: []`. It records no `impresso_requests` event."
- S2 "A turn the patient generation marks as examiner-addressed behaves the same way: acknowledged, nothing released."
- S3 "Impressos are released only by `POST .../impressos/request` ... That route does not change: an exam the station does not author is still answered `unavailable`."
- S4 "Asking for an exam in the dialogue earns no rubric credit for requesting it." The turn text still enters the evidence pool as a learner turn.
- S5 "An examiner-addressed response carries a new boolean `exam_request`." True for a deterministic authored-impresso match; otherwise decided by the marker `[EXAMINADOR:EXAME]`; `[EXAMINADOR]` gives `false`; a patient-addressed response never carries `exam_request: true`.
- S6 "`Backend.Stations.StationAI.Addressee` parses the new marker and strips it like the others. A missing or unknown marker stays patient-addressed, as today."
- S7 "Voice: the receipt of an examiner-addressed voice turn carries the same `exam_request`." The worker event stays `{role: "examiner", status: "acknowledged"}`; no worker change.
- S8 Docs: "`docs/design/turn-addressee.md` (the marker table, "Exam requests to the examiner (#302)" and the outcome table) and the `create_message/2` docs describe the new marker, `exam_request`, and that a dialogue turn never releases impressos." Plus `docs/unreal-station-client.md` documents the flag.

## Tasks

| ID | Specs | Route | Status | Commit / evidence |
| --- | --- | --- | --- | --- |
| T1 | S5, S6 | inline (bounded writer) | done | 966c899; RED 7 failing / GREEN 56 passed |
| T2 | S1-S5, S7, S8 | inline (bounded writer) | done | 713d535; RED 21 failing / GREEN 158 passed |

- T1 `Addressee` parses `[EXAMINADOR:EXAME]` (source `:exam_marker`); both prompts ask for it.
- T2 Text, voice and streamed voice examiner turns release nothing, record no event and carry
  `exam_request` (JSON message response, worker receipts); tests rewritten; docs updated.

## Log

- L1 (2026-10-25, user request relayed by the workflow): "sí, sigue en pie" — implement #351 as specified in the issue and its 2026-10-25 note.
- L2 Exploration: release happens in `acknowledge_examiner_turn/2` and `keep_examiner_voice_turn/4`
  via `release_requested_impressos/3` (`backend/lib/backend/stations.ex`). The marker source
  flows through `take_addressee/4` and the streamed `marker_gate/2`; the flag rides on it.
- L3 T1 (966c899): `Addressee` maps `[EXAMINADOR:EXAME]` to `{:examiner, :exam_marker}`;
  both prompts ask for it and keep patient questions about past exams on `[PACIENTE]`.
  RED: 7 failing in the addressee/prompt tests; GREEN: 56 passed; full backend 2347 passed.
- L4 T2 (713d535): `release_requested_impressos/3` removed; `acknowledge_examiner_turn/3`
  and `keep_examiner_voice_turn/4` carry `exam_request`; the streamed gate keeps the
  flag per marker; `StationController` serializes `exam_request`, `VoiceWorkerController`
  adds it to examiner receipts only. #302 release tests rewritten (not deleted), rubric
  test now asserts no credit until the route is used. RED: 21 failing; GREEN: 158 passed;
  full backend 2355 passed. Docs: `docs/design/turn-addressee.md`, `docs/unreal-station-client.md`.
- L5 Checks: local CI PASSED (web 337 tests, ExUnit 2355, E2E 4, Credo, Dialyzer 0 errors);
  voice worker `python -m unittest` 168 OK with no code change. Pending: the live pt-BR
  marker check (needs the real model; not run by this worker) and the web harness tests
  named in the acceptance criteria (`web/` is outside this worker's edit surface; the
  web tests mock the backend, so they still pass).
- Next step: PR review; run the live marker check and log misclassifications in the PR.
