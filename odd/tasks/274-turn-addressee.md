# #274 Decide whether each learner turn is addressed to the patient or the examiner

Parent: #237. Branch `feat/274-turn-addressee` (from `origin/feat/237-clinician-demo-readiness` at `f99758e`).

## Objective
Before generating a patient reply, classify each learner turn (text and voice) as
patient-addressed or examiner-addressed with one TypeSafe (Jev) question. An
examiner-addressed turn is stored, gets no patient generation and is acknowledged at
once by the examiner. A patient-addressed turn whose reply is refused never shows
"Anotado."; the learner sees a neutral pt-BR notice and may rephrase.

## Why
In the second half of a station the candidate verbalizes findings, lab and imaging
interpretation and the plan to the examiner. Today each of those turns costs a full
patient generation plus a verification (about 1.5-3 s) that is usually refused, and
only then shows "Examinador: Anotado.". A refused patient question shows the same
"Anotado.", which reads wrong.

## Constraints
- Grading and evidence must not change: learner turns are evidence whatever the addressee.
- One TypeSafe noul question, thresholds 0.8 (yes) / 0.2 (no); undecided, or any
  technical failure of the check, is patient-addressed (today's behaviour).
- The examiner path runs the classifier only: no generation, no verification.
- Voice: the classification runs before the sentence stream (#271) starts.
- Log the decision and its latency with no content.
- Web edits minimal (#281 edits StationScreen voice segment handling in parallel).
- No live calls; the live check stays pending.

## Tasks
- [x] T1 Design note `docs/design/turn-addressee.md` (ADR-011/ADR-008 addendum) — route: inline (one passive doc)
- [ ] T2 Jev addressee decision: optional adapter callback, TypeSafe question, `JevDecision.decide_addressee/2` with deadline and content-free log (RED→GREEN) — route: inline writer (this worker)
- [ ] T3 Text path: classify before generation; examiner → keep learner turn, `200 outcome: examiner_acknowledged`; regression check that evidence is unchanged (RED→GREEN)
- [ ] T4 Voice path (backend): classify before generation/stream; kept receipts carry `addressee` (RED→GREEN)
- [ ] T5 Voice worker: examiner-addressed kept receipt publishes `status: acknowledged`, refusal keeps `status: kept` (RED→GREEN, unittest)
- [ ] T6 Web: examiner acknowledgement shows "Anotado."; kept refusal (text and voice) shows the neutral notice (RED→GREEN)

Route note: this whole issue runs inside one delegated bounded writer (the parent
orchestrator delegated it); tasks run sequentially in this worker.

## Acceptance criteria
From #274: examiner turn makes no generation call and is acknowledged immediately;
patient refusal shows the neutral notice, not "Anotado."; undecided is
patient-addressed; grading and evidence unchanged; live check (pending, human).

## Checks
- Backend: `cd backend && mix test` (focused per task), `mix precommit` style checks via local CI.
- Worker: `cd voice-worker && uv run python -m unittest`.
- Web: `npm --prefix web test`, typecheck, lint.
- Closure: `local_ci.sh <worktree>` must print `LOCAL CI PASSED`.

## Progress
- Worktree created, deps fetched, CodeGraph initialized.

## Next step
T1.
