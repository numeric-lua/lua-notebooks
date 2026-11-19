--
-- Restricted environment for user extensions.  Built-in extensions load with
-- the normal environment; user modules get this whitelist instead.
--
local Sandbox = {}

local function readonly(source)
  return setmetatable({}, {
    __index = source,
    __newindex = function()
      error("user extensions cannot modify the host API", 2)
    end,
  })
end

function Sandbox.create(api, permissions)
  local granted = {}
  for _, permission in ipairs(permissions or { "graphics", "timer" }) do
    granted[permission] = true
  end
  local env = {
    math = math, string = string, table = table,
    ipairs = ipairs, pairs = pairs, next = next, select = select,
    tonumber = tonumber, tostring = tostring, type = type,
    assert = assert, error = error, pcall = pcall, xpcall = xpcall,
    print = print,
    lovr = readonly({
      graphics = granted.graphics and readonly(api.graphics) or nil,
      timer = granted.timer and readonly(api.timer) or nil,
      input = granted.input and api.input or nil,
      filesystem = granted.filesystem and api.filesystem or nil,
      network = granted.network and api.network or nil,
    }),
  }
  if api.vec3 then env.vec3 = api.vec3 end
  if api.mat4 then env.mat4 = api.mat4 end
  if api.quat then env.quat = api.quat end
  env._G = env
  return setmetatable(env, {
    __index = function(_, key)
      error("user extension attempted to access disallowed global: " ..
        tostring(key), 2)
    end,
  })
end

function Sandbox.apply(chunk, api, permissions)
  if type(setfenv) ~= "function" then
    return nil, "this Lua runtime has no setfenv; refusing to load user extension"
  end
  setfenv(chunk, Sandbox.create(api, permissions))
  return chunk
end

return Sandbox
