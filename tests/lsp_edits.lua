local root = (arg and arg[0] or "tests/lsp_edits.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Notebook = require("notebook.model")
local LspEdits = require("notebook.lsp_edits")
local notebook = Notebook.new({ cells = {
  { kind = "code", source = "local old = 1\nprint(old)" },
  { kind = "code", source = "return old" },
} })
local function uri(cell) return "luanb:///a.luanb?cell=" .. cell.id end
local changes = {
  [uri(notebook.cells[1])] = {
    { range = { start = { line = 0, character = 6 }, ["end"] = { line = 0, character = 9 } }, newText = "new" },
    { range = { start = { line = 1, character = 6 }, ["end"] = { line = 1, character = 9 } }, newText = "new" },
  },
  [uri(notebook.cells[2])] = {
    { range = { start = { line = 0, character = 7 }, ["end"] = { line = 0, character = 10 } }, newText = "new" },
  },
}
local count = LspEdits.apply(notebook, changes)
assert(count == 3, count)
assert(notebook.cells[1].source == "local new = 1\nprint(new)")
assert(notebook.cells[2].source == "return new")
notebook:undo()
assert(notebook.cells[1].source == "local old = 1\nprint(old)")
print("lsp edits tests ok")
