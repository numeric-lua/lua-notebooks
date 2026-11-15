local root = (arg and arg[0] or "tests/editor.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Highlight = require("ui.highlight")
local LSP = require("notebook.lsp")
local function eq(a, b)
  if a ~= b then error("expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local tokens = Highlight.line('local x = "hi" -- note')
local kinds = {}
for _, token in ipairs(tokens) do kinds[#kinds + 1] = token.kind end
assert(#tokens > 0)
assert(kinds[1] == "keyword")
assert(tokens[#tokens].kind == "comment")
local saw_string, saw_identifier = false, false
for _, token in ipairs(tokens) do
  if token.kind == "string" then saw_string = true end
  if token.kind == "identifier" and token.text == "x" then saw_identifier = true end
end
assert(saw_string and saw_identifier)
eq(LSP.diagnostics("if then") ~= nil, true)
eq(LSP.diagnostics("return 1"), nil)
eq(LSP.current_word("print(foo"), "foo")
assert(#LSP.complete("local alpha = 1") > 10)
eq(LSP.hover("print") ~= nil, true)
eq(LSP.hover("nope"), nil)
local notebook = { cells = { { kind = "code", source = "local target = 1" },
  { kind = "code", source = "target = 2" } } }
local definition = LSP.find_definition(notebook, "target")
eq(definition.cell, 1)
eq(definition.line, 1)
print("editor/lsp tests ok")
