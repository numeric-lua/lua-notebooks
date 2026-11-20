--
-- LÖVR renderer and input adapter for the Neovim ext_linegrid UI.
--
local NvimView = {}
NvimView.__index = NvimView

local function rgb(value, fallback)
  if type(value) ~= "number" then return fallback end
  return {
    math.floor(value / 65536) % 256 / 255,
    math.floor(value / 256) % 256 / 255,
    value % 256 / 255,
  }
end

local SPECIAL = {
  escape = "<Esc>", ["return"] = "<CR>", backspace = "<BS>", tab = "<Tab>",
  delete = "<Del>", home = "<Home>", ["end"] = "<End>",
  pageup = "<PageUp>", pagedown = "<PageDown>",
  up = "<Up>", down = "<Down>", left = "<Left>", right = "<Right>",
  insert = "<Insert>",
}

for index = 1, 12 do SPECIAL["f" .. index] = "<F" .. index .. ">" end

local function key_name(key)
  if SPECIAL[key] then return SPECIAL[key] end
  if #key == 1 then return key end
  return nil
end

function NvimView.new(session, font, options)
  options = options or {}
  return setmetatable({
    session = session,
    font = font,
    size = options.size or 18,
    cell_width = font:getWidth("M") * (options.size or 18),
    cell_height = (options.size or 18) * (options.line_height or 1.2),
    text_scale = (options.size or 18) * (options.text_scale or 0.86),
    scale = options.scale or 1,
  }, NvimView)
end

function NvimView:update()
  self.session:update()
end

function NvimView:resize(width, height)
  local cols = math.max(20, math.floor(width / (self.cell_width * self.scale)))
  local rows = math.max(4, math.floor(height / (self.cell_height * self.scale)))
  if cols ~= self.session.cols or rows ~= self.session.rows then
    self.session:resize(cols, rows)
  end
end

function NvimView:draw(pass, x, y, width, height, scale)
  scale = scale or self.scale
  self:resize(width / scale, height / scale)
  local grid = self.session.grid
  local cw = self.cell_width * scale
  local ch = self.cell_height * scale
  local background = rgb(grid.default_background, { 0.06, 0.07, 0.1 })
  local foreground = rgb(grid.default_foreground, { 0.85, 0.88, 0.95 })
  pass:setColor(background[1], background[2], background[3], 1)
  pass:plane(x + width / 2, y + height / 2, 0, width, height)
  local scissor_x = math.max(0, x * scale)
  local scissor_y = math.max(0, y * scale)
  local scissor_w = math.max(1, width * scale - (scissor_x - x * scale))
  local scissor_h = math.max(1, height * scale - (scissor_y - y * scale))
  pass:setScissor(scissor_x, scissor_y, scissor_w, scissor_h)
  pass:setFont(self.font)
  local rows = math.min(grid.rows, math.ceil(height / ch))
  for row = 0, rows - 1 do
    local row_y = y + row * ch
    for col = 0, grid.cols - 1 do
      local cell = grid.cells[row] and grid.cells[row][col]
      if cell then
        local attrs = grid:attrs(cell.hl)
        local fg = rgb(attrs.foreground, foreground)
        local bg = rgb(attrs.background, background)
        if attrs.reverse then fg, bg = bg, fg end
        if bg[1] ~= background[1] or bg[2] ~= background[2] or
           bg[3] ~= background[3] then
          pass:setColor(bg[1], bg[2], bg[3], 1)
          pass:plane(x + col * cw + cw / 2, row_y + ch / 2, 0, cw, ch)
        end
        if cell.text ~= " " then
          pass:setColor(fg[1], fg[2], fg[3], 1)
          pass:text(cell.text, x + col * cw,
            row_y + (ch - self.text_scale * scale) / 2,
            0, self.text_scale * scale, 0, 0, 1, 0, 0, "left", "top")
        end
      end
    end
  end
  local cursor = grid.cursor
  if cursor and cursor.row < rows then
    local cx = x + cursor.col * cw
    local cy = y + cursor.row * ch
    pass:setColor(0.75, 0.85, 1, 0.85)
    pass:plane(cx + cw / 2, cy + ch / 2, 0, math.max(2, cw), ch)
  end
  pass:setScissor()
end

function NvimView:textinput(text)
  self.session:input((text:gsub("<", "<lt>")))
end

function NvimView:keypressed(key)
  local name = key_name(key)
  if name == nil then return false end
  local ctrl = lovr.system and lovr.system.isKeyDown and
    (lovr.system.isKeyDown("lctrl") or lovr.system.isKeyDown("rctrl"))
  if ctrl and #name == 1 then name = "<C-" .. name .. ">" end
  self.session:input(name)
  return true
end

return NvimView
