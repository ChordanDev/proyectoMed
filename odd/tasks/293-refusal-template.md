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

- [x] T1 — `CandidateGate` delivers a candidate equal to the no-information
  phrase without a Jev call (first candidate and regeneration), after the
  deterministic checks; other text still goes through Jev.
  Route: inline (one module + its tests; understood).
- [x] T2 — the no-information phrase becomes the in-role "Não sei dizer,
  doutor."; tests and docs follow.
  Route: inline (one default constant, tests that pin the literal, design doc).
- [x] T3 — live check: "A dor vai para outro lugar?" gets the phrase.
  Route: inline (`mix run --no-start` script).

## Checks

- `mix test` focused files per task (RED then GREEN).
- Local CI script (`LOCAL CI PASSED`).

## Progress

- T1 — commit `71d1e3e`. RED: 3 of 5 new `candidate_gate_test.exs` tests failed
  (bypass, whitespace, regeneration: Jev was called; the two guard tests
  passed). GREEN: `candidate_gate_test.exs` 82/82; full backend 1576/1576.
- T2 — commit `d3e9eb1`. RED: `station_ai_test.exs` 20/22 (prompt and default
  phrase pinned to the new literal). GREEN: full backend 1576/1576. One T1 test
  variant (uppercase phrase) was swapped for the phrase without its final
  period: `BoundedReply` reads the uppercase "NÃO SEI DIZER, DOUTOR." as
  English (uppercase diacritics are not in its pt-BR set), a pre-existing quirk
  outside this issue.
- T3 — live 8-turn replay (`create_message/2`, AnthropicAdapter patient,
  TypesafeAdapter Jev, acute-appendicitis), run with `mix run --no-start` and
  only the station processes started (no endpoint, no port):

  | # | Learner | Reply | Jev |
  |---|---|---|---|
  | 1 | Qual é seu nome? | refused (both attempts) | low_confidence, `undecided_other` |
  | 2 | Onde começou a toa? | Começou ao redor do umbigo, doutor. | verified (`hda-01`) |
  | 3 | Há quanto tempo começou? | Começou há umas 18 horas, doutor. | verified |
  | 4 | A dor mudou de lugar? | Mudou, sim, doutor. Há umas 10 horas ... | verified |
  | 5 | Ela piorou com o tempo? | Piorou, doutor. Ela foi aumentando aos poucos. | verified |
  | 6 | A dor vai para outro lugar? | Não sei dizer, doutor. | not called (bypass) |
  | 7 | Teve febre? | Tive uma febre baixa, doutor. Medi em casa. | verified |
  | 8 | Teve náusea ou vômito? | Tive náusea e vomitei uma vez, doutor, ... | verified |

  Turn 6 now reaches the learner. Turn 1 (name, "Meu nome é Rafael Nogueira,
  doutor.") was undecided twice in this run; in #286 it verified. It is not
  caused by this change (no fact or phrase involved) and is left as a
  follow-up. The voice path uses the same gate per sentence; no live voice run
  was made here.

Concern: the default regeneration generator calls `StationAI.next_reply/2`,
whose `BoundedReply.bound/2` replaces a violating reply with the same phrase,
so a regeneration that leaked out of role is now delivered as the
no-information answer instead of being sent to Jev. It discloses nothing, but
the ADR-011 doc says a deterministic violation is never delivered.

Review: native RDD not run by this bounded writer; the parent owns it.

## Next step

Local CI, push, PR to `feat/237-clinician-demo-readiness`.
