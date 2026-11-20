--
-- Neovim ext_linegrid screen model.  Transport-independent; tests feed redraw
-- event tables directly.
--
local Grid = {}
Grid.__index = Grid

local function blank(attrs)
  return { text = " ", hl = attrs or 0 }
end

function Grid.new(cols, rows)
  local self = setmetatable({
    cols = cols or 80, rows = rows or 24,
    cells = {}, highlights = {}, cursor = { row = 0, col = 0 },
    default_foreground = 0xd8dee9, default_background = 0x1b1f27,
    mode = "normal", modes = {},
  }, Grid)
  self:resize(self.cols, self.rows)
  return self
end

function Grid:resize(cols, rows)
  self.cols, self.rows = cols, rows
  self.cells = {}
  for row = 0, rows - 1 do
    self.cells[row] = {}
    for col = 0, cols - 1 do self.cells[row][col] = blank(0) end
  end
end

function Grid:_ensure(row, col)
  self.cells[row] = self.cells[row] or {}
  for index = 0, col do
    if self.cells[row][index] == nil then self.cells[row][index] = blank(0) end
  end
end

function Grid:line(row)
  local parts = {}
  for col = 0, self.cols - 1 do
    local cell = self.cells[row] and self.cells[row][col]
    parts[#parts + 1] = cell and cell.text or " "
  end
  return table.concat(parts)
end

function Grid:set_line(row, start_col, cells)
  self:_ensure(row, start_col + #cells)
  local last_hl = 0
  local col = start_col
  for _, cell in ipairs(cells) do
    local text = cell[1] or " "
    local hl = cell[2]
    if hl == nil then hl = last_hl else last_hl = hl end
    local count = cell[3] or 1
    for offset = 0, count - 1 do
      if col + offset < self.cols then
        self.cells[row][col + offset] = { text = text, hl = hl }
      end
    end
    col = col + count
  end
end

function Grid:scroll(top, bottom, left, right, rows)
  if rows > 0 then
    for row = top, bottom - rows - 1 do
      for col = left, right - 1 do
        self.cells[row][col] = self.cells[row + rows][col]
      end
    end
    for row = bottom - rows, bottom - 1 do
      for col = left, right - 1 do self.cells[row][col] = blank(0) end
    end
  elseif rows < 0 then
    for row = bottom - 1, top - rows, -1 do
      for col = left, right - 1 do
        self.cells[row][col] = self.cells[row + rows][col]
      end
    end
    for row = top, top - rows - 1 do
      for col = left, right - 1 do self.cells[row][col] = blank(0) end
    end
  end
end

function Grid:apply(event)
  local name = event[1]
  if name == "grid_resize" then
    local args = type(event[2]) == "table" and event[2] or event
    self:resize(args[2] or args[3], args[3] or args[4])
  elseif name == "grid_clear" then
    for row = 0, self.rows - 1 do
      for col = 0, self.cols - 1 do self.cells[row][col] = blank(0) end
    end
  elseif name == "grid_line" then
    for index = 2, #event do
      local line = event[index]
      if type(line) == "table" then
        self:set_line(line[2], line[3], line[4] or {})
      end
    end
  elseif name == "grid_scroll" then
    local args = type(event[2]) == "table" and event[2] or event
    self:scroll(args[2], args[3], args[4], args[5], args[6])
  elseif name == "grid_cursor_goto" then
    local args = type(event[2]) == "table" and event[2] or event
    self.cursor = { row = args[2], col = args[3] }
  elseif name == "hl_attr_define" then
    for index = 2, #event do
      local entry = event[index]
      if type(entry) == "table" then
        self.highlights[entry[1]] = entry[2] or {}
      end
    end
  elseif name == "default_colors_set" then
    if type(event[2]) == "table" then
      self.default_foreground = event[2][1]
      self.default_background = event[2][2]
    else
      self.default_foreground = event[2]
      self.default_background = event[3]
    end
  elseif name == "mode_info_set" then
    self.mode_info = event[3]
  elseif name == "mode_change" then
    self.mode = event[2]
  end
end

function Grid:apply_redraw(params)
  for _, event in ipairs(params or {}) do self:apply(event) end
end

function Grid:attrs(hl)
  return self.highlights[hl] or {}
end

return Grid
