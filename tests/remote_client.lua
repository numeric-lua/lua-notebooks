local root = (arg and arg[0] or "tests/remote_client.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local port = tonumber(arg[1] or "8765")
local Transport = require("notebook.websocket_transport")
local Remote = require("notebook.remote_supervisor")

local transport = Transport.new("ws://127.0.0.1:" .. port)
local seen
local remote = Remote.new({
  transport = transport,
  on_result = function(_, _, message) seen = message end,
  on_error = function(_, message) error("remote error: " .. tostring(message)) end,
})
local request = remote:run("client", "print('remote client'); return 6*7", "1:1")
assert(request, "request failed")
for _ = 1, 100 do
  remote:poll()
  if seen then break end
  os.execute("sleep 0.01")
end
assert(seen, "no remote result")
assert(seen.ok, seen.value)
assert(seen.output == "remote client", seen.output)
assert(seen.value == "42", seen.value)
print("remote client ok")
remote:close()
