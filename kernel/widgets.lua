--
-- Kernel-side widget model.  A widget is a plain serializable spec plus a
-- callback kept only inside the kernel.  Host events are handled here and the
-- updated specs are sent back with the next result.
--
local Widgets = {}
Widgets.__index = Widgets

local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, child in pairs(value) do
    if type(child) ~= "function" then result[key] = copy(child) end
  end
  return result
end

local function number(value, name, required)
  if value == nil and not required then return nil end
  if type(value) ~= "number" or value ~= value then
    error(name .. " must be a number", 4)
  end
  return value
end

function Widgets.new()
  return setmetatable({
    widgets = {},
    callbacks = {},
    order = {},
    next_id = 1,
    cell = nil,
  }, Widgets)
end

function Widgets:begin_cell(cell)
  self.cell = tostring(cell or "cell")
end

local function validate_options(options)
  if options == nil then return {} end
  if type(options) ~= "table" then error("widget options must be a table", 4) end
  return options
end

function Widgets:_add(kind, options, callback)
  if self.cell == nil then
    error("widgets.begin_cell must be called before creating widgets", 3)
  end
  options = validate_options(options)
  local label = options.label
  if label ~= nil and type(label) ~= "string" then
    error("widget label must be a string", 3)
  end
  local id = "w" .. self.next_id
  self.next_id = self.next_id + 1
  local spec = {
    id = id,
    kind = kind,
    cell = self.cell,
    label = label or kind,
  }
  if kind == "slider" then
    spec.min = number(options.min, "slider min", true)
    spec.max = number(options.max, "slider max", true)
    if spec.max <= spec.min then error("slider max must exceed min", 3) end
    spec.step = number(options.step, "slider step", false) or
      (spec.max - spec.min) / 100
    if spec.step <= 0 then error("slider step must be positive", 3) end
    spec.value = number(options.value, "slider value", false) or spec.min
    spec.value = math.max(spec.min, math.min(spec.max, spec.value))
  elseif kind == "button" then
    spec.label = label or "Button"
  elseif kind == "checkbox" then
    spec.value = options.value == true
  elseif kind == "select" then
    if type(options.options) ~= "table" or #options.options == 0 then
      error("select options must be a non-empty list", 3)
    end
    spec.options = {}
    for index, option in ipairs(options.options) do
      if type(option) == "table" then
        spec.options[index] = {
          label = tostring(option.label or option.value or index),
          value = option.value,
        }
      else
        spec.options[index] = { label = tostring(option), value = option }
      end
    end
    spec.index = 1
    if options.value ~= nil then
      for index, option in ipairs(spec.options) do
        if option.value == options.value or option.label == options.value then
          spec.index = index
          break
        end
      end
    end
    spec.value = spec.options[spec.index].value
  elseif kind == "number" then
    spec.min = number(options.min, "number min", false)
    spec.max = number(options.max, "number max", false)
    spec.step = number(options.step, "number step", false) or 1
    spec.value = number(options.value, "number value", false) or spec.min or 0
  elseif kind == "text" then
    spec.value = tostring(options.value or "")
    spec.placeholder = options.placeholder
    spec.multiline = options.multiline == true
  elseif kind == "progress" then
    spec.min = number(options.min, "progress min", false) or 0
    spec.max = number(options.max, "progress max", false) or 1
    spec.value = number(options.value, "progress value", false) or spec.min
  elseif kind == "label" then
    spec.text = tostring(options.text or label or "")
  end
  self.widgets[id] = spec
  self.callbacks[id] = callback
  self.order[#self.order + 1] = id
  return spec
end

function Widgets:slider(options)
  options = validate_options(options)
  return self:_add("slider", options, options.on_change)
end

function Widgets:button(options)
  options = validate_options(options)
  return self:_add("button", options, options.on_click)
end

function Widgets:checkbox(options)
  options = validate_options(options)
  return self:_add("checkbox", options, options.on_change)
end

function Widgets:select(options)
  options = validate_options(options)
  return self:_add("select", options, options.on_change)
end

function Widgets:number(options)
  options = validate_options(options)
  return self:_add("number", options, options.on_change)
end

function Widgets:text(options)
  options = validate_options(options)
  return self:_add("text", options, options.on_change)
end

function Widgets:progress(options)
  options = validate_options(options)
  return self:_add("progress", options, nil)
end

function Widgets:label(options)
  if type(options) == "string" then options = { text = options } end
  options = validate_options(options)
  return self:_add("label", options, nil)
end

function Widgets:set_value(id_or_spec, value)
  local id = type(id_or_spec) == "table" and id_or_spec.id or id_or_spec
  local spec = self.widgets[id]
  if spec == nil then return nil end
  if spec.kind == "select" then
    for index, option in ipairs(spec.options) do
      if option.value == value or option.label == value then
        spec.index = index
        spec.value = option.value
        return spec
      end
    end
    return nil
  end
  if spec.kind == "checkbox" then
    spec.value = value == true
  elseif spec.kind == "text" then
    spec.value = tostring(value)
  else
    local num = tonumber(value)
    if num == nil then return nil end
    if spec.min then num = math.max(spec.min, num) end
    if spec.max then num = math.min(spec.max, num) end
    spec.value = num
  end
  return spec
end

function Widgets:handle(id, event)
  local spec = self.widgets[id]
  if spec == nil then return nil, "unknown widget " .. tostring(id) end
  event = event or {}
  if spec.kind == "button" then
    if event.type ~= "click" then return nil, "button expects click" end
  elseif spec.kind == "select" then
    if event.type == "next" then
      spec.index = spec.index % #spec.options + 1
    elseif event.value ~= nil then
      local updated = self:set_value(id, event.value)
      if updated == nil then return nil, "invalid select value" end
    end
    local option = spec.options[spec.index]
    spec.value = option.value
    spec.label = spec.label
  elseif spec.kind == "checkbox" then
    if event.type == "toggle" or event.value ~= nil then
      spec.value = not spec.value
      if event.value ~= nil then spec.value = event.value == true end
    end
  elseif spec.kind == "text" then
    if event.value ~= nil then spec.value = tostring(event.value) end
  elseif spec.kind == "slider" or spec.kind == "number" then
    if event.value ~= nil then
      local updated = self:set_value(id, event.value)
      if updated == nil then return nil, "invalid numeric value" end
    end
  end
  local callback = self.callbacks[id]
  if callback then
    local ok, err = pcall(callback, spec.value, spec, event)
    if not ok then return nil, tostring(err) end
  end
  return spec
end

function Widgets:export(cell)
  local result = {}
  for _, id in ipairs(self.order) do
    local spec = self.widgets[id]
    if spec and (cell == nil or spec.cell == tostring(cell)) then
      result[#result + 1] = copy(spec)
    end
  end
  return result
end

return Widgets
