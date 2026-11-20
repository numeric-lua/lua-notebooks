#!/usr/bin/env luajit
--
-- Local WebSocket gateway for remote lua-notebooks kernels.
-- Prototype: one sequential connection, no authentication, localhost by
-- default.  Run cells in the gateway process, which may use LuaJIT FFI
-- libraries available on LUA_PATH/LUA_CPATH.
--
local root = (arg and arg[0] or "scripts/kernel-gateway.lua"):
  match("^(.*)/scripts/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local json = require("notebook.json")
local Engine = require("kernel.engine")
local WebSocket = require("scripts.websocket")

local debug = os.getenv("LUANB_GATEWAY_DEBUG") == "1"
local host, port = "127.0.0.1", 8765
local token, origin, token_expires, max_frame
for index = 1, #arg do
  if arg[index] == "--host" then host = arg[index + 1]
  elseif arg[index] == "--port" then port = tonumber(arg[index + 1])
  elseif arg[index] == "--token" then token = arg[index + 1]
  elseif arg[index] == "--origin" then origin = arg[index + 1]
  elseif arg[index] == "--token-expires" then token_expires = tonumber(arg[index + 1])
  elseif arg[index] == "--max-frame" then max_frame = tonumber(arg[index + 1])
  end
end
if host == nil or port == nil then
  io.stderr:write("usage: kernel-gateway.lua [--host 127.0.0.1] [--port 8765]\n")
  os.exit(2)
end

local Policy = require("notebook.gateway_policy")
local server, err = WebSocket.listen(host, port, {
  max_frame = max_frame,
  authorize = function(request)
    return Policy.authorize(request, {
      token = token, origin = origin, token_expires = token_expires,
    })
  end,
})
if server == nil then
  io.stderr:write("gateway: " .. tostring(err) .. "\n")
  os.exit(1)
end
print(string.format("GATEWAY_READY ws://%s:%d", host, port))
io.stdout:flush()

local function send(client, message)
  local ok, text = pcall(json.encode, message)
  if not ok then
    text = json.encode({ type = "error", message = tostring(text) })
  end
  return server.send(server, client, text)
end

while true do
  local client, accept_error = server.accept(server)
  if client == nil then
    io.stderr:write("gateway accept: " .. tostring(accept_error) .. "\n")
  else
    print("GATEWAY_CLIENT")
    io.stdout:flush()
    local engines = {}
    send(client, { type = "hello", capabilities = {
      runtime = "luajit", ffi = true, threads = true, remote = true,
    } })
    local running = true
    while running do
      local frame, receive_error = server.receive(server, client)
      if frame == nil then
        running = false
      elseif frame.opcode == 8 then
        server.send(server, client, "", 8)
        running = false
      elseif frame.opcode == 9 then
        server.send(server, client, frame.payload, 10)
      elseif frame.opcode == 1 then
        local decoded, message = pcall(json.decode, frame.payload)
        if debug then print("GATEWAY_MESSAGE " .. tostring(frame.payload)) end
        if not decoded or type(message) ~= "table" then
          send(client, { type = "error", message = "invalid JSON" })
        elseif message.type == "open" then
          engines[message.notebook] = Engine.new()
          send(client, { type = "open_ok", notebook = message.notebook })
        elseif message.type == "close" then
          engines[message.notebook] = nil
          send(client, { type = "closed", notebook = message.notebook })
        elseif message.type == "restart" then
          engines[message.notebook] = Engine.new()
          send(client, { type = "open_ok", notebook = message.notebook })
        elseif (message.type == "run" or message.type == "widget") and
            engines[message.notebook] then
          local ok, result = pcall(engines[message.notebook].run,
            engines[message.notebook], message)
          if ok then
            result.type = "result"
            if debug then
              print("GATEWAY_RESULT ok=" .. tostring(result.ok) ..
                " value=" .. tostring(result.value) ..
                " output=" .. tostring(result.output))
            end
            send(client, result)
          else
            send(client, { type = "error", id = message.id,
              message = tostring(result) })
          end
        else
          send(client, { type = "error", id = message.id,
            message = "unknown request or kernel not open" })
        end
        io.stdout:flush()
      end
    end
    server.close(server, client)
  end
end
