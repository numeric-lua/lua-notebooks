#!/usr/bin/env luajit
--
-- Tiny static file server for the browser front-end.  No Python, Node, or
-- third-party modules are required; LuaJIT's FFI talks to the C sockets API.
--
local ffi = require("ffi")
local bit = require("bit")

ffi.cdef[[
typedef unsigned int socklen_t;
struct sockaddr_in {
  unsigned short sin_family;
  unsigned short sin_port;
  unsigned int sin_addr;
  unsigned char sin_zero[8];
};
int socket(int domain, int type, int protocol);
int bind(int fd, const struct sockaddr_in *addr, socklen_t len);
int listen(int fd, int backlog);
int accept(int fd, struct sockaddr_in *addr, socklen_t *len);
long read(int fd, void *buf, unsigned long count);
long write(int fd, const void *buf, unsigned long count);
int close(int fd);
int setsockopt(int fd, int level, int option, const void *value, socklen_t len);
unsigned int inet_addr(const char *address);
char *strerror(int errnum);
]]

local AF_INET = 2
local SOCK_STREAM = 1
local SOL_SOCKET = 1
local SO_REUSEADDR = 2

local function dirname(path)
  return path:match("^(.*)/[^/]*$") or "."
end

local function join(root, path)
  if root == "." then return path end
  if root:sub(-1) == "/" then return root .. path end
  return root .. "/" .. path
end

local function decode(path)
  return (path:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

local function mime(path)
  local extension = path:match("%.([%w]+)$")
  local types = {
    html = "text/html; charset=utf-8",
    css = "text/css; charset=utf-8",
    js = "text/javascript; charset=utf-8",
    mjs = "text/javascript; charset=utf-8",
    json = "application/json; charset=utf-8",
    luanb = "application/json; charset=utf-8",
    svg = "image/svg+xml",
    png = "image/png",
    ico = "image/x-icon",
    wasm = "application/wasm",
  }
  return types[(extension or ""):lower()] or "application/octet-stream"
end

local function response(status, contentType, body, close)
  if close == nil then close = true end
  local reason = status == 200 and "OK" or status == 404 and "Not Found" or
    status == 405 and "Method Not Allowed" or "Internal Server Error"
  return table.concat({
    "HTTP/1.1 " .. status .. " " .. reason,
    "Content-Type: " .. contentType,
    "Content-Length: " .. #body,
    "Cache-Control: no-store",
    "Connection: " .. (close and "close" or "keep-alive"),
    "", body,
  }, "\r\n")
end

local function send(fd, text)
  return ffi.C.write(fd, text, #text)
end

local function read_request(fd)
  local chunks = {}
  local total = 0
  local buffer = ffi.new("char[8192]")
  while total < 16384 do
    local count = tonumber(ffi.C.read(fd, buffer, 8192))
    if count == nil or count <= 0 then break end
    chunks[#chunks + 1] = ffi.string(buffer, count)
    total = total + count
    if table.concat(chunks):find("\r\n\r\n", 1, true) then break end
  end
  return table.concat(chunks)
end

local function serve_one(fd, root)
  local request = read_request(fd)
  local method, target = request:match("^(%u+)%s+([^%s]+)")
  if method == nil then
    send(fd, response(400, "text/plain; charset=utf-8", "bad request\n"))
    ffi.C.close(fd)
    return
  end
  if method ~= "GET" and method ~= "HEAD" then
    send(fd, response(405, "text/plain; charset=utf-8", "method not allowed\n"))
    ffi.C.close(fd)
    return
  end
  local path = decode(target:match("^[^?]*") or "/")
  if path == "/" then path = "/index.html" end
  if path:find("..", 1, true) or path:find("%z") then
    send(fd, response(404, "text/plain; charset=utf-8", "not found\n"))
    ffi.C.close(fd)
    return
  end
  local file = io.open(join(root, path:gsub("^/", "")), "rb")
  if file == nil then
    send(fd, response(404, "text/plain; charset=utf-8", "not found\n"))
    ffi.C.close(fd)
    return
  end
  local body = file:read("*a") or ""
  file:close()
  local payload = response(200, mime(path), body, true)
  if method == "HEAD" then payload = payload:gsub("\r\n\r\n.*$", "\r\n\r\n") end
  send(fd, payload)
  ffi.C.close(fd)
end

local function main()
  local port, host, root = 8010, "127.0.0.1", dirname(arg and arg[0] or "webapp/serve.lua")
  for index = 1, #arg do
    if arg[index] == "--port" then port = tonumber(arg[index + 1])
    elseif arg[index] == "--host" then host = arg[index + 1]
    elseif arg[index] == "--root" then root = arg[index + 1]
    end
  end
  if port == nil then
    io.stderr:write("usage: serve.lua [--host 127.0.0.1] [--port 8010] [--root webapp]\n")
    os.exit(2)
  end
  local fd = ffi.C.socket(AF_INET, SOCK_STREAM, 0)
  if fd < 0 then error("socket: " .. ffi.string(ffi.C.strerror(ffi.errno()))) end
  local one = ffi.new("int[1]", 1)
  ffi.C.setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, one, ffi.sizeof(one))
  local address = ffi.new("struct sockaddr_in")
  address.sin_family = AF_INET
  local network_port = bit.rshift(bit.bswap(port), 16)
  address.sin_port = network_port
  address.sin_addr = ffi.C.inet_addr(host)
  if ffi.C.bind(fd, address, ffi.sizeof(address)) < 0 then
    error("bind: " .. ffi.string(ffi.C.strerror(ffi.errno())))
  end
  if ffi.C.listen(fd, 16) < 0 then
    error("listen: " .. ffi.string(ffi.C.strerror(ffi.errno())))
  end
  print(string.format("SERVE_READY http://%s:%d", host, port))
  io.stdout:flush()
  while true do
    local client = ffi.C.accept(fd, nil, nil)
    if client >= 0 then
      local ok, err = pcall(serve_one, client, root)
      if not ok then
        io.stderr:write("serve error: " .. tostring(err) .. "\n")
        pcall(function() ffi.C.close(client) end)
      end
    end
  end
end

main()
