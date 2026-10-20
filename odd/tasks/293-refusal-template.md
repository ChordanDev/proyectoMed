# 293 — Deliver the patient's no-information answer without a Jev refusal

Issue: #293 (parent #237). Branch: `fix/293-no-information-template` from
`feat/237-clinician-demo-readiness`.

## Objective

When the patient has no authored fact for a question, the learner hears the
patient's honest no-information answer instead of an "Aviso".

## Why

In the #286 live check, "A dor vai para outro lugar?" (no authored radiation
fact) was refused twice: Jev scored the bare "Não tenho essa informação" as
`risk:speaks_out_of_role` 0.90 / 0.92. Refusing to invent is the right content;
the phrase just cannot get through Jev. `approved_templates` is `null` in
acute-appendicitis, so the package-level template bypass does not help.

## Constraints

- One phrase for every station: `Backend.Stations.StationAI.refusal_text/0`
  (still overridable through `:backend, :station_ai_refusal_text`).
- Only a candidate equal to that phrase (surrounding whitespace aside) skips
  Jev; any other text, even one containing the phrase, is verified by Jev.
- The deterministic `BoundedReply.check_violations/2` checks still run first.
- The bypass discloses no facts (`used_fact_ids: []`).
- Patient copy in pt-BR; artifacts in English. `BackendWeb` untouched.

## Tasks

- [ ] T1 — `CandidateGate` delivers a candidate equal to the no-information
  phrase without a Jev call (first candidate and regeneration), after the
  deterministic checks; other text still goes through Jev.
  Route: inline (one module + its tests; understood).
- [ ] T2 — the no-information phrase becomes the in-role "Não sei dizer,
  doutor."; tests and docs follow.
  Route: inline (one default constant, tests that pin the literal, design doc).
- [ ] T3 — live check: "A dor vai para outro lugar?" gets the phrase.
  Route: inline (`mix run --no-start` script).

## Checks

- `mix test` focused files per task (RED then GREEN).
- Local CI script (`LOCAL CI PASSED`).

## Progress

(updated per task)

## Next step

T1.
