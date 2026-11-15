--
-- Minimal immediate-mode notebook UI.  It intentionally avoids a GUI
-- dependency for the first milestone: cells, tabs, a tiny text editor, and a
-- real 3D viewport are enough to validate the architecture.
--
local Plot = require("ui.plot")
local Surface = require("ui.surface")
local Widgets = require("ui.widgets")
local Scroll = require("ui.scroll")
local Math = require("notebook.math")
local NotebookModel = require("notebook.model")
local Highlight = require("ui.highlight")
local LSP = require("notebook.lsp")
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

local TOKEN_COLORS = {
  keyword = { 0.78, 0.62, 1, 1 },
  string = { 0.55, 0.85, 0.62, 1 },
  number = { 0.95, 0.72, 0.45, 1 },
  comment = { 0.48, 0.54, 0.62, 1 },
  identifier = { 0.86, 0.88, 0.94, 1 },
  operator = { 0.62, 0.72, 0.86, 1 },
  space = { 0.86, 0.88, 0.94, 1 },
}

local function draw_code_line(pass, font, line, x, y, scale)
  local cursor = x
  for _, token in ipairs(Highlight.line(line)) do
    local color = TOKEN_COLORS[token.kind] or TOKEN_COLORS.identifier
    text(pass, font, token.text, cursor, y, color, scale)
    cursor = cursor + font:getWidth(token.text) * scale
  end
end

local function math_width(font, node, scale)
  if node.kind == "text" then return font:getWidth(node.text or "") * scale end
  local prefix = font:getWidth(node.prefix or "") * scale
  local suffix = font:getWidth(node.suffix or "") * scale
  local width = math.max(math_width(font, node.numerator, scale * 0.8),
    math_width(font, node.denominator, scale * 0.8))
  return prefix + width + suffix
end

local function draw_math(pass, font, node, x, y, scale, color)
  if node.kind == "text" then
    text(pass, font, node.text, x, y, color, scale)
    return
  end
  local prefix_width = font:getWidth(node.prefix or "") * scale
  local width = math.max(math_width(font, node.numerator, scale * 0.8),
    math_width(font, node.denominator, scale * 0.8))
  local left = x + prefix_width + width / 2
  draw_math(pass, font, node.numerator, left, y - 7 * scale,
    scale * 0.8, color)
  box(pass, left - width / 2, y + 1, width, 1.5, color)
  draw_math(pass, font, node.denominator, left, y + 4 * scale,
    scale * 0.8, color)
  text(pass, font, node.suffix or "", x + prefix_width + width, y, color, scale)
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
    widget_rects = {},
    output_rects = {},
    focused_output_cell = nil,
    widget_drag = nil,
    drag = nil,
    focused_surface = nil,
    focused_widget = nil,
    scroll_to_selected = true,
    last_active = nil,
    heading_rects = {},
    show_extensions = false,
    extension_rects = {},
    show_outline = false,
    outline_rects = {},
    show_help = false,
    show_palette = false,
    palette_rects = {},
    palette_query = "",
    palette_selected = 1,
    completion = nil,
    completion_rects = {},
    show_tree = false,
    hover = nil,
    vim_visual = false,
    vim_anchor = nil,
    vim_yank = nil,
    vim_registers = {},
    vim_register = '"',
    vim_pending_register = false,
    vim_char_visual = false,
    vim_char_anchor = nil,
    vim_char_yank = nil,
    vim_command = nil,
    vim_search = nil,
    vim_last_search = nil,
    tree_rects = {},
    tree_items = {},
    rename_prompt = nil,
    folder_prompt = nil,
    confirm_delete = nil,
    symbol_prompt = nil,
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
  if self.last_active ~= notebook.active then
    self.last_active = notebook.active
    self.scroll_to_selected = true
  end
  local y = 66 - self.scroll
  self.rects = {}
  local content_height = 0

  local visible = {}
  local hide_until = nil
  for index, cell in ipairs(notebook.cells) do
    local level = NotebookModel.heading_level(cell)
    if hide_until and level and level <= hide_until then hide_until = nil end
    if not hide_until then visible[#visible + 1] = index end
    if cell.collapsed and level then hide_until = level end
  end

  for _, index in ipairs(visible) do
    local cell = notebook.cells[index]
    cell._index = index
    local source_lines = split_lines(cell.source)
    local source_height = 0
    for _, source_line in ipairs(source_lines) do
      source_height = source_height +
        (Math.display_fraction(source_line) and 56 or
          (Math.display_matrix(source_line) and 90 or
          (Math.display_root(source_line) and 44 or 21)))
    end
    source_height = math.max(63, source_height)
    local widget_height = Widgets.height(cell.widgets)
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
    local diagnostic = cell.kind == "code" and LSP.diagnostics(cell.source)
    local diagnostic_height = diagnostic and 18 or 0
    local cell_height = 30 + source_height + widget_height +
      output_height + scene_height + diagnostic_height + 14
    self.rects[index] = { x = 20, y = y, w = width - 40, h = cell_height }
    content_height = content_height + cell_height + 10

    if y + cell_height > 55 and y < height - 10 then
      local selected = index == notebook.active
      local in_visual = self.vim_visual and self.vim_anchor and
        index >= math.min(self.vim_anchor, notebook.active) and
        index <= math.max(self.vim_anchor, notebook.active)
      local fill = in_visual and { 0.13, 0.16, 0.24, 1 } or
        (selected and { 0.095, 0.11, 0.15, 1 } or
        { 0.075, 0.085, 0.11, 1 })
      box(pass, 20, y, width - 40, cell_height, fill)
      if selected then
        local accent = { 0.35, 0.62, 0.95, 1 }
        box(pass, 20, y, 4, cell_height, accent)
      end
      local output_focused = self.focused_output_cell == index
      if output_focused then
        local border = { 0.35, 0.78, 0.95, 1 }
        box(pass, 20, y, width - 40, 2, border)
        box(pass, 20, y + cell_height - 2, width - 40, 2, border)
        box(pass, width - 22, y, 2, cell_height, border)
      end
      local kind_color = cell.kind == "markdown" and
        { 0.7, 0.65, 0.95, 1 } or { 0.45, 0.75, 0.95, 1 }
      local heading = NotebookModel.heading_level(cell)
      if heading then
        text(pass, app.font, cell.collapsed and "▸" or "▾", 25, y + 8,
          { 0.7, 0.8, 1, 1 }, 0.8)
        self.heading_rects[index] = { x = 20, y = y, w = width - 40, h = 30 }
      end
      text(pass, app.font, string.upper(cell.kind) .. "  " .. cell_label(index),
        34, y + 8, kind_color, 0.72)
      if cell.running then
        text(pass, app.font, "running...", width - 130, y + 8,
          { 0.95, 0.75, 0.35, 1 }, 0.72)
      end

      local source_y = y + 30
      local source_color = cell.kind == "markdown" and
        { 0.75, 0.78, 0.9, 1 } or { 0.86, 0.88, 0.94, 1 }
      local char_a, char_b
      if self.vim_char_visual and self.vim_char_anchor and
         index == notebook.active and cell.kind == "code" then
        char_a = math.min(self.vim_char_anchor, cell.cursor or 1)
        char_b = math.max(self.vim_char_anchor, cell.cursor or 1)
      end
      local line_y = source_y
      for line_index = 1, math.min(#source_lines, 14) do
        local display = source_lines[line_index]
        local display_fraction = cell.kind == "markdown" and
          Math.display_fraction(display)
        local display_matrix = cell.kind == "markdown" and
          Math.display_matrix(display)
        local display_root = cell.kind == "markdown" and
          Math.display_root(display)
        local display_math = cell.kind == "markdown" and
          Math.display(display)
        if display_fraction then
          local total = math_width(app.title_font, display_fraction, 1.2)
          draw_math(pass, app.title_font, display_fraction,
            width / 2 - total / 2, line_y + 22, 1.2,
            { 0.88, 0.9, 1, 1 })
          line_y = line_y + 56
        elseif display_matrix then
          local columns = 0
          for _, row in ipairs(display_matrix) do
            columns = math.max(columns, #row)
          end
          local column_widths = {}
          for column = 1, columns do column_widths[column] = 60 end
          for _, row in ipairs(display_matrix) do
            for column = 1, columns do
              column_widths[column] = math.max(column_widths[column],
                app.title_font:getWidth(row[column] or "") * 0.8 + 24)
            end
          end
          local total_w = 0
          for column = 1, columns do total_w = total_w + column_widths[column] end
          local left = width / 2 - total_w / 2
          local matrix_h = #display_matrix * 28
          box(pass, left - 14, line_y + 4, 2, matrix_h,
            { 0.65, 0.72, 0.9, 1 })
          box(pass, left + total_w + 12, line_y + 4, 2, matrix_h,
            { 0.65, 0.72, 0.9, 1 })
          for row_index, row in ipairs(display_matrix) do
            local column_x = left
            for column = 1, columns do
              local cell_center = column_x + column_widths[column] / 2
              text(pass, app.title_font, row[column] or "", cell_center,
                line_y + 8 + (row_index - 1) * 28,
                { 0.88, 0.9, 1, 1 }, 0.8, "center")
              column_x = column_x + column_widths[column]
            end
          end
          line_y = line_y + 90
        elseif display_root then
          local root_width = app.title_font:getWidth(display_root) * 0.9
          text(pass, app.title_font, "√", width / 2 - root_width / 2 - 16,
            line_y + 8, { 0.88, 0.9, 1, 1 }, 0.9)
          box(pass, width / 2 - root_width / 2 - 4, line_y + 10,
            root_width + 8, 1.5, { 0.75, 0.8, 0.95, 1 })
          text(pass, app.title_font, display_root, width / 2,
            line_y + 12, { 0.88, 0.9, 1, 1 }, 0.9, "center")
          line_y = line_y + 44
        elseif display_math then
          text(pass, app.title_font, display_math, width / 2, line_y,
            { 0.88, 0.9, 1, 1 }, 0.8, "center")
          line_y = line_y + 21
        elseif cell.kind == "markdown" then
          local x = 36
          for _, segment in ipairs(Math.segments(display)) do
            local line_font = app.font
            text(pass, line_font, segment.text, x, line_y, source_color, 0.86)
            x = x + line_font:getWidth(segment.text) * 0.86
          end
          line_y = line_y + 21
        else
          if char_a then
            local line_start = 0
            for previous = 1, line_index - 1 do
              line_start = line_start + #source_lines[previous] + 1
            end
            local line_end = line_start + #display
            local from = math.max(char_a, line_start + 1)
            local to = math.min(char_b, line_end + 1)
            if from < to then
              local prefix = display:sub(1, from - line_start - 1)
              local selected = display:sub(from - line_start,
                to - line_start - 1)
              local select_x = 36 + app.font:getWidth(prefix) * 0.86
              box(pass, select_x, line_y, app.font:getWidth(selected) * 0.86,
                18, { 0.18, 0.32, 0.52, 1 })
            end
          end
          draw_code_line(pass, app.font, display, 36, line_y, 0.86)
          line_y = line_y + 21
        end
      end
      if cell.kind == "code" and selected then
        local cursor_pos = cell.cursor or (#cell.source + 1)
        local line_start = 0
        local cursor_line = 1
        for candidate = 1, math.min(#source_lines, 14) do
          local line_length = #source_lines[candidate]
          if cursor_pos <= line_start + line_length + 1 then
            cursor_line = candidate
            break
          end
          line_start = line_start + line_length + 1
        end
        local cursor_text = source_lines[cursor_line] or ""
        local offset = math.max(0, math.min(#cursor_text, cursor_pos - line_start - 1))
        local cursor_x = 36 + app.font:getWidth(cursor_text:sub(1, offset)) * 0.86
        box(pass, cursor_x + 2, source_y + (cursor_line - 1) * 21 + 2, 2, 18,
          { 0.4, 0.75, 1, 1 })
      end

      if diagnostic then
        text(pass, app.font, "syntax: " .. diagnostic.message, 36,
          source_y + source_height + 2, { 0.95, 0.55, 0.55, 1 }, 0.64)
      end
      local widget_y = source_y + source_height + 2 + diagnostic_height
      if #(cell.widgets or {}) > 0 then
        local height, controls = Widgets.draw(pass, app.font, cell.widgets,
          34, widget_y, width - 68)
        for _, control in ipairs(controls) do
          control.cell = index
        end
        self.widget_rects[index] = controls
      end
      local output_y = source_y + source_height + widget_height + 6
      if #output_lines > 0 then
        self.output_rects[index] = { x = 34, y = output_y - 3,
          w = width - 68, h = output_height }
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

  -- Content height is independent of the current scroll offset.  Deriving it
  -- from the shifted bottom made max_scroll shrink as the view scrolled, which
  -- produced visible oscillation on tall final cells.
  local total = Scroll.max_scroll(content_height, height)
  self.max_scroll = total

  -- Auto-scroll exactly once when the selected cell changes.  Doing this
  -- every frame caused an oscillation when the selected cell was taller than
  -- the viewport.
  if self.scroll_to_selected then
    local selected_rect = self.rects[notebook.active]
    if selected_rect then
      local top = 60
      local bottom = height - 38
      self.scroll = Scroll.target_scroll(self.scroll, selected_rect.y,
        selected_rect.h, height, content_height)
    end
    self.scroll_to_selected = false
  end
  if self.scroll > total then self.scroll = total end

  -- Status/footer.
  box(pass, 0, height - 28, width, 28, { 0.075, 0.085, 0.11, 1 })
  local vim_label = app.vim_mode and (self.vim_normal and "VIM NORMAL" or
    "VIM INSERT") or "VIM OFF"
  text(pass, app.font, vim_label, width - 160, height - 22,
    { 0.55, 0.7, 0.85, 1 }, 0.66)
  text(pass, app.font, app.status, 16, height - 22,
    { 0.6, 0.68, 0.82, 1 }, 0.72)
  text(pass, app.font, "F5 run   F6 save   F7 load   Tab indent   Up/Down cell",
    width - 470, height - 22, { 0.45, 0.5, 0.62, 1 }, 0.65)
  self:draw_completion(pass, width, height)
  self:draw_hover(pass, width, height)
  self:draw_tree(pass, width, height)
  self:draw_rename(pass, width, height)
  self:draw_confirm(pass, width, height)
  self:draw_symbol_prompt(pass, width, height)
  self:draw_outline(pass, width, height)
  self:draw_extension_browser(pass, width, height)
  self:draw_help(pass, width, height)
  self:draw_palette(pass, width, height)
  if self.vim_command ~= nil or self.vim_search ~= nil then
    box(pass, 0, height - 32, width, 32, { 0.03, 0.04, 0.06, 1 })
    local prefix = self.vim_search ~= nil and "/" or ":"
    local value = self.vim_search ~= nil and self.vim_search or self.vim_command
    text(pass, app.font, prefix .. value .. "|", 16, height - 25,
      { 0.85, 0.92, 1, 1 }, 0.74)
  end
  return self.extension_passes
end

function UI:palette_commands()
  local commands = {
    { id = "run", label = "Run selected cell  (F5)" },
    { id = "save", label = "Save notebook  (F6)" },
    { id = "load", label = "Load notebook  (F7)" },
    { id = "new", label = "New notebook" },
    { id = "tree", label = "Notebook filetree  (F2)" },
    { id = "vim", label = "Toggle Vim mode  (F3)" },
    { id = "undo", label = "Undo" },
    { id = "redo", label = "Redo" },
    { id = "extensions", label = "Extension browser  (F10)" },
    { id = "outline", label = "Heading outline  (F11)" },
    { id = "help", label = "Shortcut help  (F12)" },
  }
  local query = self.palette_query:lower()
  if query == "" then return commands end
  local filtered = {}
  for _, command in ipairs(commands) do
    if command.label:lower():find(query, 1, true) then
      filtered[#filtered + 1] = command
    end
  end
  return filtered
end

function UI:run_palette_command(id)
  self.show_palette = false
  if id == "run" then self.app:run()
  elseif id == "save" then self.app:save()
  elseif id == "load" then self.app:load()
  elseif id == "new" then self.app:new_notebook()
  elseif id == "tree" then self.show_tree = true
  elseif id == "vim" then
    self.app.vim_mode = not self.app.vim_mode
    self.vim_normal = false
  elseif id == "undo" then self.app:notebook():undo()
  elseif id == "redo" then self.app:notebook():redo()
  elseif id == "extensions" then self.show_extensions = true
  elseif id == "outline" then self.show_outline = true
  elseif id == "help" then self.show_help = true
  end
end

function UI:draw_palette(pass, width, height)
  self.palette_rects = {}
  if not self.show_palette then return end
  local commands = self:palette_commands()
  if self.palette_selected > #commands then
    self.palette_selected = math.max(1, #commands)
  end
  local panel_w, panel_h = 460, 100 + #commands * 32
  local x, y = (width - panel_w) / 2, 100
  box(pass, x, y, panel_w, panel_h, { 0.035, 0.045, 0.07, 0.99 })
  text(pass, self.app.font, "Command palette  ·  type to filter", x + 18, y + 12,
    0.7, { 0.8, 0.86, 0.98, 1 })
  box(pass, x + 12, y + 34, panel_w - 24, 26, { 0.08, 0.1, 0.15, 1 })
  text(pass, self.app.font, self.palette_query .. "|", x + 20, y + 39, 0.72,
    { 0.9, 0.95, 1, 1 })
  if #commands == 0 then
    text(pass, self.app.font, "No matching command", x + 20, y + 78, 0.7,
      { 0.6, 0.65, 0.75, 1 })
  end
  for index, command in ipairs(commands) do
    local row_y = y + 72 + (index - 1) * 32
    local selected = index == self.palette_selected
    box(pass, x + 10, row_y, panel_w - 20, 27,
      selected and { 0.16, 0.25, 0.4, 1 } or { 0.09, 0.12, 0.18, 1 })
    text(pass, self.app.font, command.label, x + 20, row_y + 6, 0.7,
      { 0.8, 0.88, 1, 1 })
    self.palette_rects[#self.palette_rects + 1] = {
      x = x + 10, y = row_y, w = panel_w - 20, h = 27, id = command.id,
    }
  end
end

function UI:draw_help(pass, width, height)
  if not self.show_help then return end
  local lines = {
    "F5   run selected cell",
    "F6   save notebook",
    "F7   load notebook",
    "F8   reload focused extension",
    "F9   reload user extensions",
    "F10  extension browser",
    "F11  heading outline",
    "F12  close this help",
    "Tab  indent · Backspace/Delete · arrows move",
    "Drag a 3D surface to orbit; wheel to zoom",
  }
  local panel_w, panel_h = 560, 90 + #lines * 24
  local x, y = (width - panel_w) / 2, (height - panel_h) / 2
  box(pass, x, y, panel_w, panel_h, { 0.035, 0.045, 0.07, 0.99 })
  text(pass, self.app.font, "Lua Notebooks shortcuts", x + 20, y + 16, 0.85,
    { 0.9, 0.94, 1, 1 })
  for index, line in ipairs(lines) do
    text(pass, self.app.font, line, x + 26, y + 54 + (index - 1) * 24, 0.72,
      { 0.75, 0.82, 0.94, 1 })
  end
end

function UI:draw_hover(pass, width, height)
  if self.hover == nil then return end
  local panel_w, panel_h = 560, 64
  local x, y = (width - panel_w) / 2, height - 180
  box(pass, x, y, panel_w, panel_h, { 0.04, 0.05, 0.08, 1 })
  text(pass, self.app.font, self.hover.word, x + 14, y + 10,
    { 0.8, 0.9, 1, 1 }, 0.72)
  text(pass, self.app.font, self.hover.text, x + 14, y + 34,
    { 0.75, 0.82, 0.94, 1 }, 0.66)
end

function UI:draw_tree(pass, width, height)
  self.tree_rects = {}
  if not self.show_tree then return end
  local items = self.app:library_items()
  local panel_w = 360
  local panel_h = 122 + math.max(1, #items) * 26
  local x, y = 20, 66
  box(pass, x, y, panel_w, panel_h, { 0.035, 0.045, 0.07, 1 })
  text(pass, self.app.font, "Files  (F2 to close)", x + 14, y + 12,
    { 0.9, 0.94, 1, 1 }, 0.74)
  box(pass, x + 12, y + 36, (panel_w - 28) / 2, 26, { 0.12, 0.22, 0.16, 1 })
  text(pass, self.app.font, "+ Notebook", x + 22, y + 42,
    { 0.8, 0.95, 0.85, 1 }, 0.66)
  self.tree_rects[#self.tree_rects + 1] = {
    x = x + 12, y = y + 36, w = (panel_w - 28) / 2, h = 26, action = "new",
  }
  box(pass, x + 18 + (panel_w - 28) / 2, y + 36, (panel_w - 28) / 2, 26,
    { 0.12, 0.16, 0.26, 1 })
  text(pass, self.app.font, "+ Folder", x + 28 + (panel_w - 28) / 2, y + 42,
    { 0.8, 0.88, 1, 1 }, 0.66)
  self.tree_rects[#self.tree_rects + 1] = {
    x = x + 18 + (panel_w - 28) / 2, y = y + 36,
    w = (panel_w - 28) / 2, h = 26, action = "folder",
  }
  for index, item in ipairs(items) do
    local row_y = y + 72 + (index - 1) * 26
    local indent = 14 + item.depth * 18
    local active = item.kind == "file" and self.app:notebook()._path ==
      item.path
    box(pass, x + 10, row_y, panel_w - 20, 23,
      active and { 0.14, 0.22, 0.34, 1 } or { 0.065, 0.075, 0.1, 1 })
    local marker = item.kind == "directory" and
      (self.app.tree_expanded[item.path] and "▾ " or "▸ ") or "• "
    text(pass, self.app.font, marker .. item.name, x + indent, row_y + 4,
      { 0.82, 0.88, 1, 1 }, 0.66)
    self.tree_rects[#self.tree_rects + 1] = {
      x = x + 10, y = row_y, w = panel_w - 52, h = 23, path = item.path,
      kind = item.kind, name = item.name,
    }
    if item.kind == "file" then
      text(pass, self.app.font, "✎", x + panel_w - 58, row_y + 3,
        { 0.7, 0.8, 1, 1 }, 0.7)
      self.tree_rects[#self.tree_rects + 1] = {
        x = x + panel_w - 66, y = row_y, w = 24, h = 23,
        action = "rename", name = item.name,
      }
      text(pass, self.app.font, "×", x + panel_w - 32, row_y + 3,
        { 0.9, 0.45, 0.45, 1 }, 0.7)
      self.tree_rects[#self.tree_rects + 1] = {
        x = x + panel_w - 40, y = row_y, w = 26, h = 23,
        action = "delete", name = item.name,
      }
    end
  end
end

function UI:draw_rename(pass, width, height)
  if self.rename_prompt == nil then return end
  local panel_w, panel_h = 460, 90
  local x, y = (width - panel_w) / 2, 140
  box(pass, x, y, panel_w, panel_h, { 0.04, 0.05, 0.08, 1 })
  text(pass, self.app.font, "Rename notebook", x + 16, y + 12,
    { 0.9, 0.94, 1, 1 }, 0.72)
  box(pass, x + 14, y + 40, panel_w - 28, 28, { 0.09, 0.12, 0.18, 1 })
  text(pass, self.app.font, self.rename_prompt.value .. "|", x + 24, y + 47,
    { 0.85, 0.92, 1, 1 }, 0.7)
end

function UI:draw_confirm(pass, width, height)
  if self.confirm_delete == nil and self.folder_prompt == nil then return end
  local panel_w, panel_h = 500, 100
  local x, y = (width - panel_w) / 2, 150
  box(pass, x, y, panel_w, panel_h, { 0.04, 0.05, 0.08, 1 })
  if self.vim_search ~= nil then
    self.vim_search = self.vim_search .. value
    return
  end
  if self.vim_command ~= nil then
    self.vim_command = self.vim_command .. value
    return
  end
  if self.symbol_prompt then
    if key == "escape" then
      self.symbol_prompt = nil
    elseif key == "backspace" then
      self.symbol_prompt.value = self.symbol_prompt.value:sub(1, -2)
    elseif key == "return" then
      local prompt = self.symbol_prompt
      self.symbol_prompt = nil
      if prompt.value ~= "" then
        notebook:push_undo()
        local count = LSP.rename(notebook, prompt.old, prompt.value)
        self.app.status = "renamed " .. count .. " occurrence(s)"
      end
    end
    return
  end
  if self.confirm_delete then
    text(pass, self.app.font, "Delete " .. self.confirm_delete.name .. "?",
      x + 16, y + 14, { 0.95, 0.7, 0.7, 1 }, 0.72)
    text(pass, self.app.font, "Enter/Y confirms · Escape/N cancels", x + 16,
      y + 48, { 0.7, 0.76, 0.9, 1 }, 0.66)
  else
    text(pass, self.app.font, "New folder", x + 16, y + 14,
      { 0.85, 0.92, 1, 1 }, 0.72)
    box(pass, x + 14, y + 42, panel_w - 28, 28, { 0.09, 0.12, 0.18, 1 })
    text(pass, self.app.font, self.folder_prompt.value .. "|", x + 24, y + 49,
      { 0.85, 0.92, 1, 1 }, 0.7)
  end
end

function UI:draw_symbol_prompt(pass, width, height)
  if self.symbol_prompt == nil then return end
  local panel_w, panel_h = 500, 100
  local x, y = (width - panel_w) / 2, 180
  box(pass, x, y, panel_w, panel_h, { 0.04, 0.05, 0.08, 1 })
  text(pass, self.app.font, "Rename symbol: " .. self.symbol_prompt.old,
    x + 16, y + 14, { 0.85, 0.92, 1, 1 }, 0.7)
  box(pass, x + 14, y + 44, panel_w - 28, 28, { 0.09, 0.12, 0.18, 1 })
  text(pass, self.app.font, self.symbol_prompt.value .. "|", x + 24, y + 51,
    { 0.85, 0.92, 1, 1 }, 0.7)
end

function UI:draw_outline(pass, width, height)
  self.outline_rects = {}
  if not self.show_outline then return end
  local headings = self.app:notebook():headings()
  local panel_w = 320
  local panel_h = 90 + math.max(1, #headings) * 30
  local x, y = 20, 70
  box(pass, x, y, panel_w, panel_h, { 0.045, 0.055, 0.08, 0.98 })
  text(pass, self.app.font, "Outline  (F11 to close)", x + 14, y + 14, 0.78,
    { 0.9, 0.94, 1, 1 })
  if #headings == 0 then
    text(pass, self.app.font, "No markdown headings", x + 14, y + 52, 0.7,
      { 0.55, 0.6, 0.7, 1 })
  end
  for index, heading in ipairs(headings) do
    local row_y = y + 46 + (index - 1) * 30
    local selected = heading.index == self.app:notebook().active
    box(pass, x + 8, row_y, panel_w - 16, 26,
      selected and { 0.14, 0.22, 0.34, 1 } or { 0.07, 0.08, 0.11, 1 })
    text(pass, self.app.font, (heading.collapsed and "▸ " or "▾ ") ..
      string.rep("  ", heading.level - 1) .. heading.text,
      x + 18, row_y + 6, 0.68, { 0.8, 0.86, 0.98, 1 })
    self.outline_rects[#self.outline_rects + 1] = {
      x = x + 8, y = row_y, w = panel_w - 16, h = 26, index = heading.index,
    }
  end
end

function UI:draw_extension_browser(pass, width, height)
  self.extension_rects = {}
  if not self.show_extensions then return end
  local panel_w, panel_h = 520, 120 + #Extensions.list() * 36
  local x, y = (width - panel_w) / 2, 90
  box(pass, x, y, panel_w, panel_h, { 0.06, 0.07, 0.1, 0.98 })
  text(pass, self.app.font, "Extensions  (F10 to close)", x + 16, y + 14,
    0.8, { 0.9, 0.94, 1, 1 })
  for index, extension in ipairs(Extensions.list()) do
    local row_y = y + 50 + (index - 1) * 36
    local selected = extension.enabled
    box(pass, x + 12, row_y, panel_w - 24, 30,
      selected and { 0.12, 0.22, 0.16, 1 } or { 0.12, 0.13, 0.17, 1 })
    box(pass, x + 22, row_y + 7, 16, 16,
      selected and { 0.35, 0.8, 0.55, 1 } or { 0.25, 0.28, 0.35, 1 })
    text(pass, self.app.font, extension.id .. "  ·  " .. extension.title,
      x + 50, row_y + 7, 0.72,
      selected and { 0.85, 0.95, 0.9, 1 } or { 0.55, 0.6, 0.7, 1 })
    self.extension_rects[#self.extension_rects + 1] = {
      x = x + 12, y = row_y, w = panel_w - 24, h = 30, id = extension.id,
    }
  end
end

function UI:toggle_extension(id)
  Extensions.set_enabled(id, not Extensions.is_enabled(id))
  Extensions.save_preferences()
  self.app.status = (Extensions.is_enabled(id) and "enabled " or "disabled ") .. id
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
  if self.vim_search ~= nil then
    self.vim_search = self.vim_search .. value
    return
  end
  if self.vim_command ~= nil then
    self.vim_command = self.vim_command .. value
    return
  end
  if self.symbol_prompt then
    self.symbol_prompt.value = self.symbol_prompt.value .. value
    return
  end
  if self.rename_prompt then
    self.rename_prompt.value = self.rename_prompt.value .. value
    return
  end
  if self.folder_prompt then
    self.folder_prompt.value = self.folder_prompt.value .. value
    return
  end
  if self.vim_search ~= nil then
    self.vim_search = self.vim_search .. value
    return
  end
  if self.vim_command ~= nil then
    self.vim_command = self.vim_command .. value
    return
  end
  if self.symbol_prompt then
    if key == "escape" then
      self.symbol_prompt = nil
    elseif key == "backspace" then
      self.symbol_prompt.value = self.symbol_prompt.value:sub(1, -2)
    elseif key == "return" then
      local prompt = self.symbol_prompt
      self.symbol_prompt = nil
      if prompt.value ~= "" then
        notebook:push_undo()
        local count = LSP.rename(notebook, prompt.old, prompt.value)
        self.app.status = "renamed " .. count .. " occurrence(s)"
      end
    end
    return
  end
  if self.confirm_delete then return end
  if self.app.vim_mode and self.vim_normal then return end
  if self.completion then self.completion = nil end
  if self.show_palette then
    self.palette_query = self.palette_query .. value
    self.palette_selected = 1
    return
  end
  if self.focused_widget then
    local spec = self.focused_widget.spec
    spec.value = (spec.value or "") .. value
    return
  end
  if self.focused_surface then
    self.focused_surface:text(value)
    return
  end
  local cell = self.app:notebook():selected()
  if cell.kind ~= "code" then return end
  self.app:notebook():insert(value)
end

function UI:open_completion()
  local notebook = self.app:notebook()
  local cell = notebook.cells[notebook.active]
  if cell == nil or cell.kind ~= "code" then return end
  local prefix = LSP.current_word(cell.source)
  local items = LSP.complete_notebook(notebook, cell.source)
  if prefix ~= "" then
    local filtered = {}
    for _, item in ipairs(items) do
      if item:sub(1, #prefix) == prefix then filtered[#filtered + 1] = item end
    end
    items = filtered
  end
  if #items == 0 then return end
  self.completion = { cell = notebook.active, prefix = prefix, items = items,
    selected = 1 }
end

function UI:apply_completion()
  local completion = self.completion
  if completion == nil then return end
  local cell = self.app:notebook().cells[completion.cell]
  local item = completion.items[completion.selected]
  if cell and item then
    cell.source = cell.source:sub(1, #cell.source - #completion.prefix) .. item
    cell.dirty = true
    self.app.status = "completed " .. item
  end
  self.completion = nil
end

function UI:draw_completion(pass, width, height)
  self.completion_rects = {}
  if self.completion == nil then return end
  local items = self.completion.items
  local visible = math.min(#items, 8)
  local panel_w, row_h = 250, 24
  local panel_h = 12 + visible * row_h
  local x, y = 260, 100
  box(pass, x, y, panel_w, panel_h, { 0.035, 0.045, 0.07, 0.99 })
  for offset = 0, visible - 1 do
    local index = offset + 1
    local row_y = y + 6 + offset * row_h
    if index == self.completion.selected then
      box(pass, x + 5, row_y, panel_w - 10, row_h - 2,
        { 0.16, 0.25, 0.4, 1 })
    end
    text(pass, app.font, items[index], x + 14, row_y + 4,
      { 0.85, 0.9, 1, 1 }, 0.68)
    self.completion_rects[#self.completion_rects + 1] = {
      x = x + 5, y = row_y, w = panel_w - 10, h = row_h - 2, index = index,
    }
  end
end

function UI:search_vim(query)
  self.vim_last_search = query
  if query == "" then return end
  local notebook = self.app:notebook()
  for offset = 1, #notebook.cells do
    local index = ((notebook.active + offset - 2) % #notebook.cells) + 1
    local cell = notebook.cells[index]
    if LSP.find(cell.source, query) then
      notebook:select(index)
      self.scroll_to_selected = true
      self.app.status = "found " .. query .. " in " .. string.format("In [%d]", index)
      return
    end
  end
  self.app.status = "not found: " .. query
end

function UI:run_vim_command(command)
  command = command:gsub("^%s+", ""):gsub("%s+$", "")
  if command == "w" then
    self.app:save()
  elseif command == "q" then
    lovr.event.quit()
  elseif command == "wq" then
    self.app:save()
    lovr.event.quit()
  elseif command == "new" then
    self.app:new_notebook()
  elseif command == "undo" then
    self.app:notebook():undo()
  elseif command == "redo" then
    self.app:notebook():redo()
  elseif command:match("^sr/(.-)/(.-)/g?$") then
    local pattern, replacement = command:match("^sr/(.-)/(.-)/g?$")
    local global = command:sub(-1) == "g"
    local cell = self.app:notebook():selected()
    if cell and cell.kind == "code" then
      self.app:notebook():push_undo()
      local source, count = LSP.substitute_pattern(cell.source, pattern,
        replacement, global)
      cell.source = source
      cell.cursor = #source + 1
      self.app.status = "pattern substituted " .. count .. " occurrence(s)"
    end
  elseif command:match("^s/(.-)/(.-)/g?$") then
    local old_text, new_text = command:match("^s/(.-)/(.-)/g?$")
    local global = command:sub(-1) == "g"
    local cell = self.app:notebook():selected()
    if cell and cell.kind == "code" then
      self.app:notebook():push_undo()
      local source, count = LSP.substitute(cell.source, old_text, new_text, global)
      cell.source = source
      cell.cursor = #source + 1
      self.app.status = "substituted " .. count .. " occurrence(s)"
    end
  elseif command:match("^e%s+") then
    self.app:open_path("notebooks/" .. command:gsub("^e%s+", ""))
  else
    self.app.status = "unknown command: " .. command
  end
end

function UI:keypressed(key)
  local notebook = self.app:notebook()
  if self.vim_search ~= nil then
    if key == "escape" then
      self.vim_search = nil
    elseif key == "backspace" then
      self.vim_search = self.vim_search:sub(1, -2)
    elseif key == "return" then
      local query = self.vim_search
      self.vim_search = nil
      self:search_vim(query)
    end
    return
  end
  if self.vim_command ~= nil then
    if key == "escape" then
      self.vim_command = nil
    elseif key == "backspace" then
      self.vim_command = self.vim_command:sub(1, -2)
    elseif key == "return" then
      local command = self.vim_command
      self.vim_command = nil
      self:run_vim_command(command)
    end
    return
  end
  if self.vim_search ~= nil then
    self.vim_search = self.vim_search .. value
    return
  end
  if self.vim_command ~= nil then
    self.vim_command = self.vim_command .. value
    return
  end
  if self.symbol_prompt then
    if key == "escape" then
      self.symbol_prompt = nil
    elseif key == "backspace" then
      self.symbol_prompt.value = self.symbol_prompt.value:sub(1, -2)
    elseif key == "return" then
      local prompt = self.symbol_prompt
      self.symbol_prompt = nil
      if prompt.value ~= "" then
        notebook:push_undo()
        local count = LSP.rename(notebook, prompt.old, prompt.value)
        self.app.status = "renamed " .. count .. " occurrence(s)"
      end
    end
    return
  end
  if self.confirm_delete then
    if key == "return" or key == "y" then
      local path = self.confirm_delete.path
      self.confirm_delete = nil
      self.app:delete_notebook(path)
    elseif key == "escape" or key == "n" then
      self.confirm_delete = nil
    end
    return
  end
  if self.folder_prompt then
    if key == "escape" then
      self.folder_prompt = nil
    elseif key == "backspace" then
      self.folder_prompt.value = self.folder_prompt.value:sub(1, -2)
    elseif key == "return" then
      local value = self.folder_prompt.value
      self.folder_prompt = nil
      self.app:create_folder(value)
    end
    return
  end
  if self.rename_prompt then
    if key == "escape" then
      self.rename_prompt = nil
    elseif key == "backspace" then
      self.rename_prompt.value = self.rename_prompt.value:sub(1, -2)
    elseif key == "return" then
      local prompt = self.rename_prompt
      self.rename_prompt = nil
      self.app:rename_notebook(prompt.old, prompt.value)
    end
    return
  end
  if key == "r" and lovr.system and lovr.system.isKeyDown and
     (lovr.system.isKeyDown("lctrl") or lovr.system.isKeyDown("rctrl")) and
     (lovr.system.isKeyDown("lshift") or lovr.system.isKeyDown("rshift")) then
    local cell = notebook.cells[notebook.active]
    local word = cell and LSP.current_word(cell.source) or ""
    if word == "" then self.app.status = "no symbol at cursor" else
      self.symbol_prompt = { old = word, value = "" }
    end
    return
  end
  if (key == "r" or key == "z") and lovr.system and lovr.system.isKeyDown and
     (lovr.system.isKeyDown("lctrl") or lovr.system.isKeyDown("rctrl")) then
    local changed = key == "r" and notebook:redo() or notebook:undo()
    self.app.status = changed and (key == "r" and "redo" or "undo") or
      "no history"
    return
  end
  if key == "h" and lovr.system and lovr.system.isKeyDown and
     (lovr.system.isKeyDown("lctrl") or lovr.system.isKeyDown("rctrl")) then
    local cell = notebook.cells[notebook.active]
    local word = cell and LSP.current_word(cell.source) or ""
    local description = LSP.hover(word)
    if description then
      self.hover = { word = word, text = description }
    else
      self.app.status = "no hover for " .. tostring(word)
    end
    return
  elseif key == "g" and lovr.system and lovr.system.isKeyDown and
         (lovr.system.isKeyDown("lctrl") or lovr.system.isKeyDown("rctrl")) then
    local cell = notebook.cells[notebook.active]
    local word = cell and LSP.current_word(cell.source) or ""
    local definition = LSP.find_definition(notebook, word)
    if definition then
      notebook:select(definition.cell)
      self.scroll_to_selected = true
      self.app.status = "definition in " .. string.format("In [%d]:%d",
        definition.cell, definition.line)
    else
      self.app.status = "no definition for " .. tostring(word)
    end
    return
  end
  if self.hover and key == "escape" then
    self.hover = nil
    return
  end
  if self.app.vim_mode and self.vim_normal then
    if key == "/" then
      self.vim_search = ""
      return
    elseif key == "n" and self.vim_last_search then
      self:search_vim(self.vim_last_search)
      return
    elseif key == ":" then
      self.vim_command = ""
      return
    elseif key == "v" then
      local cell = notebook.cells[notebook.active]
      if cell.kind == "code" then
        self.vim_char_visual = true
        self.vim_char_anchor = cell.cursor or (#cell.source + 1)
        self.vim_visual = false
      end
      return
    elseif key == "h" then
      notebook:move_cursor(-1); return
    elseif key == "l" then
      notebook:move_cursor(1); return
    elseif self.vim_pending_register then
      if key:match("^[a-z]$") then
        self.vim_register = key
        self.app.status = "register " .. key
      end
      self.vim_pending_register = false
      return
    elseif key == '"' then
      self.vim_pending_register = true
      return
    elseif key == "escape" then
      self.vim_visual = false
      self.vim_anchor = nil
      self.vim_char_visual = false
      self.vim_char_anchor = nil
      return
    elseif key == "V" then
      self.vim_visual = not self.vim_visual
      self.vim_anchor = self.vim_visual and notebook.active or nil
      self.vim_char_visual = false
      return
    elseif key == "y" and self.vim_char_visual then
      self.vim_char_yank = notebook:selection_text(self.vim_char_anchor,
        notebook.cells[notebook.active].cursor)
      self.vim_char_visual = false
      self.vim_char_anchor = nil
      self.app.status = "yanked " .. #self.vim_char_yank .. " character(s)"
      return
    elseif key == "d" and self.vim_char_visual then
      notebook:push_undo()
      notebook:delete_range(self.vim_char_anchor,
        notebook.cells[notebook.active].cursor)
      self.vim_char_visual = false
      self.vim_char_anchor = nil
      return
    elseif key == "p" and self.vim_char_yank and #self.vim_char_yank > 0 then
      notebook:push_undo()
      notebook:insert(self.vim_char_yank)
      return
    elseif key == "y" and self.vim_visual then
      local first = math.min(self.vim_anchor, notebook.active)
      local last = math.max(self.vim_anchor, notebook.active)
      self.vim_yank = {}
      for index = first, last do
        self.vim_yank[#self.vim_yank + 1] = notebook:copy_cell(index)
      end
      self.vim_registers[self.vim_register] = self.vim_yank
      self.vim_visual = false
      self.vim_anchor = nil
      self.app.status = "yanked " .. #self.vim_yank .. " cell(s) to " ..
        self.vim_register
      return
    elseif key == "d" and self.vim_visual then
      local first = math.min(self.vim_anchor, notebook.active)
      local last = math.max(self.vim_anchor, notebook.active)
      for _ = first, last do notebook:delete_cell(first) end
      self.vim_visual = false
      self.vim_anchor = nil
      return
    elseif key == "y" then
      self.vim_yank = { notebook:copy_cell(notebook.active) }
      self.vim_registers[self.vim_register] = self.vim_yank
      self.app.status = "yanked current cell to " .. self.vim_register
      return
    elseif key == "p" and (self.vim_registers[self.vim_register] or
                           self.vim_yank) then
      local cells = self.vim_registers[self.vim_register] or self.vim_yank
      for offset, cell in ipairs(cells) do
        notebook:insert_cell(notebook.active + offset,
          notebook:copy_cell(notebook.active))
        local target = notebook.cells[notebook.active + offset]
        if target then
          for field, value in pairs(cell) do target[field] = value end
        end
      end
      return
    elseif key == "i" or key == "a" then
      self.vim_normal = false
      return
    elseif key == "j" then
      notebook:move(1); self.scroll_to_selected = true; return
    elseif key == "k" then
      notebook:move(-1); self.scroll_to_selected = true; return
    elseif key == "o" then
      notebook:add_cell("code"); self.vim_normal = false; return
    elseif key == "u" then
      self.app.status = notebook:undo() and "undo" or "nothing to undo"
      return
    elseif key == "x" then
      local cell = notebook.cells[notebook.active]
      if cell and cell.kind == "code" then
        cell.source = cell.source:sub(1, -2)
      end
      return
    end
  elseif self.app.vim_mode and key == "escape" then
    self.vim_normal = true
    return
  end
  if self.completion then
    if key == "escape" then
      self.completion = nil
      return
    elseif key == "up" then
      self.completion.selected = math.max(1, self.completion.selected - 1)
      return
    elseif key == "down" then
      self.completion.selected = math.min(#self.completion.items,
        self.completion.selected + 1)
      return
    elseif key == "return" or key == "tab" then
      self:apply_completion()
      return
    end
  end
  if key == "space" and lovr.system and lovr.system.isKeyDown and
     (lovr.system.isKeyDown("lctrl") or lovr.system.isKeyDown("rctrl")) then
    self:open_completion()
    return
  end
  if self.show_palette then
    local commands = self:palette_commands()
    if key == "escape" or key == "f1" then
      self.show_palette = false
    elseif key == "backspace" then
      self.palette_query = self.palette_query:sub(1, -2)
      self.palette_selected = 1
    elseif key == "up" then
      self.palette_selected = math.max(1, self.palette_selected - 1)
    elseif key == "down" then
      self.palette_selected = math.min(#commands, self.palette_selected + 1)
    elseif key == "return" and commands[self.palette_selected] then
      self:run_palette_command(commands[self.palette_selected].id)
    end
    return
  end
  if self.focused_widget then
    local widget = self.focused_widget
    local spec = widget.spec
    if key == "backspace" then
      local text = spec.value or ""
      local cut = #text
      while cut > 1 do
        local byte = text:byte(cut)
        if byte < 0x80 or byte >= 0xC0 then break end
        cut = cut - 1
      end
      spec.value = text:sub(1, cut - 1)
      return
    elseif key == "return" then
      spec._focused = false
      self.focused_widget = nil
      self.app:widget_event(widget.cell, spec,
        { type = "change", value = spec.value or "" })
      return
    elseif key == "escape" then
      spec.value = widget.original
      spec._focused = false
      self.focused_widget = nil
      return
    end
  end
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

function UI:set_widget_value(rect, x)
  local spec = rect.spec
  local fraction = (x - rect.track_x) / math.max(1, rect.track_w)
  fraction = math.max(0, math.min(1, fraction))
  local value = spec.min + (spec.max - spec.min) * fraction
  local step = spec.step or 0
  if step > 0 then
    value = math.floor((value - spec.min) / step + 0.5) * step + spec.min
    value = math.max(spec.min, math.min(spec.max, value))
  end
  spec.value = value
end

function UI:handle_widget(rect, cell_index, x, y)
  local spec = rect.spec
  self.app:notebook():select(cell_index)
  self.focused_surface = nil
  self.focused_output_cell = cell_index
  if spec.kind == "button" then
    self.app:widget_event(cell_index, spec, { type = "click" })
  elseif spec.kind == "checkbox" then
    self.app:widget_event(cell_index, spec, { type = "toggle" })
  elseif spec.kind == "select" then
    self.app:widget_event(cell_index, spec, { type = "next" })
  elseif spec.kind == "slider" then
    if rect.track_x and x >= rect.track_x - 8 then
      self.widget_drag = { cell = cell_index, rect = rect }
      self:set_widget_value(rect, x)
    end
  elseif spec.kind == "number" then
    local delta = 0
    if rect.minus and inside(x, y, rect.minus) then delta = -1 end
    if rect.plus and inside(x, y, rect.plus) then delta = 1 end
    if delta ~= 0 then
      spec.value = (spec.value or 0) + delta * (spec.step or 1)
      if spec.min then spec.value = math.max(spec.min, spec.value) end
      if spec.max then spec.value = math.min(spec.max, spec.value) end
      self.app:widget_event(cell_index, spec,
        { type = "change", value = spec.value })
    end
  end
end

function UI:mousepressed(x, y, button)
  if button ~= 1 then return end
  for index, rect in pairs(self.heading_rects) do
    if inside(x, y, rect) then
      local collapsed = self.app:notebook():toggle_collapsed(index)
      self.app.status = collapsed and "collapsed heading" or "expanded heading"
      return
    end
  end
  if self.hover then
    self.hover = nil
    return
  end
  if self.show_tree then
    for _, rect in ipairs(self.tree_rects) do
      if inside(x, y, rect) then
        if rect.action == "new" then
          self.app:new_notebook()
        elseif rect.action == "rename" then
          self.rename_prompt = {
            old = rect.path, value = rect.name:gsub("%.luanb$", ""),
          }
        elseif rect.action == "folder" then
          self.folder_prompt = { value = "" }
        elseif rect.action == "delete" then
          self.confirm_delete = { name = rect.name, path = rect.path }
        elseif rect.kind == "directory" then
          self.app.tree_expanded[rect.path] =
            not self.app.tree_expanded[rect.path]
        elseif rect.path then
          self.app:open_path(rect.path)
          self.show_tree = false
        end
        return
      end
    end
  end
  if self.completion then
    for _, rect in ipairs(self.completion_rects) do
      if inside(x, y, rect) then
        self.completion.selected = rect.index
        self:apply_completion()
        return
      end
    end
    self.completion = nil
  end
  if self.show_palette then
    for _, rect in ipairs(self.palette_rects) do
      if inside(x, y, rect) then
        self:run_palette_command(rect.id)
        return
      end
    end
    return
  end
  if self.show_help then
    self.show_help = false
    return
  end
  if self.show_outline then
    for _, rect in ipairs(self.outline_rects) do
      if inside(x, y, rect) then
        self.app:notebook():select(rect.index)
        self.show_outline = false
        self.app.status = "jumped to heading"
        return
      end
    end
  end
  if self.show_extensions then
    for _, rect in ipairs(self.extension_rects) do
      if inside(x, y, rect) then
        self:toggle_extension(rect.id)
        return
      end
    end
    return
  end
  for cell_index, controls in pairs(self.widget_rects) do
    for _, rect in ipairs(controls) do
      if inside(x, y, rect) then
        self:handle_widget(rect, cell_index, x, y)
        return
      end
    end
  end
  if self.focused_widget then
    self.focused_widget.spec._focused = false
    self.focused_widget = nil
  end
  for _, rect in pairs(self.scene_rects) do
    if inside(x, y, rect) then
      self.drag = rect
      self.focused_surface = rect.surface
      self.focused_output_cell = rect.cell._index
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
  for index, rect in pairs(self.output_rects) do
    if inside(x, y, rect) then
      self.app:notebook():select(index)
      self.focused_output_cell = index
      self.focused_surface = nil
      self.focused_widget = nil
      return
    end
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
      self.focused_output_cell = nil
      self.focused_surface = nil
      self.focused_widget = nil
      return
    end
  end
end

function UI:mousemoved(x, y, dx, dy)
  if self.widget_drag then
    self:set_widget_value(self.widget_drag.rect, x)
    return
  end
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
    if self.widget_drag then
      local drag = self.widget_drag
      self.widget_drag = nil
      self.app:widget_event(drag.cell, drag.rect.spec,
        { type = "change", value = drag.rect.spec.value })
      return
    end
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
