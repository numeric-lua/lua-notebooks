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
local Theme = require("ui.theme")
local Markdown = require("notebook.markdown")
local Types = require("notebook.lsp.types")
local Highlight = require("ui.highlight")
local LSP = require("notebook.editor_text")
local MathEngine = require("notebook.math.engine")
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

local function text(pass, font, value, x, y, color, scale, align)
  color = Theme.map(color)
  pass:setFont(font)
  pass:setColor(color[1], color[2], color[3], color[4] or 1)
  pass:text(value, x, y, 0, scale or 1, 0, 0, 1, 0, 0,
    align or "left", "top")
end

local function text_raw(pass, font, value, x, y, color, scale, align)
  pass:setFont(font)
  pass:setColor(color[1], color[2], color[3], color[4] or 1)
  pass:text(value, x, y, 0, scale or 1, 0, 0, 1, 0, 0,
    align or "left", "top")
end

local function stroke(pass, x1, y1, x2, y2, thickness, color)
  local dx, dy = x2 - x1, y2 - y1
  local length = math.sqrt(dx * dx + dy * dy)
  pass:setColor(color[1], color[2], color[3], color[4] or 1)
  pass:plane((x1 + x2) / 2, (y1 + y2) / 2, 0, length, thickness,
    math.atan2(dy, dx), 0, 0, 1)
end

local function box(pass, x, y, w, h, color)
  color = Theme.map(color)
  pass:setColor(color[1], color[2], color[3], color[4] or 1)
  pass:plane(x + w / 2, y + h / 2, 0, w, h)
end

local function box_raw(pass, x, y, w, h, color)
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

local LIGHT_TOKEN_COLORS = {
  keyword = { 0.42, 0.18, 0.72, 1 },
  string = { 0.02, 0.42, 0.22, 1 },
  number = { 0.68, 0.32, 0.02, 1 },
  comment = { 0.40, 0.44, 0.50, 1 },
  identifier = { 0.10, 0.12, 0.16, 1 },
  operator = { 0.16, 0.32, 0.62, 1 },
  space = { 0.10, 0.12, 0.16, 1 },
}

local function draw_code_line(pass, font, line, x, y, scale)
  local cursor = x
  local palette = Theme.mode == "light" and LIGHT_TOKEN_COLORS or TOKEN_COLORS
  for _, token in ipairs(Highlight.line(line)) do
    local color = palette[token.kind] or palette.identifier
    text_raw(pass, font, token.text, cursor, y, color, scale)
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
    math_layout_cache = {},
    source_lines_cache = {},
    show_outline = false,
    outline_rects = {},
    show_help = false,
    show_find = false,
    find_query = "",
    find_results = {},
    find_selected = 1,
    find_rects = {},
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
    vim_pending = nil,
    vim_text_object = nil,
    vim_recording = nil,
    vim_macros = {},
    vim_last_macro = nil,
    vim_replaying = false,
    vim_marks = {},
    vim_pending_mark = nil,
    vim_last_change = nil,
    nav_repeat = nil,
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
    zen_mode = false,
    show_history = false,
    history_items = {},
    history_selected = 1,
    vim_normal = app.vim_mode,
    vim_scope = app.vim_mode and "notebook" or "insert",
  }, UI)
end

function UI:draw(pass, logical_width, logical_height)
  local app = self.app
  local width, height = pass:getDimensions()
  width = logical_width or width
  height = logical_height or height
  self.width, self.height = width, height

  -- Full-resolution canvas, logical UI coordinates.  LÖVR fonts are SDFs, so
  -- scaling the projection keeps glyphs sharp instead of upscaling a bitmap.
  local projection = mat4():orthographic(0, width, 0, height, -1, 1)
  pass:setViewPose(1, mat4():identity())
  pass:setProjection(projection)
  pass:setDepthTest()

  if app.show_nvim and app.nvim_view then
    app.nvim_view:draw(pass, 44, 18, width - 56, height - 36,
      app.ui_scale or 1)
    text(pass, app.font, "F10 save   F5 save+run   F9 discard",
      width - 12, 2, { 0.35, 0.38, 0.46, 1 }, 0.6, "right")
    return {}
  end

  local light = Theme.mode == "light"
  local alpha = Theme.opacity or 1
  local background = light and { 0, 0, 0, alpha } or
    { 0.055, 0.06, 0.08, alpha }
  box(pass, 0, 0, width, height, background)
  self.tabs = {}
  self.buttons = {}
  self.extension_passes = {}
  self.scene_rects = {}
  self.widget_rects = {}
  self.output_rects = {}
  if not self.zen_mode then
  box(pass, 0, 0, width, 40,
    light and { 0, 0, 0, alpha } or { 0.08, 0.09, 0.12, alpha })

  -- Tabs are notebook titles, derived from the first markdown `#` heading.
  local tab_x = 12
  for index, notebook in ipairs(app.notebooks) do
    local label = notebook:title()
    local tab_w = math.max(92, math.min(240,
      app.font:getWidth(label) * 0.76 + 24))
    local active = index == app.active
    box(pass, tab_x, 7, tab_w, 26,
      active and { 0.18, 0.22, 0.32, 1 } or { 0.11, 0.12, 0.16, 1 })
    text(pass, app.font, label, tab_x + 10, 12,
      active and { 0.95, 0.96, 1, 1 } or { 0.55, 0.6, 0.7, 1 }, 0.76)
    self.tabs[#self.tabs + 1] = { x = tab_x, y = 7, w = tab_w, h = 26,
      index = index }
    tab_x = tab_x + tab_w + 6
  end

  -- Compact icon buttons.
  local run_x = width - 42
  box(pass, run_x, 7, 30, 26, { 0.18, 0.42, 0.30, 1 })
  stroke(pass, run_x + 10, 12, run_x + 10, 28, 2, { 0.92, 1, 0.94, 1 })
  stroke(pass, run_x + 10, 12, run_x + 20, 20, 2, { 0.92, 1, 0.94, 1 })
  stroke(pass, run_x + 20, 20, run_x + 10, 28, 2, { 0.92, 1, 0.94, 1 })
  self.buttons.run = { x = run_x, y = 7, w = 30, h = 26 }
  local add_x = run_x - 36
  box(pass, add_x, 7, 30, 26, { 0.15, 0.18, 0.25, 1 })
  stroke(pass, add_x + 15, 14, add_x + 15, 26, 2, { 0.82, 0.88, 1, 1 })
  stroke(pass, add_x + 9, 20, add_x + 21, 20, 2, { 0.82, 0.88, 1, 1 })
  self.buttons.add = { x = add_x, y = 7, w = 30, h = 26 }
  end

  local notebook = app:notebook()
  if self.last_active ~= notebook.active then
    self.last_active = notebook.active
    self.scroll_to_selected = true
  end
  local content_top = self.zen_mode and 12 or 52
  local y = content_top - self.scroll
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
    local source_lines = self.source_lines_cache[cell.source]
    if source_lines == nil then
      source_lines = split_lines(cell.source)
      self.source_lines_cache[cell.source] = source_lines
      if #self.source_lines_cache > 1024 then self.source_lines_cache = {} end
    end
    local math_layouts = {}
    local source_height = 0
    for line_index, source_line in ipairs(source_lines) do
      local expression = cell.kind == "markdown" and
        source_line:match("^%$%$(.-)%$%$$")
      if expression and not source_line:find("\\begin{matrix}", 1, true) then
        local cache_key = expression .. "|" .. tostring(width) .. "|" ..
          tostring(app.math_font)
        local result = self.math_layout_cache[cache_key]
        if result == nil then
          result = MathEngine.typeset(expression, {
            font = app.math_font, scale = 1.1, display = true,
            max_width = width - 100,
            fonts = { bold = app.math_bold, italic = app.math_italic },
          })
          self.math_layout_cache[cache_key] = result or false
          if #self.math_layout_cache > 512 then self.math_layout_cache = {} end
        end
        if result == false then result = nil end
        if result then
          math_layouts[line_index] = result
          source_height = source_height + result.h + 10
        else
          source_height = source_height + 21
        end
      else
        source_height = source_height +
          (Math.display_fraction(source_line) and 56 or
            (Math.display_matrix(source_line) and 90 or
            (Math.display_root(source_line) and 44 or 21)))
      end
    end
    source_height = math.max(21, source_height)
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
    local diagnostic = cell.kind == "code" and
      (self.app:server_diagnostic(cell) or LSP.diagnostics(cell.source))
    local diagnostic_height = diagnostic and 18 or 0
    local cell_height = 12 + source_height + widget_height +
      output_height + scene_height + diagnostic_height + 10
    self.rects[index] = { x = 20, y = y, w = width - 40, h = cell_height }
    content_height = content_height + cell_height + 10

    if y + cell_height > 55 and y < height - 10 then
      local selected = index == notebook.active
      local cell_scoped = selected and (not app.vim_mode or
        self.vim_scope == "cell")
      local in_visual = self.vim_visual and self.vim_anchor and
        index >= math.min(self.vim_anchor, notebook.active) and
        index <= math.max(self.vim_anchor, notebook.active)
      local fill
      if in_visual then
        fill = { 0.13, 0.16, 0.24, 1 }
      elseif light then
        -- White cells with a subtle translucent blend; selection is indicated
        -- by the accent rail, not a different background.
        fill = { 0, 0, 0, 0 }
      else
        fill = selected and { 0.095, 0.11, 0.15, 1 } or
          { 0.075, 0.085, 0.11, 1 }
      end
      box(pass, 20, y, width - 40, cell_height, fill)
      if selected then
        local accent = cell_scoped and { 0.30, 0.82, 1, 1 } or
          { 0.28, 0.42, 0.64, 1 }
        box(pass, 20, y, 4, cell_height, accent)
        local border = cell_scoped and { 0.30, 0.82, 1, 0.95 } or
          { 0.25, 0.37, 0.55, 0.8 }
        local thickness = cell_scoped and 2 or 1
        box(pass, 20, y, width - 40, thickness, border)
        box(pass, 20, y + cell_height - thickness, width - 40, thickness,
          border)
        box(pass, width - 20 - thickness, y, thickness, cell_height, border)
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
        text(pass, app.font, cell.collapsed and "▸" or "▾", 25, y + 5,
          { 0.7, 0.8, 1, 1 }, 0.8)
        self.heading_rects[index] = { x = 20, y = y, w = width - 40, h = 24 }
      end

      local source_y = y + 6
      cell._source_y = source_y
      local source_color = cell.kind == "markdown" and
        { 0.75, 0.78, 0.9, 1 } or { 0.86, 0.88, 0.94, 1 }
      local char_a, char_b
      if self.vim_char_visual and self.vim_char_anchor and
         index == notebook.active and cell.kind == "code" then
        char_a = math.min(self.vim_char_anchor, cell.cursor or 1)
        char_b = math.max(self.vim_char_anchor, cell.cursor or 1)
      end
      local preview = cell.kind == "markdown" and not selected
      local line_tops = {}
      local line_y = source_y
      for line_index = 1, #source_lines do
        line_tops[line_index] = line_y
        local raw_display = source_lines[line_index]
        local display = preview and Markdown.preview(raw_display) or raw_display
        local engine_layout = math_layouts[line_index]
        local display_fraction = cell.kind == "markdown" and
          Math.display_fraction(raw_display)
        local display_matrix = cell.kind == "markdown" and
          Math.display_matrix(raw_display)
        local display_root = cell.kind == "markdown" and
          Math.display_root(raw_display)
        local display_math = cell.kind == "markdown" and
          Math.display(raw_display)
        if engine_layout then
          MathEngine.draw(pass, engine_layout.box,
            width / 2 - engine_layout.box.w / 2,
            line_y + engine_layout.box.h, { 0.88, 0.9, 1, 1 })
          line_y = line_y + engine_layout.h + 10
        elseif display_fraction then
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
          local body_w = app.title_font:getWidth(display_root) * 0.9
          local rad_w = 18
          local total_w = rad_w + body_w + 10
          local left = width / 2 - total_w / 2
          local top = line_y + 12
          local bottom = line_y + 34
          stroke(pass, left, top + 10, left + 6, bottom, 2,
            { 0.8, 0.86, 1, 1 })
          stroke(pass, left + 6, bottom, left + rad_w, top, 2,
            { 0.8, 0.86, 1, 1 })
          stroke(pass, left + rad_w, top, left + total_w, top, 1.5,
            { 0.8, 0.86, 1, 1 })
          text(pass, app.title_font, display_root, left + rad_w + 5,
            line_y + 12, { 0.88, 0.9, 1, 1 }, 0.9)
          line_y = line_y + 44
        elseif display_math then
          text(pass, app.title_font, display_math, width / 2, line_y,
            { 0.88, 0.9, 1, 1 }, 0.8, "center")
          line_y = line_y + 21
        elseif cell.kind == "markdown" then
          local x = 36
          local heading_preview = preview and raw_display:match("^%s*#")
          local text_color = heading_preview and { 0.88, 0.92, 1, 1 } or
            source_color
          local text_scale = heading_preview and 0.98 or 0.86
          for _, segment in ipairs(Math.segments(display)) do
            local line_font = segment.math and (app.math_font or app.font) or
              app.font
            text(pass, line_font, segment.text, x, line_y, text_color,
              text_scale)
            x = x + line_font:getWidth(segment.text) * text_scale
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
      local first_line = source_lines[1] or ""
      local label_x = 36 + app.font:getWidth(first_line) * 0.86 + 8
      label_x = math.min(width - 52, label_x)
      text(pass, app.font, tostring(index), label_x, source_y,
        cell.running and { 0.95, 0.75, 0.35, 1 } or
        (cell_scoped and { 0.30, 0.82, 1, 1 } or kind_color), 0.6)

      if selected and (cell.kind == "code" or cell.kind == "markdown") and
         (not app.vim_mode or self.vim_scope ~= "notebook") then
        local cursor_pos = cell.cursor or (#cell.source + 1)
        local line_start = 0
        local cursor_line = 1
        for candidate = 1, #source_lines do
          local line_length = #source_lines[candidate]
          if cursor_pos <= line_start + line_length + 1 then
            cursor_line = candidate
            break
          end
          line_start = line_start + line_length + 1
        end
        local cursor_text = source_lines[cursor_line] or ""
        local simple_cursor_line = cell.kind == "code" or
          not (cursor_text:match("^%s*%$%$") or
            Math.display_fraction(cursor_text) or
            Math.display_matrix(cursor_text) or
            Math.display_root(cursor_text))
        if simple_cursor_line then
          local offset = math.max(0, math.min(#cursor_text,
            cursor_pos - line_start - 1))
          local cursor_x = 36 + app.font:getWidth(
            cursor_text:sub(1, offset)) * 0.86
          local cursor_y = (line_tops[cursor_line] or
            (source_y + (cursor_line - 1) * 21)) + 2
          local normal_mode = app.vim_mode and self.vim_normal
          if normal_mode then
            local next_char = cursor_text:sub(offset + 1, offset + 1)
            local char_width = next_char ~= "" and
              app.font:getWidth(next_char) * 0.86 or 9
            box(pass, cursor_x + 1, cursor_y, math.max(8, char_width), 18,
              { 0.35, 0.62, 0.95, 0.55 })
          else
            box(pass, cursor_x + 2, cursor_y, 2, 18, { 0.4, 0.75, 1, 1 })
          end
        end
      end

      if diagnostic then
        text(pass, app.font, "syntax: " .. diagnostic.message, 36,
          source_y + source_height + 2, { 0.95, 0.55, 0.55, 1 }, 0.64)
      end
      local widget_y = source_y + source_height + 2 + diagnostic_height
      if #(cell.widgets or {}) > 0 then
        local height, controls = Widgets.draw(pass, app.font, cell.widgets,
          34, widget_y, width - 68,
          self.app.qa_screenshot and 1 or lovr.timer.getTime(),
          self.app.ui_scale)
        for _, control in ipairs(controls) do
          control.cell = index
        end
        self.widget_rects[index] = controls
      end
      local output_y = source_y + source_height + widget_height + 6
      if #output_lines > 0 then
        self.output_rects[index] = { x = 34, y = output_y - 3,
          w = width - 68, h = output_height }
        if light then
          box_raw(pass, 34, output_y - 3, width - 68, output_height,
            { 0.94, 0.95, 0.97, 1 })
        else
          box(pass, 34, output_y - 3, width - 68, output_height,
            { 0.04, 0.05, 0.07, 1 })
        end
        local output_color = cell.error and
          (light and { 0.65, 0.10, 0.12, 1 } or { 1, 0.45, 0.45, 1 }) or
          (light and { 0.10, 0.40, 0.22, 1 } or { 0.55, 0.9, 0.65, 1 })
        for line_index = 1, math.min(#output_lines, 6) do
          if light then
            text_raw(pass, app.font, output_lines[line_index], 42,
              output_y + (line_index - 1) * 19, output_color, 0.78)
          else
            text(pass, app.font, output_lines[line_index], 42,
              output_y + (line_index - 1) * 19, output_color, 0.78)
          end
        end
        output_y = output_y + output_height + 4
      end

      if type(cell.scene) == "table" and cell.scene.type == "luaplotlib" then
        local ok, err = pcall(Plot.draw, pass, app.font, cell.scene, 34,
          output_y, width - 68, scene_height)
        if not ok then
          cell.error = "scene: " .. tostring(err)
          text(pass, app.font, tostring(err), 42, output_y + 8,
            light and { 0.65, 0.1, 0.12, 1 } or { 1, 0.45, 0.45, 1 }, 0.72)
        end
      elseif cell.scene then
        local ok, err = pcall(self.draw_scene, self, pass, 34, output_y,
          width - 68, scene_height, cell)
        if not ok then
          cell.error = "scene: " .. tostring(err)
          text(pass, app.font, tostring(err), 42, output_y + 8,
            light and { 0.65, 0.1, 0.12, 1 } or { 1, 0.45, 0.45, 1 }, 0.72)
        end
      end
    end
    y = y + cell_height + 10
  end

  -- Content height is independent of the current scroll offset.  Deriving it
  -- from the shifted bottom made max_scroll shrink as the view scrolled, which
  -- produced visible oscillation on tall final cells.
  local total = Scroll.max_scroll(content_height, height, content_top)
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
        selected_rect.h, height, content_height, content_top, self.zen_mode)
    end
    self.scroll_to_selected = false
  end
  if self.scroll > total then self.scroll = total end

  -- Status/footer.
  box(pass, 0, height - 28, width, 28, { 0.075, 0.085, 0.11, 1 })
  if not self.zen_mode then
    local vim_label
    if not app.vim_mode then vim_label = "EDITING"
    elseif not self.vim_normal then vim_label = "VIM INSERT"
    elseif self.vim_scope == "notebook" then vim_label = "VIM NOTEBOOK"
    else vim_label = "VIM CELL" end
    text(pass, app.font, vim_label, width - 160, height - 22,
      { 0.55, 0.7, 0.85, 1 }, 0.66)
    text(pass, app.font, app.status, 16, height - 22,
      { 0.6, 0.68, 0.82, 1 }, 0.72)
    text(pass, app.font, "F5 run   F6 save   F7 load   Tab indent   Up/Down cell",
      width - 470, height - 22, { 0.45, 0.5, 0.62, 1 }, 0.65)
  end
  self:draw_completion(pass, width, height)
  self:draw_hover(pass, width, height)
  self:draw_tree(pass, width, height)
  self:draw_rename(pass, width, height)
  self:draw_confirm(pass, width, height)
  self:draw_symbol_prompt(pass, width, height)
  self:draw_outline(pass, width, height)
  self:draw_history(pass, width, height)
  self:draw_extension_browser(pass, width, height)
  self:draw_find(pass, width, height)
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
    { id = "restart-kernel", label = "Restart current kernel" },
    { id = "save", label = "Save notebook  (F6)" },
    { id = "save-as", label = "Save notebook as…" },
    { id = "open-dialog", label = "Open notebook…" },
    { id = "load", label = "Load notebook  (F7)" },
    { id = "new", label = "New notebook" },
    { id = "tree", label = "Notebook filetree  (F2)" },
    { id = "vim", label = "Toggle Vim mode  (F3)" },
    { id = "zen", label = "Toggle Zen mode  (F4)" },
    { id = "screenshot", label = "Save screenshot  (Ctrl+Shift+S)" },
    { id = "theme", label = "Toggle light/dark theme  (Ctrl+Shift+T)" },
    { id = "history", label = "Undo history  (Ctrl+Shift+U)" },
    { id = "cell-below", label = "Insert code cell below  (Alt+B)" },
    { id = "cell-above", label = "Insert code cell above  (Alt+A)" },
    { id = "markdown-below", label = "Insert markdown cell below  (Alt+M)" },
    { id = "cell-delete", label = "Delete current cell  (Alt+X or dd)" },
    { id = "cell-code", label = "Make current cell code  (Ctrl+1)" },
    { id = "cell-markdown", label = "Make current cell markdown  (Ctrl+2)" },
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
  elseif id == "restart-kernel" then self.app:restart_kernel()
  elseif id == "save" then self.app:save()
  elseif id == "save-as" then self.app:save_as()
  elseif id == "open-dialog" then self.app:open_dialog()
  elseif id == "load" then self.app:load()
  elseif id == "new" then self.app:new_notebook()
  elseif id == "tree" then self.show_tree = true
  elseif id == "history" then self:open_history()
  elseif id == "cell-below" then self.app:add_cell("code")
  elseif id == "cell-above" then self.app:add_cell_above("code")
  elseif id == "markdown-below" then self.app:add_cell("markdown")
  elseif id == "cell-delete" then self.app:delete_cell()
  elseif id == "cell-code" then self.app:set_cell_kind("code")
  elseif id == "cell-markdown" then self.app:set_cell_kind("markdown")
  elseif id == "theme" then
    local mode = Theme.toggle()
    Theme.save()
    self.app.status = mode .. " theme"
  elseif id == "screenshot" then
    self.app.screenshot_requested = true
  elseif id == "zen" then
    self.zen_mode = not self.zen_mode
    self.scroll = 0
    self.scroll_to_selected = true
  elseif id == "vim" then
    self.app.vim_mode = not self.app.vim_mode
    self.vim_normal = self.app.vim_mode
    self.vim_scope = self.app.vim_mode and "notebook" or "insert"
  elseif id == "undo" then self.app:notebook():undo()
  elseif id == "redo" then self.app:notebook():redo()
  elseif id == "extensions" then self.show_extensions = true
  elseif id == "outline" then self.show_outline = true
  elseif id == "help" then self.show_help = true
  elseif id == "nvim" then self.app:open_nvim()
  elseif id == "nvim-default" then self.app:toggle_nvim_default()
  elseif id == "nvim-notebook" then self.app:open_nvim_notebook()
  elseif id == "transparency" then
    Theme.set_opacity(Theme.opacity >= 0.999 and 0.82 or 1)
    Theme.save()
    self.app.status = string.format("background opacity %.0f%%",
      Theme.opacity * 100)
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
    { 0.8, 0.86, 0.98, 1 }, 0.7)
  box(pass, x + 12, y + 34, panel_w - 24, 26, { 0.08, 0.1, 0.15, 1 })
  text(pass, self.app.font, self.palette_query .. "|", x + 20, y + 39,
    { 0.9, 0.95, 1, 1 }, 0.72)
  if #commands == 0 then
    text(pass, self.app.font, "No matching command", x + 20, y + 78,
      { 0.6, 0.65, 0.75, 1 }, 0.7)
  end
  for index, command in ipairs(commands) do
    local row_y = y + 72 + (index - 1) * 32
    local selected = index == self.palette_selected
    box(pass, x + 10, row_y, panel_w - 20, 27,
      selected and { 0.16, 0.25, 0.4, 1 } or { 0.09, 0.12, 0.18, 1 })
    text(pass, self.app.font, command.label, x + 20, row_y + 6,
      { 0.8, 0.88, 1, 1 }, 0.7)
    self.palette_rects[#self.palette_rects + 1] = {
      x = x + 10, y = row_y, w = panel_w - 20, h = 27, id = command.id,
    }
  end
end

function UI:open_find()
  self.show_find = true
  self.find_query = ""
  self.find_selected = 1
  self.find_results = {}
end

function UI:update_find()
  self.find_results = {}
  self.find_selected = 1
  local query = self.find_query:lower()
  if query == "" then return end
  for cell_index, cell in ipairs(self.app:notebook().cells) do
    local offset = 1
    for line in ((cell.source or "") .. "\n"):gmatch("(.-)\n") do
      local position = line:lower():find(query, 1, true)
      if position then
        self.find_results[#self.find_results + 1] = {
          cell = cell_index, line = line,
          cursor = offset + position - 1,
        }
        if #self.find_results >= 40 then return end
      end
      offset = offset + #line + 1
    end
  end
end

function UI:draw_find(pass, width, height)
  self.find_rects = {}
  if not self.show_find then return end
  local panel_w = math.min(760, width - 60)
  local rows = math.min(#self.find_results, 10)
  local panel_h = 74 + rows * 24
  local x, y = (width - panel_w) / 2, 80
  box(pass, x, y, panel_w, panel_h, { 0.06, 0.07, 0.10, 0.98 })
  text(pass, self.app.font, "Find in notebook  (Ctrl+F)", x + 14, y + 12,
    { 0.9, 0.94, 1, 1 }, 0.78)
  box(pass, x + 12, y + 36, panel_w - 24, 26, { 0.11, 0.13, 0.18, 1 })
  text(pass, self.app.font, self.find_query .. "|", x + 20, y + 41,
    { 0.9, 0.94, 1, 1 }, 0.75)
  for index = 1, rows do
    local result = self.find_results[index]
    local row_y = y + 68 + (index - 1) * 24
    if index == self.find_selected then
      box(pass, x + 10, row_y - 2, panel_w - 20, 22, { 0.16, 0.24, 0.36, 1 })
    end
    local label = string.format("[%d] %s", result.cell, result.line)
    text(pass, self.app.font, label:sub(1, 90), x + 18, row_y + 2,
      index == self.find_selected and { 1, 1, 1, 1 } or
      { 0.65, 0.72, 0.84, 1 }, 0.62)
    self.find_rects[#self.find_rects + 1] = {
      x = x + 10, y = row_y - 2, w = panel_w - 20, h = 22, index = index,
    }
  end
end

function UI:draw_help(pass, width, height)
  if not self.show_help then return end
  local columns = {
    {
      { title = "MODES & NAVIGATION", rows = {
        { "F3", "Vim mode on / off" },
        { "i / Enter", "open Neovim or enter cell" },
        { "i", "cell -> insert" },
        { "Esc", "step back one scope" },
        { "j / k", "move cells (hold to repeat)" },
        { "h / j / k / l", "move inside a cell" },
        { "Alt+J/K", "direct cell jump (optional)" },
        { "p / Alt+P", "run / run and next" },
      } },
      { title = "CELLS", rows = {
        { "b / a", "insert code below / above" },
        { "M", "insert markdown below" },
        { "Alt+A / B / M", "same actions, anywhere" },
        { "Alt+X / dd", "delete focused cell" },
        { "Ctrl+1 / 2", "code / markdown" },
        { "o / O", "insert below / above and edit" },
        { "Ctrl+F", "find across notebook cells" },
        { "F2", "notebook filetree" },
        { "F1", "command palette" },
      } },
      { title = "EDITING", rows = {
        { "Tab", "insert two spaces" },
        { "A / I", "insert at line end / start" },
        { "D / C", "delete / change to line end" },
        { "diw / daw", "delete inner / outer word" },
        { 'di" / ci(', "delimiter text objects" },
        { "% / *", "match bracket / search word" },
        { "u / Ctrl+R", "undo / redo" },
        { "g- / g+", "walk older / newer history" },
      } },
    },
    {
      { title = "NEOVIM", rows = {
        { "Alt+E", "open Neovim cell editor" },
        { "Alt+Shift+E", "open Neovim notebook buffer" },
        { "F10", "save from Neovim" },
        { "F5", "save from Neovim and run" },
        { "F9", "discard Neovim changes" },
        { "Alt+J/K", "save and move between cells" },
      } },
      { title = "LSP", rows = {
        { "Ctrl+Space", "completion at cursor" },
        { "Ctrl+H", "hover type / binding" },
        { "Ctrl+G", "jump to definition" },
        { "Ctrl+Shift+R", "rename symbol" },
        { "Ctrl+Shift+U", "undo tree" },
      } },
      { title = "VIEW", rows = {
        { "+ / - / 0", "UI zoom / reset" },
        { "F4", "Zen mode" },
        { "F10 / F11", "extensions / outline" },
        { "Ctrl+Shift+S", "screenshot" },
        { "Ctrl+Shift+T", "light / dark theme" },
        { "Ctrl+Shift+U", "history" },
      } },
      { title = "FILES & VIM", rows = {
        { "F5 / p", "run selected cell" },
        { "F6 / F7", "save / load notebook" },
        { "F8 / F9", "reload extension / user ext" },
        { "v / V", "char / cell visual" },
        { "q / @", "record / replay macro" },
        { "m / '", "set / jump mark" },
        { ".", "repeat last change" },
        { "ZZ", "save notebook" },
      } },
    },
  }
  local function column_height(sections)
    local total = 0
    for _, section in ipairs(sections) do
      total = total + 28 + #section.rows * 22
    end
    return total
  end
  local left_h = column_height(columns[1])
  local right_h = column_height(columns[2])
  local panel_w = math.min(850, width - 60)
  local panel_h = 76 + math.max(left_h, right_h)
  local x = (width - panel_w) / 2
  local y = math.max(46, (height - panel_h) / 2)
  box(pass, x + 5, y + 5, panel_w, panel_h, { 0, 0, 0, 0.35 })
  box(pass, x, y, panel_w, panel_h, { 0.045, 0.052, 0.075, 0.985 })
  box(pass, x, y, panel_w, 2, { 0.35, 0.68, 1, 1 })
  box(pass, x, y + 51, panel_w, 1, { 0.13, 0.17, 0.25, 1 })
  text(pass, self.app.font, "Keyboard shortcuts", x + 24, y + 14,
    { 0.92, 0.96, 1, 1 }, 0.92)
  text(pass, self.app.font, "notebook  ·  cell  ·  insert", x + 24, y + 34,
    { 0.48, 0.58, 0.74, 1 }, 0.62)
  text(pass, self.app.font, "F12 / ? / Esc  close", x + panel_w - 168,
    y + 18, { 0.5, 0.6, 0.76, 1 }, 0.64)
  local column_x = { x + 24, x + panel_w / 2 + 14 }
  local column_w = panel_w / 2 - 38
  for column_index, sections in ipairs(columns) do
    local cursor_y = y + 62
    local cx = column_x[column_index]
    for _, section in ipairs(sections) do
      text(pass, self.app.font, section.title, cx, cursor_y,
        { 0.42, 0.7, 1, 1 }, 0.62)
      box(pass, cx, cursor_y + 18, column_w, 1, { 0.12, 0.18, 0.28, 1 })
      cursor_y = cursor_y + 26
      for _, row in ipairs(section.rows) do
        local key = row[1]
        local description = row[2]
        local key_w = math.max(28, math.min(106,
          self.app.font:getWidth(key) * 0.6 + 14))
        box(pass, cx, cursor_y, key_w, 18, { 0.09, 0.12, 0.18, 1 })
        box(pass, cx, cursor_y, key_w, 1, { 0.23, 0.31, 0.46, 1 })
        box(pass, cx, cursor_y + 17, key_w, 1, { 0.06, 0.08, 0.12, 1 })
        text(pass, self.app.font, key, cx + 7, cursor_y + 3,
          { 0.86, 0.93, 1, 1 }, 0.58)
        text(pass, self.app.font, description, cx + key_w + 10,
          cursor_y + 2, { 0.66, 0.73, 0.86, 1 }, 0.64)
        cursor_y = cursor_y + 22
      end
      cursor_y = cursor_y + 8
    end
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
  local x, y = 20, 52
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
        self.app:rename_symbol(prompt.old, prompt.value)
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
  local x, y = 20, 54
  box(pass, x, y, panel_w, panel_h, { 0.045, 0.055, 0.08, 0.98 })
  text(pass, self.app.font, "Outline  (F11 to close)", x + 14, y + 14,
    { 0.9, 0.94, 1, 1 }, 0.78)
  if #headings == 0 then
    text(pass, self.app.font, "No markdown headings", x + 14, y + 52,
      { 0.55, 0.6, 0.7, 1 }, 0.7)
  end
  for index, heading in ipairs(headings) do
    local row_y = y + 46 + (index - 1) * 30
    local selected = heading.index == self.app:notebook().active
    box(pass, x + 8, row_y, panel_w - 16, 26,
      selected and { 0.14, 0.22, 0.34, 1 } or { 0.07, 0.08, 0.11, 1 })
    text(pass, self.app.font, (heading.collapsed and "▸ " or "▾ ") ..
      string.rep("  ", heading.level - 1) .. heading.text,
      x + 18, row_y + 6, { 0.8, 0.86, 0.98, 1 }, 0.68)
    self.outline_rects[#self.outline_rects + 1] = {
      x = x + 8, y = row_y, w = panel_w - 16, h = 26, index = heading.index,
    }
  end
end

function UI:draw_extension_browser(pass, width, height)
  self.extension_rects = {}
  self.permission_rects = {}
  if not self.show_extensions then return end
  local panel_w, panel_h = 520, 120 + #Extensions.list() * 36
  local x, y = (width - panel_w) / 2, 90
  box(pass, x, y, panel_w, panel_h, { 0.06, 0.07, 0.1, 0.98 })
  text(pass, self.app.font, "Extensions  (F10 to close)", x + 16, y + 14,
    { 0.9, 0.94, 1, 1 }, 0.8)
  for index, extension in ipairs(Extensions.list()) do
    local row_y = y + 50 + (index - 1) * 36
    local selected = extension.enabled
    box(pass, x + 12, row_y, panel_w - 24, 30,
      selected and { 0.12, 0.22, 0.16, 1 } or { 0.12, 0.13, 0.17, 1 })
    box(pass, x + 22, row_y + 7, 16, 16,
      selected and { 0.35, 0.8, 0.55, 1 } or { 0.25, 0.28, 0.35, 1 })
    text(pass, self.app.font, extension.id .. "  ·  " .. extension.title,
      x + 50, row_y + 7,
      selected and { 0.85, 0.95, 0.9, 1 } or { 0.55, 0.6, 0.7, 1 }, 0.72)
    if extension.permissions and #extension.permissions > 0 then
      text(pass, self.app.font, table.concat(extension.permissions, ", "),
        x + 50, row_y + 18, { 0.55, 0.65, 0.8, 1 }, 0.55)
    end
    local granted = {}
    for _, permission in ipairs(extension.permissions or {}) do
      granted[permission] = true
    end
    local button_x = x + 300
    for _, permission in ipairs(extension.all_permissions or {}) do
      local on = granted[permission] == true
      box(pass, button_x, row_y + 5, 64, 20,
        on and { 0.16, 0.34, 0.25, 1 } or { 0.2, 0.12, 0.14, 1 })
      text(pass, self.app.font, permission, button_x + 5, row_y + 9,
        on and { 0.75, 1, 0.85, 1 } or { 0.85, 0.55, 0.6, 1 }, 0.48)
      self.permission_rects[#self.permission_rects + 1] = {
        x = button_x, y = row_y + 5, w = 64, h = 20, id = extension.id,
        permission = permission,
      }
      button_x = button_x + 70
    end
    self.extension_rects[#self.extension_rects + 1] = {
      x = x + 12, y = row_y, w = 280, h = 30, id = extension.id,
    }
  end
end

function UI:toggle_permission(id, permission)
  local granted = {}
  for _, current in ipairs(Extensions.permissions(id)) do granted[current] = true end
  Extensions.set_permission(id, permission, not granted[permission])
  Extensions.save_preferences()
  self.app.status = (not granted[permission] and "granted " or "revoked ") ..
    permission .. " for " .. id
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
  if renderer.display then
    surface:render_display(renderer, lovr.timer.getTime())
  else
    surface:render(renderer, lovr.timer.getTime())
  end
  surface:composite(pass, x, y, w, h, self.app.ui_scale)
  self.scene_rects[index] = { x = x, y = y, w = w, h = h,
    surface = surface, cell = cell, renderer = renderer }
  table.insert(self.extension_passes, surface.pass)

  box(pass, x, y, w, h, { 0.02, 0.025, 0.04, 0 })
  pass:setFont(self.app.font)
  if Theme.mode == "light" then
    pass:setColor(0.35, 0.39, 0.46, 1)
  else
    pass:setColor(0.8, 0.85, 0.95, 1)
  end
  pass:text("surface: Pass + Texture (host-rendered)", x + 10, y + 8, 0, 0.72,
    0, 0, 1, 0, 0, "left", "top")
end

function UI:textinput(value)
  if self.show_find then
    self.find_query = self.find_query .. value
    self:update_find()
    return
  end
  if self.app.show_nvim then
    if self.app.nvim_view then self.app.nvim_view:textinput(value) end
    return
  end
  if value == "\r" or value == "\n" then return end
  if lovr.system and lovr.system.isKeyDown and
     (lovr.system.isKeyDown("lalt") or lovr.system.isKeyDown("ralt")) then
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
        self.app:rename_symbol(prompt.old, prompt.value)
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
  if cell.kind ~= "code" and cell.kind ~= "markdown" then return end
  self.app:notebook():insert(value)
end

function UI:run_without_focus()
  local vim_normal = self.vim_normal
  local output = self.focused_output_cell
  local widget = self.focused_widget
  local surface = self.focused_surface
  self.app:run()
  self.vim_normal = vim_normal
  self.focused_output_cell = output
  self.focused_widget = widget
  self.focused_surface = surface
  self.nav_repeat = nil
end

function UI:open_history()
  self.app:notebook():flush_history()
  self.history_items = self.app:notebook():history_nodes_flat()
  self.history_selected = 1
  for index, item in ipairs(self.history_items) do
    if item.current then self.history_selected = index; break end
  end
  self.show_history = true
end

function UI:draw_history(pass, width, height)
  if not self.show_history then return end
  local app = self.app
  local panel_w = math.min(640, width - 80)
  local rows = math.min(#self.history_items, 14)
  local panel_h = 64 + rows * 24
  local x = (width - panel_w) / 2
  local y = math.max(70, (height - panel_h) / 2)
  box(pass, x, y, panel_w, panel_h, { 0.035, 0.045, 0.065, 0.98 })
  box(pass, x, y, panel_w, 2, { 0.35, 0.62, 0.95, 1 })
  box(pass, x, y + panel_h - 1, panel_w, 1, { 0.2, 0.3, 0.45, 1 })
  text(pass, app.font, "Undo history  (Enter restore · g- / g+ undo/redo)",
    x + 16, y + 12, { 0.8, 0.86, 1, 1 }, 0.78)
  local first = math.max(1, self.history_selected - rows + 1)
  for row = 0, rows - 1 do
    local index = first + row
    local item = self.history_items[index]
    if item == nil then break end
    local row_y = y + 44 + row * 24
    if index == self.history_selected then
      box(pass, x + 8, row_y - 4, panel_w - 16, 22,
        { 0.16, 0.24, 0.38, 1 })
    end
    text(pass, app.font, string.rep("  ", item.depth) ..
      (item.current and "● " or "○ ") .. "#" .. item.node.id .. "  " ..
      item.node.label, x + 18, row_y,
      item.current and { 0.45, 0.85, 1, 1 } or { 0.7, 0.76, 0.9, 1 }, 0.7)
  end
end

function UI:update(dt)
  if self.app.show_nvim then
    if self.app.nvim_view then self.app.nvim_view:update() end
    return
  end
  if self.nav_repeat == nil then return end
  local key = self.nav_repeat.key
  local down = lovr.system and lovr.system.isKeyDown and
    lovr.system.isKeyDown(key)
  if not down then self.nav_repeat = nil; return end
  if self.nav_repeat.kind == "cell" then
    local alt = lovr.system.isKeyDown("lalt") or
      lovr.system.isKeyDown("ralt")
    if not alt then self.nav_repeat = nil; return end
  end
  local now = lovr.timer.getTime()
  if now < self.nav_repeat.next then return end
  if self.nav_repeat.kind == "line" then
    self.app:notebook():move_line(key == "j" and 1 or -1)
  else
    self.app:notebook():move(key == "j" and 1 or -1)
    self.scroll_to_selected = true
    if self.app.vim_mode then
      self.vim_normal = true
      if self.nav_repeat.kind == "cell" or
         self.nav_repeat.kind == "notebook" then
        self.vim_scope = "notebook"
      end
    end
  end
  self.nav_repeat.next = now + 0.08
end

function UI:open_completion()
  local notebook = self.app:notebook()
  local cell = notebook.cells[notebook.active]
  if cell == nil or cell.kind ~= "code" then return end
  local cursor = cell.cursor or (#cell.source + 1)
  local prefix = LSP.current_word(cell.source, cursor)
  local typed = Types.complete(cell.source, cursor)
  local items, seen = {}, {}
  local function add(label)
    if label and not seen[label] then seen[label] = true; items[#items + 1] = label end
  end
  if typed then
    for _, item in ipairs(typed) do add(item.label) end
  else
    for _, item in ipairs(Types.symbols(cell.source, cursor)) do add(item.label) end
    for _, item in ipairs(LSP.complete_notebook(notebook, cell.source)) do add(item) end
  end
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
  elseif command == "history" then
    self:open_history()
  elseif command == "earlier" then
    self.app.status = self.app:notebook():undo() and "earlier" or "start of history"
  elseif command == "later" then
    self.app.status = self.app:notebook():redo() and "later" or "end of history"
  elseif command:match("^%%sr/(.-)/(.-)/g?$") then
    local pattern, replacement = command:match("^%%sr/(.-)/(.-)/g?$")
    local global = command:sub(-1) == "g"
    self.app:notebook():push_undo()
    local total = 0
    for _, cell in ipairs(self.app:notebook().cells) do
      if cell.kind == "code" then
        local source, count = LSP.substitute_pattern(cell.source, pattern,
          replacement, global)
        cell.source = source
        total = total + count
      end
    end
    self.app.status = "notebook pattern substituted " .. total
  elseif command:match("^%%s/(.-)/(.-)/g?$") then
    local old_text, new_text = command:match("^%%s/(.-)/(.-)/g?$")
    local global = command:sub(-1) == "g"
    self.app:notebook():push_undo()
    local total = 0
    for _, cell in ipairs(self.app:notebook().cells) do
      if cell.kind == "code" then
        local source, count = LSP.substitute(cell.source, old_text, new_text,
          global)
        cell.source = source
        total = total + count
      end
    end
    self.app.status = "notebook substituted " .. total
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

function UI:play_macro()
  local macro = self.vim_last_macro
  if macro == nil or #macro == 0 then return end
  local copy = {}
  for index, key in ipairs(macro) do copy[index] = key end
  self.vim_replaying = true
  for _, key in ipairs(copy) do self:keypressed(key) end
  self.vim_replaying = false
end

function UI:keypressed(key)
  if self.app.show_nvim then
    local alt = lovr.system and lovr.system.isKeyDown and
      (lovr.system.isKeyDown("lalt") or lovr.system.isKeyDown("ralt"))
    if alt and (key == "j" or key == "k") then
      self.app:close_nvim(true)
      self.app:notebook():move(key == "j" and 1 or -1)
      self.app:open_nvim()
      return
    end
    if key == "f10" then self.app:close_nvim(true); return end
    if key == "f5" then
      if self.app.nvim_notebook then
        self.app:run_nvim_cell()
      else
        self.app:close_nvim(true)
        if self.app:notebook():selected().kind == "code" then
          self.app:run()
        else
          self.app.status = "markdown cell selected; not executed"
        end
      end
      return
    end
    if key == "f9" then self.app:close_nvim(false); return end
    if self.app.nvim_view then self.app.nvim_view:keypressed(key) end
    return
  end
  local notebook = self.app:notebook()
  local ctrl_down = lovr.system and lovr.system.isKeyDown and
    (lovr.system.isKeyDown("lctrl") or lovr.system.isKeyDown("rctrl"))
  if self.show_find then
    if key == "escape" then self.show_find = false
    elseif key == "backspace" then
      self.find_query = self.find_query:sub(1, -2); self:update_find()
    elseif key == "return" and self.find_results[self.find_selected] then
      local result = self.find_results[self.find_selected]
      notebook:select(result.cell)
      notebook.cells[result.cell].cursor = result.cursor
      self.scroll_to_selected = true
      self.show_find = false
    elseif key == "up" then
      self.find_selected = math.max(1, self.find_selected - 1)
    elseif key == "down" then
      self.find_selected = math.min(#self.find_results,
        self.find_selected + 1)
    end
    return
  end
  if ctrl_down and key == "f" then self:open_find(); return end
  if ctrl_down and (key == "k") and lovr.system and
     lovr.system.isKeyDown and (lovr.system.isKeyDown("lshift") or
       lovr.system.isKeyDown("rshift")) then
    self.app:restart_kernel()
    return
  end
  if ctrl_down and (key == "=" or key == "+" or key == "-" or
     key == "0") then
    if key == "0" then self.app:set_ui_scale(1)
    elseif key == "-" then self.app:zoom_ui(-0.1)
    else self.app:zoom_ui(0.1) end
    return
  end
  local alt_down = lovr.system and lovr.system.isKeyDown and
    (lovr.system.isKeyDown("lalt") or lovr.system.isKeyDown("ralt"))
  if alt_down and key == "b" then
    self.app:add_cell("code"); return
  elseif alt_down and key == "a" then
    self.app:add_cell_above("code"); return
  elseif alt_down and key == "m" then
    self.app:add_cell("markdown"); return
  elseif alt_down and key == "x" then
    self.app:delete_cell(); return
  elseif alt_down and key == "p" then
    self.app:run_next()
    if self.app.vim_mode then self.vim_normal = true end
    return
  end
  if alt_down and key == "e" then
    if lovr.system and lovr.system.isKeyDown and
       (lovr.system.isKeyDown("lshift") or lovr.system.isKeyDown("rshift")) then
      self.app:open_nvim_notebook()
    else
      self.app:open_nvim()
    end
    return
  end
  if alt_down and key == "t" then
    Theme.set_opacity(Theme.opacity >= 0.999 and 0.82 or 1)
    Theme.save()
    self.app.status = string.format("background opacity %.0f%%",
      Theme.opacity * 100)
    return
  end
  if alt_down and (key == "j" or key == "k") then
    if self.nav_repeat == nil or self.nav_repeat.key ~= key then
      notebook:move(key == "j" and 1 or -1)
      self.scroll_to_selected = true
      if self.app.vim_mode then
        self.vim_normal = true
        self.vim_scope = "notebook"
      end
      self.vim_char_visual = false
      self.nav_repeat = { key = key, kind = "cell",
        next = lovr.timer.getTime() + 0.35 }
    end
    return
  end
  if self.show_history then
    if key == "escape" or key == "q" then
      self.show_history = false
    elseif key == "up" then
      self.history_selected = math.max(1, self.history_selected - 1)
    elseif key == "down" then
      self.history_selected = math.min(#self.history_items,
        self.history_selected + 1)
    elseif key == "return" then
      local item = self.history_items[self.history_selected]
      if item then
        self.app:notebook():restore_history(item.node.id)
        self.show_history = false
        self.app.status = "history restored"
      end
    end
    return
  end
  if self.vim_recording and not self.vim_replaying and key ~= "q" then
    self.vim_recording[#self.vim_recording + 1] = key
  end
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
        self.app:rename_symbol(prompt.old, prompt.value)
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
  if key == "u" and lovr.system and lovr.system.isKeyDown and
     (lovr.system.isKeyDown("lctrl") or lovr.system.isKeyDown("rctrl")) and
     (lovr.system.isKeyDown("lshift") or lovr.system.isKeyDown("rshift")) then
    self:open_history(); return
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
  if (key == "1" or key == "2") and lovr.system and lovr.system.isKeyDown and
     (lovr.system.isKeyDown("lctrl") or lovr.system.isKeyDown("rctrl")) then
    self.app:set_cell_kind(key == "1" and "code" or "markdown")
    return
  end
  if key == "u" and lovr.system and lovr.system.isKeyDown and
     (lovr.system.isKeyDown("lctrl") or lovr.system.isKeyDown("rctrl")) and
     (lovr.system.isKeyDown("lshift") or lovr.system.isKeyDown("rshift")) then
    self:open_history(); return
  end
  if key == "r" and lovr.system and lovr.system.isKeyDown and
     (lovr.system.isKeyDown("lctrl") or lovr.system.isKeyDown("rctrl")) then
    self.app.status = self.app:notebook():redo() and "redo" or "nothing to redo"
    return
  end
  if key == "t" and lovr.system and lovr.system.isKeyDown and
     (lovr.system.isKeyDown("lctrl") or lovr.system.isKeyDown("rctrl")) and
     (lovr.system.isKeyDown("lshift") or lovr.system.isKeyDown("rshift")) then
    local mode = Theme.toggle()
    Theme.save()
    self.app.status = mode .. " theme"
    return
  end
  if key == "s" and lovr.system and lovr.system.isKeyDown and
     (lovr.system.isKeyDown("lctrl") or lovr.system.isKeyDown("rctrl")) and
     (lovr.system.isKeyDown("lshift") or lovr.system.isKeyDown("rshift")) then
    self.app.screenshot_requested = true
    self.app.status = "taking screenshot"
    return
  end
  if (key == "d" or key == "u") and lovr.system and lovr.system.isKeyDown and
     (lovr.system.isKeyDown("lctrl") or lovr.system.isKeyDown("rctrl")) then
    local amount = (key == "d" and 1 or -1) * 300
    self.scroll = math.max(0, math.min(self.max_scroll, self.scroll + amount))
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
    if self.vim_text_object then
      local operation = self.vim_text_object
      self.vim_text_object = nil
      local delimiters = {
        ['"'] = '"', ["'"] = "'", ["`"] = "`",
        ["("] = ")", [")"] = ")", ["["] = "]", ["]"] = "]",
        ["{"] = "}", ["}"] = "}", ["<"] = ">", [">"] = ">",
      }
      local first, last
      if key == "w" then
        first, last = notebook:word_range(not operation.inner)
      elseif delimiters[key] then
        local close = delimiters[key]
        local open = key
        if key == ")" then open = "("
        elseif key == "]" then open = "["
        elseif key == "}" then open = "{" end
        first, last = notebook:delimiter_range(open, close,
          not operation.inner)
      end
      if first then
        if operation.op == "y" then
          self.vim_char_yank = notebook:selection_text(first, last + 1)
          self.app.status = "yanked " .. #self.vim_char_yank ..
            " character(s)"
        else
          notebook:push_undo()
          notebook:delete_range(first, last + 1)
          if operation.op == "c" then self.vim_normal = false end
          self.app.status = (operation.op == "c" and "change" or "delete") ..
            " object"
        end
      end
      return
    elseif self.vim_pending_mark then
      local operation = self.vim_pending_mark
      self.vim_pending_mark = nil
      if key:match("^[a-z]$") then
        if operation == "set" then
          self.vim_marks[key] = { cell = notebook.active,
            cursor = notebook.cells[notebook.active].cursor }
          self.app.status = "mark " .. key .. " set"
        else
          local mark = self.vim_marks[key]
          if mark then
            notebook:select(mark.cell)
            notebook.cells[mark.cell].cursor = mark.cursor
            self.scroll_to_selected = true
          end
        end
      end
      return
    elseif self.vim_pending then
      local pending = self.vim_pending
      self.vim_pending = nil
      if pending == "g" and key == "g" then
        notebook:select(1); self.scroll_to_selected = true; return
      elseif pending == "Z" and key == "Z" then
        self.app:save(); return
      elseif (pending == ">" or pending == "<") and key == pending then
        local cell = notebook:selected()
        local source = cell.source
        local cursor = cell.cursor or 1
        local line_start = (source:sub(1, cursor - 1):match(".*()\n") or 0) + 1
        notebook:push_undo("indent")
        if pending == ">" then
          cell.source = source:sub(1, line_start - 1) .. "  " ..
            source:sub(line_start)
          cell.cursor = cursor + 2
        else
          local remove = source:sub(line_start, line_start + 1):match("^  ") and 2 or
            (source:sub(line_start, line_start):match("^ ") and 1 or 0)
          cell.source = source:sub(1, line_start - 1) ..
            source:sub(line_start + remove)
          cell.cursor = math.max(line_start, cursor - remove)
        end
        return
      elseif pending == "g" and key == "-" then
        self.app.status = notebook:undo() and "undo" or "nothing to undo"
        return
      elseif pending == "g" and key == "+" then
        self.app.status = notebook:redo() and "redo" or "nothing to redo"
        return
      elseif pending == "d" and key == "d" then
        self.vim_last_change = "dd"
        notebook:delete_cell(notebook.active); return
      elseif pending == "y" and key == "y" then
        self.vim_yank = { notebook:copy_cell(notebook.active) }
        self.vim_registers[self.vim_register] = self.vim_yank
        self.app.status = "yanked current cell to " .. self.vim_register
        return
      elseif (pending == "d" or pending == "c" or pending == "y") and
             key == "i" then
        self.vim_text_object = { op = pending, inner = true }; return
      elseif (pending == "d" or pending == "c" or pending == "y") and
             key == "a" then
        self.vim_text_object = { op = pending, inner = false }; return
      end
    end
    if self.vim_scope == "notebook" and key == "b" then
      self.app:add_cell("code"); return
    elseif self.vim_scope == "notebook" and key == "a" then
      self.app:add_cell_above("code"); return
    elseif self.vim_scope == "notebook" and key == "M" then
      self.app:add_cell("markdown"); return
    end
    if self.vim_scope == "notebook" and
       (key == "+" or key == "=" or key == "-" or key == "0") then
      if key == "0" then self.app:set_ui_scale(1)
      elseif key == "-" then self.app:zoom_ui(-0.1)
      else self.app:zoom_ui(0.1) end
      return
    elseif self.vim_scope == "notebook" and (key == "j" or key == "k") then
      if self.nav_repeat and self.nav_repeat.key == key and
         (self.nav_repeat.kind == "cell" or
          self.nav_repeat.kind == "notebook") then return end
      notebook:move(key == "j" and 1 or -1)
      self.scroll_to_selected = true
      self.nav_repeat = { key = key, kind = "notebook",
        next = lovr.timer.getTime() + 0.35 }
      return
    elseif self.vim_scope == "notebook" and
           (key == "i" or key == "return") then
      if self.app.nvim_default then
        self.app:open_nvim()
        return
      end
      self.vim_scope = "cell"
      self.vim_normal = false
      return
    end
    if key == "q" then
      if self.vim_recording then
        self.vim_macros.a = self.vim_recording
        self.vim_last_macro = self.vim_recording
        self.app.status = "recorded macro"
        self.vim_recording = nil
      else
        self.vim_recording = {}
        self.app.status = "recording macro"
      end
      return
    elseif key == "@" then
      self:play_macro(); return
    elseif key == "m" then
      self.vim_pending_mark = "set"; return
    elseif key == "'" then
      self.vim_pending_mark = "jump"; return
    elseif key == "." and self.vim_last_change then
      if self.vim_last_change == "x" then
        local cell = notebook.cells[notebook.active]
        if cell and cell.kind == "code" then cell.source = cell.source:sub(1, -2) end
      elseif self.vim_last_change == "J" then
        local cell = notebook.cells[notebook.active]
        notebook:push_undo()
        cell.source = cell.source:gsub("%s*\n%s*", " ")
        cell.cursor = #cell.source + 1
      elseif self.vim_last_change == "dd" then
        notebook:delete_cell(notebook.active)
      end
      return
    elseif key == "g" then
      self.vim_pending = "g"; return
    elseif key == "G" then
      notebook:select(#notebook.cells); self.scroll_to_selected = true; return
    elseif key == "0" then
      notebook.cells[notebook.active].cursor = 1; return
    elseif key == "$" then
      local cell = notebook.cells[notebook.active]
      cell.cursor = #cell.source + 1; return
    elseif key == "w" then
      local cell = notebook.cells[notebook.active]
      local rest = cell.source:sub(cell.cursor or 1)
      local offset = rest:find("%f[%w+]%w+")
      if offset then cell.cursor = (cell.cursor or 1) + offset - 1 end
      return
    elseif key == "b" then
      local cell = notebook.cells[notebook.active]
      local before = cell.source:sub(1, (cell.cursor or 1) - 1)
      local start_at = before:match(".*()%f[%w+]%w+")
      if start_at then cell.cursor = start_at end
      return
    elseif key == "J" then
      self.vim_last_change = "J"
      local cell = notebook.cells[notebook.active]
      notebook:push_undo()
      cell.source = cell.source:gsub("%s*\n%s*", " ")
      cell.cursor = #cell.source + 1
      return
    elseif key == "d" and not self.vim_visual then
      self.vim_pending = "d"; return
    elseif key == "c" and not self.vim_visual then
      self.vim_pending = "c"; return
    elseif key == "?" or (key == "/" and lovr.system and
      lovr.system.isKeyDown and
      (lovr.system.isKeyDown("lshift") or
       lovr.system.isKeyDown("rshift"))) then
      self.show_help = not self.show_help
      return
    elseif key == "/" then
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
      if self.vim_scope == "cell" then self.vim_scope = "notebook" end
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
    elseif key == "p" and not self.vim_char_visual and not self.vim_visual then
      self:run_without_focus()
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
      self.vim_pending = "y"; return
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
    elseif key == "A" or key == "I" then
      local cell = notebook:selected()
      local cursor = cell.cursor or (#cell.source + 1)
      if key == "A" then
        cell.cursor = cell.source:find("\n", cursor, true) or (#cell.source + 1)
      else
        cell.cursor = (cell.source:sub(1, cursor - 1):match(".*()\n") or 0) + 1
      end
      self.vim_normal = false
      return
    elseif key == "D" or key == "C" then
      local cell = notebook:selected()
      local cursor = cell.cursor or (#cell.source + 1)
      local line_end = cell.source:find("\n", cursor, true) or (#cell.source + 1)
      notebook:push_undo("delete to end of line")
      cell.source = cell.source:sub(1, cursor - 1) .. cell.source:sub(line_end)
      if key == "C" then self.vim_normal = false end
      return
    elseif key == "P" and self.vim_char_yank and #self.vim_char_yank > 0 then
      notebook:push_undo("paste before")
      notebook:insert(self.vim_char_yank)
      return
    elseif key == "%" then
      local target = notebook:matching_bracket()
      if target then notebook:selected().cursor = target end
      return
    elseif key == "*" then
      local cell = notebook:selected()
      local word = LSP.current_word(cell.source, cell.cursor)
      if word ~= "" then
        self.vim_last_search = word
        self:search_vim(word)
      end
      return
    elseif key == "Z" then
      self.vim_pending = "Z"; return
    elseif key == ">" or key == "<" then
      self.vim_pending = key; return
    elseif key == "i" or key == "a" or key == "return" then
      self.vim_scope = "cell"
      self.vim_normal = false
      return
    elseif key == "j" then
      if self.nav_repeat and self.nav_repeat.key == "j" then return end
      if not notebook:move_line(1) and notebook:move(1) then
        notebook:selected().cursor = 1
        self.scroll_to_selected = true
      end
      self.nav_repeat = { key = "j", kind = "line",
        next = lovr.timer.getTime() + 0.35 }
      return
    elseif key == "k" then
      if self.nav_repeat and self.nav_repeat.key == "k" then return end
      if not notebook:move_line(-1) and notebook:move(-1) then
        notebook:selected().cursor = #notebook:selected().source + 1
        self.scroll_to_selected = true
      end
      self.nav_repeat = { key = "k", kind = "line",
        next = lovr.timer.getTime() + 0.35 }
      return
    elseif key == "o" then
      notebook:add_cell("code"); self.vim_normal = false
      self.vim_scope = "cell"; return
    elseif key == "O" then
      notebook:add_cell_above("code"); self.vim_normal = false
      self.vim_scope = "cell"; return
    elseif key == "u" then
      self.app.status = notebook:undo() and "undo" or "nothing to undo"
      return
    elseif key == "x" or key == "X" then
      self.vim_last_change = key
      notebook:delete_character(key == "x")
      return
    end
  elseif self.app.vim_mode and key == "escape" then
    self.vim_normal = true
    self.vim_scope = "cell"
    return
  end
  if key == "escape" then
    if self.show_help then self.show_help = false; return end
    if self.show_palette then self.show_palette = false; return end
    if self.show_extensions then self.show_extensions = false; return end
    if self.show_outline then self.show_outline = false; return end
    if self.show_tree then self.show_tree = false; return end
    if self.hover then self.hover = nil; return end
  end
  if self.zen_mode and key == "escape" then
    self.zen_mode = false
    self.scroll = 0
    self.scroll_to_selected = true
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
  if key == "f1" then
    self.show_palette = not self.show_palette
    self.palette_query = ""
    self.palette_selected = 1
  elseif key == "f2" then
    self.show_tree = not self.show_tree
  elseif key == "f3" then
    self.app.vim_mode = not self.app.vim_mode
    self.vim_normal = self.app.vim_mode
    self.vim_scope = self.app.vim_mode and "notebook" or "insert"
    self.app.status = self.app.vim_mode and "Vim on" or "Vim off"
  elseif key == "f4" then
    self.zen_mode = not self.zen_mode
    self.scroll = 0
    self.scroll_to_selected = true
  elseif key == "f5" then
    self.app:run()
  elseif key == "f6" then
    self.app:save()
  elseif key == "f7" then
    self.app:load()
  elseif key == "f8" then
    local cell = notebook:selected()
    if type(cell.scene) == "string" then
      self.app:reload_extension(cell.scene)
    else
      self.app.status = "no extension in selected cell"
    end
  elseif key == "f9" then
    self.app:reload_user_extensions()
  elseif key == "f10" then
    self.show_extensions = not self.show_extensions
  elseif key == "f11" then
    self.show_outline = not self.show_outline
  elseif key == "f12" then
    self.show_help = not self.show_help
  elseif key == "tab" then
    if notebook:selected().kind == "code" or
       notebook:selected().kind == "markdown" then
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
    if notebook:selected().kind == "code" or
       notebook:selected().kind == "markdown" then
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
    for _, rect in ipairs(self.permission_rects or {}) do
      if inside(x, y, rect) then
        self:toggle_permission(rect.id, rect.permission)
        return
      end
    end
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
      rect.cell.cursor = 1
      if self.app.vim_mode then
        self.vim_scope = "cell"
        self.vim_normal = true
        self.vim_pending = nil
        self.vim_text_object = nil
        self.vim_pending_mark = nil
        self.vim_pending_register = false
        self.vim_command = nil
        self.vim_search = nil
      end
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
      local was_active = self.app:notebook().active == index
      local target = self.app:notebook().cells[index]
      if target and target._source_y then
        local line = math.floor((y - target._source_y) / 21) + 1
        local lines = 1
        for _ in (target.source or ""):gmatch("\n") do lines = lines + 1 end
        line = math.max(1, math.min(line, lines))
        local start = 1
        for _ = 1, line - 1 do
          local newline = target.source:find("\n", start, true)
          if newline == nil then break end
          start = newline + 1
        end
        target.cursor = start
      end
      self.app:notebook():select(index)
      if self.app.vim_mode then
        self.vim_scope = "cell"
        self.vim_normal = not was_active
        self.vim_pending = nil
        self.vim_text_object = nil
        self.vim_pending_mark = nil
        self.vim_pending_register = false
        self.vim_command = nil
        self.vim_search = nil
      end
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
      local was_active = self.app:notebook().active == index
      local target = self.app:notebook().cells[index]
      if target and target._source_y then
        local line = math.floor((y - target._source_y) / 21) + 1
        local lines = 1
        for _ in (target.source or ""):gmatch("\n") do lines = lines + 1 end
        line = math.max(1, math.min(line, lines))
        local start = 1
        for _ = 1, line - 1 do
          local newline = target.source:find("\n", start, true)
          if newline == nil then break end
          start = newline + 1
        end
        target.cursor = start
      end
      self.app:notebook():select(index)
      if self.app.vim_mode then
        self.vim_normal = not was_active
        self.vim_scope = "cell"
        self.vim_pending = nil
        self.vim_text_object = nil
        self.vim_pending_mark = nil
        self.vim_pending_register = false
        self.vim_command = nil
        self.vim_search = nil
      end
      self.focused_output_cell = nil
      self.focused_surface = nil
      self.focused_widget = nil
      if self.app.nvim_default and target and
         (target.kind == "code" or target.kind == "markdown") then
        self.app:open_nvim()
      end
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
  if self.app.show_nvim then
    if self.app.nvim_view then self.app.nvim_view:wheelmoved(dy) end
    return
  end
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
