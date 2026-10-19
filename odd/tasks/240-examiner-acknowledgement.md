# #240 Let the examiner acknowledge messages addressed to the examiner

Parent: #237. Branch: `feat/240-examiner-acknowledgement` (base `feat/237-clinician-demo-readiness`).

## Objective

In the exam room the candidate also speaks to the examiner. When the patient reply
is refused but the learner turn is kept (#235), the transcript shows an examiner
acknowledgement ("Examinador: Anotado.") instead of the system notice, and impresso
releases appear as examiner entries ("Examinador — Entrega: <título>") while the
drawer keeps working.

## Why

In the 2026-10-19 run the exam authorization and the verbalized exam findings were
kept for grading, but the learner saw "Sua mensagem foi registrada, mas o paciente
não respondeu a ela.", which reads like an error to a clinician. Impresso feedback
was a plain system string.

## Constraints

- Web-only. Examiner entries are display-only: never sent to or stored by the
  server, never patient text, never in the rubric evidence pool.
- No per-turn addressee model (needs its own ADR with real-time voice, see #235).
- The #224 technical-failure path (bubble removed, draft restored, retry notice)
  stays unchanged.
- Examiner entries are visually distinct from patient turns, accessible (role and
  aria labels), with pt-BR copy and no audio playback.

## Tasks

- [x] T1 Kept-turn refusal shows an examiner acknowledgement in the transcript
  instead of the system notice; the hook exposes `isKeptLearnerTurn`.
  Route: inline (station feature only: hook, screen, i18n, CSS, tests).
- [x] T2 Impresso releases appear as examiner entries in the transcript; the
  plain feedback notice stays only for unavailable/already-released decisions.
  Route: inline (StationScreen and its tests).

## Acceptance criteria

- After a kept-turn refusal the transcript shows the learner bubble followed by an
  examiner acknowledgement, and no system notice (tested).
- Impresso releases appear as examiner entries in the transcript (tested).
- The #224 technical-failure path is unchanged (tested, existing tests kept).
- No new message is sent/stored server-side and grading is unchanged (tested:
  no extra `onSend`/`sendMessage` call; backend untouched).

## Checks

- `npm --prefix web test` focused runs per task, then the local CI script
  mirroring `pr-validation.yml`.

## Progress

| Task | Commit | RED | GREEN |
| --- | --- | --- | --- |
| T1 | `afa5faa` | 6 of 198 failed (hook rename + 2 screen tests) | 198 passed; typecheck and lint clean |
| T2 | `12023e1` | 2 of 201 failed (release entry, stale notice) | full web suite 216 passed; typecheck and lint clean |

Local CI (mirror of `pr-validation.yml`): LOCAL CI PASSED; web 212 unit + 4
integration tests passed, backend 1122 passed, typecheck/lint/format clean.
GitHub Actions is blocked by billing.

## Next step

PR against `feat/237-clinician-demo-readiness`.
Examiner entries are not restored after a refresh (display-only by design).
