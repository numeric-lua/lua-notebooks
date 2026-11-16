--
-- Browser WebSocket transport backed by web/lovr_websocket.c.  The native
-- module batches browser WebSocket events; this adapter queues outgoing
-- messages until the socket reports open.
--
local Native = require("lovr_websocket")

local BrowserTransport = {}

function BrowserTransport.new(url)
  local ok, err = Native.open(url)
  if not ok then error(err, 2) end
  local transport = {
    url = url,
    outgoing = {},
    closed = false,
  }
  function transport:_flush()
    local pending = self.outgoing
    self.outgoing = {}
    for _, text in ipairs(pending) do
      local sent, send_error = Native.send(text)
      if not sent then
        self.closed = true
        return nil, send_error
      end
    end
    return true
  end
  function transport:send(text)
    if self.closed then return nil, "websocket is closed" end
    if Native.state() == 1 then
      if #self.outgoing > 0 then
        local ok_flush, flush_error = self:_flush()
        if not ok_flush then return nil, flush_error end
      end
      return Native.send(text)
    end
    self.outgoing[#self.outgoing + 1] = text
    return true
  end
  function transport:receive()
    while true do
      local event = Native.poll()
      if event == nil then return nil end
      if event.type == "open" then
        local ok_flush, flush_error = self:_flush()
        if not ok_flush then return nil, flush_error end
      elseif event.type == "message" then
        return event.data
      elseif event.type == "close" then
        self.closed = true
        return nil, event.message or "websocket closed"
      elseif event.type == "error" then
        self.closed = true
        return nil, event.message or "websocket error"
      end
    end
  end
  function transport:close()
    self.closed = true
    self.outgoing = {}
    Native.close()
  end
  return transport
end

return BrowserTransport
