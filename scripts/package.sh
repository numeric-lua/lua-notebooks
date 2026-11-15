#!/bin/sh
# Build a runnable LÖVR archive.  LÖVR accepts a zip file as its source.
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/dist/lua-notebooks.zip"
rm -rf "$ROOT/dist"
mkdir -p "$ROOT/dist"
cd "$ROOT"
zip -q -r "$OUT" \
  conf.lua main.lua README.md LICENSE \
  notebook kernel ui extensions
echo "wrote $OUT"
unzip -l "$OUT" | tail -3
