--
-- LSP Content-Length framing.  Byte-oriented and incremental.
--
local json = require("notebook.json")
local Framing = {}

local Decoder = {}
Decoder.__index = Decoder

function Framing.new_decoder(options)
  options = options or {}
  return setmetatable({
    buffer = "",
    max_header = options.max_header or 8192,
    max_body = options.max_body or 8 * 1024 * 1024,
  }, Decoder)
end

function Framing.encode(message)
  local body = json.encode(message)
  return string.format("Content-Length: %d\r\n\r\n%s", #body, body)
end

function Decoder:feed(chunk)
  self.buffer = self.buffer .. (chunk or "")
  local messages = {}
  while true do
    local header_end = self.buffer:find("\r\n\r\n", 1, true)
    if header_end == nil then break end
    local header = self.buffer:sub(1, header_end - 1)
    if #header > self.max_header then return messages, "header too large" end
    local length
    for line in (header .. "\n"):gmatch("(.-)\n") do
      local name, value = line:match("^([^:]+):%s*(.*)$")
      if name and name:lower() == "content-length" then
        length = tonumber(value)
      end
    end
    if length == nil or length < 0 or length > self.max_body then
      return messages, "invalid content-length"
    end
    local body_start = header_end + 4
    if #self.buffer < body_start + length - 1 then break end
    local body = self.buffer:sub(body_start, body_start + length - 1)
    self.buffer = self.buffer:sub(body_start + length)
    local ok, message = pcall(json.decode, body)
    if not ok then
      messages[#messages + 1] = {
        jsonrpc = "2.0", id = json.null,
        error = { code = -32700, message = "parse error" },
      }
    else
      messages[#messages + 1] = message
    end
  end
  return messages
end

Framing.Decoder = Decoder
return Framing
