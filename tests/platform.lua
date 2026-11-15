local root = (arg and arg[0] or "tests/platform.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Platform = require("notebook.process_platform")
local function contains(value, needle)
  assert(value:find(needle, 1, true), "missing " .. needle .. " in " .. value)
end
local posix = Platform.spawn("posix", "w.lua", "/tmp/d", "/app", "/tmp/d/log",
  "/tmp/d/pid", 524288, 12)
contains(posix, "ulimit -v 524288")
contains(posix, "exec luajit")
local windows = Platform.spawn("windows", "C:\\app\\w.lua", "C:\\tmp\\d",
  "C:\\app", "C:\\tmp\\d\\log", "C:\\tmp\\d\\pid", 1, 1)
contains(windows, "Start-Process")
contains(windows, "Out-File")
contains(Platform.kill("windows", 42), "taskkill /PID 42")
contains(Platform.remove("windows", "C:\\tmp\\d"), "rmdir /S /Q")
contains(Platform.mkdir("posix", "/tmp/d"), "mkdir -p")
print("process platform tests ok")
