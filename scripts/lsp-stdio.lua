#!/usr/bin/env luajit
--
-- Standalone JSON-RPC LSP server over stdio.
--
local script = (arg and arg[0]) or "scripts/lsp-stdio.lua"
local root = script:match("^(.*)[/\\]scripts[/\\][^/\\]+$") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local Framing = require("notebook.lsp.framing")
local Server = require("notebook.lsp.server")

local function send(message)
  if message == nil then return end
  io.write(Framing.encode(message))
  io.flush()
end

local server = Server.new({
  publish = send,
  log = function(message) io.stderr:write(tostring(message) .. "\n") end,
})
local decoder = Framing.new_decoder()
local stopped = false

while not stopped do
  local chunk = io.read(4096)
  if chunk == nil then break end
  local messages, decode_error = decoder:feed(chunk)
  for _, message in ipairs(messages) do
    local response = server:handle(message)
    send(response)
    if message.method == "exit" then stopped = true end
  end
  if decode_error then
    io.stderr:write("lsp framing error: " .. tostring(decode_error) .. "\n")
    os.exit(1)
  end
end
