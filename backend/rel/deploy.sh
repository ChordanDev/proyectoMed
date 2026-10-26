#!/usr/bin/env bash
# Routine Phoenix deploy behind the drain gate (#344, docs/operations/deploy.md).
#
#   backend/rel/deploy.sh [fly deploy arguments...]
#
# 1. Lists the app's machines and runs `/app/bin/drain start` on each over
#    `fly ssh console`: POST /sessions answers 503 draining from then on.
# 2. Polls `/app/bin/drain status` every DRAIN_POLL_S seconds (default 15)
#    until no machine has an active session, or DRAIN_CEILING_S seconds
#    (default 720, 12 minutes: a 10-minute station plus margin) have passed.
# 3. Runs `fly deploy` (bluegreen, fly.toml): new machines take new sessions;
#    requests for sessions of the old machines are replayed to them.
# If the drain status cannot be read or the deploy fails, it runs
# `/app/bin/drain stop` on every drained machine and exits non-zero.
#
# FLY_APP overrides the app named in fly.toml.
set -euo pipefail

cd -P -- "$(dirname -- "$0")/.."

app="${FLY_APP:-$(awk -F'"' '/^app *=/ { print $2; exit }' fly.toml)}"
ceiling_s="${DRAIN_CEILING_S:-720}"
poll_s="${DRAIN_POLL_S:-15}"

if [ -z "$app" ]; then
  echo "deploy: no app name (set FLY_APP or app in fly.toml)" >&2
  exit 64
fi

drain() {
  fly ssh console --app "$app" --machine "$1" --command "/app/bin/drain $2"
}

machines=()
while IFS= read -r line; do
  if [[ "$line" =~ ^[a-z0-9]+$ ]]; then machines+=("$line"); fi
done < <(fly machines list --app "$app" --quiet)

drained=()

resume() {
  local machine
  for machine in "${drained[@]+"${drained[@]}"}"; do
    drain "$machine" stop || echo "deploy: could not resume $machine; run /app/bin/drain stop on it" >&2
  done
}

fail() {
  echo "deploy: $1; resuming the drained machines" >&2
  resume
  exit 1
}

for machine in "${machines[@]+"${machines[@]}"}"; do
  drained+=("$machine")
  drain "$machine" start >/dev/null || fail "could not drain $machine"
  echo "deploy: $machine drained (no new sessions)"
done

if [ "${#machines[@]}" -gt 0 ]; then
  start_s=$SECONDS

  while true; do
    total=0

    for machine in "${machines[@]}"; do
      status="$(drain "$machine" status)" || fail "could not read the drain status of $machine"

      if [[ "$status" =~ active_sessions=([0-9]+) ]]; then
        total=$((total + BASH_REMATCH[1]))
      else
        fail "unexpected drain status from $machine: $status"
      fi
    done

    echo "deploy: active sessions: $total"
    [ "$total" -eq 0 ] && break

    if [ $((SECONDS - start_s)) -ge "$ceiling_s" ]; then
      echo "deploy: drain ceiling of ${ceiling_s}s reached with $total active sessions; deploying anyway" >&2
      break
    fi

    sleep "$poll_s"
  done
fi

fly deploy --app "$app" "$@" || fail "fly deploy failed"
echo "deploy: done"
