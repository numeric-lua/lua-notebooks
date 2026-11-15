--
-- Notebook document model.  Pure Lua so it can be tested without LÖVR.
--
local Notebook = {}
Notebook.__index = Notebook
local next_cell_id = 0

local function new_cell_id()
  next_cell_id = next_cell_id + 1
  return string.format("c%04d", next_cell_id)
end

local function cell(kind, source, id)
  return {
    id = id or new_cell_id(),
    kind = kind or "code",
    source = source or "",
    output = "",
    scene = nil,
    running = false,
    error = nil,
    cursor = #(source or "") + 1,
    widgets = {},
    collapsed = false,
  }
end

function Notebook.new(options)
  options = options or {}
  local self = setmetatable({
    name = options.name or "Untitled",
    cells = options.cells or { cell("code", "") },
    active = 1,
    dirty = false,
    undo_stack = {},
    redo_stack = {},
  }, Notebook)
  if #self.cells == 0 then
    self.cells[1] = cell("code", "")
  end
  local seen = {}
  for _, item in ipairs(self.cells) do
    if item.id == nil or seen[item.id] then item.id = new_cell_id() end
    seen[item.id] = true
    item.cursor = item.cursor or (#(item.source or "") + 1)
  end
  return self
end

function Notebook:snapshot()
  local cells = {}
  for index, item in ipairs(self.cells) do
    cells[index] = {
      id = item.id, kind = item.kind, source = item.source, output = item.output,
      scene = item.scene, running = false, error = item.error,
      cursor = item.cursor, widgets = item.widgets,
      collapsed = item.collapsed,
    }
  end
  return { active = self.active, cells = cells }
end

function Notebook:restore(snapshot)
  self.cells = snapshot.cells
  self.active = snapshot.active
  self.dirty = true
end

function Notebook:push_undo()
  self.undo_stack[#self.undo_stack + 1] = self:snapshot()
  if #self.undo_stack > 50 then table.remove(self.undo_stack, 1) end
  self.redo_stack = {}
end

function Notebook:undo()
  if #self.undo_stack == 0 then return false end
  self.redo_stack[#self.redo_stack + 1] = self:snapshot()
  self:restore(table.remove(self.undo_stack))
  return true
end

function Notebook:redo()
  if #self.redo_stack == 0 then return false end
  self.undo_stack[#self.undo_stack + 1] = self:snapshot()
  self:restore(table.remove(self.redo_stack))
  return true
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

function Notebook:delete_cell(index)
  if self.cells[index] == nil or #self.cells <= 1 then return false end
  self:push_undo()
  table.remove(self.cells, index)
  self.active = math.max(1, math.min(self.active, #self.cells))
  self.dirty = true
  return true
end

function Notebook:insert_cell(index, cell)
  self:push_undo()
  table.insert(self.cells, index, cell)
  self.active = index
  self.dirty = true
  return cell
end

function Notebook:copy_cell(index)
  local cell = self.cells[index]
  if cell == nil then return nil end
  return {
    id = new_cell_id(),
    kind = cell.kind,
    source = cell.source,
    output = "",
    scene = nil,
    widgets = {},
    collapsed = false,
    running = false,
  }
end

function Notebook:add_cell(kind, after_index)
  self:push_undo()
  local index = (after_index or self.active or #self.cells) + 1
  index = math.max(1, math.min(#self.cells + 1, index))
  table.insert(self.cells, index, cell(kind or "code", ""))
  self.active = index
  self.dirty = true
  return self.cells[index]
end

function Notebook:move(delta)
  local target = self.active + delta
  if target >= 1 and target <= #self.cells then
    self.active = target
    return true
  end
  return false
end

function Notebook:selection_text(anchor, cursor)
  local first = math.min(anchor or 1, cursor or 1)
  local last = math.max(anchor or 1, cursor or 1)
  return self:selected().source:sub(first, last - 1)
end

function Notebook:delete_range(anchor, cursor)
  local first = math.min(anchor or 1, cursor or 1)
  local last = math.max(anchor or 1, cursor or 1)
  local cell = self:selected()
  cell.source = cell.source:sub(1, first - 1) .. cell.source:sub(last)
  cell.cursor = first
  self.dirty = true
end

function Notebook:insert(text)
  self:push_undo()
  local current = self:selected()
  if current.kind ~= "code" then return end
  local cursor = current.cursor or (#current.source + 1)
  current.source = current.source:sub(1, cursor - 1) .. text ..
    current.source:sub(cursor)
  current.cursor = cursor + #text
  self.dirty = true
end

local function previous_start(text, cursor)
  local position = cursor - 1
  if position < 1 then return nil end
  while position > 1 do
    local byte = text:byte(position)
    if byte < 0x80 or byte >= 0xC0 then break end
    position = position - 1
  end
  return position
end

local function next_end(text, cursor)
  if cursor > #text then return #text + 1 end
  local position = cursor + 1
  while position <= #text do
    local byte = text:byte(position)
    if byte < 0x80 or byte >= 0xC0 then break end
    position = position + 1
  end
  return position
end

function Notebook:backspace()
  self:push_undo()
  local current = self:selected()
  if current.kind ~= "code" then return end
  local cursor = current.cursor or (#current.source + 1)
  local start = previous_start(current.source, cursor)
  if start == nil then return end
  current.source = current.source:sub(1, start - 1) .. current.source:sub(cursor)
  current.cursor = start
  self.dirty = true
end

function Notebook:delete()
  local current = self:selected()
  if current.kind ~= "code" then return end
  local cursor = current.cursor or (#current.source + 1)
  if cursor > #current.source then return end
  local finish = next_end(current.source, cursor)
  current.source = current.source:sub(1, cursor - 1) ..
    current.source:sub(finish)
  current.cursor = cursor
  self.dirty = true
end

function Notebook:move_cursor(delta)
  local current = self:selected()
  if current.kind ~= "code" then return end
  local cursor = current.cursor or (#current.source + 1)
  if delta < 0 then
    for _ = 1, -delta do
      local start = previous_start(current.source, cursor)
      if start == nil then break end
      cursor = start
    end
  else
    for _ = 1, delta do
      if cursor > #current.source then break end
      cursor = next_end(current.source, cursor)
    end
  end
  current.cursor = math.max(1, math.min(#current.source + 1, cursor))
end

function Notebook:cursor_home()
  local current = self:selected()
  if current.kind ~= "code" then return end
  local before = current.source:sub(1, (current.cursor or 1) - 1)
  local newline = before:match(".*()\n")
  current.cursor = (newline or 0) + 1
end

function Notebook:cursor_end()
  local current = self:selected()
  if current.kind ~= "code" then return end
  local after = current.source:sub(current.cursor or (#current.source + 1))
  local newline = after:find("\n", 1, true)
  current.cursor = (newline and current.cursor + newline - 1) or
    (#current.source + 1)
end

function Notebook.heading_level(cell)
  if cell == nil or cell.kind ~= "markdown" then return nil end
  local hashes = cell.source:match("^(#+)%s+")
  return hashes and #hashes or nil
end

function Notebook:headings()
  local result = {}
  for index, cell in ipairs(self.cells) do
    local level = Notebook.heading_level(cell)
    if level then
      local text = cell.source:gsub("^#+%s*", ""):gsub("\n.*$", "")
      result[#result + 1] = {
        index = index,
        level = level,
        text = text,
        collapsed = cell.collapsed == true,
      }
    end
  end
  return result
end

function Notebook:toggle_collapsed(index)
  local cell = self.cells[index]
  if cell then self:push_undo() end
  if cell == nil or Notebook.heading_level(cell) == nil then return false end
  cell.collapsed = not cell.collapsed
  self.dirty = true
  return cell.collapsed
end

function Notebook:newline()
  self:push_undo()
  self:insert("\n")
end

function Notebook:set_result(cell_index, result)
  local current = self.cells[cell_index]
  if current == nil then return end
  current.running = false
  current.output = result.output or ""
  current.error = result.ok == false and result.value or nil
  current.scene = result.scene
  current.widgets = result.widgets or {}
  if result.ok and result.value and result.value ~= "" and current.output == "" then
    current.output = tostring(result.value)
  end
end

function Notebook:apply_widget_result(index, result)
  local current = self.cells[index]
  if current == nil then return end
  current.running = false
  current.widgets = result.widgets or current.widgets or {}
  if result.output and result.output ~= "" then
    current.output = current.output == "" and result.output or
      current.output .. "\n" .. result.output
  end
  if result.ok == false then
    current.error = result.value or "widget callback failed"
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
      cell("code", [[
-- Extensions are discovered from the extensions/ directory.
return { scene = "grid" }]]),
      cell("code", [[
-- Widgets are declared in the kernel and rendered by the host.
widgets.slider({ label = "gain", min = 0, max = 10, value = 3,
  on_change = function(value) print("gain", value) end })
widgets.button({ label = "Ping",
  on_click = function() print("pong") end })
widgets.checkbox({ label = "enabled", value = true })
widgets.select({ label = "mode", options = { "fast", "slow" }, value = "fast" })
widgets.text({ label = "name", value = "notebook",
  on_change = function(value) print("name", value) end })]]),
      cell("markdown", "# A 3D notebook\nMath: $E = mc^2$ and $\\alpha + \\beta = \\pi$.\n$$\\left(\\frac{a}{b}\\right)$$\n$$\\mathbf{F}=m\\mathbf{a}$$\n$$\\sqrt{x}$$\n$$\\begin{matrix}a & b \\\\ c & d\\end{matrix}$$\n## Collapsible section\nClick the heading arrow to fold the next cells."),
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
