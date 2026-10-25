# Rubric resolver model comparison

Issue #343 (parent #326). Measured on 2026-10-25. This note compares the rubric
resolver (`Backend.Stations.RubricAssessment.Resolver.AnthropicAdapter`, issue
#301) on `claude-opus-5-5` (today's default, `ANTHROPIC_MODEL`),
`claude-sonnet-5-5` and `claude-haiku-5-5`, over the same transcripts, and
recommends a model. The owner chose Haiku on 2026-10-25 (see **Decision**).

## Summary

| | Opus 5.5 (default) | Sonnet 5.5 | Haiku 5.5 |
|---|---|---|---|
| Criterion grade (status and points) equal to Opus, live Jev | 100% (reference) | 99% | 98% |
| Criterion grade equal to Opus, resolver decides every action | 100% (reference) | 87% | 98% |
| Unstable criteria between its own 3 runs (live Jev / every action) | 0/82 / 1/82 | 0/82 / 5/82 | 2/82 / 3/82 |
| Resolver cost per session, live Jev (mean / max, USD) | 0.0239 / 0.0524 | 0.0093 / 0.0188 | 0.0010 / 0.0024 |
| Resolver cost per session, every action (mean / max, USD) | 0.0945 / 0.2275 | 0.0402 / 0.0557 | 0.0037 / 0.0048 |
| Resolver call latency p50 / p95, every action (ms) | 3,269 / 6,729 | 2,221 / 4,902 | 3,065 / 4,711 |
| Calls above the production 30 s deadline | 1 of 312 (failed, malformed) | 0 of 312 | 0 of 312 |

**Recommendation: `claude-haiku-5-5` for the resolver.** Its criterion grades
match Opus's in 98% of runs in both modes, it is about 23 times cheaper than
Opus per session (USD 0.0010 against 0.0239 with live Jev), its latency is the
same as Opus's, and every disagreement it showed fails closed: the criterion
becomes `uncertain` (no points, reported to the learner as such), never a
different level or extra credit. Sonnet is not a useful middle step: it costs
nine times Haiku, abstains (`uncertain`) far more often than either when it
must decide every action, and on one transcript it granted credit Opus withheld.

The trade-off: on the few actions Jev leaves undecided, Haiku agrees with Opus's
modal classification less often (69% of 126 actions, against 94% for Opus's
own runs) and varies more between its own runs (14 of 42 actions against 7).
Those action-level differences almost never move a criterion's grade, because
the authored rules and the `not_performed`-only zero guard (issue #228) absorb
them; where they do, Haiku leaves the criterion `uncertain` rather than graded
differently. In money, the choice is small either way: the resolver on Opus is
about USD 0.024 per session, eight times the USD 0.003 that a whole text session
cost with every other Claude seam on Haiku (`docs/operations/session-usage-cost.md`).

## What was run

- **Pipeline:** `RubricAssessment.assess/3` exactly as a finished session runs
  it: evidence pool, one Jev rubric batch, the resolver on the actions Jev left
  `uncertain`, then the authored rules, evidence validation and task order. The
  resolver adapter is the production one; the model is passed as its `:model`
  option. Only the resolver deadline was raised (180 s instead of 30 s) so that
  slow answers are still measured; calls above 30 s are counted above.
- **Two modes:**
  - *live Jev*: Jev (TypeSafe System One) was called live once per transcript;
    its answer was stored and replayed for every resolver run, so the three
    models decide the same undecided actions. This is what production does.
  - *every action*: a Jev double answers `uncertain` for every action, so the
    resolver decides all of them. This is a stress test of the resolver alone:
    it measures agreement on 990 action decisions instead of 126.
- **Runs:** each model 3 times per transcript and mode: 8 transcripts x 3
  models x 3 runs x 2 modes = 144 assessments.
- **Reference:** Opus's modal grade per criterion (and modal classification per
  action) over its 3 runs. Opus is the current default, not ground truth.
- **Usage and cost:** Claude tokens from each Messages response, attributed with
  `Backend.Stations.Usage.track/2` and priced with
  `Backend.Stations.Usage.Prices.estimate/2` (the #342 price table: Opus
  4/20/0.2/5, Sonnet 2/10/0.1/2.5, Haiku 0.1/0.5/0.01/0.125 USD per MTok input /
  output / cache read / cache write). Costs are resolver-only. Runs follow each
  other within minutes, so the cached system prompt is mostly read, not written,
  as in a busy production hour.
- **Total spend:** USD 4.27 (USD 0.82 live Jev, USD 3.32 every action, USD 0.13
  pilot), below the USD 15 budget.

### Transcripts

| Name | Station | Source |
|---|---|---|
| issue-228 | acute-appendicitis | `backend/test/backend/stations/rubric_assessment/fixtures/issue_228_session.json` |
| issue-243 | acute-appendicitis | `backend/test/backend/stations/rubric_assessment/fixtures/issue_243_session.json` (learner turns of the 2026-10-19 live attempt) |
| aa-strong, aa-partial, aa-weak | acute-appendicitis | `backend/test/backend/stations/fixtures/resolver_model_comparison/acute-appendicitis-*.json` (synthetic) |
| br-strong, br-partial, br-weak | bronquiolite-viral-lactente (companion case) | `backend/test/backend/stations/fixtures/resolver_model_comparison/bronquiolite-*.json` (synthetic, over `n8n-sample-bronquiolite-companion.md`) |

The #290/#307 live 10-turn transcripts are not stored anywhere in the
repository (sessions are content-free, ADR-001/ADR-009), so they could not be
replayed. The synthetic transcripts are guarded by
`backend/test/backend/stations/resolver_model_comparison_fixtures_test.exs`.

How much Jev left to the resolver in the live mode (actions per transcript,
`performed` / `not_performed` / `uncertain`): issue-228 32/4/7, issue-243
37/2/4, aa-strong 39/1/3, aa-partial 8/26/12, aa-weak 2/38/7, br-strong 26/1/0,
br-partial 4/17/7, br-weak 1/27/2.

## Results with live Jev

Per-criterion agreement with the Opus reference: runs whose status, and whose
status and points, equal Opus's modal grade (5 appendicitis transcripts x 3
runs = 15; 3 bronquiolite transcripts x 3 runs = 9).

| Station | Criterion | Opus status | Opus points | Sonnet status | Sonnet points | Haiku status | Haiku points |
|---|---|---|---|---|---|---|---|
| acute-appendicitis | item-01 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 |
| acute-appendicitis | item-02 | 15/15 | 15/15 | 15/15 | 15/15 | 14/15 | 14/15 |
| acute-appendicitis | item-03 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 |
| acute-appendicitis | item-04 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 |
| acute-appendicitis | item-05 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 |
| acute-appendicitis | item-06 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 |
| acute-appendicitis | item-07 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 |
| acute-appendicitis | item-08 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 |
| acute-appendicitis | item-09 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 |
| acute-appendicitis | item-10 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 |
| acute-appendicitis | item-11 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 |
| bronquiolite | item-01 | 9/9 | 9/9 | 9/9 | 9/9 | 9/9 | 9/9 |
| bronquiolite | item-02 | 9/9 | 9/9 | 9/9 | 9/9 | 8/9 | 8/9 |
| bronquiolite | item-03 | 9/9 | 9/9 | 9/9 | 9/9 | 9/9 | 9/9 |
| bronquiolite | item-04 | 9/9 | 9/9 | 9/9 | 9/9 | 9/9 | 9/9 |
| bronquiolite | item-05 | 9/9 | 9/9 | 9/9 | 9/9 | 9/9 | 9/9 |
| bronquiolite | item-06 | 9/9 | 9/9 | 6/9 | 6/9 | 6/9 | 6/9 |
| bronquiolite | item-07 | 9/9 | 9/9 | 9/9 | 9/9 | 9/9 | 9/9 |
| bronquiolite | item-08 | 9/9 | 9/9 | 9/9 | 9/9 | 9/9 | 9/9 |
| bronquiolite | item-09 | 9/9 | 9/9 | 9/9 | 9/9 | 9/9 | 9/9 |
| **all** | | **100%** | **100%** | **99%** | **99%** | **98%** | **98%** |

Every disagreement (Opus modal grade -> the model's 3 runs):

- Sonnet: br-partial item-06: assessed 0.75 -> uncertain, uncertain, uncertain.
- Haiku: issue-228 item-02: assessed 0.4 -> 0.4, uncertain, 0.4; br-partial
  item-02: assessed 0.75 -> uncertain, 0.75, 0.75; br-partial item-06: assessed
  0.75 -> uncertain, uncertain, uncertain.

Session totals (points out of 10, mean of 3 runs, min-max, mean uncertain criteria):

| Transcript | Opus | Sonnet | Haiku |
|---|---|---|---|
| issue-228 | 9.30 (9.30-9.30), 0.0 | 9.30 (9.30-9.30), 0.0 | 9.17 (8.90-9.30), 0.3 |
| issue-243 | 9.60 (9.60-9.60), 0.0 | 9.60 (9.60-9.60), 0.0 | 9.60 (9.60-9.60), 0.0 |
| aa-strong | 10.00 (10.00-10.00), 0.0 | 10.00 (10.00-10.00), 0.0 | 10.00 (10.00-10.00), 0.0 |
| aa-partial | 1.40 (1.40-1.40), 6.0 | 1.40 (1.40-1.40), 6.0 | 1.40 (1.40-1.40), 6.0 |
| aa-weak | 0.00 (0.00-0.00), 2.0 | 0.00 (0.00-0.00), 2.0 | 0.00 (0.00-0.00), 2.0 |
| br-strong | 10.00 (10.00-10.00), 0.0 | 10.00 (10.00-10.00), 0.0 | 10.00 (10.00-10.00), 0.0 |
| br-partial | 2.00 (2.00-2.00), 3.0 | 1.25 (1.25-1.25), 4.0 | 1.00 (0.50-1.25), 4.3 |
| br-weak | 0.00 (0.00-0.00), 0.0 | 0.00 (0.00-0.00), 0.0 | 0.00 (0.00-0.00), 0.0 |

Action level, on the 126 action decisions the resolver made (42 actions x 3 runs):

| Model | Equal to Opus's modal classification | Actions that differ between its own runs |
|---|---|---|
| Opus | 119/126 (94%) | 7/42 |
| Sonnet | 99/126 (79%) | 2/42 |
| Haiku | 87/126 (69%) | 14/42 |

Latency, tokens and cost per session:

| Model | Calls/session | Call p50 / p95 / max ms | Session p50 ms | Input | Output | Cache read | Cache write | USD mean | USD max |
|---|---|---|---|---|---|---|---|---|---|
| Opus | 3.2 | 2,969 / 6,055 / 7,539 | 4,041 | 3,123 | 546 | 2,249 | 0 | 0.02387 | 0.05237 |
| Sonnet | 3.2 | 1,767 / 4,937 / 5,363 | 2,379 | 3,123 | 263 | 2,162 | 86 | 0.00931 | 0.01875 |
| Haiku | 3.2 | 3,208 / 4,638 / 9,588 | 3,590 | 3,123 | 1,397 | 2,162 | 86 | 0.00104 | 0.00241 |

Session time is the resolver's wall time (Jev replayed); the first Opus run of
each transcript, which included the live Jev call, is left out.

## Results when the resolver decides every action

| Station | Criterion | Opus status | Opus points | Sonnet status | Sonnet points | Haiku status | Haiku points |
|---|---|---|---|---|---|---|---|
| acute-appendicitis | item-01 | 15/15 | 15/15 | 13/15 | 13/15 | 14/15 | 14/15 |
| acute-appendicitis | item-02 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 |
| acute-appendicitis | item-03 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 |
| acute-appendicitis | item-04 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 |
| acute-appendicitis | item-05 | 15/15 | 15/15 | 6/15 | 6/15 | 15/15 | 15/15 |
| acute-appendicitis | item-06 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 |
| acute-appendicitis | item-07 | 15/15 | 15/15 | 7/15 | 7/15 | 15/15 | 15/15 |
| acute-appendicitis | item-08 | 15/15 | 15/15 | 10/15 | 9/15 | 15/15 | 15/15 |
| acute-appendicitis | item-09 | 14/15 | 14/15 | 13/15 | 13/15 | 14/15 | 14/15 |
| acute-appendicitis | item-10 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 |
| acute-appendicitis | item-11 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 | 15/15 |
| bronquiolite | item-01 | 9/9 | 9/9 | 9/9 | 9/9 | 8/9 | 8/9 |
| bronquiolite | item-02 | 9/9 | 9/9 | 9/9 | 9/9 | 9/9 | 9/9 |
| bronquiolite | item-03 | 9/9 | 9/9 | 9/9 | 9/9 | 9/9 | 9/9 |
| bronquiolite | item-04 | 9/9 | 9/9 | 9/9 | 9/9 | 9/9 | 9/9 |
| bronquiolite | item-05 | 9/9 | 9/9 | 6/9 | 6/9 | 9/9 | 9/9 |
| bronquiolite | item-06 | 9/9 | 9/9 | 9/9 | 9/9 | 6/9 | 6/9 |
| bronquiolite | item-07 | 9/9 | 9/9 | 6/9 | 6/9 | 9/9 | 9/9 |
| bronquiolite | item-08 | 9/9 | 9/9 | 9/9 | 9/9 | 9/9 | 9/9 |
| bronquiolite | item-09 | 9/9 | 9/9 | 9/9 | 9/9 | 9/9 | 9/9 |
| **all** | | **100%** | **100%** | **87%** | **87%** | **98%** | **98%** |

Every disagreement (Opus modal grade -> the model's 3 runs):

- Sonnet (13): issue-228 item-05 (1.2 -> uncertain x3), item-07 (0.8 ->
  uncertain, uncertain, 0.8), item-08 (1.4 -> uncertain x3); issue-243 item-01
  (0.2 -> uncertain, 0.2, 0.2), item-05 (1.2 -> uncertain x3), item-07 (0.8 ->
  uncertain x3), item-08 (1.4 -> uncertain, uncertain, 0.7); aa-strong item-01
  (0.2 -> uncertain, 0.2, 0.2), item-05 (1.2 -> uncertain x3), item-07 (0.8 ->
  uncertain x3); aa-partial item-09 (uncertain -> 0.6, uncertain, 0.6);
  br-partial item-05 (uncertain -> 0.5 x3), item-07 (uncertain -> 1 x3). The
  uncertain ones are Sonnet answering `uncertain` for an action
  (`{:uncertain_sub_action, ...}`), mostly the McBurney verbalization (item-05
  criterio-2), the hypothesis (item-08 criterio-4) and the lab interpretation
  (item-07). The last three grant points Opus did not.
- Haiku (4): issue-243 item-09 (1.2 -> 1.2, uncertain, 1.2); aa-strong item-01
  (0.2 -> 0.2, uncertain, 0.2); br-strong item-01 (0.5 -> 0.5, uncertain, 0.5);
  br-partial item-06 (0.75 -> uncertain x3).
- Opus against its own mode (1): aa-strong item-09 (1.2 -> 1.2, uncertain, 1.2).

Session totals (points out of 10, mean of 3 runs, min-max, mean uncertain criteria):

| Transcript | Opus | Sonnet | Haiku |
|---|---|---|---|
| issue-228 | 9.30 (9.30-9.30), 0.0 | 6.17 (5.90-6.70), 2.7 | 9.30 (9.30-9.30), 0.0 |
| issue-243 | 9.60 (9.60-9.60), 0.0 | 6.37 (6.00-6.90), 3.0 | 9.20 (8.40-9.60), 0.3 |
| aa-strong | 9.60 (8.80-10.00), 0.3 | 7.93 (7.80-8.00), 2.3 | 9.93 (9.80-10.00), 0.3 |
| aa-partial | 0.80 (0.80-0.80), 8.0 | 1.20 (0.80-1.40), 7.3 | 0.80 (0.80-0.80), 8.0 |
| aa-weak | 0.00 (0.00-0.00), 10.0 | 0.00 (0.00-0.00), 10.0 | 0.00 (0.00-0.00), 10.0 |
| br-strong | 10.00 (10.00-10.00), 0.0 | 10.00 (10.00-10.00), 0.0 | 9.83 (9.50-10.00), 0.3 |
| br-partial | 2.00 (2.00-2.00), 6.0 | 3.50 (3.50-3.50), 4.0 | 1.25 (1.25-1.25), 7.0 |
| br-weak | 0.00 (0.00-0.00), 8.0 | 0.00 (0.00-0.00), 8.0 | 0.00 (0.00-0.00), 8.0 |

In this mode the weak and partial transcripts are mostly `uncertain`: the
resolver's `not_performed` answers cite nothing, so they never ground a zero on
their own (issue #228), whatever the model.

Action level, on 990 action decisions (330 actions x 3 runs):

| Model | Equal to Opus's modal classification | Actions that differ between its own runs |
|---|---|---|
| Opus | 969/990 (98%) | 20/330 |
| Sonnet | 873/990 (88%) | 19/330 |
| Haiku | 946/990 (96%) | 17/330 |

Latency, tokens and cost per session:

| Model | Calls/session | Call p50 / p95 / max ms | Session p50 ms | Input | Output | Cache read | Cache write | USD mean | USD max |
|---|---|---|---|---|---|---|---|---|---|
| Opus | 9.8 | 3,269 / 6,729 / 55,030 | 8,586 | 10,660 | 2,524 | 6,747 | 0 | 0.09447 | 0.22751 |
| Sonnet | 9.8 | 2,221 / 4,902 / 6,383 | 5,655 | 10,660 | 1,818 | 6,747 | 0 | 0.04017 | 0.05565 |
| Haiku | 9.8 | 3,065 / 4,711 / 22,415 | 6,902 | 10,660 | 5,047 | 6,747 | 0 | 0.00366 | 0.00480 |

The one Opus call above 30 s (aa-weak item-03, 55 s) ended `malformed_response`;
in production the 30 s deadline would have left that criterion `uncertain`.
Haiku writes the most output tokens (its adaptive thinking) and is still the
cheapest by an order of magnitude.

## Limits

- Eight transcripts on two stations, six of them synthetic and written for this
  comparison; the agreement figures are evidence for this rubric shape, not a
  general accuracy claim. Opus is the reference because it is the default, not
  because it is right.
- Jev was read once per transcript; its own run-to-run variance is not part of
  these numbers.
- Costs use list prices of the #342 table and a warm prompt cache; a cold first
  call adds the cache write of the system prompt (about 4,000 tokens: USD 0.02 on
  Opus, USD 0.0005 on Haiku).

## Decision

On 2026-10-25 the project owner switched the rubric resolver to
`claude-haiku-5-5` (comment on #343). The resolver now has its own Claude model
setting, `ANTHROPIC_RESOLVER_MODEL` (client key `:resolver_model`), defaulting
to `claude-haiku-5-5`. `ANTHROPIC_MODEL` (default `claude-opus-5-5`) now picks
only learner feedback, which this comparison did not measure, so it stays on
Opus. The patient (`ANTHROPIC_PATIENT_MODEL`) and the undecided-verdict
adjudicator (`ANTHROPIC_ADJUDICATOR_MODEL`) are unchanged. On the OpenAI
provider `RUBRIC_RESOLVER_MODEL` still applies.

The production request on Haiku is the shape measured here, because the
comparison ran the production adapter with only `:model` changed: effort
`medium`, model-default (adaptive) thinking, so no `thinking` field,
`max_tokens` 8,192, and no `fallbacks` (Haiku 5.5 has no server-side fallback).
The 30 s resolver deadline still fits: Haiku's slowest call was 22,415 ms and
none of its 312 calls exceeded 30 s.

Setting `ANTHROPIC_RESOLVER_MODEL=claude-opus-5-5` restores the previous
resolver model without touching learner feedback.
