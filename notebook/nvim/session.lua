--
-- Spawn a headless Neovim process and keep its UI grid in sync.
--
local Rpc = require("notebook.nvim.rpc")
local Grid = require("notebook.nvim.grid")
local Msgpack = require("notebook.nvim.msgpack")

local Session = {}
Session.__index = Session

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function free_port()
  return 20000 + math.random(0, 20000)
end

function Session.new(options)
  options = options or {}
  local self = setmetatable({
    cols = options.cols or 80, rows = options.rows or 24,
    exe = options.exe or "nvim", cwd = options.cwd,
    grid = Grid.new(options.cols or 80, options.rows or 24),
    rpc = nil, pid = nil, port = nil, closed = false,
  }, Session)
  local port = options.port or free_port()
  local command = { shell_quote(self.exe), "--headless", "--clean",
    "--listen", "127.0.0.1:" .. port }
  if options.file then command[#command + 1] = shell_quote(options.file) end
  local handle = assert(io.popen(table.concat(command, " ") ..
    " >/tmp/lua-notebooks-nvim.log 2>&1 & echo $!"))
  self.pid = tonumber(handle:read("*l") or "")
  handle:close()
  self.port = port
  for _ = 1, 100 do
    self.rpc = Rpc.connect("127.0.0.1", port)
    if self.rpc then break end
    os.execute("sleep 0.05")
  end
  if self.rpc == nil then
    error("could not connect to nvim on port " .. port)
  end
  self:request("nvim_ui_attach", { self.cols, self.rows,
    Msgpack.map({ ext_linegrid = true, rgb = true }) })
  return self
end

function Session:request(method, params, timeout)
  return self.rpc:wait(self.rpc:request(method, params), timeout or 5)
end

function Session:command(command)
  return self:request("nvim_command", { command })
end

function Session:refresh()
  if self.rpc == nil then return end
  self:request("nvim_ui_detach", {})
  self.grid:resize(self.cols, self.rows)
  self:request("nvim_ui_attach", { self.cols, self.rows,
    Msgpack.map({ ext_linegrid = true, rgb = true }) })
  for _ = 1, 5 do self:update() end
end

function Session:set_lines(lines, cursor_row)
  local encoded = Msgpack.array(lines)
  local ok, err = self:request("nvim_buf_set_lines", { 0, 0, -1, false,
    encoded })
  if err then return nil, err end
  self:request("nvim_win_set_cursor", { 0, Msgpack.array({
    cursor_row or 1, 0 }) })
  self:command("normal! zt")
  self:refresh()
  return true
end

function Session:get_lines()
  local lines = self:request("nvim_buf_get_lines", { 0, 0, -1, false })
  return lines or {}
end

function Session:input(keys)
  return self:request("nvim_input", { keys })
end

function Session:resize(cols, rows)
  self.cols, self.rows = cols, rows
  self.grid:resize(cols, rows)
  return self:request("nvim_ui_try_resize", { cols, rows })
end

function Session:update()
  if self.rpc == nil then return 0 end
  local count = self.rpc:feed(10) or 0
  local notifications = self.rpc.notifications
  self.rpc.notifications = {}
  for _, notification in ipairs(notifications) do
    if notification[1] == "redraw" then
      self.grid:apply_redraw(notification[2])
    end
  end
  return count
end

function Session:close()
  if self.closed then return end
  self.closed = true
  if self.rpc then
    pcall(function() self:command("qa!") end)
    pcall(function() self.rpc:close() end)
    self.rpc = nil
  end
  if self.pid then
    os.execute("kill " .. tostring(self.pid) .. " 2>/dev/null || true")
    self.pid = nil
  end
end

return Session
