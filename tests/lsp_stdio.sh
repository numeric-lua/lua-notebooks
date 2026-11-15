#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
INPUT=$(mktemp)
OUTPUT=$(mktemp)
trap 'rm -f "$INPUT" "$OUTPUT"' EXIT
luajit - "$INPUT" > "$INPUT" <<'LUA'
local json = require("notebook.json")
local Framing = require("notebook.lsp.framing")
local frames = {
  { jsonrpc = "2.0", id = 1, method = "initialize", params = {} },
  { jsonrpc = "2.0", method = "initialized", params = {} },
  { jsonrpc = "2.0", method = "textDocument/didOpen", params = {
      textDocument = { uri = "luanb:///a.luanb?cell=c1", text = "if then", version = 1 },
    } },
  { jsonrpc = "2.0", id = 2, method = "textDocument/completion", params = {
      textDocument = { uri = "luanb:///a.luanb?cell=c1" },
      position = { line = 0, character = 0 },
    } },
  { jsonrpc = "2.0", id = 3, method = "shutdown", params = json.null },
  { jsonrpc = "2.0", method = "exit" },
}
for _, frame in ipairs(frames) do io.write(Framing.encode(frame)) end
LUA
luajit notebook/lsp_server.lua < "$INPUT" > "$OUTPUT"
grep -q '"method":"textDocument/publishDiagnostics"' "$OUTPUT"
grep -q '"severity":1' "$OUTPUT"
grep -q '"items"' "$OUTPUT"
echo "lsp stdio tests ok"
