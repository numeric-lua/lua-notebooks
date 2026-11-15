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
if [ "${INSTALL_DESKTOP:-0}" = "1" ]; then
  APPS=${XDG_DATA_HOME:-$HOME/.local/share}/applications
  mkdir -p "$APPS"
  cat > "$APPS/lua-notebooks.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Lua Notebooks
Comment=Native LÖVR notebook workspace
Exec=lovr $PREFIX
Terminal=false
Categories=Development;Science;Education;
DESKTOP
  echo "installed $APPS/lua-notebooks.desktop"
fi
