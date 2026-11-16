#!/bin/sh
# End-to-end smoke for the local WebSocket kernel gateway.  Node is used only
# as a test client; it is not a project runtime dependency.
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
if ! command -v node >/dev/null 2>&1; then
  echo "remote gateway test skipped: node not found"
  exit 0
fi
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
node - "$PORT" <<'JS'
const port = process.argv[2];
const ws = new WebSocket(`ws://127.0.0.1:${port}`);
const timer = setTimeout(() => { console.error('gateway timeout'); process.exit(1); }, 5000);
ws.onopen = () => {
  ws.send(JSON.stringify({ type: 'open', notebook: 'smoke' }));
  ws.send(JSON.stringify({ type: 'run', notebook: 'smoke', id: 1,
    cell: '1:1', code: "print('remote gateway'); return 6*7" }));
};
ws.onmessage = (event) => {
  const message = JSON.parse(event.data);
  if (message.type !== 'result') return;
  if (!message.ok || message.output !== 'remote gateway' || message.value !== '42') {
    console.error('bad gateway result', message);
    process.exit(1);
  }
  clearTimeout(timer);
  ws.close();
  setTimeout(() => process.exit(0), 50);
};
ws.onerror = () => { console.error('websocket error'); process.exit(1); };
JS
echo "remote gateway ok"
