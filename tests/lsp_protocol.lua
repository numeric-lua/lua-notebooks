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

local hover_inner = server:handle({ jsonrpc = "2.0", id = 16,
  method = "textDocument/hover", params = {
    textDocument = { uri = uri3 }, position = { line = 3, character = 8 },
  } })
assert(hover_inner.result and
  hover_inner.result.contents.value:find("local `x`", 1, true),
  hover_inner.result and hover_inner.result.contents.value)

local uri4 = "luanb:///a.luanb?cell=c4"
server:handle({ jsonrpc = "2.0", method = "textDocument/didOpen", params = {
  textDocument = { uri = uri4,
    text = "local cfg = { name = \"x\", count = 1 }\nprint(cfg.name)\ncfg.name = \"y\"",
    version = 1 },
} })
local field_hover = server:handle({ jsonrpc = "2.0", id = 17,
  method = "textDocument/hover", params = {
    textDocument = { uri = uri4 }, position = { line = 1, character = 10 },
  } })
assert(field_hover.result and
  field_hover.result.contents.value:find("field `name`", 1, true),
  field_hover.result and field_hover.result.contents.value)
local field_definition = server:handle({ jsonrpc = "2.0", id = 18,
  method = "textDocument/definition", params = {
    textDocument = { uri = uri4 }, position = { line = 1, character = 10 },
  } })
assert(field_definition.result and #field_definition.result == 1)
assert(field_definition.result[1].range.start.line == 0)
local field_refs = server:handle({ jsonrpc = "2.0", id = 19,
  method = "textDocument/references", params = {
    textDocument = { uri = uri4 }, position = { line = 1, character = 10 },
  } })
assert(#field_refs.result == 3, #field_refs.result)
local field_rename = server:handle({ jsonrpc = "2.0", id = 20,
  method = "textDocument/rename", params = {
    textDocument = { uri = uri4 }, position = { line = 1, character = 10 },
    newName = "title",
  } })
assert(field_rename.result and #field_rename.result.changes[uri4] == 3,
  field_rename.result and #field_rename.result.changes[uri4])
local field_completion = server:handle({ jsonrpc = "2.0", id = 21,
  method = "textDocument/completion", params = {
    textDocument = { uri = uri4 }, position = { line = 3, character = 0 },
  } })
assert(field_completion.result and #field_completion.result.items > 0)
local symbol_uri = "file:///symbols.lua"
server:handle({ jsonrpc = "2.0", method = "textDocument/didOpen", params = {
  textDocument = { uri = symbol_uri, version = 1,
    text = "local function helper()\nend\nfunction module.run()\nend\n" },
} })
local document_symbols = server:handle({ jsonrpc = "2.0", id = 21,
  method = "textDocument/documentSymbol", params = {
    textDocument = { uri = symbol_uri },
  } })
assert(#document_symbols.result == 2, #document_symbols.result)
local workspace_symbols = server:handle({ jsonrpc = "2.0", id = 22,
  method = "workspace/symbol", params = { query = "run" } })
assert(#workspace_symbols.result == 1, #workspace_symbols.result)
local shutdown = server:handle({ jsonrpc = "2.0", id = 3, method = "shutdown", params = json.null })
eq(shutdown.result, json.null)
print("lsp protocol tests ok")
