local root = (arg and arg[0] or "tests/browser_transport.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local fake = {
  ready = 0,
  opened = false,
  sent = {},
  events = {},
}
function fake.open(url)
  fake.url = url
  fake.opened = true
  fake.ready = 0
  fake.events[#fake.events + 1] = { type = "open" }
  return true
end
function fake.state()
  return fake.ready
end
function fake.send(text)
  assert(fake.ready == 1, "send before open")
  fake.sent[#fake.sent + 1] = text
  return true
end
function fake.poll()
  local event = table.remove(fake.events, 1)
  if event and event.type == "open" then fake.ready = 1 end
  return event
end
function fake.close()
  fake.ready = 3
end
package.preload["lovr_websocket"] = function() return fake end
package.loaded["lovr_websocket"] = nil

local BrowserTransport = require("notebook.browser_transport")
local transport = BrowserTransport.new("wss://example.invalid")
assert(fake.opened)
assert(transport:send("queued"))
assert(#fake.sent == 0, "message sent before open")
local event = transport:receive()
assert(event == nil, "open event should not surface")
assert(#fake.sent == 1 and fake.sent[1] == "queued")
fake.ready = 1
assert(transport:send("live"))
fake.events[#fake.events + 1] = { type = "message", data = "reply" }
assert(transport:receive() == "reply")
transport:close()
print("browser transport ok")
