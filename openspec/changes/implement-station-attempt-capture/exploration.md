## Exploration: Implement station-attempt-capture against the Expo + Phoenix runtime

### Current State

**Both dependency PRs are now merged on `origin/main` (HEAD `3383950`):**

| PR | Issue | Title | Merged |
|---|---|---|---|
| #17 | #16 | feat(scaffold): Expo React Native + Phoenix JSON runtime | 2026-09-01T14:15:32Z |
| #18 | #12 | docs(spec): station-attempt-capture SDD artifacts | 2026-09-01T14:21:59Z |

Local `main` is **stale at `0d27786`** (the user has not yet pulled `3383950`). The working tree is checked out on `feat/capture-pilot-attempt-evidence-lineage` at `9b204d6` and contains **untracked, partially-broken leftovers from prior sessions**:

- `mobile/` — full Expo 54 TypeScript scaffold (downgraded from SDK 57 in a prior session) with `package.json`, `package-lock.json`, `.gitignore`, `App.tsx`, `__tests__/App.smoke.test.tsx`, `app.json`, `index.ts`, `tsconfig.json`, `assets/`, `node_modules/`, `.expo/`. Toolchain pins (`node 26.5.0`, `npm 11.17.0`, `expo ^54.0.37`, `react 19.1.0`, `react-native 0.81.5`, `jest-expo ~54.0.18`) match the committed `50425ff`/`origin/main` versions, but the working-tree SHA is not committed and differs in lockfile bytes from the merged copy.
- `backend/` — **only `_build/dev/test` and `deps/`** (Phoenix compiled artifacts from a prior `mix deps.get`/`mix compile`). No `mix.exs`, no `lib/`, no `config/`, no `test/`, no `.formatter.exs`, no `.tool-versions`, no `.gitignore`, no `README.md`. This is unusable for implementation until the committed source is restored.
- `openspec/changes/implement-station-attempt-capture/exploration.md` — the prior exploration (this file's predecessor), written when neither PR was merged; its `cherry-pick 50425ff` recommendation is now obsolete.
- `.codegraph/`, `.DS_Store`, `node_modules/` (root), `erl_crash.dump`, `PR_BODY.md`, `PR_BODY_12.md` — researcher/build artifacts and untracked PR drafts.

**Frozen contract on `origin/main`** (`openspec/changes/capture-pilot-attempt-evidence-lineage/specs/station-attempt-capture/spec.md`, 93 lines) defines **5 RFC-2119 requirements / 11 Given/When/Then scenarios**, byte-identical to the version at `9b204d6`. Per #19 ("No modification to the frozen #12 contract or its archived SDD artifacts") this file is read-only for the implementation change:

1. **Attempt Creation and Lifecycle States** — `created → in_progress → submitted → evaluated → closed`; `in_progress → strict_interruption` as sole lateral exit; one immutable `modality` (`oral` or `written`); mixed-modality creation rejected atomically. Scenarios: fresh-create, mixed-rejection.
2. **Append-Only Pseudonymous Event Lineage** — every event carries `attempt_id`, pseudonymous `pilot_id`, discriminator, UTC `occurred_at`, monotonic `seq`, `prior_hash`; first event references creation-snapshot hash; mutation/deletion/reordering rejected. Scenarios: ordered-append, mutation-rejected.
3. **Expected Timing Slots and Integrity Loss** — every expected slot resolves exactly once to `timing_recorded {slot_id, started_at, ended_at}` or `integrity_loss {slot_id, reason, recovery_action}`; silent omission impossible. Scenarios: all-slots-recorded, lost-slot-recorded.
4. **Strict-Interruption Replacement Integrity** — `strict_interruption` is terminal, non-consuming; replacement attempts carry `replacement_of: <interrupted attempt_id>`; interrupted chain stays read-only. Scenarios: non-consuming-terminal, replacement-links.
5. **Version Binding, Access Tiers, and No Raw Audio** — atomic creation binding of eight fields (`station`, `rubric`, `policy`, `provider_route`, `application_build`, `telemetry_schema`, `accessibility_context`, `material_unlock_state`); retroactive rewrites rejected; raw-audio bytes rejected at persistence layer with metadata-only `integrity_loss` appended; canonical participant-visible transcript is default; full-disfluency transcript requires elevated policy authorization. Scenarios: versions-captured, raw-audio-rejected, elevated-access.

**Runtime scaffold on `origin/main`** (committed at `50425ff`, declared SDD posture in `openspec/config.yaml`):

- `phases.apply.strategy: auto-chain`; `phases.apply.review_budget_lines: 800`; `phases.apply.test_command: bash scripts/test.sh`; `phases.verify.test_command: bash scripts/test.sh`.
- `strict_tdd: false` — harness is wired and tests are encouraged, but no RED-GREEN-REFACTOR gating.
- `testing.capabilities`: `runner`, `unit`, `integration`, `linter`, `type_checker`, `formatter` all `available: true`; `e2e` and `coverage` `available: false` (deferred — Expo Go live start and iOS native builds blocked by environment).
- `harnesses`: `scripts/scaffold.sh`, `scripts/test.sh` (root orchestrator: `npm --prefix mobile test` → `( cd backend && mix test )`, first non-zero exit propagates), `tests/scripts/scaffold_red.sh`, `tests/scripts/test_red.sh` — all hermetic via PATH-stub fakes.
- `BackendWeb.HealthController` returns `GET / → {"status": "ok"}` with its own ExUnit smoke; `BackendWeb.Router` has an `:api` pipeline (`plug :accepts, ["json"]`) and currently only the `GET /` scope.

**RDD posture: disabled** per `rdd-defect-workflow` skill defaults (`RDD disabled → Ordinary policy; disabled/unmanaged; no receipt or approval claim`). Confirmed by `openspec/changes/scaffold-expo-phoenix-runtime/exploration.md` and prior session summaries: no receipts, no lineage/correction/recovery, no delivery gate. Ordinary PR discipline via `branch-pr` + `work-unit-commits` skills applies; review-budget enforcement is the only automatic gate.

**Existing RDD memory:** none — search for `RDD receipt disabled delivery gate` returned zero observations, so the policy has to be re-asserted from skill default plus the project's scaffold exploration.

### Affected Areas

**Working-tree cleanup (must happen before implementation):**

- `mobile/` (untracked) vs committed `mobile/` on `origin/main` — package-lock SHA divergence likely; `node_modules/` should be regenerated by `npm install`; assets/unchanged. Strategy: remove untracked working-tree `mobile/`, restore from `origin/main` on the new branch.
- `backend/` (untracked, only `_build/` + `deps/`) — remove entirely; committed `backend/` from `origin/main` is the source of truth.
- `node_modules/` (root, untracked) — delete; rogue top-level install, not part of either project.
- `erl_crash.dump` (root, untracked) — Elixir crash dump from prior session; delete.
- `.DS_Store`, `.codegraph/` — gitignored at root; left alone.
- `PR_BODY.md`, `PR_BODY_12.md` — untracked PR drafts from PR #16 and #18. The implementation change will mint its own PR body via `work-unit-commits`; delete both.
- `openspec/changes/implement-station-attempt-capture/exploration.md` — overwritten by this refresh.

**New Phoenix backend source (`origin/main` branch, additive only):**

- `backend/lib/backend/attempts.ex` — `Backend.Attempts` GenServer/agent-less module: create/read attempt snapshots, atomic creation (single-modality, complete bindings, pseudonymous ID generation), `replacement_of` validation, modality-immutability enforcement, lifecycle projection from event chain.
- `backend/lib/backend/events.ex` — `Backend.Events`: append-only event chain store (`:ets` set or persistent_term-backed for the prototype), `seq` allocator, `prior_hash` linker, mutation/deletion/reordering rejection.
- `backend/lib/backend/lineage.ex` — canonicalization + SHA-256 hash-link algorithm (shared algorithm reference for both backend and mobile).
- `backend/lib/backend/timing.ex` — expected-slot registry + slot resolver; produces `timing_recorded` or `integrity_loss` events; one outcome per slot is enforced.
- `backend/lib/backend/replacements.ex` — strict-interruption transition guard; replacement referential integrity (`replacement_of` must point to a `strict_interruption` attempt).
- `backend/lib/backend/access_tiers.ex` — transcript projection + elevated-tier gate; reads server-side trust signal, not client-supplied flags.
- `backend/lib/backend_web/controllers/attempt_controller.ex` — `POST /api/attempts` (create), `GET /api/attempts/:id` (read snapshot), `POST /api/attempts/:id/replacement` (replacement creation).
- `backend/lib/backend_web/controllers/event_controller.ex` — `POST /api/attempts/:id/events` (append single event), `GET /api/attempts/:id/events` (list chain).
- `backend/lib/backend_web/controllers/timing_controller.ex` — `POST /api/attempts/:id/timing` (resolve slot), `GET /api/attempts/:id/integrity-losses`.
- `backend/lib/backend_web/controllers/transcript_controller.ex` — `GET /api/attempts/:id/transcript` (canonical or elevated view per server-side access tier).
- `backend/lib/backend_web/router.ex` — add `:api` scope routes for the four controllers.
- `backend/lib/backend_web/controllers/error_json.ex` — extend error shapes for the new rejection cases (`409 Conflict` for modality/replacement conflicts, `422 Unprocessable Entity` for incomplete bindings, `403 Forbidden` for unauthorized transcript reads).
- `backend/test/backend/{attempts,events,lineage,timing,replacements,access_tiers}_test.exs` — ExUnit coverage for every frozen scenario.
- `backend/test/backend_web/controllers/*_test.exs` — ConnCase-based controller tests.
- `backend/test/support/fixtures/` — shared fixtures for attempt creation, event append, timing slots.

**New Expo TypeScript client (`mobile/`, additive only):**

- `mobile/src/stationAttemptCapture/types.ts` — typed contract mirror of the frozen spec: `AttemptSnapshot`, `AttemptEvent`, `TimingRecord`, `IntegrityLoss`, `AccessTier`.
- `mobile/src/stationAttemptCapture/canonicalize.ts` — SHA-256 / canonical-JSON hash linker shared with backend (parity test required).
- `mobile/src/stationAttemptCapture/client.ts` — `POST /api/attempts`, append event, resolve timing slot, request strict interruption, link replacement, fetch transcript.
- `mobile/src/stationAttemptCapture/createAttempt.ts`, `appendEvent.ts`, `resolveTimingSlot.ts`, `requestStrictInterruption.ts`, `linkReplacement.ts`, `fetchTranscript.ts` — thin wrappers with input validation.
- `mobile/__tests__/stationAttemptCapture/canonicalize.test.ts` — golden-vector parity test against `Backend.Lineage` outputs.
- `mobile/__tests__/stationAttemptCapture/client.test.ts` — mocked fetch tests for each operation, including raw-audio rejection at the client boundary (defense-in-depth: mobile ALSO refuses to send raw audio bytes).
- `mobile/App.tsx` — replace the stub render with a minimal capture-pipeline demo screen (modal that prompts modality, creates an attempt, simulates a single timing slot, and renders the canonical transcript). Smoke test `mobile/__tests__/App.smoke.test.tsx` must continue to pass.

**New SDD artifacts (this change folder, additive only):**

- `openspec/changes/implement-station-attempt-capture/proposal.md` — intent, scope, capabilities, approach, affected areas, rollback.
- `openspec/changes/implement-station-attempt-capture/specs/station-attempt-capture-implementation/spec.md` — **delta spec with new capability identifier `station-attempt-capture-implementation`** that adds HTTP API surface, JSON schemas, hash-link algorithm, controller boundaries, and test-coverage map **without modifying the frozen `station-attempt-capture` capability**. Per #19: no MODIFIED or REMOVED sections on the frozen capability; only ADDED requirements on the new identifier. Archive promotes both as separate-but-linked canonical specs.
- `openspec/changes/implement-station-attempt-capture/design.md` — data flow (mobile capture → POST → atomic validation → snapshot + first event → append-only chain → access-tiered reads), module boundaries, hash-link algorithm specification, raw-audio rejection contract (status code, response shape, audit event), `replacement_of` referential integrity rules, access-tier authorization model.
- `openspec/changes/implement-station-attempt-capture/tasks.md` — review-workload forecast (`Decision needed before apply: No`, `Chained PRs recommended: Yes`, `400-line budget risk: Medium`); numbered work units; scenario-to-test map covering all 11 frozen scenarios.
- `openspec/changes/implement-station-attempt-capture/verify-report.md` — `bash scripts/test.sh` exit 0; 11/11 frozen-scenario coverage; `sdd-verify-validate` admitted.
- `openspec/changes/implement-station-attempt-capture/verify-report.md` (independent of `#12`'s FAIL verdict at `openspec/changes/capture-pilot-attempt-evidence-lineage/verify-report.md`) — that report remains FAIL until #12 archives, which is its own gate.

**Out-of-scope (per #19):** #13 gate evaluation; #14 frozen advancement report; #15 pilot execution; provider selection; voice-pipeline tuning; persistence beyond the attempt lineage; authentication (the access tier is a server-side policy claim, not an authn system); deployment; raw-audio retention.

### Approaches

1. **Branch off `origin/main`, clean working tree, implement as stacked PRs** — `git fetch origin && git checkout -b feat/implement-station-attempt-capture origin/main`, `git clean -fdx mobile backend node_modules erl_crash.dump PR_BODY.md PR_BODY_12.md` (after confirming no committed content), then implement the SDD artifacts + Phoenix modules + Expo client in stacked work units using `auto-chain` delivery (per `openspec/config.yaml`). Each work unit <= 800 authored lines; spec covers all 11 frozen scenarios.
   - Pros: directly honors #19's verbatim claim that "the runnable Expo + Phoenix stack is available from #16" and "the behavior contract is published in #12" — both available on `origin/main`. Restores the canonical committed state, discards the broken untracked leftovers from prior sessions, leaves the frozen contract untouched, lets `bash scripts/test.sh` run from day 1, lets `sdd-verify` produce a passing report.
   - Cons: requires `git clean -fdx` to remove untracked state; if the user has uncommitted WIP in `mobile/` worth saving, it must be rescued before cleanup. The branch is created from `origin/main` rather than continuing the existing `feat/capture-pilot-attempt-evidence-lineage` (which loses the branch-name "capture-pilot-attempt-evidence-lineage" identity, but the change folder name `implement-station-attempt-capture` is the SDD identifier, not the branch name).
   - Effort: **Medium** — one fetch+checkout+clean (low), plus the same 4–6 stacked PRs.

2. **Stay on `feat/capture-pilot-attempt-evidence-lineage` and merge `origin/main` into it** — keeps the existing branch tip but mixes contract-frozen state with the scaffold and the upcoming implementation; renames are awkward.
   - Pros: preserves the local commit `9b204d6` (frozen contract commit) as the branch tip; no destructive `git clean`.
   - Cons: branch name no longer matches change purpose (the branch is named after the contract, but the change is `implement-station-attempt-capture`); the contract commit becomes buried under merge + implementation commits; `sdd-archive` for #12 will need to identify the contract commit by content, not branch tip; invites reviewer confusion.
   - Effort: **Medium-High** — one merge (low) plus stacked PRs, but the merge produces a non-linear history that complicates the `sdd-archive` of #12.

3. **Cherry-pick scaffold from `origin/main` and implement on the contract branch (the prior recommendation)** — now obsolete: scaffold already merged, so cherry-picking `50425ff` would re-introduce files already present on `origin/main` and create merge conflicts.
   - Pros: none specific to the new reality.
   - Cons: unnecessary duplicate commits, will conflict with the merged tree.
   - Effort: **High** for cleanup later; no upside.

4. **Rebuild from scratch on a new branch, ignoring `origin/main`'s scaffold** — reconstruct `mix.exs`, `lib/`, etc., on the implementation branch.
   - Pros: zero coupling to upstream scaffold.
   - Cons: duplicates work already merged on `origin/main`; loses the contracted harness/posture; repeats the failure mode that originally motivated #16.
   - Effort: **High**.

### Recommendation

**Approach 1 — branch off `origin/main`, clean working tree, implement as stacked PRs.** It is the only option that simultaneously:

1. Honors #19's verbatim claim that both dependencies are available on `origin/main` (they are; fetch + checkout is enough).
2. Keeps the frozen `#12` contract untouched (it lives on `origin/main` under `openspec/changes/capture-pilot-attempt-evidence-lineage/`; the implementation change uses a separate capability identifier `station-attempt-capture-implementation` and declares only ADDED requirements).
3. Restores the canonical committed state and discards the untracked leftovers that prevent `bash scripts/test.sh` from running cleanly today (`mobile/` has `node_modules/` but no committed source equivalent; `backend/` has only `_build/`/`deps/`).
4. Preserves the scaffold's declared posture (`strict_tdd: false`, `auto-chain`, `review_budget_lines: 800`, `test_command: bash scripts/test.sh`) — no SDD policy re-debate, no re-derivation of the harness contract.
5. Aligns with `sdd-phase-common.md` Section E — `sdd-tasks` forecasts `Decision needed before apply: No`, `Chained PRs recommended: Yes`, `400-line budget risk: Medium`, and `sdd-apply` honors `auto-chain` while keeping each batch under the 800-line budget (default 400).
6. Lets `sdd-verify` produce a passing report — the original `#12` verify FAILed because the harness did not exist; the implementation verify can target `bash scripts/test.sh` and require scenario coverage of all 11 frozen Given/When/Then cases.
7. Honors the **RDD-disabled, clone-locally** posture — no receipts, no approval gating, no kill switch, ordinary `branch-pr` + `work-unit-commits` flow. The new `proposal.md` carries this posture forward explicitly so downstream phases do not invent RDD mechanics.
8. YAML-declared `phases.archive.on_success: openspec/specs/<capability>/spec.md synced from change delta` — `#12`'s archive happens on its own verify gate (independent of this change). The implementation change's `verify-report.md` references the frozen delta as the source of behavior truth and does not attempt to archive `#12`.

**Pre-implementation sequence the orchestrator must run before `sdd-propose`:**

1. `git fetch origin` (already done in this exploration).
2. `git checkout -b feat/implement-station-attempt-capture origin/main` to create the implementation branch from the merged tree.
3. `git status` to confirm no untracked WIP worth rescuing (the current untracked `mobile/` has only the prior-session SDK 54 downgrades; no committed equivalent diverges in behavior; safe to remove).
4. `git clean -fdx mobile backend node_modules erl_crash.dump PR_BODY.md PR_BODY_12.md` (the user must confirm; if anything in `mobile/` is real WIP it must be `git stash`-ed first, but the current state shows no committed-incompatible files).
5. `git status` and `git diff origin/main --stat` should both be clean.
6. Open the PR with `branch-pr` once `proposal.md` lands, label `enhancement` + `ready-for-agent`.

**Proposed work-unit stack (for `sdd-tasks` to make concrete):**

| Unit | Goal | Likely PR | Bounded test |
|---|---|---|---|
| 0 | Branch + clean + initial SDD artifacts (`proposal.md`, `design.md`, `specs/.../spec.md`, first `tasks.md`) | Setup PR | `bash scripts/test.sh` still passes (no behavior change) |
| 1 | Phoenix `Backend.{Attempts,Events,Lineage}` + `attempt_controller` + `event_controller` + ExUnit | Snapshot + chain core | ExUnit covers 6 scenarios (fresh-create, mixed-rejection, ordered-append, mutation-rejected, replacement-links, versions-captured) |
| 2 | Phoenix `Backend.{Timing,Replacements}` + `timing_controller` + replacement linkage in `attempt_controller` + ExUnit | Timing + interruption | ExUnit covers 3 scenarios (all-slots-recorded, lost-slot-recorded, non-consuming-terminal) + replacement rejection ExUnit |
| 3 | Phoenix `Backend.AccessTiers` + `transcript_controller` + raw-audio rejection at controller boundary + ExUnit | Access + raw-audio gate | ExUnit covers 2 scenarios (raw-audio-rejected, elevated-access); golden test for sanitized `integrity_loss` shape |
| 4 | Mobile `mobile/src/stationAttemptCapture/{types,canonicalize,client,*}.ts` + Jest | Capture client | Jest covers canonicalize parity (golden vectors), client error paths, raw-audio client-side refusal |
| 5 | Mobile→backend integration smoke in `mobile/__tests__/stationAttemptCapture/integration.test.ts` (Jest + mocked fetch + Phoenix-driven end-to-end via `bash scripts/test.sh` already wired) | Integration smoke | `bash scripts/test.sh` 0 exit; mobile Jest + backend ExUnit both green |
| 6 | `verify-report.md` admission + `sdd-verify` PASS gate | Verify PR | `gentle-ai sdd-verify-validate` admits; all 11 frozen scenarios have at least one ExUnit/Jest case |

### Risks

- **Working-tree cleanup loses untracked WIP**: `mobile/` (untracked) has the SDK 54 downgrades from the prior session. If the user wants those preserved, they must `git stash` (or copy out) before `git clean`. Mitigation: this exploration explicitly notes that `mobile/`'s working-tree SHA matches the committed `50425ff`/`origin/main` toolchain pins (Expo ^54.0.37, RN 0.81.5, jest-expo ~54.0.18), so the cleanup is safe; the lockfile bytes differ but `npm install` regenerates from `package.json` deterministically. If lockfile SHA divergence is significant, `npm ci` against the committed `package-lock.json` on `origin/main` will reconcile.
- **Hash-link algorithm drift between mobile and backend**: SHA-256 over canonical JSON, but canonicalization (key ordering, Unicode normalization, whitespace, float encoding) is easy to get wrong. Mitigation: a single `canonicalize.ts` (mobile) / `Backend.Lineage.canonicalize/1` (backend) pair with shared golden vectors exercised by both Jest and ExUnit; `sdd-design` fixes the algorithm before any controller/client code is written.
- **Raw-audio rejection bypass**: bytes-on-the-wire filtering is easy to subvert (base64-in-JSON, multipart upload, chunked transfer). Mitigation: `transcript_controller` and `event_controller` reject any payload containing `audio`, `raw_audio`, `bytes`, or `audio_b64` keys regardless of `Content-Type`; `design.md` specifies the rejection contract (status `422`, response shape `{error: :raw_audio_rejected, audit_event: {...}}`, automatic `integrity_loss` append with sanitized metadata); ExUnit + Jest both cover the rejection.
- **`replacement_of` referential integrity**: a replacement pointing to a non-existent or non-`strict_interruption` attempt must be rejected at write time, not at read time. Mitigation: `Backend.Attempts.create_replacement/2` validates the target before insertion; ExUnit covers missing target, wrong-state target, and self-referential replacement; `attempt_controller` returns `409 Conflict`.
- **Access-tier authorization**: the canonical vs. elevated transcript distinction must be a server-side decision; the mobile client cannot bypass. Mitigation: `transcript_controller` reads the trust signal from the request context (a server-set header or plug-derived claim), never trusts client-supplied tier flags; ExUnit covers canonical-only for non-elevated and elevated-only-for-elevated.
- **`strict_tdd: false` discipline gap**: harness exists but no RED-GREEN-REFACTOR is enforced. Mitigation: each work unit MUST include at least one ExUnit or Jest test that exercises the unit's surface and would fail if the unit's code regressed; `sdd-verify` runs `bash scripts/test.sh` and requires non-zero coverage on all 11 frozen scenarios documented in `verify-report.md`'s scenario-to-test map.
- **800-line review budget exceeded on a single PR**: implementation surface is large (5 frozen requirements, 4 Phoenix controllers + 6 backend modules, mobile capture client, golden parity tests, 11-scenario coverage). Mitigation: stacked PRs by work unit (Approach 1 already splits this); `sdd-tasks` MUST emit `Chained PRs recommended: Yes` and `sdd-apply` MUST honor `auto-chain` while keeping each batch under 800 authored lines (default 400).
- **Frozen contract drift**: the implementation change's `spec.md` could accidentally MODIFY or REMOVE a frozen behavior requirement. Mitigation: the implementation spec uses a separate capability identifier (`station-attempt-capture-implementation`) and only declares ADDED requirements; no MODIFIED or REMOVED sections reference the frozen capability; `sdd-verify` cross-checks that `openspec/changes/capture-pilot-attempt-evidence-lineage/specs/station-attempt-capture/spec.md` is byte-identical to its pre-implementation state.
- **Archive ordering with #12**: #12's archive happens on its own verify gate (independent of this change). The implementation change does NOT archive #12. Mitigation: `proposal.md` and `tasks.md` explicitly note the archive independence; `verify-report.md` references the frozen delta as the source of behavior truth and does not attempt to merge archives.
- **RDD-disabled drift into receipt behavior**: someone could mistake "RDD-disabled" for "no PR discipline". Mitigation: this exploration carries forward the user's clone-locally convention and the project's `branch-pr` + `work-unit-commits` flow; the proposal records the posture so subsequent phases do not invent approval/gate mechanics.
- **`openspec/config.yaml` already on `origin/main`**: phase posture is already declared; no SDD re-debate. Mitigation: `sdd-propose` cites `phases.apply.strategy: auto-chain` and `phases.apply.review_budget_lines: 800` from `origin/main`'s `openspec/config.yaml` verbatim; `sdd-tasks` reads `phases.apply.test_command: bash scripts/test.sh` from the same source.
- **Erlang `erl_crash.dump` at repo root**: a leftover from a prior session's Mix crash. Mitigation: included in `git clean -fdx` removal list.
- **CocoaPods absent (iOS native builds blocked)**: scaffold `openspec/config.yaml` declares `e2e.available: false` because Expo Go runs the JS bundle only; iOS native builds need CocoaPods which is not in the environment. Mitigation: implementation work stays on Expo Go + JSON API; no native iOS module is added; the smoke `mobile/__tests__/App.smoke.test.tsx` continues to be the mobile verification surface.

### Ready for Proposal

**Yes**, with two preconditions the orchestrator must communicate to the user before launching `sdd-propose`:

1. **The implementation branch starts from `origin/main` (HEAD `3383950`).** Local `main` is stale at `0d27786`; the working tree has untracked `mobile/` and `backend/` leftovers from prior sessions. The first step is `git fetch origin` (already done) → `git checkout -b feat/implement-station-attempt-capture origin/main` → `git status` confirmation → `git clean -fdx mobile backend node_modules erl_crash.dump PR_BODY.md PR_BODY_12.md`. The user must confirm the cleanup is acceptable (or rescue any WIP first). Without this step, `sdd-propose` cannot reference the canonical scaffold + contract tree and `sdd-verify` cannot run `bash scripts/test.sh`.

2. **The frozen `#12` contract stays untouched.** The implementation change uses a new capability identifier (`station-attempt-capture-implementation`) and only declares ADDED requirements. `#12`'s archive happens on its own verify gate, after this implementation change verifies.

After the user confirms, the orchestrator should advance to `sdd-propose` with:

- `change-name` = `implement-station-attempt-capture`
- `parent_issue` = `ChordanDev/proyectoMed#10`
- `originating_issue` = `ChordanDev/proyectoMed#19`
- `frozen_contract_reference` = `openspec/changes/capture-pilot-attempt-evidence-lineage/specs/station-attempt-capture/spec.md`
- `implementation_capability_identifier` = `station-attempt-capture-implementation` (separate from the frozen identifier)
- `delivery_strategy` = `auto-chain` (from `openspec/config.yaml`), `review_budget_lines` = 800, with explicit `Chained PRs recommended: Yes`, `Decision needed before apply: No`, `400-line budget risk: Medium`
- `rdd_posture` = `disabled/unmanaged` (per `rdd-defect-workflow` skill default; clone-locally convention); ordinary PR discipline via `branch-pr` + `work-unit-commits`; review-budget enforcement is the only automatic gate
- `tdd_posture` = `strict_tdd: false` (per `openspec/config.yaml`); mandatory test coverage per work unit; harness is wired but no RED-GREEN-REFACTOR gating
- `work_units` = 6 stacked PRs (setup + 4 Phoenix modules + mobile capture client + integration smoke + verify gate; see table above)
- `verify_command` = `bash scripts/test.sh`
- `scenario_coverage_requirement` = all 11 frozen Given/When/Then scenarios must map to at least one ExUnit or Jest test that passes under `bash scripts/test.sh`; documented in `verify-report.md`'s scenario-to-test map and admitted by `gentle-ai sdd-verify-validate`
- `archive_independence_note` = `#12` archives on its own verify gate, independent of this change; this change does NOT modify or archive the frozen `#12` SDD artifacts
