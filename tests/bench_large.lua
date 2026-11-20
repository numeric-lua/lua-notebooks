local root = (arg and arg[0] or "tests/bench_large.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Notebook = require("notebook.model")
local Format = require("notebook.format")

local cells = {}
for index = 1, 1000 do
  cells[index] = { kind = index % 5 == 0 and "markdown" or "code",
    source = string.format("local value = %d\nprint(value)", index) }
end
local started = os.clock()
local notebook = Notebook.new({ name = "bench", cells = cells })
for _ = 1, 100 do
  notebook:select((notebook.active % #notebook.cells) + 1)
end
local encoded = Format.encode(notebook)
local decoded = Format.decode(encoded)
local elapsed = os.clock() - started
assert(decoded and #decoded.cells == 1000)
print(string.format("large notebook: 1000 cells, encode %d bytes, %.3fs",
  #encoded, elapsed))
assert(elapsed < 5, "large notebook benchmark exceeded 5s")
