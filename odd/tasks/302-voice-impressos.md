# 302 — Release impressos when the learner asks the examiner out loud

Issue: #302 (parent #237). Branch: `feat/302-voice-impressos` from `feat/237-clinician-demo-readiness`.

## Objective

A learner turn kept as examiner-addressed (voice or text) whose text matches at
least one authored impresso releases it through the same deterministic
`request_impresso` path the modal uses. The web refreshes the released
impressos after an examiner acknowledgement, opens the drawer and shows the
existing "examiner hands over" bubble when new ones appear.

## Why

In the 2026-10-20 spoken rehearsal "Solicito hemograma e PCR" was routed to the
examiner and only "Anotado." appeared; the learner had to type the request in
the modal.

## Constraints

- Release stays deterministic (`Impressos.match` over `Impressos.normalize`),
  no LLM involved; the rubric sees the same impresso event as a modal request.
- An examiner remark that matches nothing records nothing (no `unavailable`).
- `BackendWeb` stays thin; only `Backend.Stations` is called.
- Learner-facing copy stays pt-BR and reuses existing strings.
- The modal keeps working as today.

## Tasks

- [x] T1 Backend: examiner-addressed turns (text + voice) release matching
  impressos; text response carries `newly_released`; rubric parity test;
  design note in `docs/design/turn-addressee.md`.
- [x] T2 Web: after an examiner acknowledgement (text reply or voice event)
  refresh impressos; when new ones appear open the drawer and add the
  hands-over bubble instead of only "Anotado.".
- [ ] T3 ADR-008 amendment comment on #104.

## Routing

- T1: delegated direct (this bounded writer), backend only.
- T2: delegated direct (this bounded writer), web feature `station` only.
- T3: `gh issue comment`.

## Checks

- `mix test` (backend), `npm --prefix web test`, local CI script
  (`LOCAL CI PASSED`).

## Progress

- T1 done. RED: 7 new/extended tests failed (turn_addressee_test +
  station_controller_test, 85 tests). GREEN: 85 passed. The #274 evidence
  regression (`turn_addressee_evidence_test.exs`) failed as expected (examiner
  lab/exam turns now add impresso events) and was updated to compare transcript
  turns and allow only impresso events on top. Full backend: 1666 passed;
  `mix format --check-formatted`, `mix credo --strict` clean.

- T2 done (feature slice). RED: 7 of 138 failed (useStation 4,
  StationScreen 1, StationScreen.voice 2). GREEN: station feature 322 passed;
  `npm run typecheck` and eslint clean. `useStation.refreshImpressos` re-reads
  impressos; the text path carries the new ones on `ExaminerAcknowledgement`;
  `StationScreen` takes `onRefreshImpressos` for voice acknowledgements.
- Open: `web/src/App.tsx` is outside the allowed edit surfaces, so
  `onRefreshImpressos={station.refreshImpressos}` is not wired yet; approval
  requested from the parent. Until wired, the live voice path releases on the
  backend but the drawer only refreshes on resume.

## Next step

T3, then App.tsx wiring if approved.
