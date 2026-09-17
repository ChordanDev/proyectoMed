#!/usr/bin/env bash
# tests/scripts/test_red.sh
#
# RED acceptance harness for scripts/test.sh.
# Task 1.3 -- proves scripts/test.sh runs the web Vitest suite before the
# backend Phoenix ExUnit suite, and that it propagates the first non-zero
# fake-suite status as its own exit code.
#
# All assertions fail in PR 1 because scripts/test.sh does not exist yet.
# Phase 3 implementation is expected to turn these assertions GREEN.

set -uo pipefail

# ---------------------------------------------------------------------------
# Test framework
# ---------------------------------------------------------------------------

TEST_FILE="${BASH_SOURCE[0]}"
TESTS_DIR="$(cd "$(dirname "$TEST_FILE")" && pwd -P)"
PROJECT_ROOT="$(cd "$TESTS_DIR/../.." && pwd -P)"
TEST_SH="$PROJECT_ROOT/scripts/test.sh"

PASSED=0
FAILED=0
CURRENT=""

SCRATCH=""
ORIG_PATH="$PATH"

# Called indirectly by the EXIT trap.
# shellcheck disable=SC2329
cleanup_scratch() {
  if [[ -n "${SCRATCH:-}" ]]; then
    rm -rf "$SCRATCH"
    SCRATCH=""
  fi
  PATH="$ORIG_PATH"
}
trap cleanup_scratch EXIT

begin() {
  CURRENT="$1"
  SCRATCH="$(mktemp -d -t test_red)" || {
    echo "FATAL: mktemp failed" >&2
    exit 2
  }
  PATH="$ORIG_PATH"
  printf "  [%s] " "$CURRENT"
}

ok() {
  echo "PASS"
  PASSED=$((PASSED + 1))
}

bad() {
  echo "FAIL -- $*"
  FAILED=$((FAILED + 1))
}

expect_eq() {
  local actual="$1" expected="$2" why="$3"
  if [[ "$actual" == "$expected" ]]; then ok; else bad "$why (expected '$expected', got '$actual')"; fi
}

# Retained as part of the tiny assertion library used by this harness family.
# shellcheck disable=SC2329
expect_path_exists() {
  local path="$1" why="$2"
  if [[ -e "$path" ]]; then ok; else bad "$why (path missing: $path)"; fi
}

expect_log_present() {
  local log="$1" why="$2"
  if [[ -s "$log" ]]; then ok; else bad "$why (log empty: $log)"; fi
}

# Build a single combined log + npm/mix stubs that both append their marker
# to that log when invoked. Lets ordering tests assert on a single source.
make_suite_stubs() {
  local log="$1" npm_code="$2" mix_code="$3"
  local dir="$SCRATCH/bin"
  mkdir -p "$dir"
  cat >"$dir/npm" <<SH
#!/usr/bin/env bash
echo "npm@start" >> "$log"
exit $npm_code
SH
  cat >"$dir/mix" <<SH
#!/usr/bin/env bash
echo "mix@start" >> "$log"
exit $mix_code
SH
  chmod +x "$dir/npm" "$dir/mix"
  echo "$dir"
}

prepend_path() { PATH="$1:$PATH"; }

detect_missing_script() {
  if [[ ! -e "$TEST_SH" ]]; then
    bad "scripts/test.sh absent at $TEST_SH (RED pre-condition: production script must exist for root test orchestrator to enter GREEN)"
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# 1.3 Root test orchestration
# ---------------------------------------------------------------------------

test_web_before_backend_order() {
  begin "1.3.1 web suite runs before backend suite"
  detect_missing_script && return
  local log="$SCRATCH/order.log"
  local bin
  bin="$(make_suite_stubs "$log" 0 0)"
  prepend_path "$bin"
  "$TEST_SH" >"$SCRATCH/out" 2>"$SCRATCH/err" || true

  expect_log_present "$log" "at least one suite logged an invocation"

  if [[ ! -s "$log" ]]; then
    return
  fi

  local npm_pos mix_pos
  npm_pos="$(grep -n '^npm@start' "$log" | head -1 | cut -d: -f1)"
  mix_pos="$(grep -n '^mix@start' "$log" | head -1 | cut -d: -f1)"
  if [[ -z "$npm_pos" || -z "$mix_pos" ]]; then
    bad "either npm or mix was never invoked (npm_pos=$npm_pos, mix_pos=$mix_pos)"
  elif ((npm_pos < mix_pos)); then
    ok
  else
    bad "npm must precede mix in the order log (npm line $npm_pos vs mix line $mix_pos)"
  fi
}

test_first_nonzero_propagates() {
  begin "1.3.2 first non-zero fake-suite status propagates as the script's exit code"
  detect_missing_script && return
  local log="$SCRATCH/order.log"
  local bin
  bin="$(make_suite_stubs "$log" 17 0)"
  prepend_path "$bin"
  local rc=0
  "$TEST_SH" >"$SCRATCH/out" 2>"$SCRATCH/err" || rc=$?
  expect_eq "$rc" "17" "exit code 17 from the web suite must propagate as scripts/test.sh's exit code"
}

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

main() {
  echo "RED harness -- Phase 3 Root Test Orchestration (work unit 1 of stacked chain)"
  echo "Change:        scaffold-expo-phoenix-runtime"
  echo "Project root:  $PROJECT_ROOT"
  echo "Target script: $TEST_SH"
  echo

  test_web_before_backend_order
  test_first_nonzero_propagates

  echo
  echo "Summary: $PASSED passed, $FAILED failed"
  echo

  if ((FAILED > 0)); then
    echo "RED state confirmed: scripts/test.sh is not yet implemented."
    exit 1
  fi

  echo "GREEN state confirmed: every test orchestration invariant holds."
  exit 0
}

main "$@"
