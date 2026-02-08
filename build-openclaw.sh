#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
cd "$SCRIPT_DIR"
LOG="/tmp/openclaw-gateway.log"
PROXY_DIR="$HOME/proxy-openclaw"

echo "==> Syncing with upstream..."
git fetch upstream
git rebase upstream/main

echo "==> Pushing to fork..."
git push origin main --force-with-lease

echo "==> Installing dependencies..."
pnpm install

echo "==> Building UI..."
pnpm ui:build

echo "==> Building project..."
pnpm build

echo "==> Stopping existing gateway..."
pkill -f "openclaw.*gateway" || true
sleep 2

echo "==> Starting gateway..."
rm -f "$LOG"
nohup pnpm openclaw gateway --port 18789 --bind lan --verbose > "$LOG" 2>&1 &
GATEWAY_PID=$!

# Gateway does a dev build on first run, give it time
echo "    Waiting for gateway to bind (up to 60s)..."
for i in $(seq 1 12); do
  if ss -ltnp | grep -q ":18789 "; then
    echo "==> Gateway is listening (PID: $GATEWAY_PID)"
    break
  fi
  if ! kill -0 "$GATEWAY_PID" 2>/dev/null; then
    echo "==> ERROR: Gateway process died. Check $LOG"
    exit 1
  fi
  sleep 5
done

if ! ss -ltnp | grep -q ":18789 "; then
  echo "==> ERROR: Gateway did not bind to port 18789 within 60s. Check $LOG"
  exit 1
fi

echo "==> Restarting proxy stack..."
sg docker -c "docker compose -f $PROXY_DIR/docker-compose.yml up -d"

echo "==> Done."
echo "    Gateway logs: tail -f $LOG"
echo "    Proxy logs:   docker compose -f $PROXY_DIR/docker-compose.yml logs -f"
echo "    UI:           https://clawd.eaglet.nl"
