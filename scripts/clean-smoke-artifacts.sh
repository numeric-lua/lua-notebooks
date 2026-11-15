#!/bin/sh
# Remove only the deterministic fixtures created by the notebook smoke tests.
set -eu
SAVE=${LOVR_SAVE_DIR:-$HOME/.local/share/LOVR/lua-notebooks}
rm -f "$SAVE/notebooks/renamed-smoke.luanb"
rm -rf "$SAVE/notebooks/folder-smoke"
echo "cleaned smoke artifacts under $SAVE/notebooks"
