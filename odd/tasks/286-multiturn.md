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

- [ ] T1 — the generator context omits learner messages that never got a patient
  reply (a learner message directly followed by another learner message); the
  Jev request still carries both.
  Route: inline (one function in `stations.ex` + tests).
- [ ] T2 — Jev seam: the patient request carries `disclosed_fact_ids`
  (validated authored ids); `TypesafeAdapter` asks no `fact_asked` question for
  those facts, so their disclosure is respected; undisclosed facts keep today's
  gating.
  Route: inline (`jev_decision.ex`, `typesafe_adapter.ex` + tests; understood).
- [ ] T3 — session memory: the verdict's `used_fact_ids` flow out of
  `CandidateGate`, are stored on the committed patient message (text, voice and
  streamed voice paths) and the session's disclosed set is passed to every
  later verification.
  Route: inline (gate, stations, conversation, sentence stream; the parent
  delegated this whole issue to this single writer).
- [ ] T4 — the patient prompt answers an unmatched question with the plain
  approved refusal phrase, without meta framing.
  Route: inline (one prompt sentence + test).
- [ ] T5 — README documents the multi-turn behaviour; live 8-turn replay.

## Checks

- Focused: `mix test test/backend/stations/multiturn_verification_test.exs`,
  `test/backend/stations/jev_decision/typesafe_adapter_test.exs`,
  `test/backend/stations/station_ai_test.exs`, candidate gate and stream tests.
- Closure: local CI script (mirrors `.github/workflows/pr-validation.yml`).

## Progress

| Task | Commit | RED | GREEN |
|---|---|---|---|

## Next step

T1.
