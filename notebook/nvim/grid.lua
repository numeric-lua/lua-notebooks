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
    local grid, cols, rows
    if type(event[2]) == "table" then
      grid, cols, rows = event[2][1], event[2][2], event[2][3]
    else
      grid, cols, rows = event[2], event[3], event[4]
    end
    if grid == 1 then self:resize(cols, rows) end
  elseif name == "grid_clear" then
    local grid = type(event[2]) == "table" and event[2][1] or event[2]
    if grid == 1 then
      for row = 0, self.rows - 1 do
        for col = 0, self.cols - 1 do self.cells[row][col] = blank(0) end
      end
    end
  elseif name == "grid_line" then
    if type(event[2]) == "table" then
      for index = 2, #event do
        local line = event[index]
        if type(line) == "table" and line[1] == 1 then
          self:set_line(line[2], line[3], line[4] or {})
        end
      end
    elseif event[2] == 1 then
      self:set_line(event[3], event[4], event[5] or {})
    end
  elseif name == "grid_scroll" then
    local grid, top, bottom, left, right, rows
    if type(event[2]) == "table" then
      grid, top, bottom, left, right, rows = event[2][1], event[2][2],
        event[2][3], event[2][4], event[2][5], event[2][6]
    else
      grid, top, bottom, left, right, rows = event[2], event[3], event[4],
        event[5], event[6], event[7]
    end
    if grid == 1 then self:scroll(top, bottom, left, right, rows) end
  elseif name == "grid_cursor_goto" then
    local grid, row, col
    if type(event[2]) == "table" then
      grid, row, col = event[2][1], event[2][2], event[2][3]
    else
      grid, row, col = event[2], event[3], event[4]
    end
    if grid == 1 then self.cursor = { row = row, col = col } end
  elseif name == "hl_attr_define" then
    if type(event[2]) == "number" then
      self.highlights[event[2]] = event[3] or {}
    else
      for index = 2, #event do
        local entry = event[index]
        if type(entry) == "table" then
          self.highlights[entry[1]] = entry[2] or {}
        end
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
  elseif name == "mode_change" then
    if type(event[2]) == "table" then
      self.mode = event[2][1]
    else
      self.mode = event[2]
    end
  elseif name == "mode_info_set" then
    self.mode_info = type(event[3]) == "table" and event[3] or event[2]
  elseif name == "popupmenu_show" then
    local nested = type(event[2]) == "table"
    local items = nested and event[2][1] or event[2]
    local selected = nested and event[2][2] or event[3]
    local row = nested and event[2][3] or event[4]
    local col = nested and event[2][4] or event[5]
    if type(selected) ~= "number" then selected = 0 end
    self.popupmenu = { items = items or {}, selected = selected + 1,
      row = row or 0, col = col or 0 }
  elseif name == "popupmenu_select" then
    local selected = type(event[2]) == "table" and event[2][2] or event[2]
    if type(selected) ~= "number" then selected = 0 end
    if self.popupmenu then self.popupmenu.selected = selected + 1 end
  elseif name == "popupmenu_hide" then
    self.popupmenu = nil
  end
end

function Grid:apply_redraw(params)
  for _, event in ipairs(params or {}) do self:apply(event) end
end

function Grid:attrs(hl)
  return self.highlights[hl] or {}
end

return Grid
