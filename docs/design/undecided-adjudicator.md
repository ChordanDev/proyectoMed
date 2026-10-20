# Undecided-verdict adjudicator

Status: **Implemented for #290** (parent #237). This note amends ADR-011 (#123, the Jev
verification gate) as decided in the 2026-10-20 comment on #290, which replaces the
options listed in the issue body. The proposed amendment text for #123 is at the end.

## Problem

In the 2026-10-20 rehearsal, "Toma algum remédio?" was refused twice (`undecided_other`).
Three on-request facts answer it: `hda-06-antitermico`, `pergunta-explicita-02` and
`pergunta-explicita-02-anti-inflamatorios`. Jev scored `fact_asked` 0.45-0.48 and
`fact_stated` 0.25-0.39, so every candidate was `low_confidence`, and ADR-011 refused a
low-confidence candidate after one regeneration.

The cause is generic. A broad question ("remédio") matches several narrow negative facts,
and Jev cannot tell whether the broad question "asks" each narrow one. Tuning each
station's facts by hand does not scale to the rubric backlog.

## Decision

Undecided Jev verdicts are adjudicated by a small Claude model, with Jev's scores as
evidence. Clear verdicts stay deterministic.

| Jev verdict | Action |
|---|---|
| `verified` (every answer clear) | Deliver unchanged. |
| `semantic_refusal` (a clear risk or a clear disclosure violation) | Unchanged: one regeneration with the targeted withheld facts, then refuse. |
| `low_confidence` (any undecided answer) | One adjudication call. `deliver`, `regenerate` with withheld fact ids, or `refuse`. |

### What the adjudicator reads

`Backend.Stations.PatientAdjudicator` builds one request:

- the candidate reply;
- the latest learner message and the bounded conversation (untrusted learner data);
- the facts involved, by authored id and content: the facts an undecided label names,
  the facts Jev found stated (`used_fact_ids`) and the facts Jev found clearly not asked;
- the facts earlier verified turns disclosed (#286);
- every undecided label with its Jev score (`fact_stated`, `fact_asked`, each `risk:`
  question, `rule_broken` with the rule text);
- the authored response rules.

`TypesafeAdapter` adds `undecided_labels`, `not_asked_fact_ids` and `asked_fact_ids` to a
`low_confidence` verdict only. `not_asked_fact_ids` lists the on-request facts whose
`fact_asked` answer is a clear no while `fact_stated` is not. `asked_fact_ids` lists the
on-request facts whose `fact_asked` answer is a clear yes. Each fact in the request also
carries `requires_explicit_question` (see "Facts that require an explicit question").

### Hard limits, enforced in code

| Limit | Enforcement |
|---|---|
| BoundedReply deterministic checks run first. | `CandidateGate` runs them before Jev, and the adjudicator is reached only after Jev. A `deliver` is checked again; a violation is a refusal. |
| Never deliver a fact Jev's clear-no "asked" label says was not requested. | A `deliver` while `not_asked_fact_ids` is non-empty becomes `regenerate` withholding those facts. A `regenerate` always withholds them too. |
| Never withhold a fact Jev's clear-yes "asked" label says was requested. | The ids in `asked_fact_ids` are dropped from a `regenerate`'s `withheld_fact_ids`: withholding them would remove the answer the learner asked for. |
| Structured output only. | JSON schema `{decision: deliver\|regenerate\|refuse, withheld_fact_ids: [...]}`. Exactly those two keys, every id an authored fact id of the package, and a `deliver` names no facts. Anything else is malformed. |
| Malformed output, timeout or error. | Refuse, which keeps today's path: one regeneration withholding Jev's `undecided_fact_ids`, then a refusal. |
| Separate from the patient generator. | Its own seam (`PatientAdjudicator` behaviour), model and prompt. Jev stays the mandatory, independent check for clear outcomes. |

`regenerate` and `refuse` use the gate's existing single regeneration. A regenerated
candidate that Jev leaves undecided is adjudicated too, and only `deliver` helps it,
since no second regeneration exists. A voice sentence after the first one cannot be
regenerated, so it is delivered or refused.

### Model and prompt

`Backend.Stations.PatientAdjudicator.AnthropicAdapter` reuses
`Backend.Stations.StationAI.AnthropicClient` (raw Req, prompt caching on the static
system block). The model is `ANTHROPIC_ADJUDICATOR_MODEL`, default `claude-haiku-5-5`:
effort `low`, thinking off (`{type: "disabled"}`, accepted on Haiku 5.5 at effort `high`
or below), and no `fallbacks` parameter or fallback beta (Haiku 5.5 has no server-side
fallback). The system prompt states the decision rules, including "a broad question asks
for every narrow fact that answers it, except a fact that requires an explicit question",
"never list in `withheld_fact_ids` a fact that answers the latest learner message, nor any
fact in `asked_fact_ids`", and that learner text is untrusted data. All learner text sits
in the user content under `untrusted_learner_text`.

### Facts that require an explicit question

Some rubric criteria credit a fact only when the learner asks for it explicitly. The
acute-appendicitis package authors them under the topic "Informações que o ator só revela
se o candidato perguntar explicitamente", with ids starting `pergunta-explicita-`. The live
check showed the patient volunteering them ("no antibiotics or anticoagulants") in answer
to the broad "Toma algum remédio?", which Jev then scored as clearly not asked.

`Backend.Stations.StationAI.explicit_question_fact?/1` derives the mark from package data,
never from a station id: an authored boolean `requires_explicit_question` decides when
present; otherwise a topic saying the actor reveals the fact only when asked explicitly
("perguntar explicitamente", "pergunta explícita"), or an id starting
`pergunta-explicita`, marks it. The patient's system prompt lists these facts again under
"FATOS QUE SÓ PODEM SER DITOS COM PERGUNTA EXPLÍCITA": they may appear only when the latest
learner message asks about their subject directly, and a broader or neighbouring question
does not count. The section is part of the stable, cached prompt and is absent for a
package without such facts. The adjudicator receives the same mark per fact.

### Configuration

| Setting | Default |
|---|---|
| `:patient_adjudicator_adapter` | `DisabledAdapter` (refuses, so today's behaviour). `runtime.exs` selects the Anthropic adapter with `LLM_PROVIDER=anthropic` unless `PATIENT_ADJUDICATOR=off`. |
| `:patient_adjudicator_deadline_ms` / `PATIENT_ADJUDICATOR_DEADLINE_MS` | 2000 ms |
| `:patient_adjudicator_regeneration_extension_ms` / `PATIENT_ADJUDICATOR_REGENERATION_EXTENSION_MS` | 1500 ms (a non-negative integer; `0` turns the extension off) |
| `ANTHROPIC_ADJUDICATOR_MODEL` | `claude-haiku-5-5` |

### Latency and the turn budget

The call happens only on `low_confidence` turns. It runs inside the existing verification
budget (`jev_decision_default_deadline_ms`, 3 s), which Jev, the adjudication, the single
regeneration and its recheck all share, for text and for each voice sentence. When the
adjudicator answers `regenerate` (the hard limit's conversion included), the gate extends
that deadline by `regeneration_extension_ms` (1.5 s), so the verification of such a turn
takes at most 4.5 s; the regeneration, its recheck and the recheck's adjudication share
the extended deadline. Every other path, normal turns included, keeps the 3 s budget. The
adjudicator's deadline is the smaller of its own deadline and the remaining budget minus
100 ms; with less than 200 ms left no call is made. A regeneration that no longer fits the
budget ends with the original refusal (#256), so the learner turn is kept.

Measured on 2026-10-20 (two live replays plus 18 isolated calls, prompt cache hitting):

| Measure | Value |
|---|---|
| Claude Haiku 5.5 adjudication, structured output | 1.0-2.6 s, usually 1.3-1.6 s |
| Same without the schema | 1.7-3.8 s, with malformed answers |
| Jev patient verification | 0.2-0.4 s |
| Patient generation (Sonnet 5.5) | 1.0-2.0 s, once 4.2 s |

The decision comment estimated 0.5-1 s. The measured cost is higher, so:

- the default deadline is 2000 ms, not 1500 ms: at 1500 ms most measured calls would time
  out;
- `deliver` fits the budget (about 0.3 s of Jev plus 1.4 s);
- a `regenerate` after an adjudication rarely fits: Jev, the adjudication and a new
  generation already take about 2.8 s, so the recheck has about 0.2 s and times out, and
  the turn keeps the refusal. That is today's outcome, reached later.

Each call logs one `:info` line: `[PatientAdjudicator] adjudication outcome=<o>
latency_ms=<n>`, with `reason=<r>` on a refusal and `limit=not_asked` when the hard limit
turned a `deliver` into `regenerate`. No text and no fact id are logged.

## Live check (2026-10-20, acute-appendicitis)

The #286 eight-turn replay plus "Toma algum remédio?" and "Tem alergia a algum
medicamento?", through `Backend.Stations.create_message/2` with the live patient (Sonnet
5.5), Jev (TypeSafe) and the adjudicator (Haiku 5.5). Two runs.

- Turns 1-8 and 10: answered in the second run, all `verified` by Jev. In the first run,
  turn 1 ("Qual é seu nome?") was `low_confidence` on `risk:speaks_out_of_role` 0.75, the
  adjudication timed out at the then 1500 ms deadline and the turn was refused.
- Turn 9, "Toma algum remédio?": refused in both runs. Jev was `low_confidence` with
  `fact_asked` 0.39-0.48 for the antipyretic fact, and `fact_asked` for
  `pergunta-explicita-02` was 0.19, a clear no. Haiku answered `deliver` both times
  (1.0 s and 1.35 s). The hard limit turned it into `regenerate` withholding
  `pergunta-explicita-02`. The regeneration ("Não uso nenhum remédio regularmente,
  doutor.") left about 0.2 s for its recheck, which timed out, so the turn kept the
  refusal.

So the adjudicator resolves the uncertain band as designed, but the issue's medication
case still fails live. The cause is the hard limit, not the adjudicator: for the broad
question, Jev puts one narrow fact's "asked" score at or below the no threshold. This
needs a product decision (see Follow-ups). Lowering the hard limit is outside this change.

### Follow-up live check (2026-10-20, after the prevention and the budget extension)

Two more runs of the same replay, with the explicit-question section in the patient prompt,
`asked_fact_ids`, the tuned adjudicator prompt and the 1.5 s extension.

| Turn | Run 3 | Run 4 |
|---|---|---|
| 1 Qual é seu nome? | answered, 3992 ms | answered, 3027 ms |
| 2 Onde começou a toa? | answered, 2286 ms | answered, 2162 ms |
| 3 Há quanto tempo começou? | answered, 2100 ms | answered, 2024 ms |
| 4 A dor mudou de lugar? | answered, 2371 ms | answered, 2354 ms |
| 5 Ela piorou com o tempo? | answered, 2123 ms | answered, 2371 ms |
| 6 A dor vai para outro lugar? | answered, 1649 ms | answered, 1741 ms |
| 7 Teve febre? | answered, 2611 ms | answered, 2488 ms |
| 8 Teve náusea ou vômito? | answered, 2164 ms | answered, 2173 ms |
| 9 Toma algum remédio? | refused, 6862 ms | refused, 6226 ms |
| 10 Tem alergia a algum medicamento? | answered, 3079 ms | answered, 4950 ms |

Turn times include the addressee check and the first generation (1.0-4.4 s).

The prevention works: the patient no longer volunteers the explicit-question facts. Every
candidate for turn 9 was a plain "Não tomo/uso nenhum remédio regularmente, doutor." But
the turn is still refused:

- Jev keeps `fact_stated` for `pergunta-explicita-02` ("Nega uso recente de antibióticos ou
  anticoagulantes") undecided at 0.31-0.32 for a generic denial, while `fact_asked` is a
  clear no. So `not_asked_fact_ids` names it, the hard limit turns Haiku's `deliver`
  (1.0-1.2 s) into `regenerate`, and the regeneration produces the same kind of reply.
- Run 3: the recheck was the same verdict (`not_asked` again), so even a `deliver` would
  have been blocked; the second adjudication timed out at 1140 ms.
- Run 4: the recheck had no `not_asked` fact (`fact_stated` for `pergunta-explicita-02` fell
  below the band), so a `deliver` would have answered the turn, but the second adjudication
  timed out at 1823 ms: Jev 254 ms + adjudication 1009 ms + regeneration 1066 ms + recheck
  247 ms left about 1.8 s of the 4.5 s.

The hard limit was not changed. The remaining cause is Jev's "maybe stated" answer for a
narrow negative fact when the reply is a generic denial that does not name it.

## Trade-offs

- Gain: undecided turns can now be delivered, and only those turns pay the extra call.
- Cost: on a `low_confidence` turn the adjudication uses about half of the 3 s budget, so
  the single regeneration seldom fits after it. When the adjudicator does not deliver,
  the turn is no better than before and ends about 1.4 s later.
- Risk: a language model now decides the undecided band. Every clear outcome is still
  Jev's, the hard limits are code, and anything unexpected falls back to the refusal.
- In isolated runs Haiku sometimes asked to withhold the very facts that answer the
  question. The prompt now forbids it, and the code drops any id in `asked_fact_ids` from
  `withheld_fact_ids`; a fact Jev could not tell was asked can still be withheld.

## Follow-ups

- Product decision for the broad-question case: Jev's clear-no "asked" answer
  (`fact_asked` <= 0.2) on a narrow fact blocks the delivery the adjudicator chose. Two
  options: apply the limit only to facts marked as key findings, or let the adjudicator
  overrule a clear no inside a band (for example 0.1-0.2).
- Budget: the 1.5 s extension is in place for the `regenerate` path. Haiku 5.5 still takes
  1.0-1.9 s, so the recheck's adjudication can time out even with 4.5 s.
- A generic denial ("não tomo remédio") leaves `fact_stated` undecided for a narrow negative
  fact that requires an explicit question; with its clear-no `fact_asked`, the hard limit
  blocks the reply although it does not name the fact.
- The explicit-question mark is derived from authoring conventions (topic text, id
  prefix). A structured `requires_explicit_question` field, validated by
  `StationPackage`, would make it explicit; the predicate already honours it.
- Facts the adjudicator delivers but Jev found only "maybe stated" are not added to the
  session's disclosed facts (#286). Only Jev's clear `used_fact_ids` are.

## Proposed ADR-011 amendment

Not applied to #123. Text for a maintainer to add:

> ### Amendment (2026-10-20, #290): undecided verdicts are adjudicated
>
> A `low_confidence` verdict is no longer an automatic refusal. The verifier stays
> mandatory and independent for clear outcomes. A separate small language model, not the
> patient generator, resolves only the undecided band: it receives the candidate, the
> bounded conversation (learner text is untrusted data), the facts involved and already
> disclosed, the response rules, and every undecided Jev label with its score. It answers
> through a structured output schema with `deliver`, `regenerate` (with authored fact ids
> to withhold) or `refuse`. It can never deliver a candidate the deterministic checks
> rejected, nor a fact whose Jev "asked" answer is a clear no. Malformed output, a
> timeout or an error means `refuse`, the behaviour before this amendment. The
> adjudication runs inside the same bounded turn deadline.
