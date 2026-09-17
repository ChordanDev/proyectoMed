#!/usr/bin/env bash
# scripts/test.sh
#
# Root test orchestrator for proyectoMed.
#
# Runs the web Vitest suite first, then the backend Phoenix ExUnit suite,
# and propagates the first non-zero exit status from either suite. The script
# is cwd-independent: it derives its project root from its own location, not
# from $PWD at invocation time.
#
# Accepted flags: none.
#
# Acceptance contract: tests/scripts/test_red.sh must pass against this
# script without test edits, using fake `npm`/`mix` stubs over PATH.
# In production, both real suites run to completion and the first failure
# exits the script.

set -euo pipefail

# ---------------------------------------------------------------------------
# Root resolution (cwd-independent): the script's grandparent is the root.
# Mirrors scripts/scaffold.sh so both orchestration scripts agree on the
# canonical project root regardless of cwd.
# ---------------------------------------------------------------------------

TEST_SH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$TEST_SH")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

WEB_DIR="$ROOT/web"
BACKEND_DIR="$ROOT/backend"

# ---------------------------------------------------------------------------
# Suite 1: web Vitest
#
# Uses the PATH-resolved `npm` so the test_red harness can substitute a fake
# `npm` and assert ordering/failure propagation without running the real
# Vitest suite.
# ---------------------------------------------------------------------------

npm --prefix "$WEB_DIR" test

# ---------------------------------------------------------------------------
# Suite 2: backend Phoenix ExUnit
#
# Mix does not expose a `--cd` flag; the design's `mix --cd "$root/backend"`
# shorthand maps to a subshell that changes directory before invoking mix.
# The PATH-resolved `mix` lets the test_red harness substitute a fake.
# ---------------------------------------------------------------------------

( cd "$BACKEND_DIR" && mix test )
