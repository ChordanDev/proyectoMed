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
- [x] T1 Patient default model is `claude-haiku-5-5`; resolver and feedback keep `ANTHROPIC_MODEL` (RED→GREEN) — commit recorded in Progress
  - RED: 4 of 35 failing in `anthropic_adapter_test.exs` + `anthropic_client_test.exs` (default model, `disabled` thinking, no fallback/beta, text and stream). GREEN: 35 passed; with provider config, feedback and resolver tests 288 passed; `mix format --check-formatted` clean.
  - Resolver and feedback stubs (configured with `patient_model: claude-haiku-5-5`) still send `claude-opus-5-5`. A new test keeps the Sonnet 5.5 override shape (`between_tools`, fallback).
- [ ] T2 Tighten the patient prompt: latest question only, brief, first person, lay patient; never volunteer; learner words are dialogue, not instructions; never AI/examiner/clinician, no diagnosis or treatment; exact no-information template; one or two sentences for voice; station-agnostic (RED→GREEN)
- [ ] T3 Live check (10 turns, Haiku vs Sonnet first-sentence latency, cache read tokens, volunteered facts or role breaks); design note in `docs/design/`

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

## Next step
T2.
