# 343 Resolver model comparison

Objective: measure how the rubric resolver grades on Claude Opus, Sonnet and Haiku 5.5 over the same transcripts, and recommend a model by agreement and cost (issue #343, parent #326).
Branch: `docs/343-resolver-model-comparison` from `feat/326-production-launch`. Delivery: single PR to `feat/326-production-launch`. Test runner: `cd backend && mix test`.

## Specs

- S1: "A comparison table (agreement per criterion and cost per session) in the PR"
- S2: "A recommendation with the trade-off"
- S3: "The default changes only after the user agrees" — this PR does not change `ANTHROPIC_MODEL` or any default.
- S4 (task brief): run the rubric assessment (Jev rubric batch + resolver) over the same stored transcripts — the #228/#243 regression transcripts, the #290/#307 live 10-turn transcripts if available in fixtures, plus at least 3 synthetic transcripts of varied quality (strong, partial, weak learner) for acute-appendicitis and one companion case — with the resolver on `claude-opus-5-5`, `claude-sonnet-5-5` and `claude-haiku-5-5`, each 3 times.
- S5 (task brief): report in `docs/research/resolver-model-comparison.md`: per-criterion agreement with Opus (status and points), run-to-run variance per model, latency, resolver tokens and estimated cost per session from the #342 price table, and a recommendation.
- S6 (task brief): save the synthetic transcripts as fixtures if a test uses them; scripts live in the scratchpad, not the repo; keep spend bounded (estimate first; stop above USD 15).

## Tasks

| ID | Specs | Route | Status | Evidence |
|---|---|---|---|---|
| T1 | S4, S6 | inline | done | 543f766; RED 18/18 failing (fixtures missing), GREEN 18/18 |
| T2 | S1, S2, S3, S5 | inline | done | research doc commit (see git log); docs-only, no runnable RED: structural readback and local CI |

## Log

- L1 (2026-10-25, workflow brief): implement issue #343 "Choose the grading resolver model by measured agreement and cost": run the resolver on Opus, Sonnet and Haiku over the same stored transcripts, compare criterion statuses, points and cost per session, recommend the cheapest model whose grades match; do not change the default model without the user's decision.
- L2: the #290/#307 live 10-turn transcripts are not stored in fixtures (sessions are content-free by design, ADR-001/ADR-009); only the #228 and #243 regression transcripts are. The companion case is the n8n bronquiolite sample (`backend/test/backend/stations/fixtures/case_format/n8n-sample-bronquiolite-companion.md`).
- L3: method: Jev is called live once per transcript and its answers are replayed for every resolver run, so the resolver models see identical undecided actions; resolver latency is measured per call with the production 30 s deadline raised for the experiment so slow answers are still collected (calls above 30 s are counted).
- L4: T1 done (543f766): six synthetic transcripts and `resolver_model_comparison_fixtures_test.exs`; RED 18 failures (files missing), GREEN 18 passed.
- L5: T2 runs (scratchpad scripts, keys sourced only in the run shell): 144 assessments (8 transcripts x 3 models x 3 runs x 2 modes: live Jev replayed, and every action undecided). Spend USD 4.27. Criterion agreement with Opus: Sonnet 99% / 87%, Haiku 98% / 98%; resolver cost per session with live Jev: Opus 0.0239, Sonnet 0.0093, Haiku 0.0010 USD. Recommendation: Haiku; default unchanged pending the user's decision (S3). Open point: `ANTHROPIC_MODEL` also drives learner feedback.
- Next step: user decides whether to move the resolver to Haiku (and how, given the shared `ANTHROPIC_MODEL`).
