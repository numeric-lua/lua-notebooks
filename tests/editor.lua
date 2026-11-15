local root = (arg and arg[0] or "tests/editor.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Highlight = require("ui.highlight")
local LSP = require("notebook.editor_text")
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
eq(LSP.current_word("alpha beta", 6), "alpha")
assert(#LSP.complete("local alpha = 1") > 10)
eq(LSP.find("abc123", "%d+"), 4)
eq(LSP.find("a.b", "%."), 2)
eq(LSP.find("a[b", "["), 2)
eq(LSP.substitute("one one", "one", "two", false), "two one")
eq(LSP.substitute_pattern("a1 a2", "a%d", "x", true), "x x")
eq(LSP.substitute_pattern("a1 a2", "a%d", "x", false), "x a2")
eq(LSP.substitute("one one", "one", "two", true), "two two")
eq(LSP.substitute("one", "missing", "x", true), "one")
local rename_notebook = { cells = {
  { kind = "code", source = "local old = 1" },
  { kind = "code", source = "print(old + old)" },
} }
eq(LSP.rename(rename_notebook, "old", "new"), 3)
eq(rename_notebook.cells[1].source, "local new = 1")
eq(rename_notebook.cells[2].source, "print(new + new)")
local workspace = { cells = {
  { kind = "code", source = "local workspace_symbol = 1" },
} }
local completions = LSP.complete_notebook(workspace, "print")
local found = false
for _, item in ipairs(completions) do
  if item == "workspace_symbol" then found = true end
end
eq(found, true)
eq(LSP.hover("print") ~= nil, true)
eq(LSP.hover("nope"), nil)
local notebook = { cells = { { kind = "code", source = "local target = 1" },
  { kind = "code", source = "target = 2" } } }
local definition = LSP.find_definition(notebook, "target")
eq(definition.cell, 1)
eq(definition.line, 1)
print("editor/lsp tests ok")
