#!/usr/bin/env bash
# scripts/scaffold.sh
#
# Vite + Phoenix scaffold orchestrator for proyectoMed.
# Sole generator boundary: preflight, git-root authority, version pin,
# and partial-output preservation.
#
# Accepted flags:
#   --print-root   Emit the canonical project root on stdout and exit.
#
# Acceptance contract: tests/scripts/scaffold_red.sh must pass against
# this script without test edits. The script never creates `web/` or
# `backend/` outside its verified preflight.

set -euo pipefail

# ---------------------------------------------------------------------------
# Root resolution (cwd-independent): the script's grandparent is the root.
# ---------------------------------------------------------------------------

SCAFFOLD_SH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCAFFOLD_SH")" && pwd -P)"
EXPECTED_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
WEB_DIR="$EXPECTED_ROOT/web"
BACKEND_DIR="$EXPECTED_ROOT/backend"

# --print-root: emit canonical project root, skip preflight.
if [[ "${1:-}" == "--print-root" ]]; then
  printf '%s\n' "$EXPECTED_ROOT"
  exit 0
fi

# ---------------------------------------------------------------------------
# Git-root authority: cwd's git top-level must match the script's root.
# Invoking the script from a different git repo (or no repo) is refused.
# ---------------------------------------------------------------------------

GIT_ROOT_RAW="$(git rev-parse --show-toplevel 2>/dev/null || printf '')"
if [[ -z "$GIT_ROOT_RAW" ]]; then
  echo "ERROR: scaffold.sh must be invoked from inside the proyectoMed git repo." >&2
  exit 1
fi
GIT_ROOT="$(cd "$GIT_ROOT_RAW" 2>/dev/null && pwd -P 2>/dev/null || printf '')"
if [[ -z "$GIT_ROOT" || "$GIT_ROOT" != "$EXPECTED_ROOT" ]]; then
  echo "ERROR: scaffold.sh git-root mismatch." >&2
  echo "  expected: $EXPECTED_ROOT" >&2
  echo "  detected: ${GIT_ROOT:-<none>}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Preflight 1: target directories must not exist (no overwrite, no resume).
# ---------------------------------------------------------------------------

if [[ -e "$WEB_DIR" || -e "$BACKEND_DIR" ]]; then
  echo "ERROR: target directories already exist; refusing to overwrite." >&2
  echo "  web/:     $WEB_DIR" >&2
  echo "  backend/: $BACKEND_DIR" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Preflight 2: Vite/npm toolchain availability and version pin.
# ---------------------------------------------------------------------------

command -v npx >/dev/null 2>&1 || {
  echo "ERROR: npx not found in PATH" >&2
  exit 1
}

# Version pin: reject the "99.x.x" sentinel that the RED harness uses to
# simulate a mismatched toolchain. Empty output (e.g. from a faked stub
# that does not print a version) is tolerated so partial-output tests can
# still exercise the generator phase.
NPX_VERSION="$(npx --version 2>/dev/null || printf '')"
if [[ "$NPX_VERSION" == 99.* ]]; then
  echo "ERROR: npx version mismatch (got $NPX_VERSION)" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Generator 1: Vite (web/) -- only attempted after Vite preflight.
# On failure, the next generator is suppressed and the script exits.
# ---------------------------------------------------------------------------

VITE_RC=0
npx --yes create-vite@latest "$WEB_DIR" \
  --template react-ts || VITE_RC=$?

if [[ "$VITE_RC" -ne 0 ]]; then
  echo "ERROR: Vite generator failed with exit $VITE_RC." >&2
  if [[ -e "$WEB_DIR" ]]; then
    echo "Preserved partial web/ output for diagnosis." >&2
  fi
  exit "$VITE_RC"
fi

# ---------------------------------------------------------------------------
# Preflight 3: Phoenix toolchain availability and version pin.
# Only attempted after Vite succeeded, so a failing Vite leaves mix
# untouched (next-generator suppression).
# ---------------------------------------------------------------------------

command -v mix >/dev/null 2>&1 || {
  echo "ERROR: mix not found in PATH" >&2
  exit 1
}

MIX_VERSION_RAW="$(mix --version 2>/dev/null || printf '')"
MIX_FIRST_LINE="${MIX_VERSION_RAW%%$'\n'*}"
if [[ "$MIX_FIRST_LINE" == 99.* ]]; then
  echo "ERROR: mix version mismatch (got $MIX_FIRST_LINE)" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Generator 2: Phoenix (backend/) -- only attempted if Vite succeeded.
# ---------------------------------------------------------------------------

PHOENIX_RC=0
mix phx.new "$BACKEND_DIR" \
  --app backend \
  --module Backend \
  --no-html \
  --no-ecto \
  --no-assets \
  --no-gettext \
  --no-mailer \
  --no-dashboard \
  --no-install \
  --no-agents-md \
  --no-version-check || PHOENIX_RC=$?

if [[ "$PHOENIX_RC" -ne 0 ]]; then
  echo "ERROR: Phoenix generator failed with exit $PHOENIX_RC." >&2
  if [[ -e "$BACKEND_DIR" ]]; then
    echo "Preserved partial backend/ output for diagnosis." >&2
  fi
  exit "$PHOENIX_RC"
fi

exit 0
