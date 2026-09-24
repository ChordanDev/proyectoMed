#!/usr/bin/env bash
# Root test orchestrator for proyectoMed.
#
# Runs the web unit suite, backend ExUnit suite, and process-level E2E suite in
# that order. `set -e` propagates the exact status of the first failed phase and
# prevents every later phase from running. The script is cwd-independent.
#
# Accepted flags: none.

set -euo pipefail

TEST_SH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$TEST_SH")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

WEB_DIR="$ROOT/web"
BACKEND_DIR="$ROOT/backend"

echo "==> Web unit tests"
npm --prefix "$WEB_DIR" run test:unit

echo "==> Backend ExUnit"
( cd "$BACKEND_DIR" && mix test )

echo "==> Process-level E2E scenarios"
npm --prefix "$WEB_DIR" run test:e2e
