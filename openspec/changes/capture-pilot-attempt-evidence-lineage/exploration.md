## Exploration: Capture valid pilot attempts and evidence lineage

### Current State

The repository is a planning/specification store for the Revalida clinical-practice MVP (Expo React Native + Elixir/Phoenix, planned but not scaffolded). Source of truth is GitHub Issues on `ChordanDev/proyectoMed`. There is no application code, no `package.json`/`mix.exs`, no test runner, and no `CONTEXT.md` or `docs/adr/` directory. `openspec/` holds only the freshly initialized `config.yaml`, an empty `specs/` tree, and an empty `archive/` subdirectory. `openspec/config.yaml` records `strict_tdd: false`, `phases.apply.strategy: auto-chain`, and `phases.apply.review_budget_lines: 800`.

Issue **#10 — Spec: One-station pilot advancement contract** is the open parent spec for the entire private pilot. It defines the primary external seam as the frozen advancement decision service/report and the **secondary external seam as station attempt capture** (the surface this change targets). It already fixes the policy frame this change must obey: Phoenix owns deterministic scoring behind a thin provider-agnostic adapter, provider outputs are untrusted candidate evidence, criteria outcomes are evidence-first and version-bound, telemetry is pseudonymous and minimal, and corrections append evidence while preserving the original result.

The closed Wayfinder tickets (#2, #3, #4, #5, #6, #7, #8, #9) supply locked-in inputs to #10 and therefore to #12: voice pipeline selection deferred to pt-BR benchmark (#2); clinician-versioned rubric contract (#3); auditable evidence + blind independent review (#4); thin role-based adapter with Qwen-first default (#5); pseudonymous invite-only account with no raw audio retention (#6); mobile accessibility behaviors including oral/written separation and non-editable transcript (#7); clinical-study asset provenance (#8); three independent advancement gates with frozen version-bound report (#9).

This change is the **first concrete step** in the #10 chain: #12 → #13 (gate evaluation) → #14 (frozen report) → #15 (verified pilot run). All four sub-issues carry the `ready-for-agent` label.

### Affected Areas

This is a planning-only repository, so "affected areas" are the SDD artifact paths plus the GitHub surfaces, not source files.

- `openspec/changes/capture-pilot-attempt-evidence-lineage/` — new change folder that will hold `proposal.md`, `exploration.md`, `specs/<capability>/spec.md`, `design.md`, `tasks.md`, and `verify-report.md`.
- `openspec/specs/station-attempt-capture/spec.md` — eventual main spec after archive; until then the delta in the change folder is the working source of truth.
- `openspec/config.yaml` — already declares phases and the `auto-chain` / 800-line delivery posture; no change required, but downstream phases must respect `strict_tdd: false`.
- `docs/PRD.md` — governing product principles (evidence before opaque scoring, transparent uncertainty, fair treatment of failures, historical integrity, data minimization); referenced by the change but not modified.
- GitHub issue `ChordanDev/proyectoMed#12` — the originating ticket; do not modify body, only add a closing comment when verification completes.
- GitHub issues `#13`, `#14`, `#15` — downstream consumers of this change's output; their blockers depend on this artifact being mergeable.

### Approaches

1. **Capability-aligned delta spec (`station-attempt-capture` capability)** — Treat #12 as the **secondary external seam** named in #10. Define one new capability `station-attempt-capture` whose sole responsibilities are: (a) attempt lifecycle state machine covering `strict | guided | oral | written | valid | interrupted`, (b) interruption handling with mandatory `replacement_of` linkage and `consumed=false` invariants for interrupted strict attempts, (c) event lineage linking each actor turn, transcript/evidence reference, timing event, accessibility mode, and material-unlock event to its parent attempt, and (d) timing-integrity accounting that records missing timestamps as `integrity_loss` rather than silently excluding them from latency denominators.
   - Pros: maps 1:1 to #10's "secondary external seam"; cleanly scopes away #13's gate evaluation and #14's frozen report; reuses #10's locked vocabulary (pseudonymous participant identifier, version-bound binding, provider outputs as untrusted candidate evidence); lets later archive sync merge into a single capability spec.
   - Cons: must avoid scope creep into clinician blind review (governed by #4/#13) or report serialization (governed by #14); capability name `station-attempt-capture` introduces a term not yet in `docs/PRD.md` and will require a glossary note.
   - Effort: Medium (spec + design + tasks + verify).

2. **Cross-cutting capability (`evidence-lineage`)** — Define one broader capability spanning attempt capture, lineage, and the report binding, capturing #12 + parts of #14 preemptively.
   - Pros: single spec captures the full evidence chain.
   - Cons: collides with #14's scope, breaks the #10 DAG (#14 has its own `ready-for-agent` ticket), blocks #13 because the gate evaluator depends on a stable lineage schema; harder to deliver via `auto-chain` because reviewers must read gate logic and serialization at once; 800-line review budget is more likely to be threatened.
   - Effort: High.

3. **Pure research/exploration doc without a formal spec** — Treat #12 as a Wayfinder `research` ticket, write only `exploration.md` and skip `sdd-spec`.
   - Pros: fastest to publish.
   - Cons: violates `openspec/config.yaml` (`phases.spec.required: true`); leaves #13/#14/#15 without an input contract; does not produce the verification gates that `verify.required_for: [archive]` demands; the ticket is labeled `ready-for-agent`, not `wayfinder:research`, signaling the team expects a real SDD change.
   - Effort: Low, but incorrect for the workflow.

### Recommendation

Use **Approach 1** — capability-aligned delta spec under the new `station-attempt-capture` capability. It is the only option that (a) honors `phases.spec.required: true`, (b) keeps the #10 DAG intact so #13/#14/#15 can dispatch in sequence under `auto-chain`, (c) lets the 800-line review budget be split cleanly across the four sub-issues, and (d) reuses the locked terminology from #4, #5, #6, #7, and #9 without re-debating settled decisions.

Concrete shape for the proposal/spec/design:

- **Capability**: `station-attempt-capture`.
- **Attempt lifecycle states** (with transitions): `created → in_progress → completed_valid | interrupted_strict | interrupted_guided | abandoned_guided`. `interrupted_strict` is terminal-but-replaced: `consumed=false`, `replacement_of` set to the prior attempt id, attempt id is excluded from coverage numerators and from valid-attempt denominators, but remains in cohort accounting.
- **Event lineage**: each `AttemptEvent` row carries `attempt_id` plus discriminator (`actor_turn | transcript_segment | evidence_reference | timing_event | accessibility_mode_event | material_unlock_event`) and references the originating artifact (provider route id + provider correlation id, transcript segment id, evidence criterion id, station version id, accessibility mode snapshot id, unlock rule id + authorization decision).
- **Timing integrity**: every expected timing event (`learner_speech_end`, `actor_response_start`, `attempt_completion`, `feedback_available`) MUST be recorded; missing rows are stored as `integrity_loss` records with `attempt_id`, `expected_event`, `reason`. Latency denominators consume all expected-event slots for evaluable attempts and treat `integrity_loss` rows as failures, never as omissions.
- **Version binding**: each attempt persists `station_version`, `rubric_version`, `policy_version`, `provider_routes_version`, `app_build_version`, `telemetry_schema_version` snapshots at attempt start; corrections append new attempts, never mutate lineage.
- **Pseudonymization**: `participant_id` is the pseudonymous handle defined by #6; raw audio is never stored; transcript text and accessibility mode are stored under `restricted_review` access tier separate from generic analytics.
- **Distinct modalities**: attempt creation requires the participant to declare `oral | written`; mixing modalities within one attempt is rejected at attempt-start and recorded as `modality_violation`.

### Risks

- **Scope creep into #13/#14**: easy to absorb gate evaluation or frozen-report serialization here because they share the lineage. Guard with explicit "OUT OF SCOPE" sections in the proposal and design.
- **Pseudonymization regression**: the lineage MUST NOT include direct email identity or raw audio. Revalidate against #6's resolution at every scenario.
- **Integrity-loss arithmetic**: if `integrity_loss` rows are silently filtered out, latency p95 will look better than reality — the #10 user story #20 explicitly forbids this. Add an explicit Given/When/Then scenario that proves a missing timestamp fails the operability gate.
- **Replacement-link referential integrity**: an interrupted strict attempt with no `replacement_of` row, or pointing to a non-existent prior attempt, must be rejected at write time. Otherwise coverage accounting becomes ambiguous.
- **No runnable test runner**: `strict_tdd: false`. Verification will be a spec-review checklist against the four acceptance criteria plus a design-traceability table mapping each user story in #10 (12, 13, 14, 15, 20, 40, 62, 63) to a scenario in the delta spec. Document this explicitly in `verify-report.md` so reviewers do not expect executable tests.
- **Capability vocabulary not in PRD**: `station-attempt-capture` is a new term; flag for `/domain-modeling` after the change archives so future issues use the same vocabulary.
- **auto-chain delivery on planning artifacts**: `auto-chain` applies to implementation slices; for this planning-only repo each phase (proposal → spec → design → tasks → verify → archive) produces documents that are individually small (< 400 lines each). `sdd-tasks` should still emit the standard forecast lines so reviewers see `Decision needed before apply: Yes`, `Chained PRs recommended: No`, `400-line budget risk: Low`.

### Ready for Proposal

Yes. The change is well-scoped, the parent contract (#10) and consumer contract (#13) are both already open and labeled `ready-for-agent`, and the four #12 acceptance criteria map cleanly into Given/When/Then scenarios. The orchestrator should advance directly to `sdd-propose` with:

- capability = `station-attempt-capture`
- parent issue = `ChordanDev/proyectoMed#10`
- originating issue = `ChordanDev/proyectoMed#12`
- downstream unblock = `ChordanDev/proyectoMed#13` (and transitively #14, #15)
- delivery posture = `auto-chain`, 800-line budget (planning-only; documents well under 400 lines each)
- TDD posture = strict TDD disabled until Expo/Phoenix stack is scaffolded, per `openspec/config.yaml`