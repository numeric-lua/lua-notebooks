local root = (arg and arg[0] or "tests/lsp_protocol.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local json = require("notebook.json")
local Framing = require("notebook.lsp.framing")
local Server = require("notebook.lsp.server")
local function eq(a, b) if a ~= b then error(tostring(a) .. " ~= " .. tostring(b), 2) end end

local decoder = Framing.new_decoder()
local frame = Framing.encode({ jsonrpc = "2.0", id = 1, method = "initialize", params = {} })
local messages = decoder:feed(frame:sub(1, 7))
eq(#messages, 0)
messages = decoder:feed(frame:sub(8))
eq(#messages, 1)
eq(messages[1].method, "initialize")

local published = {}
local server = Server.new({ publish = function(message) published[#published + 1] = message end })
local init = server:handle({ jsonrpc = "2.0", id = 1, method = "initialize", params = {} })
eq(init.result.capabilities.hoverProvider, true)
server:handle({ jsonrpc = "2.0", method = "initialized", params = {} })
server:handle({ jsonrpc = "2.0", method = "textDocument/didOpen", params = {
  textDocument = { uri = "luanb:///a.luanb?cell=c1", text = "if then", version = 1 },
} })
eq(#published, 1)
eq(published[1].params.diagnostics[1].severity, 1)
local completion = server:handle({ jsonrpc = "2.0", id = 2,
  method = "textDocument/completion", params = {
    textDocument = { uri = "luanb:///a.luanb?cell=c1" }, position = { line = 0, character = 0 },
  } })
assert(#completion.result.items > 5)
local shutdown = server:handle({ jsonrpc = "2.0", id = 3, method = "shutdown", params = json.null })
eq(shutdown.result, json.null)
print("lsp protocol tests ok")
