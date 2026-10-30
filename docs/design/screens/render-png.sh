#!/usr/bin/env bash
# Renders every screen mockup in html/ to a 1600x900 PNG in png/ with headless Chrome.
# Usage: docs/design/screens/render-png.sh   (set CHROME to override the browser path)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
profile="$(mktemp -d)"
trap 'rm -rf "$profile"' EXIT

# Headless Chrome writes the screenshot but may not exit, so stop it once the PNG exists.
render() {
  local out="$1" page="$2" png="$here/png/$1.png" pid waited=0
  rm -f "$png"
  "$chrome" --headless=new --disable-gpu --hide-scrollbars --no-first-run \
    --user-data-dir="$profile" --window-size=1600,900 --virtual-time-budget=8000 \
    --screenshot="$png" "file://$here/html/$page" >/dev/null 2>&1 &
  pid=$!
  while [ ! -s "$png" ] && [ "$waited" -lt 60 ]; do sleep 0.5; waited=$((waited + 1)); done
  sleep 0.5
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  if [ -s "$png" ]; then echo "png/$out.png"; else echo "FAILED png/$out.png" >&2; return 1; fi
}

for file in "$here"/html/*.dc.html; do
  name="$(basename "$file" .dc.html)"
  render "$name" "$name.dc.html"
done

# Alternate states, set through URL props (see html/support.js).
render Main--exam-selected "Main.dc.html?startMode=exam"
render BriefTraining--mic-blocked "BriefTraining.dc.html?micBlocked=true"
render BriefExam--mic-blocked "BriefExam.dc.html?state=micBlocked"
render HudTraining--overtime "HudTraining.dc.html?overtime=true"
render HudTraining--voice-lost "HudTraining.dc.html?voice=lost"
render Invalidated--training "Invalidated.dc.html?variant=trainingServer"
render ResultExam--level-1 "ResultExam.dc.html?level=1"
render History--empty "History.dc.html?emptyState=true"
render Quota--subscription "Quota.dc.html?variant=subscription"
