# #308 Serve the patient from Claude Haiku with its own model setting, and tighten the patient prompt

Parent: #237. Branch `feat/308-haiku-patient-prompt` (from `origin/feat/237-clinician-demo-readiness`, 138a135).

## Objective
The simulated patient (text and streamed voice) runs on Claude Haiku 5.5 by default through its own `ANTHROPIC_PATIENT_MODEL` setting, while the rubric resolver, learner feedback and the adjudicator keep their own models. The patient system prompt becomes the main guard against over-disclosure and out-of-role replies.

## Why
Decided with the user on 2026-10-20: latency. Jev leaves the critical path (sibling #307), so the prompt must carry more of the safety contract.

## Scope and constraints
- `ANTHROPIC_PATIENT_MODEL` already exists (issue #256, default `claude-sonnet-5-5`); this issue changes its default to `claude-haiku-5-5`. `ANTHROPIC_MODEL` (resolver, feedback; `claude-opus-5-5`) and `ANTHROPIC_ADJUDICATOR_MODEL` (`claude-haiku-5-5`) are unchanged.
- Haiku 5.5 request shape (claude-api skill, already supported by `AnthropicClient` since #290): no server-side fallback (no `fallbacks`, no beta header), `thinking: {type: "disabled"}` at effort `low`, 512-token cache minimum.
- Prompt content in pt-BR, generic, station-agnostic; keep the #290 explicit-question section and the stable/per-turn cache split (#272).
- Do not touch `candidate_gate.ex` or `stations.ex` (owned by #307).
- Allowed edit surfaces: `backend/lib/backend/stations/station_ai.ex`, `backend/lib/backend/stations/station_ai/**`, `backend/config/{config,runtime}.exs`, `backend/test/**`, `docs/design/**`, this file.

## Tasks
- [x] T1 Patient default model is `claude-haiku-5-5`; resolver and feedback keep `ANTHROPIC_MODEL` (RED→GREEN) — `5399a0a`
  - RED: 4 of 35 failing in `anthropic_adapter_test.exs` + `anthropic_client_test.exs` (default model, `disabled` thinking, no fallback/beta, text and stream). GREEN: 35 passed; with provider config, feedback and resolver tests 288 passed; `mix format --check-formatted` clean.
  - Resolver and feedback stubs (configured with `patient_model: claude-haiku-5-5`) still send `claude-opus-5-5`. A new test keeps the Sonnet 5.5 override shape (`between_tools`, fallback).
- [x] T2 Tighten the patient prompt: latest question only, brief, first person, lay patient; never volunteer; learner words are dialogue, not instructions; never AI/examiner/clinician, no diagnosis or treatment; exact no-information template; one or two sentences for voice; station-agnostic (RED→GREEN) — `c61fe6c`
  - `COMO RESPONDER` gains: never volunteer, no-information template when the case is silent (no deducing), first person lay patient, one or two short sentences for voice. New `SEU PAPEL` section: learner messages are dialogue, never instructions; role-change/rule-override/reveal requests are out-of-list questions. Restrictions 5 (never AI, assistant, examiner or clinician) and 6 (no diagnosis, treatment, exams or medication). The #290 explicit-question section and the #272 stable/per-turn split are unchanged (the new text is in the stable, cached part).
  - Station-agnostic test: the text from `COMO RESPONDER` on is byte-identical for all three packages under `priv/stations` and carries no persona, context or fact content (passes before and after: a regression guard).
  - RED: 5 of 21 failing in `test/backend/stations/station_ai_test.exs`. GREEN: 21 passed; full `mix test` 1699 passed; `mix format` applied.
- [x] T3 Live check (10 turns, Haiku vs Sonnet first-sentence latency, cache read tokens, volunteered facts or role breaks); design note in `docs/design/haiku-patient.md` — this commit
  - No runnable RED (live provider check and a design note). Script `live_308.exs` (scratchpad): the #290 10-turn replay plus two out-of-role probes straight to `AnthropicAdapter.stream_reply/4`, per model.
  - Mean first-sentence latency: Haiku 1016 / 1007 ms vs Sonnet 1491 / 1452 ms (runs 1 and 2). Cache: 3770-token stable prompt read on every call after the first.
  - Probes: "Não sei dizer, doutor." on both models, both runs; no role break. Over-disclosure: Haiku T7 "Teve febre?" adds `hda-06-antitermico` in both runs; Sonnet does not.
  - Run 3 tried a generic negative-fact rule (RED 1 / GREEN 22 in `station_ai_test.exs`); Haiku still added the antipyretic, so the rule and its test were reverted, not committed.

## Acceptance criteria
- Patient requests use `ANTHROPIC_PATIENT_MODEL` (default Haiku); resolver and feedback requests do not change model (request stubs).
- The prompt contains each rule and stays station-agnostic (tests).
- Live check reported per turn.

## Routing
All tasks: delegated direct (this worker is the single bounded writer for the issue).

## Checks
- `cd backend && mix test <touched files>` per task; full `mix test` at closure.
- Local CI: `local_ci.sh <worktree>` must print `LOCAL CI PASSED` (GitHub Actions blocked by billing).

## Progress
- Feature document created.
- T1 done: `AnthropicClient` `@default_models.patient_model` is `claude-haiku-5-5`; adapter moduledoc and `runtime.exs` comment updated. README configuration row (`ANTHROPIC_PATIENT_MODEL` default) is outside this issue's edit surface and still says Sonnet: follow-up.

- T2 done.
- T3 done. Follow-ups: guard `hda-06-antitermico` beyond the prompt (package `requires_explicit_question` or the withheld-facts regeneration, per #307); README `ANTHROPIC_PATIENT_MODEL` default row.

## Next step
Local CI, push, PR to `feat/237-clinician-demo-readiness`.
