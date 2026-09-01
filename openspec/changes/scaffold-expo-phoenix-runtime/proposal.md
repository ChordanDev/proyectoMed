# Proposal: Scaffold Expo Phoenix Runtime

## Intent

Establish the smallest runnable Expo React Native and Phoenix foundation so future capability changes have deterministic runtime proof. This adds no clinical or #12 behavior.

## Scope

### In Scope
- Generate `mobile/` as a blank TypeScript Expo app and `backend/` as a JSON-only Phoenix API without Ecto or HTML tooling.
- Add a deterministic project-root test command that runs both mobile Jest and Phoenix ExUnit suites.
- Add one baseline smoke test per runtime, plus ignored generated artifacts.
- Constrain the Node/npm, Expo, Elixir/OTP, and Phoenix toolchain versions required to reproduce the scaffold.
- Document local setup, run, test, and CocoaPods limitation for developers.

### Out of Scope
- #12 (`station-attempt-capture`) semantics or executable contract behavior.
- Database/persistence, deployment, HTML/LiveView/EEx, authentication, voice providers, and GitHub mutations.
- Enabling `strict_tdd`; it remains `false` until a #12 implementation change uses the harness.

## Capabilities

### New Capabilities
- `runtime-scaffold`: A reproducible Expo and Phoenix runtime with baseline test proof and developer operating guidance.

### Modified Capabilities
None.

## Approach

Use default generators with minimal flags: `create-expo-app` blank TypeScript for `mobile/` and `mix phx.new` with `--no-html --no-ecto` and related UI/assets exclusions for `backend/`. Add root orchestration for both test suites, version constraints, smoke tests, `.gitignore` entries, README guidance, and `openspec/config.yaml` harness commands/capabilities while preserving `strict_tdd: false`.

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `mobile/` | New | Generated Expo app and smoke test. |
| `backend/` | New | Generated Phoenix API and smoke test. |
| `scripts/test.sh` | New | Deterministic root test entry point. |
| `openspec/config.yaml` | Modified | Test capabilities and commands; TDD remains disabled. |
| `README.md`, `.gitignore` | New/Modified | Developer guidance and generated-artifact ignores. |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Generator/toolchain drift | Med | Record version constraints and test both runtimes. |
| Native iOS build unavailable | Med | Document CocoaPods limitation; validate Expo/JS smoke tests. |

## Rollback Plan

Revert the scaffold commit and restore `openspec/config.yaml`, `.gitignore`, and README to their prior state; no persisted data or external resources require cleanup.

## Dependencies

- Node/npm, Elixir/OTP, Phoenix generator, and network access for dependency installation.

## Success Criteria

- [ ] A fresh clone can run the documented root test command successfully.
- [ ] Expo and Phoenix smoke tests pass without implementing #12 behavior.
- [ ] Version constraints and local development limitations are documented.
