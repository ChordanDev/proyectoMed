## Exploration: scaffold-expo-phoenix-runtime

### Current State

Planning/specification-only repository. Source of truth is GitHub Issues on `ChordanDev/proyectoMed`. `openspec/config.yaml` declares `strict_tdd: false` and lists every testing capability (`runner`, `unit`, `integration`, `e2e`, `coverage`, `linter`, `type_checker`, `formatter`) as `unavailable`. There is no `package.json`, `mix.exs`, source tree, `CONTEXT.md`, or `docs/adr/` directory. `openspec/specs/` is empty. The only completed SDD change is `capture-pilot-attempt-evidence-lineage` (issue #12, parent #10), which produced a pure artifact contract (delta spec, design, tasks) and a `verify-report.md` that records `verdict: fail` with the explicit root cause: *"No runtime proof exists: all 11 required scenarios lack a passed covering test."*

Local toolchains required to scaffold are already present:

- Node `v26.5.0`, npm `11.17.0`, npx available.
- Elixir `1.20.2` on Erlang/OTP 29; `mix phx.new` reachable.
- `xcodebuild` present, but `pod` (CocoaPods) is not installed.
- `create-expo-app` (current) supports `--template blank-typescript`, `--no-install`, `--no-agents-md`.

The locked #10 chain (#12 → #13 → #14 → #15) and closed tickets #2–#9 supply every product/clinical/privacy/policy input that the eventual implementation must obey, but they do not pick a stack framework version, a database adapter, a logging library, or a deployment target. Those choices remain open and are NOT the concern of this change.

The verify-report for #12 explicitly recommends: *"A follow-up runnable-stack change should add source paths plus focused lifecycle, lineage, timing, interruption, binding, access-control, and raw-audio rejection tests before this capability is implemented or archived."* That recommendation is the trigger for this change.

### Affected Areas

- `openspec/changes/scaffold-expo-phoenix-runtime/exploration.md` — this file (new).
- `openspec/changes/scaffold-expo-phoenix-runtime/proposal.md` — produced by `sdd-propose` (not yet written).
- `openspec/changes/scaffold-expo-phoenix-runtime/specs/<capability>/spec.md` — delta spec under a new `runtime-scaffold` (or `expo-phoenix-runtime`) capability.
- `openspec/changes/scaffold-expo-phoenix-runtime/design.md`, `tasks.md`, `verify-report.md` — follow-on phases.
- `mobile/` — new Expo React Native app (created by `npx create-expo-app mobile --template blank-typescript`).
- `backend/` — new Phoenix API (created by `mix phx.new backend --no-html --no-ecto --no-tailwind --no-assets --no-gettext --no-mailer --no-dashboard --no-install`).
- `openspec/config.yaml` — update `testing.capabilities` to reflect the new harness (runner, unit, integration, linter, type_checker, formatter become available; e2e and coverage remain unavailable with rationale).
- `openspec/config.yaml` — populate `phases.apply.test_command` and `phases.verify.test_command` with the new commands so subsequent SDD phases can reach a `verdict: pass`.
- `.gitignore` — extend from its current single-line (`.atl/`) to cover `node_modules/`, `_build/`, `deps/`, `priv/static/assets/`, `*.beam`, `.elixir_ls/`, `.exenv/`, `mobile/.expo/`, etc.
- `README.md` (new, root) — documents `mobile/` and `backend/` run/test commands for human and agent reviewers.
- GitHub issues `#12`, `#13`, `#14`, `#15` — body MUST NOT be edited. No new comments required. This change is independently scoped; it does not depend on #12 acceptance and does not unblock it semantically — it only provides the harness a future "implement #12 contract" change can write executable tests against.
- `docs/PRD.md` — referenced for stack intent (Expo + Phoenix); not modified.

### Approaches

1. **Default generator scaffolds with explicit minimum flags** — run `npx create-expo-app mobile --template blank-typescript` and `mix phx.new backend --no-html --no-ecto --no-tailwind --no-assets --no-gettext --no-mailer --no-dashboard --no-install`. Add one passing baseline test in each side (`mobile/__tests__/` placeholder smoke test using the already-wired `jest-expo`, default Phoenix generated tests in `backend/test/`). Update `.gitignore`, add root `README.md`, refresh `openspec/config.yaml` testing capabilities and test commands.
   - Pros: smallest review surface that is still genuinely runnable; zero hand-rolled config that could mask bugs; community defaults align with PRD's stated Expo + Phoenix intent; both generators ship with working Jest (Expo) and ExUnit (Phoenix) harnesses out of the box; `--no-ecto` honestly defers a database decision that #6/#10 imply but do not codify; backend still boots as a JSON API and serves a `GET /` placeholder, mobile boots in Expo Go without native build steps, sidestepping the missing CocoaPods.
   - Cons: pulls template opinions (TS strictness, default ESLint config, default EEx view layer removed); `--no-ecto` postpones a real persistence decision that #13 evaluation will eventually need; the Phoenix `--no-html` flag removes the HTML pipeline that some future "console for clinicians" PRD section hints at (deferred — see Open Questions).
   - Effort: **Low** (apply will be small enough to fit a single review slice, ~150–250 lines of authored diff on top of the generated bulk that is mechanically created by the generators).

2. **Opinionated monorepo with custom tooling** — hand-curate `package.json`, `tsconfig.json`, `mix.exs`, Husky hooks, lint-staged, custom Jest config, custom ExUnit aliases, turbo/pnpm workspace, root-level `Makefile` running both test suites.
   - Pros: production-grade ergonomics, single command for everything.
   - Cons: multiplies review surface well past the 400-line review guard; introduces tooling choices (pnpm vs npm, turbo vs none, Husky vs Lefthook) that are explicitly out of scope; risks tangling this change with subsequent ones; requires live network access to bootstrap; fights "smallest viable vertical".
   - Effort: **High**.

3. **Hand-rolled minimal scaffold (no generators)** — write `package.json`, `metro.config.js`, `babel.config.js`, `app.json`, `tsconfig.json`, `mix.exs`, `config/*`, `lib/*` from scratch.
   - Pros: total control of every byte.
   - Cons: Expo has many inter-locking config files (`metro`, `babel`, `app.json` schema); hand-rolling is error-prone for SDK 51+; Phoenix generator produces safe config based on current OTP/Plug versions; review surface balloons; the orchestrator's "smallest viable vertical" instruction is violated.
   - Effort: **Medium**.

### Recommendation

**Approach 1 — default generator scaffolds with explicit minimum flags.**

Rationale:

- It is the only option that (a) produces a *runnable* Expo + Phoenix stack immediately, (b) keeps the authored diff under the 400-line budget without chained PRs, (c) defers every decision that the PRD marks open (database adapter, deployment target, view layer), and (d) gives `sdd-verify` real test commands for downstream changes (#13, #14, #15) to exercise the existing delta spec.
- The generated bulk is mechanically produced by community-maintained tools; reviewers focus on the *committed config edits* (`.gitignore`, `openspec/config.yaml`, `README.md`, baseline tests), not on regenerable boilerplate.
- Both generators ship with working test harnesses already (`jest-expo` for mobile, `mix test`/`ExUnit` for Phoenix), so the deliverable can satisfy `phases.verify.gates` for this change with actual passing tests, not artifact tracing.
- `--no-ecto` is the honest way to flag that persistence is undecided. Any choice here would silently leak into #12/#13 contracts.
- The missing CocoaPods is irrelevant for Expo Go development and unit testing; if/when a native module is needed, a follow-up change adds the iOS native project.

Concretely, the apply phase will:

1. Run the two generators with the flags above (no application code authored by hand for the generators' output).
2. Install JS deps with `npm install` and Elixir deps with `mix deps.get` in the respective subdirectories.
3. Add **one baseline smoke test per side** (`mobile/__tests__/smoke.test.ts` asserting the root component renders; `backend/test/smoke_test.exs` asserting the generated `GET /` returns 200). These are not #12 behavior — they only prove the harness works.
4. Update `openspec/config.yaml` `testing.capabilities` (runner, unit, integration, linter, type_checker, formatter → `available` with command; e2e, coverage → remain `unavailable` with rationale).
5. Populate `phases.apply.test_command` and `phases.verify.test_command` with project-root scripts (see Risks for the exact shape).
6. Extend `.gitignore` (currently only `.atl/`) to ignore generated artifacts.
7. Add a root `README.md` documenting how to run/test each side independently.
8. No GitHub mutations, no `#12` body edits, no application code beyond the baseline tests.

### Risks

- **Toolchain drift**: `create-expo-app` and `phx.new` both move with SDK/Erlang versions; pinning template versions in `package.json` `engines` and `elixir_version`/`otp_version` in `.tool-versions` (or equivalent) is required so a re-run six months from now reproduces the scaffold.
- **Persistence deferral leaks**: `--no-ecto` is a real choice. If a downstream change reintroduces Ecto without a follow-up SDD change, the PRD's "version-bound pseudonymous minimal telemetry" contract could be implemented inconsistently. Mitigation: add an explicit `Out of Scope` line to the proposal and a TODO in `backend/README.md` referencing the future Ecto change.
- **Review budget**: generated bulk (`mobile/`, `backend/`) is large but mostly mechanical. `sdd-tasks` MUST forecast the *authored* diff (config + baseline tests + README + `.gitignore`) against the 400-line budget, not the generated file count. Forecast lines `Decision needed before apply`, `Chained PRs recommended`, `400-line budget risk` are still mandatory.
- **Two toolchains = two test commands**: a single review slice must pick *one* command (mobile OR backend) as `phases.verify.test_command` OR run both in series and gate on `npm test && (cd backend && mix test)`. Series is safer; record the exit code of both. Add a tiny `scripts/test.sh` to keep the command deterministic.
- **`strict_tdd: false` until harness exists**: this change flips harness availability to `available`, but `strict_tdd` should remain `false` until a real capability change (e.g., an implement-#12 follow-up) proves the harness under TDD. Do not flip the flag in this change.
- **CocoaPods missing**: iOS native builds cannot run locally. Document this in README; Expo Go and Android emulator are sufficient for unit + smoke tests.
- **PRD vocabulary drift**: PRD names the stack as "Expo React Native + Elixir/Phoenix" but does not name Postgres, so `--no-ecto` is consistent. If PRD is later amended to require Postgres, this change must be re-evaluated, not silently extended.
- **Scope independence from #12**: the contract for `station-attempt-capture` MUST NOT appear in this change's spec, design, or tasks. Baseline tests only verify "the harness runs", not "an attempt can be created". Verify-report must explicitly assert scope independence.

### Ready for Proposal

Yes. The change is independently scoped (it does not depend on #12 acceptance), the generators are available on the host, the artifact contract from #12 explicitly recommends this follow-up, and the recommended approach stays well under the 400-line authored-diff budget. The orchestrator should advance to `sdd-propose` with:

- capability = `runtime-scaffold` (new, separate from `station-attempt-capture`).
- parent issue = none (no GitHub ticket for this change — it is an internal infrastructure prerequisite; the change folder itself documents the intent).
- originating issue = none (no `#12` body edits, no comments).
- downstream unblock = provides the test harness that a future "implement #12 capability" SDD change will need to write executable tests against; does not unblock #12 itself.
- delivery posture = `auto-chain`, 800-line review budget. `sdd-tasks` should still emit the standard forecast lines (`Decision needed before apply: No`, `Chained PRs recommended: No`, `400-line budget risk: Low`).
- TDD posture = `strict_tdd: false` retained; harness becomes `available`, but the discipline switch is left to the change that actually implements #12.
- scope guardrail = explicit `Out of Scope` clause in the proposal covering: any #12 contract semantics, GitHub mutations, persistence/database selection, deployment target, view layer (HTML, LiveView, EEx), authentication provider, voice/STT/TTS provider selection.
