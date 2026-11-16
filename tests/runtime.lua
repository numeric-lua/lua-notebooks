local root = (arg and arg[0] or "tests/runtime.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local Runtime = require("notebook.runtime")
local passed, failed = 0, 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1; io.write(".")
  else
    failed = failed + 1
    io.write("F\n  " .. name .. ": " .. tostring(err) .. "\n")
  end
end
local function eq(a, b)
  if a ~= b then error(tostring(a) .. " ~= " .. tostring(b), 2) end
end

local real_lovr = lovr
test("web disables threads and processes", function()
  lovr = {
    system = { getOS = function() return "Web" end },
    thread = { newThread = function() end, getChannel = function() end },
  }
  eq(Runtime.is_web(), true)
  eq(Runtime.has_threads(), false)
  eq(Runtime.has_processes(), false)
  eq(Runtime.has_native_filesystem(), false)
end)
test("desktop detects thread support", function()
  lovr = {
    system = { getOS = function() return "Linux" end },
    thread = { newThread = function() end, getChannel = function() end },
  }
  eq(Runtime.is_web(), false)
  eq(Runtime.has_threads(), true)
end)
test("no lovr means no thread or process runtime", function()
  lovr = nil
  eq(Runtime.is_web(), false)
  eq(Runtime.has_threads(), false)
  eq(Runtime.has_processes(), Runtime.has_ffi())
end)
lovr = real_lovr

io.write(string.format("\n%d runtime tests, %d passed, %d failed\n",
  passed + failed, passed, failed))
if failed > 0 then os.exit(1) end
