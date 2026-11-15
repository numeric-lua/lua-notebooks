local root = (arg and arg[0] or "tests/sandbox.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Sandbox = require("ui.extension_sandbox")
local env = Sandbox.create({
  graphics = { newTexture = function() end },
  timer = { getTime = function() return 0 end },
})
local chunk = assert(loadstring("return { draw = function() return 1 end }"))
assert(setfenv(chunk, env))
local descriptor = chunk()
assert(type(descriptor.draw) == "function")
local probe = assert(loadstring("return os"))
setfenv(probe, env)
local ok = pcall(probe)
assert(not ok, "sandbox exposed os")
print("sandbox isolation ok")
