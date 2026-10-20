# Turn addressee: patient or examiner

Status: **Implemented for #274** (parent #237). This note adds to ADR-011 (#123, the
Jev verification gate) and ADR-008 (the station conversation). #235 recorded that
deciding who a learner turn is addressed to deserves its own decision once real-time
voice landed. It does not change ADR-011's gate, the grading contract (ADR-012) or any
claim boundary in [jev-prototype.md](jev-prototype.md).

## Problem

In the exam room the candidate talks to the patient and also says findings, lab and
imaging interpretation, the diagnosis and the plan out loud to the examiner. Until #274
every learner turn produced a patient reply: a generation, then a Jev verification.
A turn meant for the examiner is usually refused by the gate (the patient cannot
answer it), and only then did the learner see "Examinador: Anotado.". That cost about
1.5-3 s per turn in the second half of the station. A refused reply to a real patient
question showed the same "Anotado.", which reads as if the examiner had answered.

## Decision

Before any generation, each learner turn, text or voice, is classified once by Jev.

| Item | Decision |
|---|---|
| Check | One TypeSafe `noul` question: "Is the message in `latest_learner_message` addressed to the examiner rather than to the patient?" with criteria for each side. No extra LLM call. |
| State sent | The latest learner message and the bounded recent conversation (same minimization, trust labels and caps as the patient decision). No authored package content. |
| Thresholds | `yes_threshold` 0.8 / `no_threshold` 0.2, the same TypeSafe adapter settings as the patient decision. |
| Examiner | noul ≥ 0.8. |
| Patient | noul ≤ 0.2. |
| Undecided | 0.2 < noul < 0.8: **patient-addressed**. |
| Failure | Timeout, disabled adapter, an adapter without the check, malformed output: **patient-addressed**, the behaviour before #274. The check never blocks or fails a turn. |
| Deadline | Its own budget (`:jev_addressee_deadline_ms`, default 1,000 ms). It runs before the patient reply's 3 s verification budget starts, so it never shortens that budget. |
| Logging | One line per turn: `[Stations] turn_addressee decision=<examiner\|patient\|undecided\|error> channel=<text\|voice> latency_ms=<n>`. No learner text, no noul. |

The check runs sequentially before generation and on its own on the examiner path:
an examiner turn makes no generation and no verification call. A patient turn pays
about 0.3 s more. Starting generation in parallel would hide that cost but would spend
a generation on every examiner turn, which is exactly what #274 removes.

## What each outcome shows

| Outcome | Stored | Text API | Voice | Web |
|---|---|---|---|---|
| Examiner-addressed | Learner turn, no reply | `200` with `outcome: "examiner_acknowledged"`, `reply_text: null`, `learner_turn` | Receipt `status: "kept"`, `addressee: "examiner"`; the worker speaks nothing and publishes `{role: "examiner", status: "acknowledged"}` | "Examinador: Anotado." |
| Patient-addressed, verified | Learner turn and reply | `200` with `outcome: "patient_reply"` and `reply_text` | Sentences as in #271 | Patient reply |
| Patient-addressed, refused (#235, #269) | Learner turn, no reply | `502 reply_verification_failed` with `learner_turn` (unchanged) | Receipt `status: "kept"`, `addressee: "patient"`; the worker publishes `{role: "examiner", status: "kept"}` | Neutral notice "O paciente não respondeu a essa mensagem. Você pode reformulá-la." — never "Anotado." |
| Technical failure | Turn rolled back (unchanged) | Unchanged | Unchanged | Unchanged retry notice |

The neutral notice is a display-only transcript entry labelled "Aviso", placed after
the kept learner turn like the examiner's "Anotado.", so the learner turn stays visible
and the input stays empty for a rephrased message. Neither entry is stored or graded.

Compatibility: a response without `outcome` is read as `patient_reply`. A worker
event `status: "kept"` from a worker built before #274 now shows the neutral notice.

## Grading

Grading does not change. An examiner-addressed turn is stored exactly as a refused
patient-addressed turn is stored since #235: one learner message with the same role,
modality and text, and no patient message. The evidence pool and rubric assessment
read learner turns without any addressee, so the same learner turns give the same
evidence and the same grade (tested in
`backend/test/backend/stations/turn_addressee_evidence_test.exs`).

## Open points

- The thresholds and question wording are not calibrated on live pt-BR turns. The live
  check of #274 (findings, labs and plan acknowledged in under 1 s; patient questions
  answered) is pending a human run.
- A turn that mixes both addressees ("o abdome está doloroso; o senhor tem febre?") is
  expected to land undecided and so goes to the patient, as before #274.
