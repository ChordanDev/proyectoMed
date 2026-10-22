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

- [ ] T1 — Generator prompt `docs/n8n/generator-prompt.md`: current clinical rules + every tag of the spec + companion actors + numbering left to the DB + originality rule. Test: the prompt names every tag of the spec and its embedded example parses with zero errors.
- [ ] T2 — Reviewer prompt `docs/n8n/reviewer-prompt.md` (arithmetic, tags, links, actor/question coverage; `APROVADO` or a list of fixes) and Neon insert `docs/n8n/neon-insert.md` + `docs/n8n/README.md` (flow, HITL checklist). Test: the insert SQL in `neon-insert.md` runs against the `cases` table and returns a sequential number with status `pending`.
- [ ] T3 — Three sample cases generated with the generator prompt (one with a companion) saved as fixtures; test that each parses with zero errors via `Backend.Stations.parse_case/1`.

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

(none yet)

## Next step

T1.
