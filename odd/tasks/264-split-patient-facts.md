# #264 Split bundled patient facts so each rubric characteristic must be asked on its own

Parent: #237. Branch: `fix/264-split-patient-facts` (base `feat/237-clinician-demo-readiness`).

## Objective

Each acute-appendicitis `on_request` fact answers at most one rubric characteristic
of items 2, 3 and 4, so the patient reveals only what the learner asked.

## Why

In the 2026-10-19 rehearsal "O que o trouxe aqui hoje? Onde começou a dor?" got the
onset location, the migration and the 18-hour duration in one reply, because
`hda-01` bundles three item-2 characteristics in one sentence. Item 2 scored 0.4 of
0.8: the learner never asked about migration or duration, and patient turns are not
evidence. `hda-02` bundles character, progression and intensity the same way.

## Constraints

- Content only: split sentences, never invent facts; fictional case, pt-BR.
- Keep ids stable: the first part keeps the old id, new parts get a suffixed id.
- Touch only `revealable_facts` in `package.json` (#265 edits the rubric in parallel).
- Qualification fixtures change only fact ids in notes; expected verdicts unchanged.
- No live calls (no keys): the live check stays pending.

## Tasks

- [x] T0 Feature document. Route: inline.
- [x] T1 Split the item-2 facts: `hda-01` into initial location, migration and time
  since onset; `hda-02` into character, progression and intensity. Update the mapping
  record, the clinical review checklist and the qualification notes that name
  `hda-01`. Route: inline (one content file plus docs; already understood).
- [x] T2 Split the item-3/4 bundles: `antecedentes-01` (comorbidities vs prior
  hospitalizations and surgeries) and `pergunta-explicita-02` (recent
  anti-inflammatories vs recent antibiotics or anticoagulants). Route: inline.
- [x] T3 Confirm the patient prompt and Jev per-fact questions work at the new
  granularity (no code change expected). Route: inline.

### Reviewed and kept whole

- `hda-03` (worsening and relief): both are item-2 criterion 6.
- `hda-04` (nausea and vomiting): item-3 criterion 2.
- `hda-06` (fever, no antipyretic): item-3 criterion 1.
- `hda-07` (bowel habit and gases): item-3 criterion 4.
- `pergunta-explicita-03`, `-04` (alarm signs): item-3 criterion 6.

## Acceptance criteria

- The package validates; each item-2 characteristic is a separate on-request fact (tested).
- Existing tests and the qualification harness pass; fixture notes follow the new ids.
- Live check: "Onde começou a dor?" gets only the initial location; migration and
  duration come out only when asked. Pending (needs the maintainer's keys).

## Checks

- `mix test` (backend); local CI script mirroring `pr-validation.yml`.

## Progress

| Task | Commit | RED | GREEN |
| --- | --- | --- | --- |
| T1 | `0dd7a56` | 2 of 11 failed (`acute_appendicitis_package_test.exs`); then the checklist test failed on the new ids (14 of 15) | 15 of 15; full backend 1256 passed; `mix format --check-formatted` clean |
| T2 | `e4b747f` | 1 of 12 failed (`each item-4 characteristic is a separate on-request fact`) | 12 of 12; full backend 1257 passed; format clean |
| T3 | this commit (see `git log`) | n/a: no behavior change (review only) | n/a |

## T3 findings (no code change)

- Patient prompt (`StationAI.base_prompt/1`) lists every fact with its authored id and
  already tells the model to answer only what was asked (#242); finer facts need no
  prompt change.
- Jev (`TypesafeAdapter.plan_facts/1`) asks one `fact_stated:<n>` and one
  `fact_asked:<n>` per on-request fact by position, so each split fact gets its own
  questions. The dialogue request grows by 12 questions (6 new on-request facts); no
  per-call question cap applies to the dialogue gate.
- Open risk for the live check: `patient_profile.presenting_context` still carries
  "dor abdominal iniciada há cerca de 18 horas" and "dor atual de intensidade 7/10".
  The prompt marks the other clinical data of the context as not revealable, but the
  live check should confirm the model does not answer duration or intensity from it.
  Changing that field is outside this issue's surface.

## Next step

Local CI, push, PR. Live check pending (needs the maintainer's keys).
