#!/bin/sh
# Headless browser QA for the webapp scene renderer.  Serves the front-end with
# the dependency-free Lua server, renders every scene fixture in Canvas, and
# checks the actual pixels for a non-blank frame plus the series colour.  The
# page and screenshots stay under a scratch directory; nothing is committed.
#
# Usage: scripts/scene-qa.sh
# Requires: luajit, chromium (or chromium-browser).
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${LUANB_QA_OUT:-$(mktemp -d "${TMPDIR:-/tmp}/luanb-scene-qa.XXXXXX")}
mkdir -p "$OUT"
OUT=$(CDPATH='' cd -- "$OUT" && pwd)
CHROME=${CHROMIUM:-$(command -v chromium || command -v chromium-browser || true)}
if [ -z "$CHROME" ]; then
  echo "scene-qa: chromium is required" >&2
  exit 1
fi
command -v luajit >/dev/null 2>&1 || {
  echo "scene-qa: luajit is required" >&2
  exit 1
}
cd "$ROOT"

PORT=${LUANB_QA_PORT:-$((18000 + ($$ % 1000)))}
luajit webapp/serve.lua --host 127.0.0.1 --port "$PORT" --root webapp \
  >"$OUT/serve.log" 2>&1 &
SERVER=$!
cleanup() {
  kill "$SERVER" 2>/dev/null || true
  wait "$SERVER" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

READY=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if grep -Fq "SERVE_READY" "$OUT/serve.log" 2>/dev/null; then
    READY=1
    break
  fi
  sleep 0.2
done
if [ "$READY" != "1" ]; then
  echo "scene-qa: webapp server did not start" >&2
  cat "$OUT/serve.log" >&2
  exit 1
fi

URL="http://127.0.0.1:$PORT/tests/scene-qa.html"
DOM="$OUT/scene-qa.dom.html"
"$CHROME" --headless=new --no-sandbox --disable-gpu --hide-scrollbars \
  --user-data-dir="$OUT/profile" --window-size=760,1200 \
  --virtual-time-budget=4000 --dump-dom "$URL" >"$DOM" 2>"$OUT/chromium.log" || {
  echo "scene-qa: chromium failed" >&2
  cat "$OUT/chromium.log" >&2
  exit 1
}

RESULT="$OUT/scene-qa-result.txt"
sed -n '/<pre id="result">/,/<\/pre>/p' "$DOM" \
  | sed -e 's/<pre id="result">//' -e 's/<\/pre>//' -e 's/<[^>]*>//g' \
  | sed 's/^[[:space:]]*//' >"$RESULT"
if ! grep -Fq "SCENE_QA_OK" "$RESULT" || grep -Fq "SCENE_QA_FAIL" "$RESULT"; then
  echo "scene-qa: browser scene check failed" >&2
  grep '^case=' "$RESULT" >&2 || true
  cat "$OUT/chromium.log" >&2
  exit 1
fi
grep '^case=' "$RESULT" || true
echo "scene-qa ok: $OUT"
