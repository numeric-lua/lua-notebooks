--
-- LÖVR named-channel transport.  Carries framed JSON-RPC byte strings.
--
local Channel = {}
Channel.__index = Channel

function Channel.new(in_name, out_name)
  return setmetatable({
    input = lovr.thread.getChannel(in_name),
    output = lovr.thread.getChannel(out_name),
  }, Channel)
end

function Channel:send(bytes)
  self.output:push(bytes)
end

function Channel:read()
  local value = self.input:pop(true)
  if value == nil or value == "__quit" then return nil end
  return value
end

return Channel
