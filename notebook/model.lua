--
-- Notebook document model.  Pure Lua so it can be tested without LÖVR.
--
local Notebook = {}
Notebook.__index = Notebook

local function cell(kind, source)
  return {
    kind = kind or "code",
    source = source or "",
    output = "",
    scene = nil,
    running = false,
    error = nil,
  }
end

function Notebook.new(options)
  options = options or {}
  local self = setmetatable({
    name = options.name or "Untitled",
    cells = options.cells or { cell("code", "") },
    active = 1,
    dirty = false,
  }, Notebook)
  if #self.cells == 0 then
    self.cells[1] = cell("code", "")
  end
  return self
end

function Notebook:cell(index)
  return self.cells[index]
end

function Notebook:selected()
  return self.cells[self.active]
end

function Notebook:select(index)
  if type(index) ~= "number" or index < 1 or index > #self.cells then
    return false
  end
  self.active = index
  return true
end

function Notebook:add_cell(kind)
  self.cells[#self.cells + 1] = cell(kind or "code", "")
  self.active = #self.cells
  self.dirty = true
  return self.cells[#self.cells]
end

function Notebook:move(delta)
  local target = self.active + delta
  if target >= 1 and target <= #self.cells then
    self.active = target
    return true
  end
  return false
end

function Notebook:insert(text)
  local current = self:selected()
  if current.kind ~= "code" then return end
  current.source = current.source .. text
  self.dirty = true
end

function Notebook:backspace()
  local current = self:selected()
  if current.kind ~= "code" then return end
  -- Remove one UTF-8 codepoint, not one byte.
  local text = current.source
  local cut = #text
  while cut > 1 do
    local byte = text:byte(cut)
    if byte < 0x80 or byte >= 0xC0 then break end
    cut = cut - 1
  end
  if cut >= 1 then
    current.source = text:sub(1, cut - 1)
  end
  self.dirty = true
end

function Notebook:newline()
  self:insert("\n")
end

function Notebook:set_result(cell_index, result)
  local current = self.cells[cell_index]
  if current == nil then return end
  current.running = false
  current.output = result.output or ""
  current.error = result.ok == false and result.value or nil
  current.scene = result.scene
  if result.ok and result.value and result.value ~= "" and current.output == "" then
    current.output = tostring(result.value)
  end
end

function Notebook.demo()
  local first = Notebook.new({
    name = "welcome.luanb",
    cells = {
      cell("code", [[
print("hello from Lua Notebooks")
print("press F5 to run a cell")]]),
      cell("code", [[
local total = 0
for i = 1, 10 do total = total + i end
print("sum 1..10 =", total)
return total]]),
      cell("code", [[
-- A cell may return a scene request.
return { scene = "cube" }]]),
      cell("code", [[
-- A renderer-agnostic luaplotlib scene table.
local xs, ys = {}, {}
for i = 1, 80 do
  local x = (i - 1) * 0.1
  xs[i] = x
  ys[i] = math.sin(x)
end
return { scene = {
  type = "luaplotlib", width = 800, height = 300,
  title = "sin(x)", xlabel = "x", ylabel = "y",
  xlim = { 0, 8 }, ylim = { -1.2, 1.2 }, grid = true,
  series = {
    { kind = "line", x = xs, y = ys,
      style = { color = "#1f77b4", alpha = 1, label = "sin" } },
    { kind = "scatter", x = { 0, math.pi / 2, math.pi },
      y = { 0, 1, 0 },
      style = { color = "#ff7f0e", radius = 5, label = "samples" } },
  },
} }]]),
      cell("markdown", "# A 3D notebook\nCells, kernels, and a real-time viewport."),
    },
  })
  local second = Notebook.new({
    name = "second-kernel.luanb",
    cells = {
      cell("code", [[
-- This kernel has its own globals and lifetime.
counter = 0
counter = counter + 1
print("counter =", counter)]]),
    },
  })
  return { first, second }
end

return Notebook
