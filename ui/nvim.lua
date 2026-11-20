--
-- LÖVR renderer and input adapter for the Neovim ext_linegrid UI.
--
local Theme = require("ui.theme")
local NvimView = {}
NvimView.__index = NvimView

local function char_count(value)
  local count = 0
  for _ in value:gmatch("[^\128-\191]") do count = count + 1 end
  return count
end

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
  local glyph_width = font:getWidth("M")
  local glyph_height = 1
  if font.getHeight then glyph_height = font:getHeight() or 1 end
  if glyph_height > 1 then glyph_width = glyph_width / glyph_height end
  return setmetatable({
    session = session,
    font = font,
    size = options.size or 18,
    cell_width = glyph_width * (options.size or 18) *
      (options.text_scale or 0.86),
    cell_height = (options.size or 18) * (options.text_scale or 0.86) *
      (options.line_height or 1.2),
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
  local grid = self.session.grid
  local cw = self.cell_width * scale
  local ch = self.cell_height * scale
  local wanted_cols = math.max(20, math.floor(width / cw))
  local wanted_rows = math.max(4, math.floor(height / ch))
  if wanted_cols ~= self.session.cols or wanted_rows ~= self.session.rows then
    self.session:resize(wanted_cols, wanted_rows)
  end
  self.origin_x, self.origin_y = x, y
  self.draw_cw, self.draw_ch = cw, ch
  local background = rgb(grid.default_background, { 0.06, 0.07, 0.1 })
  local foreground = rgb(grid.default_foreground, { 0.85, 0.88, 0.95 })
  pass:setColor(background[1], background[2], background[3],
    Theme.opacity or 1)
  pass:plane(x + width / 2, y + height / 2, 0, width, height)
  local scissor_x = math.max(0, x * scale)
  local scissor_y = math.max(0, y * scale)
  local scissor_w = math.max(1, width * scale)
  local scissor_h = math.max(1, height * scale - (scissor_y - y * scale))
  pass:setScissor(scissor_x, scissor_y, scissor_w, scissor_h)
  pass:setFont(self.font)
  local rows = math.min(grid.rows, math.ceil(height / ch))
  local cursor = grid.cursor
  if cursor and cursor.row < rows then
    local cx = x + cursor.col * cw + 12
    local cy = y + cursor.row * ch
    pass:setColor(0.75, 0.85, 1, 0.9)
    pass:plane(cx + cw / 2, cy + ch - 1, 0, math.max(2, cw), 2)
  end

  for row = 0, rows - 1 do
    local row_y = y + row * ch
    local col = 0
    while col < grid.cols do
      local cell = grid.cells[row] and grid.cells[row][col]
      if cell == nil then break end
      local hl = cell.hl
      local first = col
      local parts = {}
      while col < grid.cols do
        local current = grid.cells[row][col]
        if current == nil or current.hl ~= hl then break end
        parts[#parts + 1] = current.text
        col = col + 1
      end
      local text = table.concat(parts)
      local attrs = grid:attrs(hl)
      local fg = rgb(attrs.foreground, foreground)
      local bg = rgb(attrs.background, background)
      if attrs.reverse then fg, bg = bg, fg end
      if bg[1] ~= background[1] or bg[2] ~= background[2] or
         bg[3] ~= background[3] then
        pass:setColor(bg[1], bg[2], bg[3], 1)
        local cells = char_count(text)
        pass:plane(x + first * cw + (cells * cw) / 2, row_y + ch / 2, 0,
          cells * cw, ch)
      end
      if text:find("%S") then
        pass:setColor(fg[1], fg[2], fg[3], 1)
        local run_x = x + first * cw
        pass:setScissor(math.max(0, run_x * scale), scissor_y,
          math.max(1, (x + width - run_x) * scale), scissor_h)
        pass:text("|" .. text, run_x - cw,
          row_y + (ch - self.text_scale * scale) / 2,
          0, self.text_scale * scale, 0, 0, 1, 0, 0, "left", "top")
        pass:setScissor(scissor_x, scissor_y, scissor_w, scissor_h)
      end
    end
  end
  local menu = grid.popupmenu
  if menu and #menu.items > 0 then
    local item_h = ch
    local width = 160
    for _, item in ipairs(menu.items) do
      local word = tostring(item[1] or "")
      width = math.max(width, #word * cw + 16)
    end
    width = math.min(width, width)
    local visible = math.min(#menu.items, 8)
    local menu_x = x + menu.col * cw
    local menu_y = y + (menu.row + 1) * ch
    if menu_y + visible * item_h > y + height then
      menu_y = math.max(y, y + height - visible * item_h)
    end
    pass:setColor(0.97, 0.98, 1, 0.98)
    pass:plane(menu_x + width / 2, menu_y + visible * item_h / 2, 0,
      width, visible * item_h)
    for index = 1, visible do
      local item = menu.items[index]
      local selected = index == menu.selected
      if selected then
        pass:setColor(0.72, 0.82, 1, 1)
        pass:plane(menu_x + width / 2, menu_y + (index - 1) * item_h +
          item_h / 2, 0, width, item_h)
      end
      pass:setColor(selected and 0.05 or 0.12, selected and 0.08 or 0.15,
        selected and 0.12 or 0.2, 1)
      pass:text(tostring(item[1] or ""), menu_x + 6, menu_y +
        (index - 1) * item_h + (item_h - self.text_scale) / 2, 0,
        self.text_scale, 0, 0, 1, 0, 0, "left", "top")
    end
  end
  pass:setScissor()
end

function NvimView:mousepressed(px, py, button)
  if button ~= 1 or self.origin_x == nil then return false end
  local col = math.floor((px - self.origin_x) / self.draw_cw)
  local row = math.floor((py - self.origin_y) / self.draw_ch)
  if col < 0 or row < 0 or col >= self.session.grid.cols or
     row >= self.session.grid.rows then return false end
  self.session:request("nvim_input_mouse", { "left", "press", "", 0, row, col })
  self.session:request("nvim_input_mouse", { "left", "release", "", 0, row, col })
  return true
end

function NvimView:wheelmoved(dy)
  local direction = dy > 0 and "up" or "down"
  local cursor = self.session.grid.cursor or { row = 0, col = 0 }
  self.session:request("nvim_input_mouse", { "wheel", direction, "",
    0, cursor.row, cursor.col })
  return true
end

function NvimView:textinput(text)
  text = text:gsub("\r", ""):gsub("\n", ""):gsub("\t", "")
  if text == "" then return end
  local ctrl = lovr.system and lovr.system.isKeyDown and
    (lovr.system.isKeyDown("lctrl") or lovr.system.isKeyDown("rctrl"))
  local alt = lovr.system and lovr.system.isKeyDown and
    (lovr.system.isKeyDown("lalt") or lovr.system.isKeyDown("ralt"))
  if ctrl and not alt then return end
  self.session:input((text:gsub("<", "<lt>")))
end

function NvimView:keypressed(key)
  local name = SPECIAL[key]
  local ctrl = lovr.system and lovr.system.isKeyDown and
    (lovr.system.isKeyDown("lctrl") or lovr.system.isKeyDown("rctrl"))
  if name == nil and ctrl and #key == 1 then
    name = "<C-" .. key .. ">"
  end
  if name == nil then return false end
  self.session:input(name)
  return true
end

return NvimView
