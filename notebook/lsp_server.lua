--
-- Standalone LSP service over stdio.
--   luajit notebook/lsp_server.lua
-- Frames are Content-Length JSON-RPC messages.
--
local root = (arg and arg[0] or "notebook/lsp_server.lua"):match("^(.*)/notebook/")
  or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local json = require("notebook.json")
local Framing = require("notebook.lsp.framing")
local Server = require("notebook.lsp.server")

local function write(message)
  if message then
    io.write(Framing.encode(message))
    io.flush()
  end
end

local server = Server.new({
  publish = write,
  log = function(message) io.stderr:write(tostring(message) .. "\n") end,
})

while true do
  local headers = {}
  local content_length
  while true do
    local line = io.stdin:read("*l")
    if line == nil then return end
    line = line:gsub("\r$", "")
    if line == "" then break end
    local name, value = line:match("^([^:]+):%s*(.*)$")
    if name and name:lower() == "content-length" then
      content_length = tonumber(value)
    end
  end
  if content_length == nil then
    io.stderr:write("missing Content-Length\n")
    os.exit(1)
  end
  local body = io.stdin:read(content_length)
  if body == nil then os.exit(1) end
  local ok, message = pcall(json.decode, body)
  if not ok then
    write({ jsonrpc = "2.0", id = json.null,
      error = { code = -32700, message = "parse error" } })
  else
    write(server:handle(message))
    if message.method == "exit" then return end
  end
end
