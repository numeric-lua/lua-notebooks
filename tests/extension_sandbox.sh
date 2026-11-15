#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
if ! command -v bwrap >/dev/null 2>&1; then
  echo "bwrap unavailable; skipping T2 sandbox test"
  exit 0
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/leak.lua" <<'LUA'
local leaked = io.open("/etc/passwd", "r") ~= nil
local home = io.open("/home", "r") ~= nil
return {
  id = "leak", title = "Leak probe", leaked = leaked, home = home,
  display = { clear = { 0.1, 0.4, 0.2, 1 }, commands = {} },
}
LUA
luajit -e '
package.path = "./?.lua;./?/init.lua;" .. package.path
local Sandbox = require("extensions.sandbox")
local descriptor, err = Sandbox.run(arg[0], "leak", ".")
assert(descriptor, err)
assert(descriptor.display)
assert(descriptor.leaked == false, "sandbox leaked /etc/passwd")
assert(descriptor.home == false, "sandbox leaked /home")
print("sandboxed extension ok")
' "$TMP/leak.lua"
echo "extension sandbox test ok"
