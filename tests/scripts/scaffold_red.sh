#!/usr/bin/env bash
# tests/scripts/scaffold_red.sh
#
# RED acceptance harness for scripts/scaffold.sh.
# Phase 1 — Safety Harness, work unit 1 of the stacked PR chain
# (openspec/changes/scaffold-expo-phoenix-runtime/tasks.md).
#
# Every assertion in this file SHOULD fail in PR 1 (RED state) because
# scripts/scaffold.sh does not exist yet. Subsequent PRs implementing
# scripts/scaffold.sh per design.md are expected to turn these assertions
# GREEN without test edits.
#
# The harness uses bash fake generators over PATH so the suite is hermetic:
# no real npm/npx/mix, no real generators, no network access required.
#
# The harness operates against a FIXTURE root under $SCRATCH (not against
# the real $PROJECT_ROOT). The fixture contains a copy of scripts/scaffold.sh
# so its computed project root is the fixture root, and is initialized as a
# git repo so the script's git-root check passes. This isolates the harness
# from the real generated mobile/ and backend/ runtimes: destructive cases
# (target-already-exists, retry-after-partial) cannot damage production
# state, because the production script never sees the real repository root
# from inside the fixture.

set -uo pipefail

# ---------------------------------------------------------------------------
# Test framework
# ---------------------------------------------------------------------------

TEST_FILE="${BASH_SOURCE[0]}"
TESTS_DIR="$(cd "$(dirname "$TEST_FILE")" && pwd -P)"
PROJECT_ROOT="$(cd "$TESTS_DIR/../.." && pwd -P)"
PROD_SCAFFOLD_SH="$PROJECT_ROOT/scripts/scaffold.sh"

PASSED=0
FAILED=0
CURRENT=""

SCRATCH=""
ORIG_PATH="$PATH"
FIXTURE_ROOT=""
FIXTURE_SCAFFOLD_SH=""

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
  SCRATCH="$(mktemp -d -t scaffold_red)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
  PATH="$ORIG_PATH"
  FIXTURE_ROOT="$SCRATCH/proj"
  mkdir -p "$FIXTURE_ROOT/scripts"
  # Canonicalize via cd -P so the path matches what scripts/scaffold.sh
  # computes (it uses `cd -P` which resolves the /var -> /private/var
  # symlink on macOS).
  FIXTURE_ROOT="$(cd "$FIXTURE_ROOT" && pwd -P)"
  cp "$PROD_SCAFFOLD_SH" "$FIXTURE_ROOT/scripts/scaffold.sh"
  chmod +x "$FIXTURE_ROOT/scripts/scaffold.sh"
  ( cd "$FIXTURE_ROOT" && git init -q -b main >/dev/null )
  FIXTURE_SCAFFOLD_SH="$FIXTURE_ROOT/scripts/scaffold.sh"
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

expect_ne() {
  local actual="$1" unwanted="$2" why="$3"
  if [[ "$actual" != "$unwanted" ]]; then ok; else bad "$why (got unwanted '$unwanted')"; fi
}

expect_nonzero() {
  local code="$1" why="$2"
  if [[ "$code" -ne 0 ]]; then
    ok
  else
    bad "$why (expected non-zero exit, got 0)"
  fi
}

expect_path_exists() {
  local path="$1" why="$2"
  if [[ -e "$path" ]]; then ok; else bad "$why (path missing: $path)"; fi
}

expect_path_absent() {
  local path="$1" why="$2"
  if [[ ! -e "$path" ]]; then ok; else bad "$why (path should be absent: $path)"; fi
}

expect_log_present() {
  local log="$1" why="$2"
  if [[ -s "$log" ]]; then ok; else bad "$why (log empty: $log)"; fi
}

expect_log_absent() {
  local log="$1" why="$2"
  if [[ ! -s "$log" ]]; then ok; else bad "$why (log should be empty: $log)"; fi
}

# ---------------------------------------------------------------------------
# Stub builder: drop a single executable that records its invocation in $log
# and exits with the requested status. Optionally append a bash snippet
# executed before the exit so the stub can create files/dirs.
# ---------------------------------------------------------------------------

make_stub() {
  local name="$1" log="$2" code="${3:-0}" extra_cmd="${4:-}"
  local dir
  dir="$(dirname "$log")/bin"
  mkdir -p "$dir"
  {
    echo "#!/usr/bin/env bash"
    echo "echo \"$name invoked\" >> \"$log\""
    [[ -n "$extra_cmd" ]] && echo "$extra_cmd"
    echo "exit $code"
  } > "$dir/$name"
  chmod +x "$dir/$name"
  echo "$dir"
}

prepend_path() { PATH="$1:$PATH"; }

# Detect the "production script missing" failure mode so tests report a
# meaningful RED-state failure instead of leaking a coincidental pass.
detect_missing_script() {
  if [[ ! -e "$PROD_SCAFFOLD_SH" ]]; then
    bad "scripts/scaffold.sh absent at $PROD_SCAFFOLD_SH (RED pre-condition: production script must exist for safety harness to enter GREEN)"
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# 1.1 Git-root authority
# ---------------------------------------------------------------------------

test_git_other_repo_fails() {
  begin "1.1.1 git -C from a different repo fails scaffold"
  detect_missing_script && return
  local other="$SCRATCH/other-repo"
  mkdir -p "$other"
  ( cd "$other" && git init -q >/dev/null )
  local rc=0
  ( cd "$other" && "$FIXTURE_SCAFFOLD_SH" ) >"$SCRATCH/out" 2>"$SCRATCH/err" || rc=$?
  expect_nonzero "$rc" "scaffold.sh must exit non-zero when invoked from a foreign git repo"
  expect_path_absent "$FIXTURE_ROOT/mobile" "fixture mobile/ must not be created"
  expect_path_absent "$FIXTURE_ROOT/backend" "fixture backend/ must not be created"
}

test_relative_and_absolute_resolve_same_root() {
  begin "1.1.2 relative and absolute invocations resolve the same expected root"
  detect_missing_script && return
  local rel_root abs_root
  rel_root="$("$FIXTURE_SCAFFOLD_SH" --print-root 2>/dev/null | head -1)"
  abs_root="$(bash "$FIXTURE_SCAFFOLD_SH" --print-root 2>/dev/null | head -1)"
  if [[ -z "$rel_root" || -z "$abs_root" ]]; then
    bad "scripts/scaffold.sh must support --print-root and emit a non-empty normalized path"
    return
  fi
  expect_eq "$rel_root" "$abs_root" "relative and absolute script invocations must resolve the same canonical root"
  expect_eq "$rel_root" "$FIXTURE_ROOT" "resolved root equals the canonical fixture root"
}

# ---------------------------------------------------------------------------
# 1.2 Fake-command safety cases
# ---------------------------------------------------------------------------

test_no_preflight_mutation() {
  begin "1.2.1 preflight must not mutate target dirs"
  detect_missing_script && return
  local npx_log="$SCRATCH/npx.log" mix_log="$SCRATCH/mix.log"
  local bin
  bin="$(make_stub npx "$npx_log" 0)"
  make_stub mix "$mix_log" 0 >/dev/null
  prepend_path "$bin"
  local rc=0
  ( cd "$FIXTURE_ROOT" && "$FIXTURE_SCAFFOLD_SH" ) >"$SCRATCH/out" 2>"$SCRATCH/err" || rc=$?
  expect_path_absent "$FIXTURE_ROOT/mobile" "preflight must not create mobile/"
  expect_path_absent "$FIXTURE_ROOT/backend" "preflight must not create backend/"
}

test_target_refusal_when_present() {
  begin "1.2.2 refuses to run when target dirs already exist"
  detect_missing_script && return
  mkdir -p "$FIXTURE_ROOT/mobile" "$FIXTURE_ROOT/backend"
  local rc=0
  ( cd "$FIXTURE_ROOT" && "$FIXTURE_SCAFFOLD_SH" ) >"$SCRATCH/out" 2>"$SCRATCH/err" || rc=$?
  expect_nonzero "$rc" "scaffold.sh must exit non-zero when target dirs already exist"
}

test_version_refusal_on_mismatch() {
  begin "1.2.3 refuses mismatched tool versions"
  detect_missing_script && return
  local dir="$SCRATCH/bin"
  mkdir -p "$dir"
  cat > "$dir/npx" <<'SH'
#!/usr/bin/env bash
echo "99.0.0"
exit 0
SH
  cat > "$dir/mix" <<'SH'
#!/usr/bin/env bash
echo "99.99.99"
exit 0
SH
  chmod +x "$dir/npx" "$dir/mix"
  prepend_path "$dir"
  local rc=0
  ( cd "$FIXTURE_ROOT" && "$FIXTURE_SCAFFOLD_SH" ) >"$SCRATCH/out" 2>"$SCRATCH/err" || rc=$?
  expect_nonzero "$rc" "scaffold.sh must exit non-zero on tool version mismatch"
  expect_path_absent "$FIXTURE_ROOT/mobile" "no fixture mobile/ must be generated on version mismatch"
  expect_path_absent "$FIXTURE_ROOT/backend" "no fixture backend/ must be generated on version mismatch"
}

test_failure_propagation() {
  begin "1.2.4 propagates generator exit code"
  detect_missing_script && return
  local npx_log="$SCRATCH/npx.log" mix_log="$SCRATCH/mix.log"
  local bin
  bin="$(make_stub npx "$npx_log" 42)"
  make_stub mix "$mix_log" 0 >/dev/null
  prepend_path "$bin"
  local rc=0
  ( cd "$FIXTURE_ROOT" && "$FIXTURE_SCAFFOLD_SH" ) >"$SCRATCH/out" 2>"$SCRATCH/err" || rc=$?
  expect_ne "$rc" "0" "scaffold.sh must propagate a non-zero generator exit code"
}

test_next_generator_suppression() {
  begin "1.2.5 next generator suppressed after Expo (npx) fails"
  detect_missing_script && return
  local npx_log="$SCRATCH/npx.log" mix_log="$SCRATCH/mix.log"
  local bin
  bin="$(make_stub npx "$npx_log" 1)"
  make_stub mix "$mix_log" 0 >/dev/null
  prepend_path "$bin"
  ( cd "$FIXTURE_ROOT" && "$FIXTURE_SCAFFOLD_SH" ) >"$SCRATCH/out" 2>"$SCRATCH/err" || true
  expect_log_present "$npx_log" "Expo (npx) was attempted first"
  expect_log_absent "$mix_log" "Phoenix (mix) suppressed after Expo failure"
}

test_partial_output_preserved() {
  begin "1.2.6 partial output preserved on later generator failure"
  detect_missing_script && return
  local npx_log="$SCRATCH/npx.log" mix_log="$SCRATCH/mix.log"
  local bin
  bin="$(make_stub npx "$npx_log" 0 "mkdir -p '$FIXTURE_ROOT/mobile'")"
  make_stub mix "$mix_log" 1 >/dev/null
  prepend_path "$bin"
  ( cd "$FIXTURE_ROOT" && "$FIXTURE_SCAFFOLD_SH" ) >"$SCRATCH/out" 2>"$SCRATCH/err" || true
  expect_path_exists "$FIXTURE_ROOT/mobile" "fixture mobile/ preserved after Phoenix failure"
}

test_retry_refusal_after_partial() {
  begin "1.2.7 retry refused when target already exists"
  detect_missing_script && return
  mkdir -p "$FIXTURE_ROOT/mobile"
  local rc=0
  ( cd "$FIXTURE_ROOT" && "$FIXTURE_SCAFFOLD_SH" ) >"$SCRATCH/out" 2>"$SCRATCH/err" || rc=$?
  expect_nonzero "$rc" "scaffold.sh must refuse a retry that would overwrite an existing target"
}

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

main() {
  echo "RED harness -- Phase 1 Safety Harness (work unit 1 of stacked chain)"
  echo "Change:        scaffold-expo-phoenix-runtime"
  echo "Project root:  $PROJECT_ROOT"
  echo "Target script: $PROD_SCAFFOLD_SH (exercised via hermetic fixture under \$SCRATCH)"
  echo

  test_git_other_repo_fails
  test_relative_and_absolute_resolve_same_root
  test_no_preflight_mutation
  test_target_refusal_when_present
  test_version_refusal_on_mismatch
  test_failure_propagation
  test_next_generator_suppression
  test_partial_output_preserved
  test_retry_refusal_after_partial

  echo
  echo "Summary: $PASSED passed, $FAILED failed"
  echo

  # The harness exits zero only in GREEN state. In RED state, at least one
  # assertion per scenario fails, so exit 1 is expected here.
  if (( FAILED > 0 )); then
    echo "RED state confirmed: scripts/scaffold.sh is not yet implemented."
    exit 1
  fi

  echo "GREEN state confirmed: every safety invariant holds."
  exit 0
}

main "$@"
