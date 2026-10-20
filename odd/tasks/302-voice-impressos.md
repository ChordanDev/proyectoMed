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
- [x] T3 ADR-008 amendment comment on #104.
- [x] T4 Wire `onRefreshImpressos={station.refreshImpressos}` in `web/src/App.tsx`.
- [x] T5 Jorge advisory review and confirmed repairs.
- [x] T6 Drawer screenshots (desktop + mobile).

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

- T1 commit 8e3155d, T2 commit b6cc96e.
- T3 done: amendment posted on #104 (issuecomment-6299656793).
- Local CI: LOCAL CI PASSED (web 337 tests, backend 1666 tests, plus the
  remaining CI steps). GitHub Actions is blocked by billing.
- Pending: App.tsx wiring (approval), drawer screenshots after a spoken
  request (desktop + mobile) need a live run.

- T4 done: App.tsx wiring in b784455 (merged with the parent at 3083300).
  Local CI: LOCAL CI PASSED.
- T5 done: Jorge advisory review on PR #303 (base e251636, head 3083300).
  Advisory approval, no blockers. One CONFIRMED finding (Cluster A): the voice
  release re-read the latest learner message instead of the turn's own text,
  so a learner turn committed during classification could drive the release
  under `voice-turn-<N>`. Fixed test-first in 9b8c381 (RED: released
  `imagem-radiografia-torax` instead of the lab impresso; GREEN: 20/20 in
  `turn_addressee_test.exs`). Local CI: LOCAL CI PASSED (web 337, backend
  1681). Non-blocking follow-ups: the web drops the text reply's
  `newly_released` and re-reads with an extra GET (Cluster B); refresh
  responses replace the list without ordering (Cluster C, display only);
  failed releases are silent and voice transcripts are not length-checked
  before matching (Cluster D). Negated mentions releasing impressos (Cluster F)
  follow the spec and are a product question. No duplicated code or tests from
  the concurrent writers.
- T6 done: headless Firefox, text path ("Solicito hemograma e PCR" routed to
  the examiner by a scratch-only addressee adapter, because the E2E approving
  adapter has no `decide_addressee`). The drawer opened with 2 impressos and
  one hands-over entry. Saved outside the repository as
  `shots-302/desktop-impressos-drawer.png` and
  `shots-302/mobile-impressos-drawer.png` in the session scratchpad.
  Pre-existing: on mobile (390px) the input row overflows horizontally.

## Next step

Human review and merge of PR #303 into `feat/237-clinician-demo-readiness`.
