--
-- LÖVR worker thread running the LSP server over named channels.
--
local in_name, out_name = ...
local thread = require("lovr.thread")
local Framing = require("notebook.lsp.framing")
local Server = require("notebook.lsp.server")
local input = thread.getChannel(in_name)
local output = thread.getChannel(out_name)
local decoder = Framing.new_decoder()

local function send(message)
  if message then output:push(Framing.encode(message)) end
end

local server = Server.new({ publish = send })
while true do
  local bytes = input:pop(true)
  if bytes == nil or bytes == "__quit" then break end
  local messages = decoder:feed(bytes)
  for _, message in ipairs(messages) do
    send(server:handle(message))
    if message.method == "exit" then return end
  end
end
