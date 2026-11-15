--
-- Command construction for the file-backed process kernel on POSIX and
-- Windows.  Pure string logic so both branches can be tested on one host.
--
local Platform = {}

function Platform.detect()
  return package.config:sub(1, 1) == "\\" and "windows" or "posix"
end

local function posix_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function windows_quote(value)
  return '"' .. tostring(value):gsub('"', '\\"') .. '"'
end

function Platform.quote(platform, value)
  if platform == "windows" then return windows_quote(value) end
  return posix_quote(value)
end

function Platform.temp_dir(id, time_value)
  if Platform.detect() == "windows" then
    local base = os.getenv("TEMP") or os.getenv("TMP") or "."
    return base .. "\\lua-notebooks-process-" .. tostring(time_value) .. "-" ..
      tostring(id):gsub("[^%w_-]", "_")
  end
  return string.format("/tmp/lua-notebooks-process-%d-%s", time_value,
    tostring(id):gsub("[^%w_-]", "_"))
end

function Platform.mkdir(platform, dir)
  if platform == "windows" then
    return "if not exist " .. windows_quote(dir) .. " mkdir " ..
      windows_quote(dir)
  end
  return "mkdir -p " .. posix_quote(dir)
end

function Platform.remove(platform, dir)
  if platform == "windows" then
    return "rmdir /S /Q " .. windows_quote(dir) .. " 2>nul"
  end
  return "rm -rf " .. posix_quote(dir)
end

function Platform.kill(platform, pid)
  if platform == "windows" then
    return "taskkill /PID " .. tostring(pid) .. " /F >nul 2>&1"
  end
  return "kill " .. posix_quote(pid) .. " 2>/dev/null || true"
end

function Platform.spawn(platform, script, dir, root, log, pid_file,
                        memory_kb, cpu_seconds)
  if platform == "windows" then
    local args = table.concat({
      windows_quote(script), windows_quote(dir), windows_quote(root),
    }, ",")
    return string.format(
      "powershell -NoProfile -ExecutionPolicy Bypass -Command " ..
      '"$p = Start-Process -FilePath luajit -ArgumentList @(%s) ' ..
      "-RedirectStandardOutput %s -RedirectStandardError %s " ..
      "-WindowStyle Hidden -PassThru; $p.Id | Out-File -Encoding ascii %s\"",
      args, windows_quote(log), windows_quote(log .. ".err"),
      windows_quote(pid_file))
  end
  return string.format(
    "(ulimit -v %d 2>/dev/null || true; ulimit -t %d 2>/dev/null || true; " ..
    "exec luajit %s %s %s) > %s 2>&1 & echo $! > %s",
    memory_kb, cpu_seconds, posix_quote(script), posix_quote(dir),
    posix_quote(root), posix_quote(log), posix_quote(pid_file))
end

return Platform
