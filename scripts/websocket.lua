--
-- Minimal blocking WebSocket server for the local kernel gateway.
-- LuaJIT FFI only; no external dependencies.  Intended for localhost/prototype
-- use, not as an internet-facing server.
--
local ffi = require("ffi")
local bit = require("bit")

ffi.cdef[[
typedef unsigned int socklen_t;
typedef unsigned short sa_family_t;
struct sockaddr_in {
  uint16_t sin_family;
  uint16_t sin_port;
  uint32_t sin_addr;
  char sin_zero[8];
};
int socket(int domain, int type, int protocol);
int setsockopt(int fd, int level, int option, const void *value, socklen_t len);
int bind(int fd, const struct sockaddr_in *address, socklen_t len);
int connect(int fd, const struct sockaddr_in *address, socklen_t len);
struct pollfd { int fd; short events; short revents; };
int poll(struct pollfd *fds, unsigned long nfds, int timeout);
int listen(int fd, int backlog);
int accept(int fd, struct sockaddr *address, socklen_t *len);
long recv(int fd, void *buffer, size_t length, int flags);
long send(int fd, const void *buffer, size_t length, int flags);
int close(int fd);
]]

local AF_INET = 2
local SOCK_STREAM = 1
local SOL_SOCKET = 1
local SO_REUSEADDR = 2
local INVALID = -1

local WebSocket = {}

local function htons(value)
  return bit.bor(bit.lshift(value, 8), bit.rshift(value, 8))
end

local function sha1(message)
  local bytes = {}
  for index = 1, #message do bytes[index] = message:byte(index) end
  local bit_length = #bytes * 8
  bytes[#bytes + 1] = 0x80
  while (#bytes % 64) ~= 56 do bytes[#bytes + 1] = 0 end
  local high = math.floor(bit_length / 4294967296)
  local low = bit_length % 4294967296
  for shift = 24, 0, -8 do
    bytes[#bytes + 1] = bit.band(bit.rshift(high, shift), 0xff)
  end
  for shift = 24, 0, -8 do
    bytes[#bytes + 1] = bit.band(bit.rshift(low, shift), 0xff)
  end

  local h0, h1, h2, h3, h4 = 0x67452301, 0xefcdab89,
    0x98badcfe, 0x10325476, 0xc3d2e1f0
  local words = {}
  for chunk = 0, (#bytes / 64) - 1 do
    local base = chunk * 64
    for index = 1, 16 do
      local offset = base + (index - 1) * 4
      words[index] = bit.bor(
        bit.lshift(bytes[offset + 1], 24),
        bit.lshift(bytes[offset + 2], 16),
        bit.lshift(bytes[offset + 3], 8),
        bytes[offset + 4])
    end
    for index = 17, 80 do
      words[index] = bit.rol(bit.bxor(words[index - 3],
        words[index - 8], words[index - 14], words[index - 16]), 1)
    end
    local a, b, c, d, e = h0, h1, h2, h3, h4
    for index = 1, 80 do
      local f, k
      if index <= 20 then
        f = bit.bor(bit.band(b, c), bit.band(bit.bnot(b), d))
        k = 0x5a827999
      elseif index <= 40 then
        f = bit.bxor(b, c, d)
        k = 0x6ed9eba1
      elseif index <= 60 then
        f = bit.bor(bit.band(b, c), bit.band(b, d), bit.band(c, d))
        k = 0x8f1bbcdc
      else
        f = bit.bxor(b, c, d)
        k = 0xca62c1d6
      end
      local temp = bit.band(bit.rol(a, 5) + f + e + k + words[index],
        0xffffffff)
      e, d, c, b, a = d, c, bit.rol(b, 30), a, temp
    end
    h0 = bit.band(h0 + a, 0xffffffff)
    h1 = bit.band(h1 + b, 0xffffffff)
    h2 = bit.band(h2 + c, 0xffffffff)
    h3 = bit.band(h3 + d, 0xffffffff)
    h4 = bit.band(h4 + e, 0xffffffff)
  end
  local digest = {}
  for _, value in ipairs({ h0, h1, h2, h3, h4 }) do
    for shift = 24, 0, -8 do
      digest[#digest + 1] = bit.band(bit.rshift(value, shift), 0xff)
    end
  end
  return string.char(unpack(digest))
end

local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function base64(value)
  local output = {}
  for index = 1, #value, 3 do
    local a = value:byte(index) or 0
    local b = value:byte(index + 1) or 0
    local c = value:byte(index + 2) or 0
    local triple = a * 65536 + b * 256 + c
    output[#output + 1] = alphabet:sub(math.floor(triple / 262144) % 64 + 1,
      math.floor(triple / 262144) % 64 + 1)
    output[#output + 1] = alphabet:sub(math.floor(triple / 4096) % 64 + 1,
      math.floor(triple / 4096) % 64 + 1)
    output[#output + 1] = alphabet:sub(math.floor(triple / 64) % 64 + 1,
      math.floor(triple / 64) % 64 + 1)
    output[#output + 1] = alphabet:sub(triple % 64 + 1, triple % 64 + 1)
  end
  local padding = (3 - (#value % 3)) % 3
  for index = 1, padding do
    output[#output - index + 1] = "="
  end
  return table.concat(output)
end

local function receive_exact(fd, length)
  local buffer = ffi.new("uint8_t[?]", length)
  local offset = 0
  while offset < length do
    local count = ffi.C.recv(fd, ffi.cast("uint8_t*", buffer) + offset,
      length - offset, 0)
    if count <= 0 then return nil end
    offset = offset + tonumber(count)
  end
  return ffi.string(buffer, length)
end

local function send_all(fd, data)
  local offset = 1
  while offset <= #data do
    local count = ffi.C.send(fd, ffi.cast("const char*", data:sub(offset)),
      #data - offset + 1, 0)
    if count <= 0 then return nil, "send failed" end
    offset = offset + tonumber(count)
  end
  return true
end

local function read_http(fd)
  local chunks = {}
  local total = 0
  while total < 16384 do
    local byte = receive_exact(fd, 1)
    if byte == nil then return nil end
    chunks[#chunks + 1] = byte
    total = total + 1
    if total >= 4 and table.concat(chunks, ""):sub(-4) == "\r\n\r\n" then
      return table.concat(chunks, "")
    end
  end
  return nil
end

local function handshake(fd, authorize)
  local request = read_http(fd)
  if request == nil then return nil, "missing HTTP request" end
  if authorize ~= nil and not authorize(request) then
    pcall(send_all, fd, "HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\n\r\n")
    return nil, "unauthorized"
  end
  local key = request:match("[Ss]ec%-[Ww]eb[Ss]ocket%-[Kk]ey:%s*([^\r\n]+)")
  if key == nil then return nil, "missing Sec-WebSocket-Key" end
  key = key:gsub("%s+$", "")
  local accept = base64(sha1(key .. "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
  local response = "HTTP/1.1 101 Switching Protocols\r\n" ..
    "Upgrade: websocket\r\nConnection: Upgrade\r\n" ..
    "Sec-WebSocket-Accept: " .. accept .. "\r\n\r\n"
  local ok, err = send_all(fd, response)
  if not ok then return nil, err end
  return true
end

function WebSocket.listen(host, port, options)
  options = options or {}
  local fd = ffi.C.socket(AF_INET, SOCK_STREAM, 0)
  if fd == INVALID then return nil, "socket() failed" end
  local reuse = ffi.new("int[1]", 1)
  ffi.C.setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, reuse, ffi.sizeof("int"))
  local address = ffi.new("struct sockaddr_in")
  address.sin_family = AF_INET
  address.sin_port = htons(port)
  if host == nil or host == "127.0.0.1" or host == "localhost" then
    address.sin_addr = 0x0100007f
  elseif host == "0.0.0.0" then
    address.sin_addr = 0
  else
    ffi.C.close(fd)
    return nil, "unsupported gateway host (use 127.0.0.1 or 0.0.0.0)"
  end
  if ffi.C.bind(fd, address, ffi.sizeof(address)) ~= 0 then
    ffi.C.close(fd)
    return nil, "bind failed on port " .. tostring(port)
  end
  if ffi.C.listen(fd, 8) ~= 0 then
    ffi.C.close(fd)
    return nil, "listen failed"
  end
  return {
    fd = fd,
    authorize = options.authorize,
    accept = function(self)
      local client = ffi.C.accept(self.fd, nil, nil)
      if client == INVALID then return nil, "accept failed" end
      local ok, err = handshake(client, self.authorize)
      if not ok then ffi.C.close(client); return nil, err end
      return { fd = client }
    end,
    receive = function(_, client)
      local first = receive_exact(client.fd, 2)
      if first == nil then return nil, "closed" end
      local b1, b2 = first:byte(1), first:byte(2)
      local opcode = bit.band(b1, 0x0f)
      local fin = bit.band(b1, 0x80) ~= 0
      local masked = bit.band(b2, 0x80) ~= 0
      local length = bit.band(b2, 0x7f)
      if length == 126 then
        local extended = receive_exact(client.fd, 2)
        if extended == nil then return nil, "closed" end
        length = extended:byte(1) * 256 + extended:byte(2)
      elseif length == 127 then
        local extended = receive_exact(client.fd, 8)
        if extended == nil then return nil, "closed" end
        length = 0
        for index = 1, 8 do length = length * 256 + extended:byte(index) end
      end
      if not masked then return nil, "client frame is not masked" end
      local mask = receive_exact(client.fd, 4)
      if mask == nil then return nil, "closed" end
      local payload = receive_exact(client.fd, length)
      if payload == nil then return nil, "closed" end
      local bytes = {}
      for index = 1, #payload do
        bytes[index] = bit.bxor(payload:byte(index),
          mask:byte((index - 1) % 4 + 1))
      end
      return {
        opcode = opcode,
        fin = fin,
        payload = string.char(unpack(bytes)),
      }
    end,
    send = function(self, client, payload, opcode)
      opcode = opcode or 1
      local length = #payload
      local header
      if length < 126 then
        header = string.char(0x80 + opcode, length)
      elseif length < 65536 then
        header = string.char(0x80 + opcode, 126, math.floor(length / 256),
          length % 256)
      else
        header = string.char(0x80 + opcode, 127, 0, 0, 0, 0,
          math.floor(length / 16777216) % 256,
          math.floor(length / 65536) % 256,
          math.floor(length / 256) % 256, length % 256)
      end
      local ok, err = send_all(client.fd, header .. payload)
      if not ok then return nil, err end
      return true
    end,
    close = function(self, client)
      if client then ffi.C.close(client.fd) end
    end,
    shutdown = function(self)
      ffi.C.close(self.fd)
    end,
  }
end

local function random_bytes(count)
  math.randomseed(os.time() + math.floor(os.clock() * 1000000))
  local bytes = {}
  for index = 1, count do bytes[index] = math.random(0, 255) end
  return string.char(unpack(bytes))
end

local function parse_frame(fd, expect_mask)
  local first = receive_exact(fd, 2)
  if first == nil then return nil, "closed" end
  local b1, b2 = first:byte(1), first:byte(2)
  local opcode = bit.band(b1, 0x0f)
  local masked = bit.band(b2, 0x80) ~= 0
  local length = bit.band(b2, 0x7f)
  if expect_mask and not masked then return nil, "unmasked server frame" end
  if length == 126 then
    local extended = receive_exact(fd, 2)
    if extended == nil then return nil, "closed" end
    length = extended:byte(1) * 256 + extended:byte(2)
  elseif length == 127 then
    local extended = receive_exact(fd, 8)
    if extended == nil then return nil, "closed" end
    length = 0
    for index = 1, 8 do length = length * 256 + extended:byte(index) end
  end
  local mask = nil
  if masked then
    mask = receive_exact(fd, 4)
    if mask == nil then return nil, "closed" end
  end
  local payload = receive_exact(fd, length)
  if payload == nil then return nil, "closed" end
  if mask then
    local bytes = {}
    for index = 1, #payload do
      bytes[index] = bit.bxor(payload:byte(index),
        mask:byte((index - 1) % 4 + 1))
    end
    payload = string.char(unpack(bytes))
  end
  return { opcode = opcode, payload = payload }
end

local function masked_frame(payload, opcode)
  local length = #payload
  local header
  local mask = random_bytes(4)
  local mask_flag = 0x80
  if length < 126 then
    header = string.char(0x80 + opcode, mask_flag + length)
  elseif length < 65536 then
    header = string.char(0x80 + opcode, mask_flag + 126,
      math.floor(length / 256), length % 256)
  else
    header = string.char(0x80 + opcode, mask_flag + 127, 0, 0, 0, 0,
      math.floor(length / 16777216) % 256,
      math.floor(length / 65536) % 256,
      math.floor(length / 256) % 256, length % 256)
  end
  local bytes = {}
  for index = 1, #payload do
    bytes[index] = bit.bxor(payload:byte(index),
      mask:byte((index - 1) % 4 + 1))
  end
  return header .. mask .. string.char(unpack(bytes))
end

function WebSocket.connect(host, port)
  local fd = ffi.C.socket(AF_INET, SOCK_STREAM, 0)
  if fd == INVALID then return nil, "socket() failed" end
  local address = ffi.new("struct sockaddr_in")
  address.sin_family = AF_INET
  address.sin_port = htons(port)
  if host == nil or host == "127.0.0.1" or host == "localhost" then
    address.sin_addr = 0x0100007f
  else
    ffi.C.close(fd)
    return nil, "unsupported client host (use 127.0.0.1)"
  end
  if ffi.C.connect(fd, address, ffi.sizeof(address)) ~= 0 then
    ffi.C.close(fd)
    return nil, "connect failed"
  end
  local key = base64(random_bytes(16))
  local request = "GET / HTTP/1.1\r\nHost: " .. host .. ":" ..
    tostring(port) .. "\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" ..
    "Sec-WebSocket-Key: " .. key .. "\r\nSec-WebSocket-Version: 13\r\n\r\n"
  local ok, err = send_all(fd, request)
  if not ok then ffi.C.close(fd); return nil, err end
  local response = read_http(fd)
  if response == nil or not response:match("^HTTP/1%.1 101") then
    ffi.C.close(fd)
    return nil, "websocket handshake failed"
  end
  local expected = base64(sha1(key ..
    "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
  local accept = response:match(
    "[Ss]ec%-[Ww]eb[Ss]ocket%-[Aa]ccept:%s*([^\r\n]+)")
  if accept == nil or accept:gsub("%s+$", "") ~= expected then
    ffi.C.close(fd)
    return nil, "invalid websocket accept"
  end
  local client = { fd = fd }
  function client:send(payload, opcode)
    return send_all(self.fd, masked_frame(payload, opcode or 1))
  end
  function client:receive()
    local descriptor = ffi.new("struct pollfd[1]")
    descriptor[0].fd = self.fd
    descriptor[0].events = 1
    local ready = ffi.C.poll(descriptor, 1, 0)
    if ready <= 0 then return nil end
    local frame, receive_error = parse_frame(self.fd, false)
    if frame == nil then return nil, receive_error end
    if frame.opcode == 9 then
      self:send(frame.payload, 10)
      return self:receive()
    end
    if frame.opcode == 8 then return nil, "closed" end
    return frame
  end
  function client:close()
    pcall(self.send, self, "", 8)
    ffi.C.close(self.fd)
  end
  return client
end

return WebSocket
