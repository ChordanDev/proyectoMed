#!/usr/bin/env bash
# Hermetic acceptance harness for scripts/test.sh.
#
# PATH-resolved npm and mix stubs prove the exact three phase invocations,
# ordering, and fail-fast exit-code propagation without running real suites.

set -uo pipefail

TEST_FILE="${BASH_SOURCE[0]}"
TESTS_DIR="$(cd "$(dirname "$TEST_FILE")" && pwd -P)"
PROJECT_ROOT="$(cd "$TESTS_DIR/../.." && pwd -P)"
TEST_SH="$PROJECT_ROOT/scripts/test.sh"

PASSED=0
FAILED=0
SCRATCH=""
ORIG_PATH="$PATH"

cleanup_scratch() {
  if [[ -n "${SCRATCH:-}" ]]; then
    rm -rf "$SCRATCH"
    SCRATCH=""
  fi
  PATH="$ORIG_PATH"
}
trap cleanup_scratch EXIT

begin() {
  cleanup_scratch
  SCRATCH="$(mktemp -d -t test_red)" || {
    echo "FATAL: mktemp failed" >&2
    exit 2
  }
  printf "  [%s] " "$1"
}

ok() {
  echo "PASS"
  PASSED=$((PASSED + 1))
}

bad() {
  echo "FAIL -- $*"
  FAILED=$((FAILED + 1))
}

make_suite_stubs() {
  local log="$1" unit_code="$2" backend_code="$3" e2e_code="$4"
  local bin="$SCRATCH/bin"
  mkdir -p "$bin"

  cat >"$bin/npm" <<SH
#!/usr/bin/env bash
case "\$*" in
  "--prefix $PROJECT_ROOT/web run test:unit")
    echo "web-unit" >> "$log"
    exit $unit_code
    ;;
  "--prefix $PROJECT_ROOT/web run test:e2e")
    echo "e2e" >> "$log"
    exit $e2e_code
    ;;
  *)
    echo "unexpected-npm:\$*" >> "$log"
    exit 97
    ;;
esac
SH

  cat >"$bin/mix" <<SH
#!/usr/bin/env bash
if [[ "\$PWD" == "$PROJECT_ROOT/backend" && "\$*" == "test" ]]; then
  echo "backend-exunit" >> "$log"
  exit $backend_code
fi
echo "unexpected-mix:\$PWD:\$*" >> "$log"
exit 98
SH

  chmod +x "$bin/npm" "$bin/mix"
  PATH="$bin:$ORIG_PATH"
}

assert_run() {
  local label="$1" unit_code="$2" backend_code="$3" e2e_code="$4"
  local expected_rc="$5" expected_log="$6"
  begin "$label"

  if [[ ! -x "$TEST_SH" ]]; then
    bad "scripts/test.sh is missing or not executable"
    return
  fi

  local log="$SCRATCH/order.log" rc=0 actual_log=""
  make_suite_stubs "$log" "$unit_code" "$backend_code" "$e2e_code"
  "$TEST_SH" >"$SCRATCH/out" 2>"$SCRATCH/err" || rc=$?
  if [[ -f "$log" ]]; then
    actual_log="$(<"$log")"
  fi

  if [[ "$rc" == "$expected_rc" && "$actual_log" == "$expected_log" ]]; then
    ok
  else
    bad "expected rc/log '$expected_rc'/'${expected_log//$'\n'/, }', got '$rc'/'${actual_log//$'\n'/, }'"
  fi
}

main() {
  echo "Acceptance harness -- root test orchestration"
  echo "Project root:  $PROJECT_ROOT"
  echo "Target script: $TEST_SH"
  echo

  assert_run \
    "all phases run in order" \
    0 0 0 0 \
    $'web-unit\nbackend-exunit\ne2e'
  assert_run \
    "web unit failure propagates and stops later phases" \
    17 0 0 17 \
    "web-unit"
  assert_run \
    "backend failure propagates and stops E2E" \
    0 23 0 23 \
    $'web-unit\nbackend-exunit'
  assert_run \
    "E2E failure propagates exact status" \
    0 0 29 29 \
    $'web-unit\nbackend-exunit\ne2e'

  echo
  echo "Summary: $PASSED passed, $FAILED failed"

  if ((FAILED > 0)); then
    exit 1
  fi

  echo "GREEN state confirmed: every test orchestration invariant holds."
}

main "$@"
