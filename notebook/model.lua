--
-- Notebook document model.  Pure Lua so it can be tested without LÖVR.
--
local Search = require("notebook.search")

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
    history_nodes = {},
    history_current = nil,
    history_sequence = 0,
    history_dirty = false,
    history_pending_label = nil,
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
  self.history_root = self:add_history_node(nil, "initial", self:snapshot())
  self.history_current = self.history_root
  return self
end

function Notebook:snapshot()
  local cells = {}
  for index, item in ipairs(self.cells) do
    cells[index] = {
      id = item.id, kind = item.kind, source = item.source, output = item.output,
      scene = item.scene, running = false, error = item.error,
      cursor = item.cursor, widgets = item.widgets,
      collapsed = item.collapsed, elapsed = item.elapsed,
    }
  end
  return { active = self.active, cells = cells }
end

function Notebook:copy_snapshot(snapshot)
  local cells = {}
  for index, item in ipairs(snapshot.cells) do
    local copy = {}
    for key, value in pairs(item) do copy[key] = value end
    cells[index] = copy
  end
  return { active = snapshot.active, cells = cells }
end

function Notebook:restore(snapshot)
  local copy = self:copy_snapshot(snapshot)
  self.cells = copy.cells
  self.active = copy.active
  self.dirty = true
end

function Notebook:add_history_node(parent, label, snapshot)
  self.history_sequence = self.history_sequence + 1
  local node = {
    id = self.history_sequence,
    parent = parent,
    children = {},
    snapshot = snapshot or self:snapshot(),
    label = label or "edit",
  }
  if parent then
    parent.children[#parent.children + 1] = node
    parent.active_child = node.id
  end
  self.history_nodes[#self.history_nodes + 1] = node
  return node
end

function Notebook:flush_history()
  if self.history_dirty then
    self:checkpoint_history(self.history_pending_label)
  end
end

function Notebook:checkpoint_history(label)
  local node = self:add_history_node(self.history_current,
    label or self.history_pending_label or "edit")
  self.history_current = node
  self.history_dirty = false
  self.history_pending_label = nil
  return node
end

function Notebook:push_undo(label)
  if self.history_dirty then
    self:checkpoint_history(self.history_pending_label)
  end
  self.history_pending_label = label or "edit"
  self.history_dirty = true
end

function Notebook:undo()
  if self.history_dirty then
    self:checkpoint_history(self.history_pending_label)
  end
  local current = self.history_current
  if current == nil or current.parent == nil then return false end
  current.parent.active_child = current.id
  self.history_current = current.parent
  self:restore(current.parent.snapshot)
  self.history_dirty = false
  self.history_pending_label = nil
  return true
end

function Notebook:redo()
  if self.history_dirty then
    self:checkpoint_history(self.history_pending_label)
  end
  local current = self.history_current
  if current == nil or #current.children == 0 then return false end
  local target
  for _, child in ipairs(current.children) do
    if child.id == current.active_child then target = child; break end
  end
  target = target or current.children[#current.children]
  self.history_current = target
  self:restore(target.snapshot)
  self.history_dirty = false
  self.history_pending_label = nil
  return true
end

function Notebook:reset_history()
  self.history_nodes = {}
  self.history_sequence = 0
  self.history_root = self:add_history_node(nil, "initial", self:snapshot())
  self.history_current = self.history_root
  self.history_dirty = false
  self.history_pending_label = nil
end

function Notebook:history_nodes_flat()
  local result = {}
  local function walk(node, depth)
    result[#result + 1] = { node = node, depth = depth,
      current = node == self.history_current }
    for _, child in ipairs(node.children) do walk(child, depth + 1) end
  end
  if self.history_root then walk(self.history_root, 0) end
  return result
end

function Notebook:restore_history(id)
  local target
  for _, node in ipairs(self.history_nodes) do
    if node.id == id then target = node; break end
  end
  if target == nil then return false end
  if target == self.history_current then return true end
  self.history_current = target
  self:restore(target.snapshot)
  self.history_dirty = false
  self.history_pending_label = nil
  return true
end

function Notebook:cell(index)
  return self.cells[index]
end

function Notebook:title()
  for _, cell in ipairs(self.cells) do
    if cell.kind == "markdown" then
      local title = cell.source:match("^%s*#%s+([^\n]+)")
      if title then
        title = title:gsub("%s+#*%s*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if title ~= "" then return title end
      end
    end
  end
  return (self.name or "Untitled"):gsub("%.luanb$", "")
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

function Notebook:duplicate(index)
  local source = self.cells[index] or self:selected()
  if source == nil then return nil end
  local copy = {}
  for key, value in pairs(source) do copy[key] = value end
  copy.id = new_cell_id()
  copy.running = false
  table.insert(self.cells, index + 1, copy)
  self.active = index + 1
  self.dirty = true
  return copy
end

function Notebook:add_cell_above(kind)
  return self:add_cell(kind, math.max(0, (self.active or 1) - 1))
end

function Notebook:set_cell_kind(index, kind)
  local cell = self.cells[index]
  if cell == nil or (kind ~= "code" and kind ~= "markdown") then
    return false
  end
  self:push_undo("change cell kind")
  cell.kind = kind
  cell.output = ""
  cell.scene = nil
  cell.widgets = {}
  cell.error = nil
  self.dirty = true
  return true
end

function Notebook:delete_cell(index)
  if self.cells[index] == nil or #self.cells <= 1 then return false end
  self:push_undo("delete cell")
  table.remove(self.cells, index)
  self.active = math.max(1, math.min(self.active, #self.cells))
  self.dirty = true
  return true
end

function Notebook:insert_cell(index, cell)
  self:push_undo("insert cell")
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

function Notebook:new_cell(kind, source)
  return cell(kind or "code", source or "")
end

function Notebook:add_cell(kind, after_index)
  self:push_undo("add cell")
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

function Notebook:matching_bracket(position)
  local source = self:selected().source
  position = position or self:selected().cursor or 1
  local pairs = { ["("] = ")", ["["] = "]", ["{"] = "}", [")"] = "(",
    ["]"] = "[", ["}"] = "{" }
  local char = source:sub(position, position)
  if char == "" or pairs[char] == nil then
    local line_start = (source:sub(1, position - 1):match(".*()\n") or 0) + 1
    local line_end = source:find("\n", position, true) or (#source + 1)
    local found = source:find("[%(%[%{%)%]%}]", position, false)
    if found == nil or found >= line_end then
      found = source:find("[%(%[%{%)%]%}]", line_start)
    end
    if found == nil or found >= line_end then return nil end
    position = found
    char = source:sub(position, position)
  end
  local target = pairs[char]
  local opening = char == "(" or char == "[" or char == "{"
  local depth = 0
  local step = opening and 1 or -1
  local index = position
  while index >= 1 and index <= #source do
    local current = source:sub(index, index)
    if current == char then depth = depth + 1
    elseif current == target then
      depth = depth - 1
      if depth == 0 then return index end
    end
    index = index + step
  end
  return nil
end

function Notebook:word_range(around)
  local cell = self:selected()
  if cell == nil then return nil end
  local source = cell.source
  local function word_at(position)
    local char = source:sub(position, position)
    return char ~= "" and char:match("[%w_]") ~= nil
  end
  local position = math.min(cell.cursor or 1, #source)
  if position < 1 then return nil end
  if not word_at(position) then
    while position <= #source and not word_at(position) do
      position = position + 1
    end
    if position > #source then
      position = math.min(cell.cursor or 1, #source)
      while position >= 1 and not word_at(position) do
        position = position - 1
      end
    end
  end
  if position < 1 or not word_at(position) then return nil end
  local first, last = position, position
  while first > 1 and word_at(first - 1) do first = first - 1 end
  while last < #source and word_at(last + 1) do last = last + 1 end
  if around then
    while last < #source and source:sub(last + 1, last + 1):match("%s") do
      last = last + 1
    end
  end
  return first, last
end

function Notebook:delimiter_range(open, close, around)
  local cell = self:selected()
  if cell == nil then return nil end
  local source = cell.source
  local cursor = cell.cursor or 1
  if open == '"' or open == "'" or open == "`" then
    local line_start = (source:sub(1, cursor - 1):match(".*()\n") or 0) + 1
    local line_end = source:find("\n", cursor, true) or (#source + 1)
    local opening
    local best
    local index = line_start
    while index < line_end do
      local char = source:sub(index, index)
      if char == open then
        local escaped = index > 1 and source:sub(index - 1, index - 1) == "\\"
        if not escaped then
          if opening == nil then
            opening = index
          else
            if opening <= cursor and cursor <= index then
              best = { opening, index }
            end
            opening = nil
          end
        end
      end
      index = index + 1
    end
    if best == nil then return nil end
    if around then return best[1], best[2] end
    return best[1] + 1, best[2] - 1
  end
  local pairs = { ["("] = ")", ["["] = "]", ["{"] = "}", ["<"] = ">" }
  if pairs[open] ~= close then return nil end
  local stack = {}
  local best
  local index = 1
  while index <= #source do
    local char = source:sub(index, index)
    if char == open then
      stack[#stack + 1] = index
    elseif char == close and #stack > 0 then
      local start = table.remove(stack)
      if start <= cursor and cursor <= index then
        if best == nil or start > best[1] then best = { start, index } end
      end
    end
    index = index + 1
  end
  if best == nil then return nil end
  if around then return best[1], best[2] end
  return best[1] + 1, best[2] - 1
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
  self:push_undo("insert text")
  local current = self:selected()
  if current.kind ~= "code" and current.kind ~= "markdown" then return end
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
  self:push_undo("backspace")
  local current = self:selected()
  if current.kind ~= "code" and current.kind ~= "markdown" then return end
  local cursor = current.cursor or (#current.source + 1)
  local start = previous_start(current.source, cursor)
  if start == nil then return end
  current.source = current.source:sub(1, start - 1) .. current.source:sub(cursor)
  current.cursor = start
  self.dirty = true
end

function Notebook:delete()
  local current = self:selected()
  if current.kind ~= "code" and current.kind ~= "markdown" then return end
  local cursor = current.cursor or (#current.source + 1)
  if cursor > #current.source then return end
  local finish = next_end(current.source, cursor)
  current.source = current.source:sub(1, cursor - 1) ..
    current.source:sub(finish)
  current.cursor = cursor
  self.dirty = true
end

function Notebook:delete_character(forward)
  local cell = self:selected()
  if cell == nil then return false end
  local source = cell.source or ""
  local cursor = math.max(1, math.min(cell.cursor or 1, #source + 1))
  local position = forward and cursor or cursor - 1
  if position < 1 or position > #source then return false end
  self:push_undo(forward and "delete character" or "delete previous character")
  cell.source = source:sub(1, position - 1) .. source:sub(position + 1)
  cell.cursor = math.min(position, #cell.source + 1)
  return true
end

function Notebook:move_line(delta)
  local cell = self:selected()
  if cell == nil then return false end
  local source = cell.source
  local cursor = cell.cursor or (#source + 1)
  local before = source:sub(1, cursor - 1)
  local line = select(2, before:gsub("\n", ""))
  local last_newline = before:match(".*()\n") or 0
  local column = cursor - last_newline - 1
  local target = line + delta
  local total_lines = select(2, source:gsub("\n", "")) + 1
  if target < 0 or target >= total_lines then return false end
  local line_start = 1
  for _ = 1, target do
    local newline = source:find("\n", line_start, true)
    if newline == nil then return false end
    line_start = newline + 1
  end
  local line_end = source:find("\n", line_start, true) or (#source + 1)
  cell.cursor = math.min(line_start + column, line_end)
  return true
end

function Notebook:move_cursor(delta)
  local current = self:selected()
  if current.kind ~= "code" and current.kind ~= "markdown" then return end
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
  if current.kind ~= "code" and current.kind ~= "markdown" then return end
  local before = current.source:sub(1, (current.cursor or 1) - 1)
  local newline = before:match(".*()\n")
  current.cursor = (newline or 0) + 1
end

function Notebook:cursor_end()
  local current = self:selected()
  if current.kind ~= "code" and current.kind ~= "markdown" then return end
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
  self:push_undo("newline")
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
  current.elapsed = type(result.elapsed) == "number" and result.elapsed or nil
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
      cell("markdown", "## More plots\nThe renderer accepts Cartesian line, scatter, bar, and histogram series plus polar line, scatter, and bar scenes. Each cell returns a plain Lua table, so scenes are testable without a GPU."),
      cell("code", [[
-- Bar chart.
return { scene = {
  type = "luaplotlib", width = 800, height = 300,
  title = "weekly totals", xlabel = "day", ylabel = "count", grid = true,
  xlim = { 0, 6 }, ylim = { 0, 10 },
  series = {
    { kind = "bar", x = { 1, 2, 3, 4, 5 },
      y = { 3, 7, 4, 9, 5 }, width = 0.7,
      style = { color = "#2ca02c", alpha = 1, label = "count" } },
  },
} }]]),
      cell("code", [[
-- Histogram from precomputed edges and counts.
local edges, counts = {}, {}
for i = 1, 17 do edges[i] = (i - 1) * 0.25 end
for i = 1, 16 do
  counts[i] = math.floor(10 * math.exp(-((edges[i] - 2) ^ 2)))
end
return { scene = {
  type = "luaplotlib", width = 800, height = 300,
  title = "histogram", xlabel = "value", ylabel = "frequency", grid = true,
  xlim = { 0, 4 }, ylim = { 0, 11 },
  series = {
    { kind = "hist", edges = edges, counts = counts,
      style = { color = "#9467bd", alpha = 1, label = "samples" } },
  },
} }]]),
      cell("code", [[
-- Multiple lines and a scatter overlay.
local xs = {}
for i = 1, 120 do xs[i] = i * 0.05 end
local sin, cos = {}, {}
for i = 1, #xs do
  sin[i] = math.sin(xs[i])
  cos[i] = math.cos(xs[i])
end
return { scene = {
  type = "luaplotlib", width = 800, height = 320,
  title = "trigonometric pair", xlabel = "x", ylabel = "y",
  xlim = { 0, 6 }, ylim = { -1.2, 1.2 }, grid = true,
  series = {
    { kind = "line", x = xs, y = sin,
      style = { color = "#1f77b4", alpha = 1, label = "sin" } },
    { kind = "line", x = xs, y = cos,
      style = { color = "#d62728", alpha = 1, label = "cos" } },
    { kind = "scatter", x = { 0, math.pi }, y = { 0, 0 },
      style = { color = "#ff7f0e", radius = 5 } },
  },
} }]]),
      cell("code", [[
-- Polar scene IR: the live viewport and the HTML export share the geometry.
local theta, r = {}, {}
for i = 1, 160 do
  local angle = (i - 1) * 2 * math.pi / 160
  theta[i] = angle
  r[i] = 1.4 + 0.5 * math.sin(4 * angle)
end
return { scene = {
  type = "luaplotlib", orientation = "polar",
  title = "polar rose", width = 800, height = 320,
  polar = {
    theta_zero = 0, theta_direction = "counterclockwise", rmax = 2,
    theta_ticks = {
      { value = 0, label = "0" }, { value = math.pi / 2, label = "90" },
      { value = math.pi, label = "180" },
      { value = 3 * math.pi / 2, label = "270" },
    },
    r_ticks = {
      { value = 0.5, label = "0.5" }, { value = 1, label = "1" },
      { value = 1.5, label = "1.5" }, { value = 2, label = "2" },
    },
    series = {
      { kind = "line", theta = theta, r = r,
        style = { color = "#1f77b4", label = "rose" } },
      { kind = "scatter", theta = { 0, math.pi / 2, math.pi },
        r = { 1, 2, 1 },
        style = { color = "#ff7f0e", radius = 5, label = "samples" } },
      { kind = "bar", theta = { math.pi / 4 }, r = { 1.5 },
        widths = { 0.45 }, colors = { "#2ca02c" } },
    },
  },
} }]]),
      cell("code", [[
-- Polar heatmap, contour, and colorbar IR.
local rows, cols = 5, 8
local values = {}
for row = 1, rows do
  values[row] = {}
  for col = 1, cols do
    local radius = (row - 1) / (rows - 1)
    local angle = (col - 1) * 2 * math.pi / cols
    values[row][col] = 0.5 + 0.5 * math.sin(3 * angle) * radius
  end
end
return { scene = {
  type = "luaplotlib", orientation = "polar",
  title = "polar heatmap", width = 800, height = 320,
  polar = {
    theta_zero = 0, theta_direction = "counterclockwise", rmax = 2,
    theta_ticks = {
      { value = 0, label = "0" }, { value = math.pi / 2, label = "90" },
      { value = math.pi, label = "180" },
      { value = 3 * math.pi / 2, label = "270" },
    },
    r_ticks = {
      { value = 0.5, label = "0.5" }, { value = 1, label = "1" },
      { value = 1.5, label = "1.5" }, { value = 2, label = "2" },
    },
    heatmaps = { {
      rows = rows, cols = cols, values = values,
      vmin = 0, vmax = 1, rmin = 0, rmax = 2,
      theta_min = 0, theta_max = 2 * math.pi,
      alpha = 1, label = "density", colorbar = true,
    } },
    contours = { {
      rows = rows, cols = cols,
      levels = {
        { level = 0.25, segments = {
          { 0, 0.8, 1.2, 1.2 }, { 2.4, 0.8, 3.8, 1.2 } } },
        { level = 0.75, segments = {
          { 0.4, 1.2, 1.6, 1.6 }, { 2.8, 1.0, 4.2, 1.4 } } },
      },
      labels = true,
      style = { color = "#ffd166", linewidth = 1.5, alpha = 0.95,
        linestyle = "dashed", label = "isolines" },
    } },
    colorbar = { orientation = "vertical", vmin = 0, vmax = 1,
      ticks = { 0, 0.5, 1 }, label = "density" },
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
  on_change = function(value) print("name", value) end })
widgets.shader({ label = "Star Nest", shader = "star_nest", height = 180 })]]),
      cell("markdown", "# A 3D notebook\n\nA notebook is a list of cells. Code cells share one persistent kernel; markdown cells render prose and math.\n\n## Math\nInline: $E = mc^2$ and $\\alpha + \\beta = \\pi$.\n\n$$\\left(\\frac{a}{b}\\right)$$\n$$\\mathbf{F}=m\\mathbf{a}$$\n$$\\sqrt{x}$$\n$$\\begin{matrix}a & b \\\\ c & d\\end{matrix}$$\n\n## Keyboard\n- **F5** run the selected cell\n- **F6 / F7** save and load\n- **F10** extensions\n- **F1** shortcut help\n\n## Links\nThis notebook links to [[Second kernel]].\n\nTags: #lua #notebook\n\n## Collapsible section\nClick the heading arrow to fold the following cells. Add your own plots by returning `{ scene = { ... } }` from a code cell."),
      cell("code", [[
-- Large polar heatmap: fields above the paint cap are sampled into blocks.
local rows, cols = 96, 96
local values = {}
for row = 1, rows do
  values[row] = {}
  for col = 1, cols do
    local radius = (row - 1) / (rows - 1)
    local angle = (col - 1) * 2 * math.pi / cols
    values[row][col] = 0.5 + 0.5 * math.sin(3 * angle) * radius
  end
end
return { scene = {
  type = "luaplotlib", orientation = "polar",
  title = "large polar heatmap", width = 800, height = 320,
  polar = {
    theta_zero = 0, theta_direction = "counterclockwise", rmax = 2,
    theta_ticks = {
      { value = 0, label = "0" }, { value = math.pi / 2, label = "90" },
      { value = math.pi, label = "180" },
      { value = 3 * math.pi / 2, label = "270" },
    },
    r_ticks = {
      { value = 0.5, label = "0.5" }, { value = 1, label = "1" },
      { value = 1.5, label = "1.5" }, { value = 2, label = "2" },
    },
    heatmaps = { {
      rows = rows, cols = cols, values = values,
      vmin = 0, vmax = 1, rmin = 0, rmax = 2,
      theta_min = 0, theta_max = 2 * math.pi,
      alpha = 1, label = "density", colorbar = true,
    } },
    colorbar = { orientation = "vertical", vmin = 0, vmax = 1,
      ticks = { 0, 0.5, 1 }, label = "density" },
  },
} }]]),
      cell("code", [[
-- Polar quiver: local tangential/radial components, decimated for display.
local theta, r, u, v = {}, {}, {}, {}
for i = 1, 48 do
  local angle = (i - 1) * 2 * math.pi / 48
  theta[i] = angle
  r[i] = 1.6
  u[i] = math.cos(3 * angle)
  v[i] = math.sin(3 * angle)
end
return { scene = {
  type = "luaplotlib", orientation = "polar",
  title = "polar quiver", width = 800, height = 320,
  polar = {
    theta_zero = 0, theta_direction = "counterclockwise", rmax = 2,
    theta_ticks = {
      { value = 0, label = "0" }, { value = math.pi / 2, label = "90" },
      { value = math.pi, label = "180" },
      { value = 3 * math.pi / 2, label = "270" },
    },
    r_ticks = {
      { value = 0.5, label = "0.5" }, { value = 1, label = "1" },
      { value = 1.5, label = "1.5" }, { value = 2, label = "2" },
    },
    series = {
      { kind = "quiver", theta = theta, r = r, u = u, v = v,
        scale = 14, pivot = "middle", max_arrows = 12,
        style = { color = "#e45756", linewidth = 1.4, head = 5,
          alpha = 0.95, label = "flow" } },
    },
  },
} }]]),
      cell("code", [[
-- Polar streamplot: integrated streamlines with mid-line arrows.
local lines = {}
for k = 1, 2 do
  local line, arrows = { theta = {}, r = {} }, {}
  for i = 1, 24 do
    local angle = (k - 1) * math.pi + (i - 1) * 0.18
    local radius = 0.5 + 0.04 * (i - 1) + 0.35 * (k - 1)
    line.theta[i] = angle
    line.r[i] = radius
    if i == 12 then
      local next_angle = angle + 0.18
      local next_radius = radius + 0.04
      local x1, y1 = radius * math.cos(angle), -radius * math.sin(angle)
      local x2 = next_radius * math.cos(next_angle)
      local y2 = -next_radius * math.sin(next_angle)
      arrows[1] = { theta = angle, r = radius,
        angle = math.deg(math.atan2(y2 - y1, x2 - x1)) }
    end
  end
  line.arrows = arrows
  lines[k] = line
end
return { scene = {
  type = "luaplotlib", orientation = "polar",
  title = "polar streamplot", width = 800, height = 320,
  polar = {
    theta_zero = 0, theta_direction = "counterclockwise", rmax = 2.4,
    theta_ticks = {
      { value = 0, label = "0" }, { value = math.pi / 2, label = "90" },
      { value = math.pi, label = "180" },
      { value = 3 * math.pi / 2, label = "270" },
    },
    r_ticks = {
      { value = 1, label = "1" }, { value = 2, label = "2" },
    },
    series = {
      { kind = "streamplot",
        theta = { 0, math.pi / 2, math.pi, 3 * math.pi / 2, 2 * math.pi },
        r = { 0.25, 0.75, 1.25, 1.75, 2.25 },
        lines = lines, periodic = true, density = 1,
        step = 0.08, step_mode = "explicit", resolved_step = 0.08,
        step_unit = "data_radius_units", max_steps = 300,
        max_lines = 16, max_points = 800, head = 6, truncated = false,
        style = { color = "#2ca02c", linewidth = 1.5, alpha = 0.95,
          label = "flow" } },
    },
  },
} }]]),
      cell("code", [[
-- Polar streamplot clip: lines outside rmax are cut at the frame, and a
-- dashed style splits the visible runs instead of drawing past the circle.
local lines = {
  { theta = { 0.0, 0.4, 0.8, 1.2 }, r = { 0.8, 1.2, 1.6, 2.0 },
    arrows = { { theta = 0.6, r = 1.4, angle = 35 } } },
  { theta = { 2.2, 2.5, 2.8, 3.1 }, r = { 1.2, 2.0, 2.6, 3.2 },
    arrows = { { theta = 2.5, r = 2.0, angle = 120 } } },
}
return { scene = {
  type = "luaplotlib", orientation = "polar",
  title = "polar streamplot clip", width = 800, height = 320,
  polar = {
    theta_zero = 0, theta_direction = "counterclockwise", rmax = 2,
    theta_ticks = {
      { value = 0, label = "0" }, { value = math.pi / 2, label = "90" },
      { value = math.pi, label = "180" },
      { value = 3 * math.pi / 2, label = "270" },
    },
    r_ticks = { { value = 1, label = "1" }, { value = 2, label = "2" } },
    series = {
      { kind = "streamplot",
        theta = { 0, math.pi / 2, math.pi, 3 * math.pi / 2, 2 * math.pi },
        r = { 0.25, 0.75, 1.25, 1.75 },
        lines = lines, arrows = true, head = 6, density = 1,
        step = 0.08, step_mode = "explicit", resolved_step = 0.08,
        max_steps = 300, max_lines = 16, max_points = 800,
        periodic = false, truncated = false,
        style = { color = "#b279a2", linewidth = 1.6, alpha = 0.9,
          linestyle = "dashed", label = "clipped flow" } },
    },
  },
} }]]),
      cell("markdown", "# Markdown checklist\n\n- [x] render inline math and **emphasis**\n- [x] preview links such as [[Second kernel]]\n- [ ] add `docs` for your own notebook\n\nChecklists preview as boxes and export as disabled HTML checkboxes."),
    },
  })
  local second = Notebook.new({
    name = "second-kernel.luanb",
    cells = {
      cell("markdown", "# Second kernel"),
      cell("code", [[
-- This kernel has its own globals and lifetime.
counter = 0
counter = counter + 1
print("counter =", counter)]]),
    },
  })
  return { first, second }
end

function Notebook:replace_all(find, replacement, options)
  if type(find) ~= "string" or find == "" then return 0, false end
  local total, changed = Search.replace_cells(self.cells, find,
    replacement or "", options)
  if changed then
    self:push_undo("replace in notebook")
    self.dirty = true
  end
  return total, changed
end

return Notebook
