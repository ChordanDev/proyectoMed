# 284 — Stop Jev from refusing every in-role patient reply

Issue: #284 (parent #237). Branch: `fix/284-jev-role-threshold` from
`feat/237-clinician-demo-readiness`.

## Objective

In-role patient replies ("Meu nome é Rafael Nogueira.") are verified again on the
28-fact acute-appendicitis package, with no `TYPESAFE_NO_THRESHOLD` override.

## Why

After the #264/#273 fact splits, `risk:speaks_out_of_role` scores benign in-role
replies 0.22–0.47. Under the global no threshold 0.2 that is undecided, the verdict
is `:low_confidence` and the gate refuses both attempts (`undecided_other`).
Secondary: "Onde começou a dor?" sometimes also volunteers the migration
(`hda-01-migracao`) while its `fact_asked` is undecided, which no targeted retry
covers.

## Constraints

- Global 0.2/0.8 thresholds stay for every other risk and fact label.
- The per-risk threshold is validated like the global ones and fails closed.
- `BoundedReply`'s deterministic roleplay-leakage check still covers obvious
  out-of-role text.
- Learner-facing and patient prompt copy in pt-BR; artifacts in English.

## Tasks

- [x] T1 — `risk:speaks_out_of_role` gets its own no threshold
  (`:out_of_role_no_threshold`, env `TYPESAFE_OUT_OF_ROLE_NO_THRESHOLD`, default
  0.5), validated like the global no threshold; README documents it.
  Route: inline (one adapter + runtime config + tests; already understood).
- [x] T2 — a stated-yes / asked-undecided on-request fact is named in
  `undecided_fact_ids`, so `CandidateGate` regenerates once with it withheld.
  Route: inline (one function in the adapter + tests).
- [x] T3 — the patient instruction keeps sibling facts of the same subject unsaid
  (where the pain started vs. where it went later).
  Route: inline (one prompt sentence + test).
- [x] T4 — live check on acute-appendicitis: "Qual é seu nome?", "Onde começou a
  dor?", "Há quanto tempo começou?" each get a patient answer.

## Checks

- Focused: `mix test test/backend/stations/jev_decision/typesafe_adapter_test.exs`,
  `test/backend/stations/station_ai_test.exs`, candidate gate tests.
- Closure: local CI script (mirrors `.github/workflows/pr-validation.yml`).

## Progress

| Task | Commit | RED | GREEN |
|---|---|---|---|
| T1 | `eb6cce5` | 4 failing in `typesafe_adapter_test.exs` (default band, invalid config, two runtime.exs) | `test/backend/stations/jev_decision/`: 202 passed |
| T2 | `0630886` | 2 failing (adapter naming, CandidateGate end to end through TypesafeAdapter) | `test/backend/stations/`: 935 passed |
| T3 | `ff65b52` | 1 failing in `station_ai_test.exs` | `test/backend/stations/`: 936 passed |
| T4 | no code | — | live, see below |

T1 note: unset, the out-of-role no threshold is `0.5`, or the global no threshold
when `yes_threshold` is itself `0.5`, so a valid global config never becomes
invalid through the default.

T4 live check (TypeSafe Jev + configured patient LLM, `TYPESAFE_NO_THRESHOLD`
unset, single-turn, through `Backend.Stations.verify_patient_reply/3`):

| Question | Candidate | Verdict | `speaks_out_of_role` |
|---|---|---|---|
| Qual é seu nome? | Meu nome é Rafael Nogueira. | verified, delivered | 0.200 |
| Onde começou a dor? | A dor começou ao redor do umbigo. | verified, delivered | 0.220 |
| Há quanto tempo começou? | Começou há umas 18 horas. | verified, delivered | 0.180 |

Refusal causes: verified 3, none refused. The 0.220 turn would have been
`undecided_other` under the old global 0.2.

Review: native RDD not run by this bounded writer; the parent owns it.

## Next step

Local CI, push, PR to `feat/237-clinician-demo-readiness`.
