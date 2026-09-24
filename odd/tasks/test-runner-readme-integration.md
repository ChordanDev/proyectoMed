# Test Runner and README Integration

- **Feature:** `test-runner-readme-integration`
- **Issue:** #59
- **Parent issue:** #31
- **Branch:** `feat/59-test-runner-readme-integration`
- **Base:** `origin/feat/31-e2e-integration` at `a871e6a`
- **Merge target:** `feat/31-e2e-integration`
- **Status:** Complete — merged locally into `feat/31-e2e-integration`.
- **Engram mirror:** Pending — local Engram server is incompatible with the installed client.
- **TDD mode:** Disabled by `openspec/config.yaml` (`strict_tdd: false`).
- **Test runner:** `bash scripts/test.sh`
- **Delivery strategy:** `ask-on-risk`; forecast below 400 authored changed lines.

## Objective

Make the standard repository test runner execute the web unit suite, backend ExUnit suite, and the process-level end-to-end scenarios explicitly, then document prerequisites, focused commands, scenarios, and expected failure behavior.

## Scope

- Add explicit web unit and E2E npm scripts while preserving `npm --prefix web test` as the complete web suite.
- Update `scripts/test.sh` to run web unit tests, backend ExUnit, and process-level E2E in a visible order.
- Strengthen `tests/scripts/test_red.sh` so it proves all three phases run and any phase failure exits non-zero without running later phases.
- Update `README.md` with prerequisites, commands, E2E scenarios, expected outcomes, and the process/API boundary.
- Update `openspec/config.yaml` so testing capability metadata matches the implemented E2E harness.

## Constraints

- Keep `bash scripts/test.sh` as the single root test command.
- Preserve `npm --prefix web test` as the complete web test entry point required by repository instructions.
- Do not modify the existing E2E harness or scenario implementation unless verification exposes a defect.
- Keep technical artifacts in English.
- Do not introduce browser automation; the existing suite exercises a real Phoenix process over HTTP with a deterministic local provider mock.

## Tasks

- [x] **ODD-59-1 — Integrate process-level E2E into the standard runner and docs**
  - State: Done.
  - Route: delegated writer; multi-file write trigger (five non-trivial files).
  - Allowed edit surfaces: `web/package.json`, `scripts/test.sh`, `tests/scripts/test_red.sh`, `README.md`, `openspec/config.yaml`, `odd/tasks/test-runner-readme-integration.md`.
  - Acceptance:
    - The root runner visibly executes web unit tests, backend ExUnit, and E2E scenarios.
    - Happy-path, technical-failure, and session-expiry scenarios run through the E2E phase.
    - A failure in any phase propagates a non-zero status and prevents later phases from running.
    - README documents prerequisites, commands, scenarios, and expected outcomes.
    - OpenSpec testing capability metadata reflects the process-level E2E harness.
  - Verification:
    - `bash tests/scripts/test_red.sh`
    - `bash -n scripts/test.sh tests/scripts/test_red.sh`
    - `npm --prefix web run typecheck`
    - `npm --prefix web run lint`
    - `bash scripts/test.sh`
  - Evidence:
    - Commit: `96fc776` (`test(e2e): integrate scenarios into root runner`).
    - Writer verification: all required commands passed.
    - Independent verification: PASS with no blocking findings.
    - Parent spot check: `bash tests/scripts/test_red.sh` passed (4 passed, 0 failed).

- [x] **ODD-59-2 — Merge the completed work unit into the parent feature branch**
  - State: Done.
  - Route: inline Git state operation after verification.
  - Acceptance:
    - The implementation commit exists on `feat/59-test-runner-readme-integration`.
    - Local `feat/31-e2e-integration` contains the verified work through an explicit merge.
  - Evidence:
    - Merge commit: `b3df763` on local `feat/31-e2e-integration`.
    - The parent branch contains implementation commit `96fc776` and verification evidence commit `9634811`.

## Verification evidence

- `bash tests/scripts/test_red.sh`: passed (4 passed, 0 failed) in writer, independent verifier, and parent spot check.
- `bash -n scripts/test.sh tests/scripts/test_red.sh`: passed with no output.
- `npm --prefix web run typecheck`: passed.
- `npm --prefix web run lint`: passed.
- `bash scripts/test.sh`: passed (62 web unit tests, 157 ExUnit tests, 4 process-level E2E tests).
- Native assessment: unassessable because the ODD task document is intentionally untracked; the mandated high-risk fallback independent verifier passed.

## Next step

Push `feat/31-e2e-integration` only when explicitly requested; no remote branches were changed in this work unit.
