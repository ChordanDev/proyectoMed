#!/usr/bin/env bash
# Runs Unreal automation tests headless and prints the per-test results.
# Usage: scripts/run-unreal-tests.sh [test filter]   (default: ProyectoMed)
# Close the editor first. The Phoenix tests need a local Phoenix; see
# docs/unreal-station-client.md.
set -euo pipefail

FILTER="${1:-ProyectoMed}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/unreal/ProyectoMed.uproject"
ENGINE="${UE_ROOT:-/Users/Shared/Epic Games/UE_5.8}"
EDITOR="$ENGINE/Engine/Binaries/Mac/UnrealEditor.app/Contents/MacOS/UnrealEditor"
LOG="$ROOT/unreal/Saved/Logs/AutomationTests.log"

mkdir -p "$(dirname "$LOG")"
set +e
"$EDITOR" "$PROJECT" -ExecCmds="Automation RunTests $FILTER; Quit" \
  -unattended -nullrhi -nosplash -nosound -NoLogTimes -stdout -FullStdOutLogOutput >"$LOG" 2>&1
STATUS=$?
set -e

# Engine start-up logs errors of its own; report only what the test run logged.
sed -n '/Found [0-9]* automation tests/,$p' "$LOG" \
  | grep -E "Found [0-9]+ automation tests|Test Completed\. Result=|Error: |TEST COMPLETE\. EXIT CODE" || true
echo "Editor exit status: $STATUS (full log: $LOG)"

# Pass only when tests ran, all passed, and the editor exited cleanly: a filter
# that matches nothing also ends with exit code 0.
grep -qE "Found [1-9][0-9]* automation tests" "$LOG" || { echo "No tests matched '$FILTER'."; exit 1; }
grep -q "TEST COMPLETE. EXIT CODE: 0" "$LOG"
[ "$STATUS" -eq 0 ]
