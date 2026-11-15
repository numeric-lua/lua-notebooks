#!/bin/sh
# Local, no-root install of the notebook app.
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
PREFIX=${PREFIX:-$HOME/.local/share/lua-notebooks}
rm -rf "$PREFIX"
mkdir -p "$PREFIX"
cp -R "$ROOT"/conf.lua "$ROOT"/main.lua "$ROOT"/notebook "$ROOT"/kernel \
  "$ROOT"/ui "$ROOT"/extensions "$ROOT"/README.md "$ROOT"/LICENSE "$PREFIX"/
echo "installed $PREFIX"
echo "run: lovr $PREFIX"
