--
-- Lua 5.1-safe kernel engine.  Executes notebook cells in an isolated
-- environment with captured output and widget state.  It has no LÖVR or FFI
-- dependency, so the same engine runs in a LÖVR thread on desktop and inline
-- on the web.
--
local Widgets = require("kernel.widgets")

local Engine = {}
Engine.__index = Engine

local widget_names = { "slider", "button", "checkbox", "select", "number",
  "text", "progress", "label", "shader" }

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

function Engine.new()
  local self = setmetatable({
    model = Widgets.new(),
    lines = {},
  }, Engine)
  self:_create_environment()
  return self
end

function Engine:_create_environment()
  local env = {}
  env._G = env

  local api = {}
  for _, name in ipairs(widget_names) do
    api[name] = function(options)
      return self.model[name](self.model, options)
    end
  end
  api.set_value = function(handle, value)
    return self.model:set_value(handle, value)
  end
  env.widgets = api

  env.print = function(...)
    local parts = {}
    for index = 1, select("#", ...) do
      parts[index] = stringify((select(index, ...)))
    end
    self.lines[#self.lines + 1] = table.concat(parts, "\t")
  end

  local io_proxy = setmetatable({}, { __index = io })
  io_proxy.write = function(...)
    for index = 1, select("#", ...) do
      self.lines[#self.lines + 1] = tostring((select(index, ...)))
    end
  end
  env.io = io_proxy

  setmetatable(env, { __index = _G })
  self.env = env
end

function Engine:_capture(fn)
  self.lines = {}
  local ok, result = xpcall(fn, debug.traceback)
  return ok, result, table.concat(self.lines, "\n")
end

function Engine:_set_chunk_environment(chunk)
  if type(setfenv) ~= "function" then
    error("lua-notebooks requires a Lua 5.1-compatible runtime", 3)
  end
  setfenv(chunk, self.env)
end

function Engine:reset()
  self.model = Widgets.new()
  self.lines = {}
  self:_create_environment()
end

function Engine:run(job)
  local cell = job.cell or "cell"
  self.model:begin_cell(cell)

  local ok, result, captured
  if job.widget then
    ok, result, captured = self:_capture(function()
      local spec, err = self.model:handle(job.widget, job.event or {})
      if spec == nil then error(err or "widget event failed", 0) end
      return spec
    end)
  else
    local chunk, compile_error = loadstring(job.code or "", "@cell")
    if chunk then
      self:_set_chunk_environment(chunk)
      ok, result, captured = self:_capture(chunk)
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

  return {
    id = job.id,
    ok = ok,
    output = captured,
    value = value,
    scene = scene,
    widgets = self.model:export(cell),
  }
end

return Engine
