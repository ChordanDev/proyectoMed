# Result disclaimer and coverage comprehension: human review record

**Status: not reviewed.** This is a template. Every field marked PENDING must be completed by the named human reviewer. No review is recorded here, and nothing below may be read as one.

## Why this review exists

Issue #130 requires a human to confirm that people understand the result disclaimer and the coverage summary, and that incomplete evidence never reads as failure or as readiness.

An earlier review exists for the result screens of issue #129 (see "Human review" in [`docs/educational-result-api.md`](../../educational-result-api.md)). Its limits are the reason for this record:

- it was done by the PR author, with a local preview fed by a fictional **partial** fixture;
- it did **not** render a **complete** result or a **no-eligible** result;
- it did not use a live assessment.

## What to review

The review covers every surface below, in every listed result state.

### Surfaces

| Surface | What the reviewer looks at |
|---|---|
| Notice before starting (voice and text) | The disclaimer, before any interaction. |
| Result screen | The disclaimer, the coverage summary, the totals, each criterion with its status. |
| Loading | What is shown while the result is computed. |
| Technical recovery | What is shown when the assessment fails technically. |

The disclaimer must appear exactly as authored:

> Estimativa educacional gerada por IA. Não é nota oficial do Revalida. Não indica aprovação, reprovação, certificação ou prontidão para o exame.

### Result states

| State | Definition (from the result contract) | Reviewed in #129? |
|---|---|---|
| Partial | At least one eligible criterion is `uncertain` or `not_observable`. `total` is `null`; a subtotal and the unresolved criteria are shown. | Yes, fictional fixture only |
| Complete | Every eligible criterion is `assessed`. `total` equals the subtotal. | **No** |
| No eligible criteria | The rubric is empty or every criterion is excluded. No total is shown. | **No** |
| Technical failure | The attempt is invalid. No criteria and no estimate are shown. | Recovery screen only |
| Placeholder content | The package is `placeholder: true`. The result says **Exemplo — dados fictícios**. | Yes |

### Conditions

Each state is reviewed under each condition.

- [ ] Desktop width
- [ ] Mobile width
- [ ] Keyboard-only navigation
- [ ] Screen reader (name the reader and browser below)
- [ ] The source of the rendered result is recorded: fictional fixture, scripted double, or live assessment

## Comprehension questions

The reviewer answers each question for each result state, from the reader's point of view. "Reader" means a person who matches the intended learner, not the author of the screen. Record who the readers were.

### Disclaimer

1. Without prompting, what does the reader say this result is? (Expected reading: an AI-generated educational estimate.)
2. Does the reader think this is an official Revalida score, or equivalent to one?
3. Does the reader think the result says whether they would pass, fail, be certified, or are ready for the exam?
4. Is the disclaimer seen before the reader interprets any number? Is it still present on the technical recovery screen?

### Coverage and incomplete evidence

5. In a **partial** result, does the reader understand that some criteria were not resolved, and which ones?
6. Does the reader read an unresolved criterion as **failure**, as zero points, or as something they did wrong?
7. Does the reader read the subtotal of a partial result as their **total score**?
8. Does the reader read a partial result, or a high subtotal, as **readiness**?
9. Can the reader tell an unresolved criterion from a criterion assessed at a zero-point level (a genuine omission)?
10. In a **complete** result, does the reader understand the total as an estimate over this station only, and not as a pass mark?
11. In a **no-eligible** result, does the reader understand that nothing was scored, and not that they scored zero?
12. On a **technical failure**, does the reader understand that the attempt was not assessed, and not that they performed badly?

### Status and wording

13. Is each criterion status understandable from its text alone, without relying on colour?
14. Is the fictional label noticed and understood on placeholder content?
15. Is any authored text (description, level, recommendation) in a language the reader does not expect? (English placeholder content needs re-authoring by the Content Partner, not ad hoc translation.)

## Record (to be completed by the reviewer)

| Field | Value |
|---|---|
| Reviewer name | PENDING |
| Reviewer role | PENDING |
| Independent of the screen's author? | PENDING (yes / no) |
| Review date | PENDING |
| Commit or build reviewed | PENDING |
| Station and package version | PENDING |
| Source of the rendered results | PENDING (fictional fixture / scripted double / live assessment) |
| Browsers, devices and screen reader | PENDING |
| Readers consulted (number, profile) | PENDING |

| Result state | Rendered and reviewed? | Outcome |
|---|---|---|
| Partial | PENDING | PENDING |
| Complete | PENDING | PENDING |
| No eligible criteria | PENDING | PENDING |
| Technical failure | PENDING | PENDING |
| Placeholder content | PENDING | PENDING |

| Question | Answer and observations |
|---|---|
| 1–4 Disclaimer | PENDING |
| 5–12 Coverage and incomplete evidence | PENDING |
| 13–15 Status and wording | PENDING |

Findings and required changes: PENDING

Overall outcome: PENDING (comprehension confirmed / changes required / not completed)

Reviewer statement, in the reviewer's words: PENDING

## What this record does not cover

- Clinical review of the station content ([`clinical-review-checklist.md`](clinical-review-checklist.md)).
- Qualification of the Jev decisions ([`qualification-results.md`](qualification-results.md)).
- Provider, privacy, zero-data-retention and legal acceptance.

A completed record confirms comprehension of the screens reviewed. It does not approve activation.
