--
-- Neovim msgpack-RPC over a local TCP socket.  Pure LuaJIT FFI; no luv/lua-mp.
--
local ffi = require("ffi")
local Msgpack = require("notebook.nvim.msgpack")

ffi.cdef[[
typedef struct { uint16_t sin_family; uint16_t sin_port; uint32_t sin_addr; char pad[8]; } sockaddr_in;
typedef struct { long tv_sec; long tv_usec; } timeval;
typedef struct { int fd; short events; short revents; } pollfd;
typedef struct { uint16_t sun_family; char sun_path[108]; } sockaddr_un;
typedef struct { uint8_t sun_len; uint8_t sun_family; char sun_path[104]; } sockaddr_un_osx;
int socket(int domain, int type, int protocol);
int connect(int fd, const void *addr, unsigned int len);
long send(int fd, const void *buf, unsigned long len, int flags);
long recv(int fd, void *buf, unsigned long len, int flags);
int select(int nfds, void *readfds, void *writefds, void *exceptfds, timeval *timeout);
int poll(pollfd *fds, unsigned long nfds, int timeout);
int close(int fd);
int fcntl(int fd, int cmd, int arg);
uint16_t htons(uint16_t value);
uint32_t htonl(uint32_t value);
]]

local AF_INET, AF_UNIX, SOCK_STREAM = 2, 1, 1
local O_NONBLOCK = ffi.os == "OSX" and 4 or 2048
local Rpc = {}
Rpc.__index = Rpc

local function send_all(fd, data)
  local offset = 1
  local deadline = os.clock() + 5
  while offset <= #data do
    local chunk = data:sub(offset)
    local sent = tonumber(ffi.C.send(fd, chunk, #chunk, 0))
    if sent ~= nil and sent > 0 then
      offset = offset + sent
    else
      local errno = ffi.errno()
      if errno == 4 then
        -- interrupted; retry immediately
      elseif errno == 11 or errno == 35 then
        local pfd = ffi.new("pollfd[1]", { { fd = fd, events = 4 } })
        ffi.C.poll(pfd, 1, 100)
      else
        return nil, "send failed"
      end
      if os.clock() > deadline then return nil, "send timeout" end
    end
  end
  return true
end

function Rpc.connect_unix(path)
  local fd = ffi.C.socket(AF_UNIX, SOCK_STREAM, 0)
  if fd < 0 then return nil, "socket failed" end
  local address
  if ffi.os == "OSX" then
    address = ffi.new("sockaddr_un_osx")
    address.sun_len = #path + 1
    address.sun_family = AF_UNIX
    ffi.copy(address.sun_path, path, math.min(#path, 103))
  else
    address = ffi.new("sockaddr_un")
    address.sun_family = AF_UNIX
    ffi.copy(address.sun_path, path, math.min(#path, 107))
  end
  if ffi.C.connect(fd, address, ffi.sizeof(address)) ~= 0 then
    ffi.C.close(fd)
    return nil, "connect failed"
  end
  local flags = ffi.C.fcntl(fd, 3, 0)
  ffi.C.fcntl(fd, 4, bit.bor(flags, O_NONBLOCK))
  return setmetatable({ fd = fd, buffer = "", seq = 0,
    callbacks = {}, notifications = {} }, Rpc)
end

function Rpc.connect(host, port)
  local fd = ffi.C.socket(AF_INET, SOCK_STREAM, 0)
  if fd < 0 then return nil, "socket failed" end
  local address = ffi.new("sockaddr_in")
  address.sin_family = AF_INET
  address.sin_port = ffi.C.htons(port)
  address.sin_addr = ffi.C.htonl(0x7f000001)
  if ffi.C.connect(fd, address, ffi.sizeof(address)) ~= 0 then
    ffi.C.close(fd)
    return nil, "connect failed"
  end
  local flags = ffi.C.fcntl(fd, 3, 0)
  ffi.C.fcntl(fd, 4, bit.bor(flags, O_NONBLOCK))
  return setmetatable({ fd = fd, buffer = "", seq = 0,
    callbacks = {}, notifications = {} }, Rpc)
end

function Rpc:send(message)
  return send_all(self.fd, Msgpack.encode(message))
end

function Rpc:request(method, params, callback)
  self.seq = self.seq + 1
  local seq = self.seq
  self.callbacks[seq] = callback
  local ok, err = self:send(Msgpack.array({ 0, seq, method,
    Msgpack.array(params or {}) }))
  if not ok then
    self.callbacks[seq] = nil
    return nil, err
  end
  return seq
end

function Rpc:notify(method, params)
  return self:send(Msgpack.array({ 2, method, Msgpack.array(params or {}) }))
end

function Rpc:_dispatch(message)
  if type(message) ~= "table" then return end
  if message[1] == 1 then
    local seq, err, result = message[2], message[3], message[4]
    local callback = self.callbacks[seq]
    self.callbacks[seq] = nil
    if callback then callback(err, result) end
  elseif message[1] == 2 then
    local method, params = message[2], message[3] or {}
    self.notifications[#self.notifications + 1] = { method, params }
  elseif message[1] == 0 then
    local id, method = message[2], message[3]
    self:send(Msgpack.array({ 1, id,
      { code = -32601, message = "unsupported client request: " ..
        tostring(method) }, nil }))
  end
end

function Rpc:feed(timeout)
  local buffer = ffi.new("char[65536]")
  local decoded = 0
  while true do
    local count = tonumber(ffi.C.recv(self.fd, buffer, 65536, 0))
    if count == nil or count < 0 then
      local errno = ffi.errno()
      if errno == 4 or errno == 11 then break end
      return decoded, "error"
    end
    if count == 0 then return decoded, "closed" end
    self.buffer = self.buffer .. ffi.string(buffer, count)
    if #self.buffer > 8388608 then
      self.buffer = ""
      return decoded, "error"
    end
    while #self.buffer > 0 do
      local ok, message, position = pcall(Msgpack.decode, self.buffer, 1)
      if not ok or position == nil or position <= 1 or
         position > #self.buffer + 1 then break end
      self.buffer = self.buffer:sub(position)
      self:_dispatch(message)
      decoded = decoded + 1
    end
  end
  return decoded
end

function Rpc:wait(seq, timeout)
  if seq == nil then return nil, "no request" end
  local deadline = os.clock() + (timeout or 5)
  local response
  local original = self.callbacks[seq]
  self.callbacks[seq] = function(err, result)
    response = { err = err, result = result }
    if original then original(err, result) end
  end
  local pfd = ffi.new("pollfd[1]", { { fd = self.fd, events = 1 } })
  while response == nil and os.clock() < deadline do
    ffi.C.poll(pfd, 1, 5)
    local _, status = self:feed(50)
    if status then break end
  end
  if response == nil then self.callbacks[seq] = original end
  return response and response.result, response and response.err
end

function Rpc:close()
  if self.fd then ffi.C.close(self.fd); self.fd = nil end
end

return Rpc
