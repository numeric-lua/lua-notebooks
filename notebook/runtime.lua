--
-- Runtime capability detection.  The web build uses PUC Lua 5.1 and disables
-- threads/processes; desktop LÖVR uses LuaJIT and exposes both.
--
local Runtime = {}

local function system_os()
  if type(lovr) == "table" and type(lovr.system) == "table" and
      type(lovr.system.getOS) == "function" then
    local ok, value = pcall(lovr.system.getOS)
    if ok then return value end
  end
  return nil
end

function Runtime.is_web()
  return system_os() == "Web"
end

function Runtime.has_threads()
  if Runtime.is_web() then return false end
  return type(lovr) == "table" and type(lovr.thread) == "table" and
    type(lovr.thread.newThread) == "function" and
    type(lovr.thread.getChannel) == "function"
end

function Runtime.has_ffi()
  local ok = pcall(require, "ffi")
  return ok
end

function Runtime.has_processes()
  if Runtime.is_web() then return false end
  return Runtime.has_ffi() and type(os.execute) == "function" and
    type(io.open) == "function"
end

function Runtime.has_native_filesystem()
  return not Runtime.is_web() and type(os.rename) == "function" and
    type(os.remove) == "function"
end

return Runtime
