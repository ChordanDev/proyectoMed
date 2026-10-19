# Do not read the patient's stage directions aloud (#257)

Parent tracker: #237. Branch: `fix/257-tts-stage-directions` from `feat/237-clinician-demo-readiness`.

## Objective
Text-to-speech speaks only the patient's words: nonverbal stage directions such as
`*(curvado, com a mão na barriga)*` are removed from the text sent to the voice
provider (OpenAI and ElevenLabs). The transcript and the web keep the full text.

## Why
With Claude as the patient (#252), replies begin with stage directions. In the
2026-10-19 rehearsal ElevenLabs (#253) read them aloud through "Ouvir resposta".

## Scope and constraints
- Backend only. Sanitize inside `Backend.Stations.TTS` before any provider call, so
  both providers share it. Transcript and web output are unchanged.
- Rule: remove every `*…*` span, then a parenthesized group at the very start of the
  reply and a parenthesized group at the end of the reply when it stands alone
  (whole text, or after sentence-ending punctuation). Parentheses inside a sentence stay.
- If nothing speakable remains, return the existing `:invalid_text` outcome (HTTP 400,
  "nothing to synthesize") without calling the provider.
- Never log the text. Keep the rule simple and documented (moduledoc + README).

## Acceptance criteria
- `*(curvado, com a mão na barriga)* Vim por causa de uma dor na barriga.` is
  synthesized as `Vim por causa de uma dor na barriga.` (tested, both providers).
- Text without stage directions is unchanged, including in-sentence parentheses (tested).
- A reply made only of a stage direction makes no provider call (tested).
- Live check: "Ouvir resposta" does not read the actions (pending, human).

## Tasks
- [x] T1 — Strip stage directions before synthesis (route: inline; one module, one
  test file, README paragraph; no delegation trigger fired).
  - RED: 5 new tests in `backend/test/backend/tts_test.exs` (`describe "stage directions"`);
    `mix test test/backend/tts_test.exs` -> 20/24 passed, 4 failed. The "unchanged text"
    test passes by construction.
  - GREEN: `mix test test/backend/tts_test.exs test/backend_web/controllers/tts_controller_test.exs`
    -> 31 passed.
  - Commit: `ba6b460` (`fix(tts): do not read the patient's stage directions aloud`).

## Checks
- `mix test test/backend/tts_test.exs` (focused).
- Local CI (`local_ci.sh`), mirroring `.github/workflows/pr-validation.yml`.

## Progress
- T1 done. Local CI passed: web 213 tests (9 files), backend 1244 tests, runner 4 tests,
  dialyzer 0 errors.

## Next step
- Human live check with ElevenLabs: "Ouvir resposta" must not read the actions.
