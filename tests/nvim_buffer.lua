local root = (arg and arg[0] or "tests/nvim_buffer.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Buffer = require("notebook.nvim.buffer")

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
print("nvim buffer ok")
