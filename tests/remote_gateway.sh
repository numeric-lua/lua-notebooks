#!/bin/sh
# End-to-end smoke for the local WebSocket gateway and remote supervisor.
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
if ! command -v luajit >/dev/null 2>&1; then
  echo "remote gateway test skipped: luajit not found"
  exit 0
fi
PORT=$((8800 + $$ % 500))
LOG=/tmp/luanb-gateway-$$.log
luajit scripts/kernel-gateway.lua --port "$PORT" >"$LOG" 2>&1 &
PID=$!
cleanup() {
  kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  rm -f "$LOG"
}
trap cleanup EXIT INT TERM
for _ in $(seq 1 50); do
  grep -q GATEWAY_READY "$LOG" 2>/dev/null && break
  sleep 0.1
done
grep -q GATEWAY_READY "$LOG" || { echo "gateway did not start"; cat "$LOG"; exit 1; }
luajit tests/remote_client.lua "$PORT"
