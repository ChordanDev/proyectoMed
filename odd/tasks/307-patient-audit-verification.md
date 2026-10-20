# #307 Take Jev and the adjudicator off the patient-reply critical path

Parent: #237. Branch: `feat/307-patient-audit-verification` (base `feat/237-clinician-demo-readiness`).

## Objective

Deliver patient replies as soon as the deterministic `BoundedReply` check passes, and
verify them with Jev after delivery, for audit and measurement only. Keep today's
blocking gate (CandidateGate + adjudicator + regeneration) as a selectable fallback.

## Why

Every refusal investigated in the 2026-10-20 rehearsals was a Jev false positive
(e.g. `risk:speaks_out_of_role` 0.67 on "Meu nome é Rafael Nogueira, doutor."), while
blocking verification plus the Haiku adjudicator (#290) adds 0.3-2 s per turn. The
grader uses only learner evidence, so a patient over-disclosure never awards rubric
points by itself.

## Constraints

- `PATIENT_VERIFICATION=blocking|audit|off`, default `audit`, invalid values rejected.
- `blocking` keeps today's behaviour exactly; its tests stay unchanged (the suite pins
  `blocking` in `test_helper.exs`; audit/off tests set the mode explicitly).
- `audit`: a slow or undecided Jev never delays, blocks, regenerates or rewrites a
  delivered reply, in text and voice (including sentence streaming).
- A `BoundedReply` rejection regenerates once, then uses the refusal path (keep the
  learner turn).
- Audit logs carry outcome, unclear labels and latency only: never transcript text.
- Audit results stay on the session (`patient_audits`); the patient message's
  `verified_fact_ids` come from the audit verdict when it lands.
- `off`: no patient-side Jev call. The adjudicator runs only in `blocking`.
- Do not touch `station_ai.ex` prompt text (#308 owns it).

## Tasks

- [ ] T1 Mode setting: `Backend.Stations.PatientVerification.mode/0` (validated),
  config default `:audit`, `PATIENT_VERIFICATION` parsed in `runtime.exs` (invalid
  value fails the boot).
  Route: inline (config plus one small module, understood).
- [ ] T2 Text path in `audit`/`off`: BoundedReply-only delivery with one regeneration;
  asynchronous Jev audit after commit, logged and recorded on the session
  (`Conversation.record_patient_audit/3`).
  Route: inline (Stations + new internal module + Conversation; seams mapped).
- [ ] T3 Voice paths (`process_voice_turn/3`, `stream_voice_turn/5`) in `audit`/`off`.
  Route: inline (same seams as T2).
- [ ] T4 Design note `docs/design/patient-audit-verification.md`, ADR-011 amendment
  comment on #123, live check on acute-appendicitis.
  Route: inline.

## Acceptance criteria

- `audit`: a 5 s or undecided stub Jev does not delay or change the delivered reply,
  in text and voice streaming (tested).
- `audit`: a BoundedReply rejection regenerates once (tested).
- `blocking`: existing CandidateGate/adjudicator tests pass unchanged.
- Invalid `PATIENT_VERIFICATION` is rejected (tested).
- Live check: every turn answered; per-turn wall time vs the last blocking run.
- ADR-011 amendment posted on #123.

## Checks

- `mix test` (backend) per task; local CI script mirroring `pr-validation.yml` at closure.

## Progress

| Task | Commit | RED | GREEN |
| --- | --- | --- | --- |

## Next step

T1.
