--
-- Headless Lua kernel.  Runs in a LÖVR thread with its own Lua state and
-- delegates cell execution to the shared Lua 5.1-safe engine.
--
local in_name, out_name, source = ...
assert(in_name and out_name, "kernel worker needs input/output channel names")
source = source or "."
package.path = source .. "/?.lua;" .. source .. "/?/init.lua;" .. package.path
local thread = require("lovr.thread")
local Engine = require("kernel.engine")
local input = thread.getChannel(in_name)
local output = thread.getChannel(out_name)
local engine = Engine.new()

while true do
  local job = input:pop(true)
  if job == nil or job == "__quit" then break end
  output:push(engine:run(job))
end
