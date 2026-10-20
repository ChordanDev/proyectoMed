# 286 — Keep patient replies verifiable as the conversation grows

Issue: #286 (parent #237). Branch: `fix/286-multiturn-verification` from
`feat/237-clinician-demo-readiness`.

## Objective

From the fifth turn of a station on, patient replies keep being verified: each
generation answers only the latest learner question, and a fact an earlier
verified patient turn already disclosed is not re-gated by Jev.

## Why

Rehearsal on dc8af83: turns 1–4 answered, every turn from the fifth refused. Two
compounding causes (live 8-turn replay):

1. A refused or cancelled learner turn stores no patient reply, so
   `format_context/2` hands the generator a history ending in 2–3 learner
   questions, and "responda a cada parte" makes it answer the stale ones too
   ("Teve febre?" → "Sobre a dor ir para outro lugar: não tenho essa
   informação.").
2. `fact_asked:N` is recomputed over the whole conversation every request; an
   STT-garbled question ("Onde começou a toa?") scored 0.88 once and 0.46–0.66
   later, so every restatement of hda-01 became stated=yes/asked=undecided.

Also: meta refusal phrasings ("Só o que posso dizer é…", "Sobre X: não tenho
essa informação") score `risk:speaks_out_of_role` ≈ 0.6 (undecided).

## Constraints

- Only the generator context drops unanswered learner turns; Jev keeps the full
  history.
- The disclosed-fact set is per session and lives in the Conversation state
  (ETS), derived from committed patient turns, so it survives resume, kept
  turns and cancelled turns. Facts of a cancelled or refused candidate are never
  recorded.
- Disclosed facts keep `fact_stated` (for `used_fact_ids`) and every risk
  question, `risk:contradicts_patient` included; only `fact_asked` is skipped.
- Patient prompt copy in pt-BR; artifacts in English. `BackendWeb` untouched.

## Tasks

- [x] T1 — the generator context omits learner messages that never got a patient
  reply (a learner message directly followed by another learner message); the
  Jev request still carries both.
  Route: inline (one function in `stations.ex` + tests).
- [x] T2 — Jev seam: the patient request carries `disclosed_fact_ids`
  (validated authored ids); `TypesafeAdapter` asks no `fact_asked` question for
  those facts, so their disclosure is respected; undisclosed facts keep today's
  gating.
  Route: inline (`jev_decision.ex`, `typesafe_adapter.ex` + tests; understood).
- [x] T3 — session memory: the verdict's `used_fact_ids` flow out of
  `CandidateGate`, are stored on the committed patient message (text, voice and
  streamed voice paths) and the session's disclosed set is passed to every
  later verification.
  Route: inline (gate, stations, conversation, sentence stream; the parent
  delegated this whole issue to this single writer).
- [x] T4 — the patient prompt answers an unmatched question with the plain
  approved refusal phrase, without meta framing.
  Route: inline (one prompt sentence + test).
- [x] T5 — README documents the multi-turn behaviour; live 8-turn replay.

## Checks

- Focused: `mix test test/backend/stations/multiturn_verification_test.exs`,
  `test/backend/stations/jev_decision/typesafe_adapter_test.exs`,
  `test/backend/stations/station_ai_test.exs`, candidate gate and stream tests.
- Closure: local CI script (mirrors `.github/workflows/pr-validation.yml`).

## Progress

| Task | Commit | RED | GREEN |
|---|---|---|---|
| T1 | `c190c4c` | 2 failing in `multiturn_verification_test.exs` (generator saw the stale questions) | `mix test test/backend`: 1416 passed |
| T2 | `7b28ae5` | 4 failing in `typesafe_adapter_test.exs` (fact_asked still asked for a disclosed fact) | `test/backend/stations/jev_decision`: 208 passed; `mix test`: 1561 passed |
| T3 | `87d7db1` | 5 failing in `multiturn_verification_test.exs` (`disclosed_fact_ids` always `[]`), 3 in `candidate_gate_test.exs` (`verify/4` undefined), each observed with the implementation stashed | `mix test`: 1570 passed |
| T4 | `9c8017e` | 1 failing in `station_ai_test.exs` | `mix test`: 1571 passed |
| T5 | this commit | — (docs + live check) | live, see below |

T3 design: the disclosed set is derived from the transcript
(`Conversation.disclosed_fact_ids/1` over the patient messages'
`verified_fact_ids`), so it needs no new session field, is per session, survives
resume through ETS, and a kept, rolled back or cancelled turn cannot add or drop
facts. `Conversation.resolve_patient_reply/4` records the ids atomically with the
reply; a stale generation records nothing. Streamed replies record the union of
the verdicts of the sentences actually handed over.

T5 live check (2026-10-20, `mix run` in `dev`, `ACTIVE_STATION_ID=acute-appendicitis`,
`JEV_ADAPTER=typesafe`, Claude patient, real text path `Stations.create_message/2`,
26 provider calls). Script:
`scratchpad/multiturn_live_286.exs` (session scratch, not in the repo).

| # | Learner | Candidate | Verdict | Cause | Latency |
|---|---|---|---|---|---|
| 1 | Qual é seu nome? | Meu nome é Rafael Nogueira. | verified | — | 2475 ms |
| 2 | Onde começou a toa? | A dor começou ao redor do umbigo. | verified (`hda-01`) | — | 1940 ms |
| 3 | Há quanto tempo começou? | Começou há 18 horas. | verified (`hda-01-tempo`) | — | 2404 ms |
| 4 | A dor mudou de lugar? | Sim, há cerca de 10 horas ela migrou para a parte inferior direita da barriga. | verified (`hda-01-migracao`) | — | 2056 ms |
| 5 | Ela piorou com o tempo? | Sim, foi aumentando aos poucos. | verified (`hda-02-progressao`) | — | 2248 ms |
| 6 | A dor vai para outro lugar? | Não tenho essa informação (both attempts) | semantic_refusal, kept | `risk`: `speaks_out_of_role` 0.90 / 0.92 | 4003 ms |
| 7 | Teve febre? | Tive uma febre baixa, medi em casa. | verified (`hda-06`) | — | 2038 ms |
| 8 | Teve náusea ou vômito? | Tive náusea e vomitei uma vez, sem sangue nem bile. | verified (`hda-04`) | — | 2108 ms |

Every generation answered only the latest question (turn 7's context did not
carry the refused turn 6). Turn 6 is a radiation question with no authored
fact, so the plain refusal phrase is the right content, but Jev scores the bare
"Não tenho essa informação" as out of role (0.90). Not fixed here: making the
refusal pass needs a content decision (an approved template for it, which the
clinical review owns, D20, or a more in-role refusal phrase).

Review: native RDD not run by this bounded writer; the parent owns it.

## Next step

Local CI, push, PR to `feat/237-clinician-demo-readiness`. Follow-up: the bare
refusal phrase scored out of role by Jev.
