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

-- Cross-cell language features
local uri2 = "luanb:///a.luanb?cell=c2"
server:handle({ jsonrpc = "2.0", method = "textDocument/didOpen", params = {
  textDocument = { uri = uri2, text = "local shared = 1\nprint(shared)", version = 1 },
} })
local definition = server:handle({ jsonrpc = "2.0", id = 10,
  method = "textDocument/definition", params = {
    textDocument = { uri = uri2 }, position = { line = 1, character = 8 },
  } })
assert(definition.result and #definition.result >= 1)
local references = server:handle({ jsonrpc = "2.0", id = 11,
  method = "textDocument/references", params = {
    textDocument = { uri = uri2 }, position = { line = 1, character = 8 },
    context = { includeDeclaration = true },
  } })
assert(references.result and #references.result >= 2)
local rename = server:handle({ jsonrpc = "2.0", id = 12,
  method = "textDocument/rename", params = {
    textDocument = { uri = uri2 }, position = { line = 1, character = 8 },
    newName = "renamed",
  } })
assert(rename.result and rename.result.changes[uri2])

local uri3 = "luanb:///a.luanb?cell=c3"
server:handle({ jsonrpc = "2.0", method = "textDocument/didOpen", params = {
  textDocument = { uri = uri3, text = "local x = 1\ndo\n  local x = 2\n  print(x)\nend\nprint(x)", version = 1 },
} })
local scoped_rename = server:handle({ jsonrpc = "2.0", id = 13,
  method = "textDocument/rename", params = {
    textDocument = { uri = uri3 }, position = { line = 2, character = 8 },
    newName = "inner",
  } })
assert(scoped_rename.result and scoped_rename.result.changes[uri3])
assert(#scoped_rename.result.changes[uri3] == 2,
  #scoped_rename.result.changes[uri3])

local refs_inner = server:handle({ jsonrpc = "2.0", id = 14,
  method = "textDocument/references", params = {
    textDocument = { uri = uri3 }, position = { line = 3, character = 8 },
    context = { includeDeclaration = true },
  } })
assert(#refs_inner.result == 2, #refs_inner.result)
local definition_inner = server:handle({ jsonrpc = "2.0", id = 15,
  method = "textDocument/definition", params = {
    textDocument = { uri = uri3 }, position = { line = 3, character = 8 },
  } })
assert(definition_inner.result and #definition_inner.result == 1)
assert(definition_inner.result[1].range.start.line == 2,
  definition_inner.result[1].range.start.line)
local shutdown = server:handle({ jsonrpc = "2.0", id = 3, method = "shutdown", params = json.null })
eq(shutdown.result, json.null)
print("lsp protocol tests ok")
