# Patient reply verification after delivery

Status: **Implemented for #307** (parent #237). This note amends ADR-011 (#123, the Jev
verification gate) and the undecided-verdict adjudicator (#290,
[undecided-adjudicator.md](undecided-adjudicator.md)), as decided with the user on
2026-10-20. The amendment is posted as a comment on #123.

## Problem

Every refusal investigated in the 2026-10-20 rehearsals was a Jev false positive. One
example: `risk:speaks_out_of_role` scored 0.67 on "Meu nome é Rafael Nogueira, doutor.".
Blocking verification plus the Haiku adjudicator added 0.3-2 s per turn. In the last
spoken rehearsal, 3 of 5 patient turns went through the adjudicator, at +1.3-1.5 s each.

The grader uses only learner evidence. A patient that says too much never earns the
learner a rubric point by itself, so blocking on Jev protects little and costs every turn.

## Decision

The only pre-delivery gate is the deterministic `BoundedReply` check. Jev verifies
patient replies after delivery, for audit and measurement only.

`PATIENT_VERIFICATION` selects the mode (`config :backend, :patient_verification`):

| Mode | Before delivery | After delivery |
|---|---|---|
| `audit` (default) | `BoundedReply` | One Jev verdict per delivered reply, asynchronous |
| `blocking` | `CandidateGate`: Jev, adjudicator, single regeneration (ADR-011 as before) | Nothing |
| `off` | `BoundedReply` | Nothing: no patient-side Jev call |

Any other value fails the boot, naming it. The adjudicator runs only in `blocking`.

### `audit` and `off`

- Text, whole voice replies and streamed voice sentences are delivered once
  `BoundedReply.check_violations/2` passes (`Backend.Stations.PatientVerification.check_delivery/3`).
- A rejected candidate gets one regeneration, which never sees the rejected text. When the
  regeneration is rejected too, the learner turn is kept with refusal `:bounded_reply`,
  like any refused reply (#235). In a stream, only the first sentence can regenerate; a
  later rejection keeps the sentences already spoken (#271).
- A slow, undecided, refusing or failing Jev never delays, blocks, regenerates or rewrites
  a delivered reply.

### The audit

- `PatientVerification.start_audit/2` runs Jev on the stored reply, against the
  conversation it answered and the facts disclosed before it, in an unlinked task with
  its own deadline (`patient_audit_deadline_ms`, 10 s).
- The patient's no-information answer is not sent to Jev (`outcome: :bypassed`); it
  discloses nothing.
- One `:info` log line per audit: `[PatientVerification] audit outcome=<o>
  unclear=<labels> latency_ms=<ms>`. Labels are question names and fact ids
  (`risk:speaks_out_of_role`, `fact_asked:hda-02`, `fact_unasked:<id>`), never text.
- The audit is kept on the session (`Backend.Stations.patient_audits/1`): `message_index`,
  `outcome`, `unclear_labels`, `used_fact_ids`, `latency_ms`. A later qualification report
  can read it.
- The verdict's `used_fact_ids` become the message's `verified_fact_ids`, so
  `Conversation.disclosed_fact_ids/1` still follows Jev for the patient context (#286).
  Until the audit lands, the message has none.

## Unchanged

- Rubric grading by Jev, the turn addressee (#274; decided by the patient generation since #309) and impresso release (#302).
- `blocking` mode: today's CandidateGate, adjudicator and regeneration tests run unchanged.
  The backend suite pins `blocking` in `test/test_helper.exs`; audit and off tests set the
  mode themselves.
- The station qualification run (`Backend.Stations.Qualification`) still measures the
  CandidateGate directly.

## Evidence

Live check on acute-appendicitis, 2026-10-20, the 10-turn #290 replay (Sonnet patient,
TypeSafe Jev), `PATIENT_VERIFICATION=audit`:

| Run | Answered | Wall time per turn (ms) | Mean |
|---|---|---|---|
| Last blocking run (#290, run 8) | 9/10 (turn 9 refused) | 2644, 2023, 2329, 2116, 2325, 1587, 1954, 2230, 7539, 2409 | 2716 |
| `audit` (#307) | 10/10 | 2363, 1700, 1574, 1647, 1601, 1754, 1861, 1580, 1649, 1654 | 1738 |

Ten audits landed after delivery, 245-307 ms each, with no adjudicator call. Two were
`low_confidence`: turn 1 (`risk:speaks_out_of_role`, the false positive above) and turn 9
("Toma algum remédio?", the case #290 was built for). Both replies were delivered.
