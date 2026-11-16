--
-- Blocking WebSocket transport for the remote supervisor.  Intended for
-- desktop/native clients and tests; the web front-end needs an async bridge.
--
local WebSocket = require("scripts.websocket")

local Transport = {}

function Transport.new(url)
  local host, port = tostring(url):match("^ws://([^:/]+):(%d+)$")
  if host == nil then
    error("websocket transport expects ws://host:port", 2)
  end
  local client, err = WebSocket.connect(host, tonumber(port))
  if client == nil then error(err, 2) end
  return {
    send = function(text) return client:send(text, 1) end,
    receive = function()
      local frame, receive_error = client:receive()
      if frame == nil then return nil, receive_error end
      return frame.payload
    end,
    close = function() client:close() end,
  }
end

return Transport
