--
-- Plain-LuaJIT kernel process.  The host writes one atomic job file and reads
-- one atomic result file; no graphics libraries are loaded here.
--
local dir = assert(arg[1], "process kernel needs a work directory")
local root = assert(arg[2], "process kernel needs the project root")
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local json = require("notebook.json")
local Widgets = require("kernel.widgets")
local model = Widgets.new()

local widget_api = {}
for _, name in ipairs({ "slider", "button", "checkbox", "select", "number",
                        "text", "progress", "label" }) do
  widget_api[name] = function(options)
    return model[name](model, options)
  end
end
widget_api.set_value = function(handle, value)
  return model:set_value(handle, value)
end
_G.widgets = widget_api

local ffi = require("ffi")
pcall(ffi.cdef, [[int usleep(unsigned int usec);]])

local job_path = dir .. "/job.json"
local result_path = dir .. "/result.json"
local ready_path = dir .. "/ready"

local function atomic_write(path, data)
  local temporary = path .. ".tmp"
  local file = assert(io.open(temporary, "w"))
  file:write(data)
  file:close()
  assert(os.rename(temporary, path))
end

local function stringify(value)
  if type(value) == "string" then return value end
  if type(value) ~= "table" then return tostring(value) end
  local seen, parts = {}, {}
  local function render(item)
    if type(item) ~= "table" then return tostring(item) end
    if seen[item] then return "<cycle>" end
    seen[item] = true
    local fields = {}
    for key, child in pairs(item) do
      fields[#fields + 1] = tostring(key) .. "=" .. render(child)
    end
    table.sort(fields)
    return "{" .. table.concat(fields, ", ") .. "}"
  end
  local ok, rendered = pcall(render, value)
  return ok and rendered or tostring(value)
end

local function capture(fn)
  local lines = {}
  local real_print, real_write = print, io.write
  print = function(...)
    local parts = {}
    for index = 1, select("#", ...) do
      parts[index] = stringify((select(index, ...)))
    end
    lines[#lines + 1] = table.concat(parts, "\t")
  end
  io.write = function(value) lines[#lines + 1] = tostring(value) end
  local ok, result = xpcall(fn, debug.traceback)
  print, io.write = real_print, real_write
  return ok, result, table.concat(lines, "\n")
end

local function execute(job)
  local cell = job.cell or "cell"
  model:begin_cell(cell)
  local ok, result, output
  if job.widget then
    ok, result, output = capture(function()
      local spec, err = model:handle(job.widget, job.event or {})
      if spec == nil then error(err or "widget event failed", 0) end
      return spec
    end)
  else
    local chunk, compile_error = loadstring(job.code or "", "@cell")
    if chunk then
      ok, result, output = capture(chunk)
    else
      ok, result, output = false, compile_error, ""
    end
  end
  local scene = nil
  if ok and type(result) == "table" and result.scene ~= nil then
    scene, result = result.scene, nil
  end
  local value = nil
  if not ok then value = tostring(result)
  elseif result ~= nil and (type(result) ~= "table" or result.id == nil) then
    value = stringify(result)
  end
  return {
    id = job.id,
    ok = ok,
    output = output,
    value = value,
    scene = scene,
    widgets = model:export(cell),
  }
end

local ready = io.open(ready_path, "w")
if ready then ready:write("ready"); ready:close() end

while true do
  local file = io.open(job_path, "r")
  if file then
    local data = file:read("*a")
    file:close()
    os.remove(job_path)
    local parsed, job = pcall(json.decode, data)
    if parsed and job.quit then break end
    local result
    if parsed then
      result = execute(job)
    else
      result = { id = 0, ok = false, output = "", value = tostring(job) }
    end
    atomic_write(result_path, json.encode(result))
  end
  if ffi.C.usleep then ffi.C.usleep(10000) else os.execute("sleep 0.01") end
end
