--
-- Minimal immediate-mode notebook UI.  It intentionally avoids a GUI
-- dependency for the first milestone: cells, tabs, a tiny text editor, and a
-- real 3D viewport are enough to validate the architecture.
--
local Plot = require("ui.plot")
local Surface = require("ui.surface")
local Extensions = require("extensions")

local UI = {}
UI.__index = UI

local function cell_label(index)
  return string.format("In [%d]", index)
end

local function split_lines(text)
  local lines = {}
  if text == nil or text == "" then
    return { "" }
  end
  for line in (text .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  return lines
end

local function inside(x, y, rect)
  return x >= rect.x and x <= rect.x + rect.w and
         y >= rect.y and y <= rect.y + rect.h
end

local function text(pass, font, value, x, y, color, scale)
  pass:setFont(font)
  pass:setColor(color[1], color[2], color[3], color[4] or 1)
  pass:text(value, x, y, 0, scale or 1, 0, 0, 1, 0, 0, "left", "top")
end

local function box(pass, x, y, w, h, color)
  pass:setColor(color[1], color[2], color[3], color[4] or 1)
  pass:plane(x + w / 2, y + h / 2, 0, w, h)
end

function UI.new(app)
  return setmetatable({
    app = app,
    scroll = 0,
    max_scroll = 0,
    rects = {},
    tabs = {},
    buttons = {},
    extension_passes = {},
    surfaces = {},
    scene_rects = {},
    drag = nil,
    focused_surface = nil,
  }, UI)
end

function UI:draw(pass)
  local app = self.app
  local width, height = pass:getDimensions()
  self.width, self.height = width, height

  -- 2D pixel-space projection.  LÖVR's orthographic mode maps the window to
  -- pixels when the font's pixel density is 1, as in the official 2D example.
  pass:setViewPose(1, mat4():identity())
  pass:setProjection("orthographic")
  pass:setDepthTest()

  box(pass, 0, 0, width, height, { 0.055, 0.06, 0.08, 1 })
  box(pass, 0, 0, width, 50, { 0.08, 0.09, 0.12, 1 })
  text(pass, app.title_font, "Lua Notebooks", 18, 14,
    { 0.92, 0.94, 1, 1 })

  -- Notebook tabs.
  self.tabs = {}
  local tab_x = 210
  for index, notebook in ipairs(app.notebooks) do
    local label = notebook.name
    local tab_w = 180
    local active = index == app.active
    box(pass, tab_x, 10, tab_w, 30,
      active and { 0.18, 0.22, 0.32, 1 } or { 0.11, 0.12, 0.16, 1 })
    text(pass, app.font, label, tab_x + 10, 17,
      active and { 0.95, 0.96, 1, 1 } or { 0.55, 0.6, 0.7, 1 }, 0.85)
    self.tabs[#self.tabs + 1] = { x = tab_x, y = 10, w = tab_w, h = 30, index = index }
    tab_x = tab_x + tab_w + 8
  end

  -- Toolbar buttons.
  self.buttons = {}
  local run_x = width - 110
  box(pass, run_x, 10, 92, 30, { 0.18, 0.42, 0.30, 1 })
  text(pass, app.font, "Run  F5", run_x + 12, 18, { 0.92, 1, 0.94, 1 }, 0.8)
  self.buttons.run = { x = run_x, y = 10, w = 92, h = 30 }
  local add_x = run_x - 110
  box(pass, add_x, 10, 96, 30, { 0.15, 0.18, 0.25, 1 })
  text(pass, app.font, "+ Cell", add_x + 16, 18, { 0.8, 0.86, 1, 1 }, 0.8)
  self.buttons.add = { x = add_x, y = 10, w = 96, h = 30 }

  local notebook = app:notebook()
  local y = 66 - self.scroll
  self.rects = {}
  local content_bottom = 0

  for index, cell in ipairs(notebook.cells) do
    cell._index = index
    local source_lines = split_lines(cell.source)
    local source_height = math.max(3, #source_lines) * 21
    local output_lines = cell.output ~= "" and split_lines(cell.output) or {}
    local output_height = 0
    if #output_lines > 0 then
      output_height = math.min(#output_lines, 6) * 19 + 14
    end
    local scene_height = 0
    if type(cell.scene) == "table" and cell.scene.type == "luaplotlib" then
      scene_height = 230
    elseif cell.scene then
      scene_height = 170
    end
    local cell_height = 30 + source_height + output_height + scene_height + 14
    self.rects[index] = { x = 20, y = y, w = width - 40, h = cell_height }
    content_bottom = y + cell_height

    if y + cell_height > 55 and y < height - 10 then
      local selected = index == notebook.active
      box(pass, 20, y, width - 40, cell_height,
        selected and { 0.095, 0.11, 0.15, 1 } or { 0.075, 0.085, 0.11, 1 })
      if selected then
        local accent = { 0.35, 0.62, 0.95, 1 }
        box(pass, 20, y, 4, cell_height, accent)
      end
      local kind_color = cell.kind == "markdown" and
        { 0.7, 0.65, 0.95, 1 } or { 0.45, 0.75, 0.95, 1 }
      text(pass, app.font, string.upper(cell.kind) .. "  " .. cell_label(index),
        34, y + 8, kind_color, 0.72)
      if cell.running then
        text(pass, app.font, "running...", width - 130, y + 8,
          { 0.95, 0.75, 0.35, 1 }, 0.72)
      end

      local source_y = y + 30
      local source_color = cell.kind == "markdown" and
        { 0.75, 0.78, 0.9, 1 } or { 0.86, 0.88, 0.94, 1 }
      for line_index = 1, math.min(#source_lines, 14) do
        text(pass, app.font, source_lines[line_index], 36,
          source_y + (line_index - 1) * 21, source_color, 0.86)
      end
      if cell.kind == "code" and selected then
        local cursor_line = math.min(#source_lines, 14)
        local cursor_text = source_lines[cursor_line]
        local cursor_x = 36 + app.font:getWidth(cursor_text) * 0.86
        box(pass, cursor_x + 2, source_y + (cursor_line - 1) * 21 + 2, 2, 18,
          { 0.4, 0.75, 1, 1 })
      end

      local output_y = source_y + source_height + 6
      if #output_lines > 0 then
        box(pass, 34, output_y - 3, width - 68, output_height,
          { 0.04, 0.05, 0.07, 1 })
        local output_color = cell.error and { 1, 0.45, 0.45, 1 } or
          { 0.55, 0.9, 0.65, 1 }
        for line_index = 1, math.min(#output_lines, 6) do
          text(pass, app.font, output_lines[line_index], 42,
            output_y + (line_index - 1) * 19, output_color, 0.78)
        end
        output_y = output_y + output_height + 4
      end

      if type(cell.scene) == "table" and cell.scene.type == "luaplotlib" then
        Plot.draw(pass, app.font, cell.scene, 34, output_y, width - 68,
          scene_height)
      elseif cell.scene then
        self:draw_scene(pass, 34, output_y, width - 68, scene_height, cell)
      end
    end
    y = y + cell_height + 10
  end

  local total = math.max(0, content_bottom - height + 40)
  self.max_scroll = total

  -- Keep the selected cell in view.  Changing the scroll takes effect on the
  -- next frame; that is fine for mouse selection and cell execution.
  local selected_rect = self.rects[notebook.active]
  if selected_rect then
    local top = 60
    local bottom = height - 38
    if selected_rect.y < top then
      self.scroll = math.max(0, self.scroll - (top - selected_rect.y))
    elseif selected_rect.y + selected_rect.h > bottom then
      self.scroll = math.min(total,
        self.scroll + (selected_rect.y + selected_rect.h - bottom))
    end
  end
  if self.scroll > total then self.scroll = total end

  -- Status/footer.
  box(pass, 0, height - 28, width, 28, { 0.075, 0.085, 0.11, 1 })
  text(pass, app.font, app.status, 16, height - 22,
    { 0.6, 0.68, 0.82, 1 }, 0.72)
  text(pass, app.font, "F5 run   F6 save   F7 load   Tab indent   Up/Down cell",
    width - 470, height - 22, { 0.45, 0.5, 0.62, 1 }, 0.65)
  return self.extension_passes
end

function UI:draw_scene(pass, x, y, w, h, cell)
  local index = self.app.active .. ":" .. tostring(cell._index)
  local surface = self.surfaces[index]
  if surface == nil then
    surface = Surface.new()
    self.surfaces[index] = surface
  end
  local renderer = Extensions.get(cell.scene)
  if renderer == nil then
    box(pass, x, y, w, h, { 0.03, 0.03, 0.04, 1 })
    text(pass, self.app.font, "unknown extension: " .. tostring(cell.scene),
      x + 10, y + 10, { 1, 0.55, 0.55, 1 }, 0.75)
    return
  end
  surface:ensure(renderer, w, h)
  surface:render(renderer, lovr.timer.getTime())
  surface:composite(pass, x, y, w, h)
  self.scene_rects[index] = { x = x, y = y, w = w, h = h,
    surface = surface, cell = cell, renderer = renderer }
  table.insert(self.extension_passes, surface.pass)

  box(pass, x, y, w, h, { 0.02, 0.025, 0.04, 0 })
  pass:setFont(self.app.font)
  pass:setColor(0.8, 0.85, 0.95, 1)
  pass:text("surface: Pass + Texture (host-rendered)", x + 10, y + 8, 0, 0.72,
    0, 0, 1, 0, 0, "left", "top")
end

function UI:textinput(value)
  if value == "\r" or value == "\n" then return end
  if self.focused_surface then
    self.focused_surface:text(value)
    return
  end
  local cell = self.app:notebook():selected()
  if cell.kind ~= "code" then return end
  self.app:notebook():insert(value)
end

function UI:keypressed(key)
  local notebook = self.app:notebook()
  if key == "f5" then
    self.app:run()
  elseif key == "tab" then
    if notebook:selected().kind == "code" then
      notebook:insert("  ")
    end
  elseif key == "backspace" then
    notebook:backspace()
  elseif key == "delete" then
    notebook:delete()
  elseif key == "left" then
    notebook:move_cursor(-1)
  elseif key == "right" then
    notebook:move_cursor(1)
  elseif key == "home" then
    notebook:cursor_home()
  elseif key == "end" then
    notebook:cursor_end()
  elseif key == "return" then
    if notebook:selected().kind == "code" then
      notebook:newline()
    end
  elseif key == "up" then
    notebook:move(-1)
  elseif key == "down" then
    notebook:move(1)
  end
end

function UI:mousepressed(x, y, button)
  if button ~= 1 then return end
  for _, rect in pairs(self.scene_rects) do
    if inside(x, y, rect) then
      self.drag = rect
      self.focused_surface = rect.surface
      self.app:notebook():select(rect.cell._index)
      rect.surface:pointer({
        type = "down",
        x = x - rect.x,
        y = y - rect.y,
        dx = 0,
        dy = 0,
      })
      return
    end
  end
  self.focused_surface = nil
  if self.buttons.run and inside(x, y, self.buttons.run) then
    self.app:run()
    return
  end
  if self.buttons.add and inside(x, y, self.buttons.add) then
    self.app:add_cell()
    return
  end
  for _, tab in ipairs(self.tabs) do
    if inside(x, y, tab) then
      self.app:set_tab(tab.index)
      return
    end
  end
  for index, rect in pairs(self.rects) do
    if inside(x, y, rect) then
      self.app:notebook():select(index)
      return
    end
  end
end

function UI:mousemoved(x, y, dx, dy)
  if self.drag and self.drag.surface then
    local rect = self.drag
    rect.surface:pointer({
      type = "move",
      x = x - rect.x,
      y = y - rect.y,
      dx = dx or 0,
      dy = dy or 0,
    })
  end
end

function UI:mousereleased(x, y, button)
  if button == 1 then
    if self.drag and self.drag.surface then
      local rect = self.drag
      rect.surface:pointer({
        type = "up",
        x = x - rect.x,
        y = y - rect.y,
        dx = 0,
        dy = 0,
      })
    end
    self.drag = nil
  end
end

function UI:wheelmoved(dy)
  local mx, my = lovr.system.getMousePosition()
  for _, rect in pairs(self.scene_rects) do
    if inside(mx, my, rect) then
      rect.surface:pointer({ type = "wheel", dy = dy })
      return
    end
  end
  self.scroll = math.max(0, math.min(self.max_scroll, self.scroll + dy * 28))
end

return UI
