--
-- Headless Lua kernel.  Runs in a LÖVR thread with its own Lua state.
-- The host owns graphics; this file only executes code and reports results.
--
local in_name, out_name = ...
assert(in_name and out_name, "kernel worker needs input/output channel names")

local thread = require("lovr.thread")
local input = thread.getChannel(in_name)
local output = thread.getChannel(out_name)

local function stringify(value)
  local kind = type(value)
  if kind == "string" then return value end
  if kind == "number" or kind == "boolean" or kind == "nil" then
    return tostring(value)
  end
  if kind == "table" then
    local ok, encoded = pcall(function()
      -- Avoid a hard dependency on a JSON module in the sandbox.
      local function render(item, seen)
        if type(item) ~= "table" then return tostring(item) end
        if seen[item] then return "<cycle>" end
        seen[item] = true
        local parts = {}
        for key, child in pairs(item) do
          parts[#parts + 1] = tostring(key) .. "=" .. render(child, seen)
        end
        table.sort(parts)
        return "{" .. table.concat(parts, ", ") .. "}"
      end
      return render(value, {})
    end)
    if ok then return encoded end
  end
  return tostring(value)
end

while true do
  local job = input:pop(true)
  if job == nil or job == "__quit" then break end

  local lines = {}
  local real_print = print
  local real_write = io.write
  local function capture(...)
    local parts = {}
    for index = 1, select("#", ...) do
      parts[index] = stringify((select(index, ...)))
    end
    lines[#lines + 1] = table.concat(parts, "\t")
  end
  print = capture
  io.write = function(value)
    lines[#lines + 1] = tostring(value)
  end

  local chunk, compile_error = loadstring(job.code or "", "@cell")
  local ok, value
  if chunk then
    ok, value = xpcall(chunk, debug.traceback)
  else
    ok, value = false, compile_error
  end

  print = real_print
  io.write = real_write

  local scene = nil
  if ok and type(value) == "table" and value.scene ~= nil then
    scene = value.scene
    value = nil
  end

  output:push({
    id = job.id,
    ok = ok,
    output = table.concat(lines, "\n"),
    value = ok and value ~= nil and stringify(value) or nil,
    scene = scene,
  })
end
