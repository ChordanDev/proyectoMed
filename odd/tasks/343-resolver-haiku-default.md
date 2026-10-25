# 343 Resolver on Claude Haiku 5.5 by default

Objective: give the Claude rubric resolver its own model setting, defaulting to `claude-haiku-5-5`, per the owner's decision on #343.
Branch: `feat/343-resolver-haiku-default` (base `feat/326-production-launch`). Delivery: single PR (`Refs #343`). Runner: `mix test` (backend), local CI script.

## Specs

- S1: "a resolver-specific Anthropic model setting (ANTHROPIC_RESOLVER_MODEL, default claude-haiku-5-5, validated like the other model settings); the Anthropic resolver adapter uses it".
- S2: "learner feedback, the patient (ANTHROPIC_PATIENT_MODEL) and the adjudicator keep their current settings and defaults (tests pin that)".
- S3: "Check Haiku request shape for the resolver (thinking disabled/effort, max_tokens) matches what the comparison used, and that the resolver deadline still fits."
- S4: "Update README config table, the research doc's 'Decision' section and docs/operations/session-usage-cost.md if it lists models."
- S5: Sibling #340 may touch `config.exs`/`runtime.exs`: keep the config change minimal.

Why: owner decision on #343 (2026-10-25): "switch the rubric resolver to claude-haiku-5-5. Implementation: a resolver-specific Anthropic model setting (e.g. ANTHROPIC_RESOLVER_MODEL, default claude-haiku-5-5); learner feedback keeps its current model (not measured)."

## Tasks

- [x] T1 (S1, S2, S3, S5) `:resolver_model` client setting, resolver adapter uses it, `ANTHROPIC_RESOLVER_MODEL` in runtime.exs, tests pinning the other seams, README row. Route: inline (small, one understood change). Commit: 2f0aa77. RED 4/55 failed, GREEN 55/55.
- [x] T2 (S3, S4) Research doc Decision section, operations doc resolver model. Route: inline. Commit: 0c3e5eb (passive docs, structural readback).

## Log

- L1 (2026-10-25, user): "sí, pasamos a kaiku" (owner decision recorded on #343: resolver to `claude-haiku-5-5`).
- L2: S3 check. The comparison ran the production adapter with only `:model` changed (doc "What was run"): effort `medium`, model-default (adaptive) thinking, so no `thinking` field, `max_tokens` 8,192, and no `fallbacks` on Haiku (`@no_fallback_models`). Production on Haiku sends exactly that shape. Haiku's slowest call was 22,415 ms, under the 30 s resolver deadline; no Haiku call missed it (0 of 312).
- L3: "validated like the other model settings": the other `ANTHROPIC_*_MODEL` variables are written when set and otherwise fall back to the client default; the new variable joins the same list, so it behaves identically.
- L4: Local CI PASSED: credo no issues, web 337/337, ExUnit 2312 passed, end-to-end 4/4, dialyzer passed. GitHub Actions is blocked by billing.
- L5: Out of the edit surface, left stale: `backend/lib/backend/stations/station_ai/anthropic_adapter.ex` moduledoc ("The resolver and learner feedback keep `:model`") and `docs/design/haiku-patient.md` table row for `ANTHROPIC_MODEL`. Next step: owner review of the PR.
