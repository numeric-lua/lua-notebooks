-- Guard the committed visual baselines and the demo cells they render.
--
-- The pixel comparison itself lives in scripts/visual-baseline.sh because it
-- needs LÖVR and a display.  This pure-Lua check catches the cheap mistakes:
-- a demo edit that shifts the baseline cell indices, or a baseline image that
-- was deleted, truncated, or replaced with a different canvas size.
local script = arg and arg[0] or "tests/visual_baseline.lua"
local root = script:match("^(.*)[/\\]tests[/\\][^/\\]+$") or "."
if root == "" then root = "." end
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local Notebook = require("notebook.model")

local expected = {
  { index = 4, marker = 'title = "sin(x)"', name = "sin scene" },
  { index = 6, marker = 'title = "weekly totals"', name = "bar scene" },
  { index = 7, marker = 'title = "histogram"', name = "histogram scene" },
}
local expected_width, expected_height = 640, 400
local signature = "\137PNG\r\n\26\n"

local function be32(data, offset)
  return data:byte(offset) * 16777216 + data:byte(offset + 1) * 65536 +
    data:byte(offset + 2) * 256 + data:byte(offset + 3)
end

local cells = Notebook.demo()[1].cells
for _, item in ipairs(expected) do
  local cell = cells[item.index]
  assert(cell ~= nil, "demo is missing baseline cell " .. item.index)
  assert(cell.source:find(item.marker, 1, true),
    string.format("baseline cell %d is no longer the %s", item.index,
      item.name))

  local path = string.format("%s/tests/visual/baseline/cell%d.png", root,
    item.index)
  local handle = assert(io.open(path, "rb"), "missing visual baseline " .. path)
  local data = handle:read("*a")
  handle:close()
  assert(data:sub(1, #signature) == signature,
    "visual baseline is not a PNG: " .. path)
  assert(#data >= 24, "truncated visual baseline: " .. path)
  local width, height = be32(data, 17), be32(data, 21)
  assert(width == expected_width and height == expected_height,
    string.format("visual baseline %s is %dx%d, expected %dx%d", path, width,
      height, expected_width, expected_height))
end

print("visual baseline guard ok: cells 4, 6, 7")
