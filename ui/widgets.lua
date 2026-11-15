--
-- Host-side renderer for kernel-declared widgets.
--
local Widgets = {}
local Theme = require("ui.theme")

local function text(pass, font, value, x, y, scale, color, halign, valign)
  color = Theme.map(color)
  pass:setFont(font)
  pass:setColor(color[1], color[2], color[3], color[4] or 1)
  pass:text(value, x, y, 0, scale or 0.72, 0, 0, 1, 0, 0,
    halign or "left", valign or "top")
end

local function box(pass, x, y, w, h, color)
  color = Theme.map(color)
  pass:setColor(color[1], color[2], color[3], color[4] or 1)
  pass:plane(x + w / 2, y + h / 2, 0, w, h)
end

local function value_text(value)
  if type(value) == "number" then
    if value % 1 == 0 then return tostring(value) end
    return string.format("%.3g", value)
  end
  return tostring(value)
end

local function split_lines(value)
  local lines = {}
  for line in (value .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
  if #lines == 0 then lines[1] = "" end
  return lines
end

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function text_lines(spec)
  if spec.kind ~= "text" or not spec.multiline then return 1 end
  local value = tostring(spec.value or "")
  local count = 1
  for _ in value:gmatch("\n") do count = count + 1 end
  return count
end

local function row_height(spec)
  if spec.kind == "text" and spec.multiline then
    return math.max(36, text_lines(spec) * 18 + 18)
  end
  return 36
end

function Widgets.height(widgets)
  local height = 4
  for _, spec in ipairs(widgets or {}) do height = height + row_height(spec) end
  return height
end

function Widgets.draw(pass, font, widgets, x, y, width)
  local controls = {}
  local row_y = y
  for _, spec in ipairs(widgets or {}) do
    local height = row_height(spec)
    local row_height = height
    box(pass, x, row_y, width, row_height - 4, { 0.065, 0.075, 0.10, 1 })
    text(pass, font, spec.label or spec.id, x + 10, row_y + 9, 0.68,
      { 0.78, 0.83, 0.95, 1 })
    local control_x = x + 170
    local control_w = math.max(80, width - 260)
    local rect = { spec = spec, kind = spec.kind, x = x, y = row_y,
      w = width, h = row_height - 4 }

    if spec.kind == "slider" then
      local track_x = control_x
      local track_w = control_w
      local track_y = row_y + 18
      box(pass, track_x, track_y, track_w, 4, { 0.18, 0.22, 0.30, 1 })
      local fraction = (spec.value - spec.min) / (spec.max - spec.min)
      fraction = clamp(fraction, 0, 1)
      box(pass, track_x, track_y, math.max(2, track_w * fraction), 4,
        { 0.35, 0.62, 0.95, 1 })
      box(pass, track_x + track_w * fraction - 5, track_y - 6, 10, 16,
        { 0.85, 0.9, 1, 1 })
      text(pass, font, value_text(spec.value), x + width - 72, row_y + 9, 0.68,
        { 0.85, 0.9, 1, 1 }, "right")
      rect.track_x = track_x
      rect.track_w = track_w
    elseif spec.kind == "button" then
      box(pass, control_x, row_y + 5, 120, 24, { 0.18, 0.42, 0.30, 1 })
      text(pass, font, spec.label or "Run", control_x + 58, row_y + 11, 0.68,
        { 0.9, 1, 0.92, 1 }, "center")
      rect.hit = { x = control_x, y = row_y + 5, w = 120, h = 24 }
    elseif spec.kind == "checkbox" then
      box(pass, control_x, row_y + 9, 18, 18, { 0.12, 0.15, 0.2, 1 })
      if spec.value then
        box(pass, control_x + 4, row_y + 13, 10, 10, { 0.35, 0.75, 0.55, 1 })
      end
      text(pass, font, spec.value and "on" or "off", control_x + 28,
        row_y + 9, 0.68, { 0.75, 0.8, 0.9, 1 })
    elseif spec.kind == "select" then
      box(pass, control_x, row_y + 5, 190, 24, { 0.12, 0.16, 0.24, 1 })
      local option = spec.options and spec.options[spec.index or 1]
      text(pass, font, option and option.label or value_text(spec.value),
        control_x + 10, row_y + 11, 0.68, { 0.85, 0.9, 1, 1 })
      text(pass, font, "click to cycle", control_x + 200, row_y + 11, 0.58,
        { 0.5, 0.56, 0.68, 1 })
    elseif spec.kind == "number" then
      box(pass, control_x, row_y + 7, 24, 22, { 0.18, 0.2, 0.27, 1 })
      text(pass, font, "-", control_x + 12, row_y + 12, 0.8,
        { 0.9, 0.9, 1, 1 }, "center")
      box(pass, control_x + 30, row_y + 7, 80, 22, { 0.09, 0.11, 0.15, 1 })
      text(pass, font, value_text(spec.value), control_x + 70, row_y + 12, 0.7,
        { 0.9, 0.92, 1, 1 }, "center")
      box(pass, control_x + 116, row_y + 7, 24, 22, { 0.18, 0.2, 0.27, 1 })
      text(pass, font, "+", control_x + 128, row_y + 12, 0.8,
        { 0.9, 0.9, 1, 1 }, "center")
      rect.minus = { x = control_x, y = row_y + 7, w = 24, h = 22 }
      rect.plus = { x = control_x + 116, y = row_y + 7, w = 24, h = 22 }
    elseif spec.kind == "text" then
      local focused = spec._focused
      local field_h = spec.multiline and (height - 14) or 24
      box(pass, control_x, row_y + 5, control_w, field_h,
        focused and { 0.12, 0.18, 0.28, 1 } or { 0.09, 0.11, 0.15, 1 })
      local lines = spec.multiline and split_lines(spec.value or "") or
        { spec.value or "" }
      for line_index, line in ipairs(lines) do
        text(pass, font, line, control_x + 8,
          row_y + 10 + (line_index - 1) * 18, 0.68, { 0.85, 0.9, 1, 1 })
      end
      if focused then
        local last = lines[#lines] or ""
        local caret_x = control_x + 8 + font:getWidth(last) * 0.68
        local caret_y = row_y + 8 + (#lines - 1) * 18
        box(pass, caret_x + 1, caret_y, 2, 17, { 0.45, 0.8, 1, 1 })
      end
    elseif spec.kind == "progress" then
      box(pass, control_x, row_y + 12, control_w, 10, { 0.15, 0.18, 0.24, 1 })
      local fraction = (spec.value - spec.min) / (spec.max - spec.min)
      fraction = clamp(fraction, 0, 1)
      box(pass, control_x, row_y + 12, control_w * fraction, 10,
        { 0.35, 0.7, 0.55, 1 })
    elseif spec.kind == "label" then
      text(pass, font, spec.text or spec.label, control_x, row_y + 9, 0.7,
        { 0.8, 0.85, 0.95, 1 })
    end
    controls[#controls + 1] = rect
    row_y = row_y + height
  end
  return row_y - y + 4, controls
end

return Widgets
