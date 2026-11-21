local root = (arg and arg[0] or "tests/nvim_buffer.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Buffer = require("notebook.nvim.buffer")
local Notebook = require("notebook.model")

local lines, rows = Buffer.encode({
  { kind = "code", source = "print('a')\nprint('b')" },
  { kind = "markdown", source = "# title\n\ntext" },
  { kind = "code", source = "" },
})
assert(#rows == 3 and rows[1].index == 1 and rows[2].index == 2)
local sources = Buffer.decode(lines)
assert(sources[1] == "print('a')\nprint('b')", sources[1])
assert(sources[2] == "# title\n\ntext", sources[2])
assert(sources[3] == "", "empty cell")
local duplicate, order, duplicate_error = Buffer.decode({
  "-- %% cell 1 code", "a", "-- %% cell 1 code", "b",
})
assert(duplicate_error == "duplicate cell marker 1", tostring(duplicate_error))
local before, _, before_error = Buffer.decode({ "stray", "-- %% cell 1 code", "a" })
assert(before_error, "text before marker")
local swapped, swapped_order = Buffer.decode({
  "-- %% cell 2 code", "b", "-- %% cell 1 code", "a",
})
assert(swapped_order[1] == 2 and swapped_order[2] == 1)
assert(swapped[2] == "b" and swapped[1] == "a")
local typed, typed_order, _, typed_kinds = Buffer.decode({
  "-- %% cell 1 markdown", "# title", "-- %% cell 2 code", "print(1)",
})
assert(typed_kinds[1] == "markdown" and typed_kinds[2] == "code")
print("nvim buffer ok")

-- A missing marker is a deletion request, not an automatic delete.  The plan
-- exposes the omitted cells and apply stays fail-closed until the caller
-- explicitly confirms.
local notebook = Notebook.new({ name = "markers.luanb", cells = {
  { kind = "code", source = "one" },
  { kind = "code", source = "two" },
  { kind = "code", source = "three" },
} })
local marker_lines = Buffer.encode(notebook.cells)
-- Remove only the marker for cell 2; its body is absorbed by cell 1.
local without_marker = {}
for _, line in ipairs(marker_lines) do
  if line ~= "-- %% cell 2 code" then
    without_marker[#without_marker + 1] = line
  end
end
local plan, plan_error = Buffer.plan(notebook.cells, without_marker)
assert(plan ~= nil, tostring(plan_error))
assert(#plan.missing == 1 and plan.missing[1] == 2, "missing cell 2")
assert(plan.sources[1] == "one\ntwo", plan.sources[1])
local rejected, reject_error = Buffer.apply(notebook, plan)
assert(rejected == nil, "unconfirmed deletion must fail closed")
assert(reject_error == "missing marker for cell 2", tostring(reject_error))
assert(#notebook.cells == 3 and notebook.cells[2].source == "two",
  "failed apply must not mutate the notebook")

local applied, apply_error = Buffer.apply(notebook, plan, { delete_missing = true })
assert(applied ~= nil, tostring(apply_error))
assert(applied.deleted == 1 and applied.changed == true)
assert(#notebook.cells == 2, "cell 2 was explicitly deleted")
assert(notebook.cells[1].source == "one\ntwo", notebook.cells[1].source)
assert(notebook.cells[2].source == "three", notebook.cells[2].source)
assert(notebook.dirty, "explicit deletion marks the notebook dirty")
assert(notebook:undo(), "explicit deletion is undoable")
assert(#notebook.cells == 3 and notebook.cells[2].source == "two",
  "undo restores the deleted cell")

local clean_plan = Buffer.plan(notebook.cells, Buffer.encode(notebook.cells))
assert(clean_plan and #clean_plan.missing == 0 and clean_plan.added == 0)
local extra = Buffer.encode(notebook.cells)
extra[#extra + 1] = "-- %% cell 4 code"
extra[#extra + 1] = "four"
local added_plan = Buffer.plan(notebook.cells, extra)
assert(added_plan and added_plan.added == 1)
local added_ok = Buffer.apply(notebook, added_plan)
assert(added_ok and #notebook.cells == 4 and notebook.cells[4].source == "four",
  "new marker creates a cell")
assert(Buffer.plan(notebook.cells, { "no marker here" }) == nil,
  "text before the first marker is still rejected")
print("nvim marker deletion ok")
