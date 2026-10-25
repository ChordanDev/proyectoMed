# Turn addressee: patient or examiner

Status: **Implemented for #274, decided by the patient generation since #309** (parent
#237). This note adds to ADR-011 (#123, the Jev verification gate) and ADR-008 (the
station conversation). #235 recorded that deciding who a learner turn is addressed to
deserves its own decision once real-time voice landed. It does not change ADR-011's
gate, the grading contract (ADR-012) or any claim boundary in
[jev-prototype.md](jev-prototype.md).

## Problem

In the exam room the candidate talks to the patient and also says findings, lab and
imaging interpretation, the diagnosis and the plan out loud to the examiner. Until #274
every learner turn produced a patient reply: a generation, then a Jev verification.
A turn meant for the examiner is usually refused by the gate (the patient cannot
answer it), and only then did the learner see "Examinador: Anotado.". That cost about
1.5-3 s per turn in the second half of the station. A refused reply to a real patient
question showed the same "Anotado.", which reads as if the examiner had answered.

#274 added a separate Jev `turn_addressee` question per turn, and #294 ran it beside
the generation. It still cost 0.2-0.5 s per turn (one 1 s error in the 2026-10-20
rehearsal) and spent a generation that was thrown away on every examiner turn.

## Decision (#309)

The patient generation decides the addressee in the same call. There is no Jev
addressee request on any path (text, voice, streamed voice).

| Item | Decision |
|---|---|
| Marker | The patient prompt ends with `MARCAÇÃO DO DESTINATÁRIO`: every reply starts with exactly `[PACIENTE]` or `[EXAMINADOR]`. Examiner = the learner addresses the examiner or the station: asks for an exam, a maneuver, the physical exam or a result, or tells the examiner what was done, found, concluded or planned. Nothing follows `[EXAMINADOR]`. In doubt, `[PACIENTE]`. |
| Parsing | `Backend.Stations.StationAI.Addressee`, in code, from the first characters: case and spaces inside the brackets are ignored. The marker is stripped before BoundedReply, Jev, the transcript, the client or TTS see the text; it is never spoken, shown or stored. |
| Missing or unknown marker | Patient-addressed, the text kept whole (an unknown bracket such as a stage direction is not lost), and logged with `source=missing_marker`. |
| Impresso request | A learner text in which `Impressos.match` finds an authored impresso (#302, with the #305 negation rules) is examiner-addressed before any generation, without the model. |
| Logging | One line per turn: `[Stations] turn_addressee decision=<examiner\|patient> source=<marker\|missing_marker\|impresso> channel=<text\|voice> latency_ms=<n>`, the time from the start of the turn to the decision. No learner or patient text. |

### Paths

- Text (`create_message/2`) and non-streamed voice (`process_voice_turn/3`): the whole
  reply is generated, its marker read, and an examiner reply is acknowledged without
  verification; a patient reply continues to the pre-delivery check of its
  verification mode (#307).
- Streamed voice (`stream_voice_turn/5`): the generated pieces are held back until the
  marker is decided, and the decision reaches the sentence gate
  (`SentenceStream`'s `:gate`) before any text does. Examiner stops the reply: nothing
  of the generation is verified, handed to the worker, stored or logged as a
  `voice_sentence`. A marker decided before the generation failed still wins: the turn
  is acknowledged, not failed.
- The CandidateGate's regeneration (`StationAI.next_reply/2`) strips the marker too; a
  regeneration is always patient-addressed.
- The verification of an examiner turn is never spent, and no `verified_fact_ids` are
  recorded for it (#286).

## A station with a companion (#341)

A package whose `actors` include a companion (`role: companion`, at most one)
plays both actors in the same generation.

| Item | Decision |
|---|---|
| Marker | The prompt asks for `[PACIENTE]`, `[ACOMPANHANTE]` or `[EXAMINADOR]`. `[ACOMPANHANTE]` = the learner addresses the companion, or asks for a fact only the companion's list has. In doubt, whoever has the fact in its list; if nobody has it, `[PACIENTE]`. `Addressee` reads `[ACOMPANHANTE]` only for such a package (`companion: true`); without a companion it stays an unknown marker, as before. |
| Profiles and facts | The prompt (`StationAI`, `companion_prompt`) shows each actor's profile and its own fact list (`Backend.Stations.Actors.facts/2`). A companion reply is checked and audited against the companion's own profile and facts (`Actors.speaker_package/2`). |
| Speaker | The reply, the stored patient message and the generator history carry the speaker: `speaker: :companion` and `[ACOMPANHANTE]` before the earlier reply. Each streamed sentence carries `speaker` and `voice` (the voice key) to the voice worker, which labels the room event and picks the voice (see `docs/unreal-station-client.md`). |
| Mandatory questions | In the last `:mandatory_questions_window_ms` (default 3 minutes) the per-turn part of the prompt lists the actors' mandatory questions no stored reply contains yet, each with its marker; the speaker asks the next one on a learner turn that asks for no fact. |
| Grading | Unchanged: evidence is the learner turns, whoever they were addressed to, so a question to the companion counts like one to the patient (`companion_turn_test.exs`). |

A single-actor package is unchanged on every path: same prompt, markers,
messages, results and sentence events (no `speaker` or `voice` key).

Limitations: the text API response and the session transcript are serialized by
controllers this issue does not change, so they do not show the speaker yet;
the non-streamed voice receipt carries no speaker either, and the worker reads
it as `patient`.

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

## Exam requests to the examiner (#302)

A turn (text or voice) whose text names at least one authored impresso is an
impresso request, and since #309 examiner-addressed without the model: the backend matches it with `Impressos.match`
over `Impressos.normalize(text)` (deterministic, no model) and, when anything
matches, records it through `Stations.request_impresso/2`, the path of the impressos
modal. The release and its `impresso_requests` event are therefore those of a modal
request, and the rubric counts them the same way. A voice turn uses the request id
`voice-turn-<turn_id>`, so a retried turn is not recorded twice.

A remark that matches nothing records nothing: unlike a modal request, it is not an
`unavailable` request. A repeated request is recorded as `already_released`, as from
the modal. A patient-addressed turn never releases impressos.

An exam named only to decline it is not a request (#305). `Impressos.match` splits
the text into clauses (sentence punctuation, `;`, `,`, "mas", "porém", "e solicito",
"e peço") and ignores a keyword occurrence preceded in its clause by a negation cue
("não", "nem", "sem", "dispenso", "dispensa") or followed by a clause-ending "não" /
"não é necessário(a)" / "não precisa". So "não preciso do ECG, mas solicito hemograma"
releases only the hemograma, and an examiner turn whose every exam mention is declined
releases and records nothing; from the modal it is an `unavailable` request.

- Text API: the `examiner_acknowledged` response carries `newly_released` (impresso
  objects, empty when nothing was released).
- Voice: the receipt and the worker event are unchanged; the web learns of the release
  by listing the session impressos after the examiner acknowledgement.
- Web: after an examiner acknowledgement (text reply or voice event) `useStation`
  re-reads the released impressos (`getImpressos`). When new ones appear, the examiner's
  existing hand-over entry ("Entrega: <títulos>") follows "Anotado." and the impressos
  drawer opens; with none, only "Anotado." shows. The impressos modal is unchanged.

## Grading

Grading does not change. An examiner-addressed turn is stored exactly as a refused
patient-addressed turn is stored since #235: one learner message with the same role,
modality and text, and no patient message. The evidence pool and rubric assessment
read learner turns without any addressee, so the same learner turns give the same
evidence and the same grade (tested in
`backend/test/backend/stations/turn_addressee_evidence_test.exs`). Since #302 the only
addition is the impresso events of exam requests made to the examiner.

## Open points

- The prompt wording is not calibrated on a full set of live pt-BR turns; the #309 live
  check covers the 10-turn script and three examiner phrasings.
- A turn that mixes both addressees ("o abdome está doloroso; o senhor tem febre?") is
  expected to be marked `[PACIENTE]` (the doubt rule), as before #274.
- A patient question that names an authored exam ("o senhor já fez hemograma?") is an
  exam request to the examiner by the impresso rule.
