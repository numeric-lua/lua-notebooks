--
-- Headless Lua kernel.  Runs in a LÖVR thread with its own Lua state.
-- The host owns graphics; this file executes cells, manages widgets, and
-- reports serializable results over a channel.
--
local in_name, out_name, source = ...
assert(in_name and out_name, "kernel worker needs input/output channel names")
source = source or "."
package.path = source .. "/?.lua;" .. source .. "/?/init.lua;" .. package.path
local thread = require("lovr.thread")
local Widgets = require("kernel.widgets")
local input = thread.getChannel(in_name)
local output = thread.getChannel(out_name)
local model = Widgets.new()

local widget_api = {}
for _, name in ipairs({ "slider", "button", "checkbox", "select", "number",
                        "text", "progress", "label", "shader" }) do
  widget_api[name] = function(options)
    return model[name](model, options)
  end
end
widget_api.set_value = function(handle, value)
  return model:set_value(handle, value)
end
_G.widgets = widget_api

local function stringify(value)
  local kind = type(value)
  if kind == "string" then return value end
  if kind == "number" or kind == "boolean" or kind == "nil" then
    return tostring(value)
  end
  if kind == "table" then
    local seen = {}
    local function render(item)
      if type(item) ~= "table" then return tostring(item) end
      if seen[item] then return "<cycle>" end
      seen[item] = true
      local parts = {}
      for key, child in pairs(item) do
        parts[#parts + 1] = tostring(key) .. "=" .. render(child)
      end
      table.sort(parts)
      return "{" .. table.concat(parts, ", ") .. "}"
    end
    local ok, rendered = pcall(render, value)
    if ok then return rendered end
  end
  return tostring(value)
end

local function capture(fn)
  local lines = {}
  local real_print = print
  local real_write = io.write
  local function write(...)
    local parts = {}
    for index = 1, select("#", ...) do
      parts[index] = stringify((select(index, ...)))
    end
    lines[#lines + 1] = table.concat(parts, "\t")
  end
  print = write
  io.write = function(value)
    lines[#lines + 1] = tostring(value)
  end
  local ok, result = xpcall(fn, debug.traceback)
  print = real_print
  io.write = real_write
  return ok, result, table.concat(lines, "\n")
end

while true do
  local job = input:pop(true)
  if job == nil or job == "__quit" then break end
  local cell = job.cell or "cell"
  model:begin_cell(cell)

  local ok, result, captured
  if job.widget then
    ok, result, captured = capture(function()
      local spec, err = model:handle(job.widget, job.event or {})
      if spec == nil then error(err or "widget event failed", 0) end
      return spec
    end)
  else
    local chunk, compile_error = loadstring(job.code or "", "@cell")
    if chunk then
      ok, result, captured = capture(chunk)
    else
      ok, result, captured = false, compile_error, ""
    end
  end

  local scene = nil
  if ok and type(result) == "table" and result.scene ~= nil then
    scene = result.scene
    result = nil
  end
  local value = nil
  if not ok then
    value = tostring(result)
  elseif result ~= nil and (type(result) ~= "table" or result.id == nil) then
    value = stringify(result)
  end

  output:push({
    id = job.id,
    ok = ok,
    output = captured,
    value = value,
    scene = scene,
    widgets = model:export(cell),
  })
end
