#!/usr/bin/env bash
# Usage:
#   ./deploy.sh v1         first run: starts everything, blue goes live
#   ./deploy.sh v2         deploys v2 to the idle color, then switches traffic
#   ./deploy.sh rollback   switches traffic back to the standby color
set -euo pipefail
cd "$(dirname "$0")"

ARG="${1:?Usage: ./deploy.sh <version | rollback>}"
UPSTREAM_FILE="nginx/conf.d/upstream.conf"
ROUTER="nginx-router"
URL="http://localhost:8088"

mkdir -p nginx/conf.d

write_upstream() {
  printf 'upstream app {\n    server app-%s:3000;\n}\n' "$1" > "$UPSTREAM_FILE"
}

wait_healthy() {
  local name="$1" status=""
  echo "==> Waiting for $name to be healthy..."
  for _ in $(seq 1 30); do
    status=$(docker inspect --format '{{.State.Health.Status}}' "$name" 2>/dev/null || true)
    if [ "$status" = "healthy" ]; then
      echo "    $name is healthy"
      return 0
    fi
    if [ "$status" = "unhealthy" ]; then
      break
    fi
    sleep 2
  done
  echo "!! $name did not become healthy. Live traffic was NOT touched."
  docker logs --tail 20 "$name" || true
  exit 1
}

switch_to() {
  write_upstream "$1"
  docker exec "$ROUTER" nginx -t
  docker exec "$ROUTER" nginx -s reload
  echo "==> Traffic now goes to: $1"
}

# ---------- First run: nothing exists yet ----------
if [ ! -f "$UPSTREAM_FILE" ]; then
  if [ "$ARG" = "rollback" ]; then echo "Nothing to roll back yet."; exit 1; fi
  echo "==> First run: starting everything with blue live"
  write_upstream blue
  printf 'BLUE_VERSION=%s\nGREEN_VERSION=%s\n' "$ARG" "$ARG" > .env
  docker compose up -d --build
  wait_healthy app-blue
  wait_healthy app-green
  curl -fsS --retry 5 --retry-connrefused --retry-delay 1 "$URL/health"; echo
  exit 0
fi

# ---------- Which color is live right now? ----------
if grep -q "app-blue" "$UPSTREAM_FILE"; then
  ACTIVE=blue;  IDLE=green
else
  ACTIVE=green; IDLE=blue
fi

# ---------- Rollback ----------
if [ "$ARG" = "rollback" ]; then
  wait_healthy "app-$IDLE"
  switch_to "$IDLE"
  exit 0
fi

# ---------- Normal deploy ----------
VERSION="$ARG"
echo "==> Live: $ACTIVE | deploying $VERSION to: $IDLE"

if [ "$IDLE" = "blue" ]; then VAR=BLUE_VERSION; else VAR=GREEN_VERSION; fi
sed -i.bak "s/^$VAR=.*/$VAR=$VERSION/" .env && rm -f .env.bak

# Rebuild and restart ONLY the idle container. Live traffic is untouched.
docker compose up -d --build --no-deps "app-$IDLE"
wait_healthy "app-$IDLE"

switch_to "$IDLE"

# Smoke test through the router; undo the switch if it fails
if ! curl -fsS --retry 3 --retry-delay 1 "$URL/health" >/dev/null; then
  echo "!! Smoke test failed. Rolling back to $ACTIVE"
  switch_to "$ACTIVE"
  exit 1
fi

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $VERSION live on $IDLE" >> deploy.log
echo "==> Success: $IDLE ($VERSION) is live. $ACTIVE stays on standby for rollback."