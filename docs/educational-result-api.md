# Educational result API v2

The station web result now consumes the explicit v2 educational assessment from
issue #128. This is a contract migration, not clinical activation or approval.
The legacy result remains separate and unchanged. Never fall back to it when v2
fails technically.

## Versioned boundary

`GET /api/v2/stations/active/sessions/:id/result` delegates through
`Backend.Stations.get_educational_result/2`. Successful responses have
`schema_version: "2"`, `session_id`, `status: "completed"`, authored `placeholder`,
`criteria`, `coverage`, and `estimates`. Responses use `Cache-Control: no-store`.

| Field | Contract |
| --- | --- |
| `criteria[].id`, `description` | Rubric order, identifier and authored description |
| `status` | `assessed`, `uncertain`, `not_observable`, or `not_applicable` |
| `max_points` | Exact maximum over the criterion's authored levels, even for excluded criteria |
| `level`, `level_description`, `points` | Present **only** when assessed; authored label/description and exact points |
| `evidence_ids`, `evidence` | Validated current-session excerpts `{id, role, text}`, in pool order; unresolved/excluded criteria have empty evidence |
| `reason` | `null` when assessed; otherwise the bounded categories below |
| `recommendation` | For `assessed` criteria, LLM-written feedback (issue #215) generated from the graded record only, in the package `language`, at most 400 characters; it explains the outcome and never changes `level`, `status` or `points`. Falls back to the authored `practice_recommendation` on any provider failure, timeout or invalid output, and always for non-assessed criteria. Generated once per session and kept while the criterion's graded outcome is unchanged |
| `coverage` | Counts for all four statuses, including excluded criteria |
| `placeholder` | True only when package metadata explicitly authors `placeholder: true` |

**Response time (issue #226).** The first fetch for a session runs the rubric
resolver and then generates learner feedback before it answers, so it may take
up to about a minute. Learner feedback has a 60 s deadline by default;
`LEARNER_FEEDBACK_DEADLINE_MS` (a positive integer, read at boot outside `:test`)
overrides it, and any other value keeps the default. The override is capped at
65 s, so the resolver (10 s) plus feedback stay inside the web client's 80 s
wait. Each call logs its latency,
never the texts. Later fetches reuse the cached feedback. The web client waits
up to 80 s for this request only and shows a waiting message meanwhile; every
other request keeps its 15 s timeout.

Allowlisted reasons are `assessment_unresolved`,
`required_modality_unavailable`, and `authored_exclusion`. They deliberately omit
raw internal reasons, tagged tuples, provider detail, call diagnostics, and
sub-action classifications. Sub-actions are not presented as credited actions.

## How a criterion is graded (issue #228)

Grading follows what the learner actually did. Three rules keep a criterion's
outcome tied to the transcript:

- **Action context.** Each rubric action is asked of the classifier (Jev)
  together with the description of the criterion it belongs to, so a short
  action ("PCR") is read in its clinical context.
- **Impresso-backed actions.** An action authored with `impresso_ids`
  (`docs/content/authoring-guide.md`) is performed when a verified Impressos
  request released one of those impressos. It is decided in code, citing that
  request, and is asked of neither Jev nor the rubric resolver.
- **No zero without proof.** A zero-point level needs no evidence, because a
  genuine omission leaves nothing to cite. The rubric resolver's
  `not_performed` answers cite nothing either, so they never ground a zero on
  their own: when a criterion reaches its zero-point level only because of
  them (with those actions left undecided, Jev's answers and the rules reach
  other levels too), the criterion is `uncertain` with reason
  `assessment_unresolved`, not assessed at `"0"`. A zero that Jev's own
  answers or a deterministic rule decide stays assessed. The resolver request
  runs at `temperature` 0.

Every point value is a shortest exact **decimal string**, not a JSON number:
`"0"`, `"0.025"`, `"0.125"`, `"0.4"`, `"1.125"`, etc. A value has at most three
fraction digits, no trailing zero, and is a multiple of 0.025. The backend uses
integer fortieths; the web decoder validates and reconciles totals with integer
arithmetic. Rendering only replaces the decimal separator with a comma, without
rounding or rescaling.

Amended 2026-10-07 (issue #130, amending ADR-012, #124): the granularity was widened from multiples of 0.125 to multiples of 0.025 to follow the tenths used by PEP 2025/2; strings already emitted for values in eighths are unchanged.

## Coverage and totals

- `scored_subtotal`: sum of assessed points, including genuine zero-point levels.
- `scored_max`: sum of maxima over assessed criteria only.
- `eligible_max`: sum of maxima over every non-excluded criterion, including
  uncertain and unobservable criteria.
- `total`: equals the subtotal only when at least one eligible criterion exists
  and all eligible criteria are assessed; otherwise **null**.
- `unresolved`: ordered `{id, status}` entries for uncertain and unobservable
  criteria, never excluded criteria.

The fictional partial-reconciliation fixture yields:

```json
{
  "total": null,
  "scored_subtotal": "0.25",
  "scored_max": "0.25",
  "eligible_max": "1.25",
  "unresolved": [{"id": "criterion-b", "status": "uncertain"}]
}
```

Complete coverage can report `"1.125"` of `"1.5"`. A genuine omission has an
assessed authored zero level and `points: "0"`. Uncertain, unobservable, and
excluded criteria never acquire zero points or levels. Empty/all-excluded
rubrics have null total and zero subtotals/maxima, displayed as no eligible
criteria rather than a fabricated total score. There are no percentages,
normalization, pass/fail thresholds, certification, or readiness claims.

## Failure and legacy migration

| HTTP | Error | Meaning |
| --- | --- | --- |
| 422 | `session_not_finished` | Session is active |
| 404 | `session_not_found` | Session is unknown or discarded |
| 410 | `session_expired` | Session passed its fixed safety TTL |
| 502 | `invalid_attempt` | Technical/provider/authoring failure: no criteria or estimate |

V2 technical failure is not educational uncertainty. The web displays recovery,
not partial points, and makes no v1 fallback request. The decision adapter remains
disabled by default; without a separately authorized provider, nonempty
assessments fail as invalid attempts. Tests use deterministic doubles only.

Legacy `GET /api/stations/active/sessions/:id/result` still uses the heuristic
`Backend.Stations.get_session_result/1`: `{session_id, status, criteria}` with
criterion `{id, status: met|omitted|uncertain, evidence: string[], recommendation}`
and no scores. The web retains explicitly named `LegacySessionResult`,
`LegacyResultCriterion`, and `fetchLegacyResult` for explicit migration use, not
the educational main path. The internal `to_legacy/1` projection is not used by
this legacy route.

## Disclosure, lifecycle, and human review

Before starting (voice or text) and on results (including technical recovery),
the interface displays exactly:

> Estimativa educacional gerada por IA. Não é nota oficial do Revalida. Não indica aprovação, reprovação, certificação ou prontidão para o exame.

Authored placeholder results visibly say **Exemplo — dados fictícios**. Status
explanations use semantic text, not color alone, with wrapping layout for mobile.
Descriptions, level descriptions and recommendations remain the authored values;
current English clinical content needs content-partner translation/re-authoring
under #130, not ad hoc translation in this result layer.

Evidence is computed from ephemeral session data, not persisted as assessment
history or logged here. The only browser-storage value is the session ID. The
existing fixed 30-minute safety TTL is not extended by reading results. Explicit
reset waits for discard acknowledgement; failed discard retains state for retry.
Acknowledged pagehide discard clears result/evidence state so a BFCache-restored
page cannot show the deleted session. Late finish/resume result responses cannot
restore evidence after successful reset/discard. Keepalive delivery itself remains
best effort, not a deletion guarantee.

**Human review:** on 2026-10-07 the PR author reviewed the rendered notice,
result, loading and recovery screens at desktop and mobile widths, with keyboard
navigation and VoiceOver, covering disclaimer prominence, comprehension of
unresolved coverage and the fictional label. The review used a local preview fed
by the fictional partial-coverage fixture, not a live assessment; complete and
no-eligible results were not rendered. Provider/privacy/ZDR, legal and clinical
qualification/activation remain outside this change; no external provider is
enabled.

The pending review of complete and no-eligible results, and of how readers understand incomplete evidence, is recorded in [`docs/content/acute-appendicitis/result-comprehension-review.md`](content/acute-appendicitis/result-comprehension-review.md) (issue #130; not yet completed).

## Verification locators

- `backend/test/backend_web/controllers/educational_result_test.exs`: public HTTP
  and context evidence, exact reconciliation, failures, lifecycle, legacy safety.
- `web/src/features/station/api/educational-result.test.ts`: strict v2 decoding,
  exact reconciliation and no fallback.
- `web/src/features/station/result/educational-result.fixture.ts`: fictional
  partial result matching the backend package fixture.
- Result, notice, and hook colocated tests: accessible status copy, exact
  disclosure, recovery, reset and late-response regressions.
