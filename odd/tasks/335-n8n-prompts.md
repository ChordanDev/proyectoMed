# 335 — n8n generator and reviewer prompts for the tagged format

Issue: #335 (parent spec #326). Branch: `docs/335-n8n-prompts` → PR base `feat/326-production-launch`.

## Objective

Put in the repo, next to the format spec, the prompts the n8n pipeline uses to produce cases in the tagged format: the AI Agent (generator) system prompt, the reviewer-node prompt, and the Neon insert node instructions. The user applies them in n8n (HITL).

## Why

n8n today generates human-readable Markdown the backend cannot load (#326). The parser (#330) and the `cases` table (#331) exist; the generator must now emit the tagged format, keep the clinical rules of the current prompt, support a companion actor, leave numbering to Postgres and stay original (never reproduce official cases verbatim).

## Constraints

- Prompts in pt-BR (they address a pt-BR examiner persona); repository docs around them in English.
- Production n8n runs OpenAI; prompt wording stays model-agnostic. Samples were generated with the Anthropic API only to prove parseability.
- Insert contract is the one documented by #331 in `docs/case-format/README.md`: n8n sets only `area`, `theme`, `markdown`.
- Allowed edit surfaces: `docs/n8n/**`, `docs/case-format/**`, `backend/test/backend/stations/fixtures/case_format/**`, `backend/test/backend/stations/case_format_n8n_samples_test.exs`, this file.
- Planning heuristic: about 400 authored changed lines per task (advisory only).

## Checklist

- [x] T1 — Generator prompt `docs/n8n/generator-prompt.md`: current clinical rules + every tag of the spec + companion actors + numbering left to the DB + originality rule. Test: the prompt names every tag of the spec and its embedded example parses with zero errors.
- [x] T2 — Reviewer prompt `docs/n8n/reviewer-prompt.md` (arithmetic, tags, links, actor/question coverage; `APROVADO` or a list of fixes) and Neon insert `docs/n8n/neon-insert.md` + `docs/n8n/README.md` (flow, HITL checklist). Test: the insert SQL in `neon-insert.md` runs against the `cases` table and returns a sequential number with status `pending`.
- [x] T3 — Three sample cases generated with the generator prompt (one with a companion) saved as fixtures; test that each parses with zero errors via `Backend.Stations.parse_case/1`.

## Routing

All tasks: delegated direct (this worker is the single bounded writer for #335).

## Acceptance criteria (issue)

- Both prompts are in the repo next to the format spec.
- A case generated with the new prompt parses with zero errors in at least 3 sample themes (one with a companion).
- The insert instructions match the cases table.
- The user confirms the flow is updated in n8n (HITL, pending).

## Checks

- Focused: `mix test test/backend/stations/case_format_n8n_samples_test.exs`.
- Full: local CI script (backend tests, web typecheck/lint, format, compile warnings, credo strict, dialyzer).

## Progress

- T1 (generator prompt): RED — 0/2 (`docs/n8n/generator-prompt.md` missing); GREEN — 2/2 (prompt names all 21 spec tags; embedded companion example parses). Commit 62c7fa5.
- T2 (reviewer prompt, Neon insert, flow README + HITL checklist): RED — 2/4 (`docs/n8n/neon-insert.md` missing); GREEN — 4/4 (documented SQL equals the spec contract; run against the test DB it returns increasing numbers and stores `pending`). The generator prompt also learned the regeneration input (ESTAÇÃO ANTERIOR + CORREÇÕES). Reviewer prompt is passive prose: no runnable RED; structural readback only. Commit 347c866.

- T3 (three generated samples): generated with the generator prompt through the Anthropic API (`claude-opus-5-5`, effort medium, no RAG context): Clínica Médica (cetoacidose diabética), Pediatria (bronquiolite, patient + mother as companion), Ginecologia e Obstetrícia (pré-eclâmpsia grave). RED — 4/5 (no fixtures; the coverage test failed). First run: 2/3 parsed; the pré-eclâmpsia case had a Cyrillic `е` inside an id (`iеca-sublingual`). Fixed the prompts (ASCII-only ids: generator rule 9, reviewer rule A4) and regenerated all three; GREEN — 8/8 (all three samples parse with zero errors, one has a companion). Samples saved unedited. Commit a541447.
- Full local CI: LOCAL CI PASSED (backend 1956 tests, web 337 + 4 tests, dialyzer 0 errors). PR #358.

## Next step

Pending after merge: HITL — the user applies the prompts in n8n and confirms on #335.
