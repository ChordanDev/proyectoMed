```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:83ad3f36997f57662b16205f282c7e7062efcc06e3d68f1075ba23aa69de29c9
verdict: fail
blockers: 1
critical_findings: 0
requirements: 5/6
scenarios: 11/12
test_command: "bash scripts/test.sh"
test_exit_code: 0
test_output_hash: not-recorded
build_command: "npm --prefix mobile exec -- tsc --noEmit && ( cd backend && mix compile --warnings-as-errors ) && ( cd backend && mix format --check-formatted )"
build_exit_code: 0
build_output_hash: not-recorded
```

## Verification Report

**Change**: scaffold-expo-phoenix-runtime
**Version**: N/A (delta spec)
**Mode**: Standard (`strict_tdd: false`)

### Completeness

| Metric | Value |
|---|---:|
| Tasks total | 12 |
| Tasks complete | 11 |
| Tasks incomplete | 1 |

The runtime artifacts have been restored and bounded automated verification passes. Task 4.2 remains incomplete: its Expo Go startup check is a manual/device-oriented check and was not run as part of this bounded remediation.

### Build & Tests Execution

**Tests**: ✅ Passed — `bash scripts/test.sh` ran the mobile Jest smoke suite followed by the Phoenix ExUnit suite.

```text
Test Suites: 1 passed, 1 total
Tests:       1 passed, 1 total
Result: 3 passed
```

- Exact command: `bash scripts/test.sh`
- Exit code: `0`
- Output hash: not recorded for this bounded remediation.
- Mobile Jest and Phoenix ExUnit both executed.

**Additional harness evidence**:

| Command | Exit | Result | Output SHA-256 |
|---|---:|---|---|
| `bash tests/scripts/scaffold_red.sh` | 0 | 16 passed, 0 failed; exercises a scratch fixture and does not mutate runtime directories | not recorded |
| `bash tests/scripts/test_red.sh` | 0 | 3 passed, 0 failed | not recorded |

The safety harness exercises a scratch fixture and does not mutate the real `mobile/` or `backend/` runtime directories.

**Build / static checks**: ✅ Passed — the mobile TypeScript check and backend compile/format checks completed.

```text
No application warnings or formatting failures.
```

- Exact command: `npm --prefix mobile exec -- tsc --noEmit && ( cd backend && mix compile --warnings-as-errors ) && ( cd backend && mix format --check-formatted )`
- Exit code: `0`
- Output hash: not recorded for this bounded remediation.

**Coverage**: ➖ Not available; `openspec/config.yaml` declares coverage unavailable.

### Spec Compliance Matrix

| Requirement | Scenario | Covering runtime test | Result |
|---|---|---|---|
| Reproducible Mobile Runtime | Mobile boots under Expo Go | Manual check not run | ⚠️ UNTESTED |
| Reproducible Mobile Runtime | No native project directories committed | Filesystem inspection | ✅ PASS |
| Reproducible Backend Runtime | Backend returns 200 JSON on root | `health_controller_test.exs` | ✅ PASS |
| Reproducible Backend Runtime | Backend excludes persistence and view tooling | `backend/mix.exs` inspection | ✅ PASS |
| Root Test Orchestration | Root script passes when both suites pass | `bash scripts/test.sh` | ✅ PASS |
| Root Test Orchestration | Root script fails when any suite fails | `bash tests/scripts/test_red.sh` | ✅ PASS |
| Baseline Smoke Coverage Per Runtime | Mobile smoke passes in isolation | `npm --prefix mobile test -- --runInBand` | ✅ PASS |
| Baseline Smoke Coverage Per Runtime | Backend smoke passes in isolation | `mix --cd backend test` | ✅ PASS |
| Pinned Toolchain Constraints | Mobile declares Node and npm engines | `mobile/package.json` inspection | ✅ PASS |
| Pinned Toolchain Constraints | Backend declares Elixir and OTP versions | `backend/.tool-versions` inspection | ✅ PASS |
| Developer Setup And Limitation Guidance | README documents setup, run, and test | README inspection | ✅ PASS |
| Developer Setup And Limitation Guidance | iOS native limitation is documented | README inspection | ✅ PASS |

**Compliance summary**: 11/12 scenarios are verified by bounded automated checks. The Expo Go startup scenario remains pending manual verification, so this report remains non-final.

### Correctness (Static Evidence)

| Requirement | Status | Notes |
|---|---|---|
| Reproducible Mobile Runtime | ⚠️ Partial | The blank TypeScript app and smoke test are present; Expo Go startup remains manual. |
| Reproducible Backend Runtime | ✅ Present | JSON `GET /` health endpoint is covered by ExUnit. |
| Root Test Orchestration | ✅ Passing | `scripts/test.sh` completed both runtime suites. |
| Baseline Smoke Coverage Per Runtime | ✅ Present | Both baseline smoke suites pass in isolation. |
| Pinned Toolchain Constraints | ✅ Present | Both package lockfiles and toolchain declarations are committed paths. |
| Developer Setup And Limitation Guidance | ✅ Present | README and root `.gitignore` retain the documented runtime guidance. |

### Coherence (Design)

| Decision | Followed? | Notes |
|---|---|---|
| Retain generated mobile and backend runtimes | ✅ Yes | Both runtime directories and required lockfiles are present. |
| Isolate scaffold safety checks from real runtime outputs | ✅ Yes | `tests/scripts/scaffold_red.sh` only uses a scratch fixture. |
| Cwd-independent sequential root test script | ✅ Yes | The root script completed mobile Jest followed by Phoenix ExUnit. |
| Managed Expo scope with no native directories | ✅ Yes | `mobile/ios/` and `mobile/android/` are absent. |
| Pinned setup and guidance | ✅ Yes | Package engines, `.tool-versions`, lockfiles, README, and config are present. |

### Issues Found

**PENDING**:

1. Start the app in Expo Go and record the manual result before completing task 4.2 and finalizing verification.

### Verdict

FAIL

Not final: the bounded automated remediation passes, but Expo Go startup was intentionally not run.
