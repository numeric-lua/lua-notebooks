#!/bin/sh
# Rebuild the offline LÖVR 0.19 reference pack.
# Requires git, curl, and a matching lovr binary on PATH.
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP=${TMPDIR:-/tmp}/lua-notebooks-lovr-docs
rm -rf "$TMP"
git clone --depth 1 https://github.com/bjornbytes/lovr-docs.git "$TMP"
cp "$TMP"/guides/*.md "$ROOT/docs/lovr/guides/"
cp "$TMP"/README.md "$ROOT/docs/lovr/README.md"
rm -rf "$ROOT/docs/lovr/api/lovr"
cp -r "$TMP"/api/lovr "$ROOT/docs/lovr/api/lovr"
rm -rf "$ROOT/docs/lovr/examples"
cp -r "$TMP"/examples "$ROOT/docs/lovr/examples"
find "$ROOT/docs/lovr/examples" -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.glb' -o -name '*.gltf' -o -name '*.bin' -o -name '*.ktx' -o -name '*.wav' -o -name '*.ogg' -o -name '*.obj' \) -delete
(cd "$TMP" && lovr api cats)
rm -rf "$ROOT/docs/lovr/library"
cp -r "$TMP"/api/cats/library "$ROOT/docs/lovr/library"
cp "$TMP"/api/cats/config.json "$ROOT/docs/lovr/config.json"
echo "updated $ROOT/docs/lovr"
