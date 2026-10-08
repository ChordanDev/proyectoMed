# Acute appendicitis: qualification status and results

**Status: not qualified for any clinical or pilot use.** No case is adjudicated, no threshold is defined, and no model-backed result exists. Nothing below is a clinical accuracy claim, a medical validation, or a statement of equivalence with any official exam.

| | |
|---|---|
| Station | `acute-appendicitis` (`placeholder: true`, not the active station) |
| Harness | `Backend.Stations.Qualification`, run with `mix stations.qualify acute-appendicitis` |
| Cases and thresholds | `backend/priv/stations/qualification/acute-appendicitis/` |
| Jev adapter on this branch | `Backend.Stations.JevDecision.DisabledAdapter` (the only adapter) |

## What the harness measures

- It sends each fictional case through the real code path, with the configured Jev adapter:
  - a `dialogue_gate` case gives a candidate patient reply to the candidate gate (`CandidateGate.verify_and_deliver/4`), without regeneration;
  - a `rubric_assessment` case builds a session from the case's turns and assesses it (`RubricAssessment.assess/3`), then reads one criterion or one of its actions.
- It records one **structural outcome label** per case, for example `delivered`, `low_confidence`, `assessed:inadequado` or `action:uncertain`.
- It counts, per category, how many observed outcomes agree with a **human adjudication**.

## What it does not measure

- **Clinical correctness.** A label says what the code path did, not whether that was medically right.
- **Anything, until a human adjudicates.** Each case carries a `proposed_expected` outcome. That is the structural question the case was written to probe. It is not an adjudication, and the harness never compares against it.
- **A verdict.** The harness never compares counts with thresholds and never prints a qualification decision. That decision is human.
- **Real conversations.** Every input is fictional pt-BR text written for this harness. No patient data, no learner transcript, no official exam text.

## How a case is counted

Each case lands in exactly one column, checked in this order:

| Result | Meaning |
|---|---|
| `adapter_disabled` | The Jev adapter is disabled. Nothing was observed. |
| `not_adjudicated` | No human recorded an expected outcome for the case. |
| `agreed_with_adjudication` | The observed outcome is one the adjudicator accepted. |
| `technical_failure` | The call failed where the adjudicator expected a decision. |
| `disagreed` | Any other observed outcome. |

## Privacy

- The report holds case ids, categories, surfaces and outcome labels only.
- The harness keeps and writes no case text, candidate reply, rationale or adapter payload. It writes a file only when `--out <path>` is given, and then only the same report.
- The Jev seam logs fixed, text-free warnings such as `[JevDecision] Adapter is disabled`.
- A future live adapter sends the fictional case text to its provider. Running the harness against one therefore needs the provider, privacy and zero-data-retention gate below to be accepted first.

## Case inventory

33 cases, all `pending`. "Probes" names the gaps of [`package-mapping.md`](package-mapping.md) and of `docs/design/jev-prototype.md` that a case was written around.

| Category | Dialogue gate | Rubric assessment |
|---|---|---|
| `ambiguity` | `ambiguity-01`, `ambiguity-02` | `ambiguity-03`, `ambiguity-04`, `ambiguity-05`, `ambiguity-06` |
| `unsupported_or_early_disclosure` | `unsupported-or-early-disclosure-01`, `-02`, `-03` | `unsupported-or-early-disclosure-04` |
| `contradiction` | `contradiction-01`, `contradiction-02` | `contradiction-03` |
| `injection` | `injection-01`, `injection-02` | `injection-03` |
| `uncertainty` | `uncertainty-01`, `uncertainty-02` | `uncertainty-03`, `uncertainty-04` |
| `modality_gap` | `modality-gap-03`, `modality-gap-04` | `modality-gap-01`, `modality-gap-02`, `modality-gap-05`, `modality-gap-06` |
| `chronology` | `chronology-01`, `chronology-02` | `chronology-03`, `chronology-04` |
| `technical_failure` | `technical-failure-01`, `technical-failure-03` | `technical-failure-02` |

| Probe | Cases |
|---|---|
| G1 | `ambiguity-05`, `ambiguity-06` |
| G2b | `ambiguity-04`, `chronology-03` |
| G5 | `modality-gap-05` |
| G6 | `modality-gap-06` |
| G8 | `modality-gap-02` |
| G9 | `ambiguity-01`, `unsupported-or-early-disclosure-02` |
| G10 | `unsupported-or-early-disclosure-01` |
| G11 | `modality-gap-01`, `modality-gap-03`, `modality-gap-04` |
| G14 | `modality-gap-01`, `modality-gap-02` |
| G16 | `unsupported-or-early-disclosure-03`, `uncertainty-02` |
| `first_n_enumeration`, `single_turn_answer_order` | `chronology-03` |

### Known limits of the cases

- **`first_n` and answer order.** The package authors no `first_n` and no `order` rule, so the assessment never asks Jev to enumerate answers for this station. `chronology-03` only observes how an action is classified when one turn lists several answers. The enumeration gaps recorded in `docs/design/jev-prototype.md` cannot be exercised with this package.
- **Technical failure.** A case cannot make a real adapter fail. The three cases in that category use an already expired deadline or a blank candidate reply, which the code decides before calling the adapter. Timeouts, malformed output and provider errors of a real adapter are covered by unit tests with scripted doubles, not by these cases.
- **Deterministic deny rules.** With the disabled adapter, no reply other than the blank one was denied before the Jev call. The role-change and stage-direction replies (`injection-01`, `injection-02`, `modality-gap-04`) reached the Jev step.
- **G7, G12, G13, G15, G17** have no case: they concern content that is never released, learner-facing display, or fields the assessment does not read.

## Thresholds

Defined in `thresholds.json` as the required fraction of adjudicated cases that agree. Every value is `null`.

| Scope | Required agreement | Defined by | Date |
|---|---|---|---|
| Overall | undefined — pending human definition | — | — |
| `ambiguity` | undefined — pending human definition | — | — |
| `unsupported_or_early_disclosure` | undefined — pending human definition | — | — |
| `contradiction` | undefined — pending human definition | — | — |
| `injection` | undefined — pending human definition | — | — |
| `uncertainty` | undefined — pending human definition | — | — |
| `modality_gap` | undefined — pending human definition | — | — |
| `chronology` | undefined — pending human definition | — | — |
| `technical_failure` | undefined — pending human definition | — | — |

The unit of the threshold (a fraction of agreeing adjudicated cases per category) is a proposal of the file format. The humans who define the thresholds may replace it.

## Observed results

### 2026-10-07 — disabled adapter (automated run on the branch)

| | |
|---|---|
| Command | `mix stations.qualify acute-appendicitis` |
| Branch | `feat/130-clinical-content` |
| Adapter | `Backend.Stations.JevDecision.DisabledAdapter` |
| Provider and model | None. No request left the process. |
| Run by | The implementation agent, as part of the automated checks. Not a human qualification run. |
| Thresholds | Undefined |
| Adjudicated cases | 0 of 33 |

Counts as printed:

```text
category | cases | agreed_with_adjudication | disagreed | not_adjudicated | adapter_disabled | technical_failure
ambiguity | 6 | 0 | 0 | 0 | 6 | 0
unsupported_or_early_disclosure | 4 | 0 | 0 | 0 | 4 | 0
contradiction | 3 | 0 | 0 | 0 | 3 | 0
injection | 3 | 0 | 0 | 0 | 3 | 0
uncertainty | 4 | 0 | 0 | 0 | 4 | 0
modality_gap | 6 | 0 | 0 | 0 | 6 | 0
chronology | 4 | 0 | 0 | 0 | 4 | 0
technical_failure | 3 | 0 | 0 | 3 | 0 | 0
total | 33 | 0 | 0 | 3 | 30 | 0
```

What this run shows:

- 30 cases need a Jev decision and report `adapter_disabled`.
- The 3 `technical_failure` cases were decided in code before the adapter: `technical-failure-01` and `technical-failure-02` observed `technical_failure` (expired deadline), and `technical-failure-03` observed `denied` (blank reply). They are `not_adjudicated`.
- The run printed 30 text-free `[JevDecision] Adapter is disabled` log lines.

What this run does not show:

- **No model-backed result exists.** No real model has classified any case.
- **No clinical accuracy, medical validation or official equivalence is claimed**, here or anywhere else in this repository.
- Zero agreements and zero disagreements mean "not measured", not "no errors".

### Run log template (for future human-run entries)

Copy this block for each run. Leave a field as PENDING rather than guessing.

```text
Date:
Commit:
Command:
Adapter module:
Provider and model (name, version):
Privacy / ZDR / legal acceptance reference (who accepted, where recorded):
Run by:
Thresholds in force (defined by, date), or "undefined":
Adjudicator(s) and adjudication date(s):
Adjudicated cases: __ of __
Counts as printed (paste the category table):
Disagreements and technical failures reviewed by (name, date):
Notes:
```

## Before any activation

All five gates are human decisions. None is closed.

- [ ] **Provenance and rights.** The Content Partner attests the station ([`provenance-and-rights.md`](provenance-and-rights.md)).
- [ ] **Clinical review.** A qualified human reviews every fact, disclosure condition, template, applicability predicate, level, point and rule ([`clinical-review-checklist.md`](clinical-review-checklist.md)).
- [ ] **Thresholds and adjudication.** Named humans define every threshold in `thresholds.json` and adjudicate every case (set `status`, `adjudicator`, `date` and `expected.outcomes` in the case files).
- [ ] **Provider, privacy, ZDR and legal.** A live Jev adapter and its provider terms are accepted before any case text is sent to a provider.
- [ ] **Disclaimer and coverage comprehension.** The result review is completed for partial, complete and no-eligible results ([`result-comprehension-review.md`](result-comprehension-review.md)).

Closing these gates does not by itself qualify the station. Qualification is the recorded human decision that follows a model-backed run.
