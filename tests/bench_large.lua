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

-- Large polar fields are sampled before painting.  The matrix is built once so
-- the measurement covers collect/resolve and cell projection, not fixture setup.
local Polar = require("notebook.polar")
local ROWS, COLS = 512, 512
local values = {}
for row = 1, ROWS do
  values[row] = {}
  for col = 1, COLS do
    values[row][col] = (row - 1) / (ROWS - 1) +
      0.25 * math.sin((col - 1) * 2 * math.pi / COLS)
  end
end
local scene = {
  type = "luaplotlib", orientation = "polar",
  polar = {
    rmax = 2,
    heatmaps = { {
      rows = ROWS, cols = COLS, values = values,
      vmin = 0, vmax = 1, rmin = 0, rmax = 2,
      theta_min = 0, theta_max = 2 * math.pi, alpha = 1,
    } },
  },
}
started = os.clock()
local resolved
for _ = 1, 10 do resolved = Polar.resolve(scene) end
local blocks = Polar.heatmap_cells(resolved.heatmaps[1], 300, 200, 150,
  resolved.rmax, resolved.theta_zero, resolved.direction)
elapsed = os.clock() - started
assert(resolved.heatmaps[1].sampled)
assert(#blocks <= Polar.HEATMAP_CELL_LIMIT)
print(string.format(
  "large polar field: %dx%d -> %d blocks, 10 resolves %.3fs",
  ROWS, COLS, #blocks, elapsed))
assert(elapsed < 5, "large polar field benchmark exceeded 5s")
