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

math.randomseed(os.time() + math.floor(os.clock() * 100000))

function Session.available(exe)
  local status = os.execute("command -v " .. shell_quote(exe or "nvim") ..
    " >/dev/null 2>&1")
  return status == 0 or status == true
end

function Session.new(options)
  options = options or {}
  if options.exe == nil and not Session.available("nvim") then
    error("nvim is not installed or not on PATH")
  end
  local self = setmetatable({
    cols = options.cols or 80, rows = options.rows or 24,
    exe = options.exe or "nvim", cwd = options.cwd,
    grid = Grid.new(options.cols or 80, options.rows or 24),
    rpc = nil, pid = nil, port = nil, closed = false,
  }, Session)
  local port, rpc, pid
  for attempt = 1, 12 do
    port = options.port or free_port()
    local command = { shell_quote(self.exe), "--headless" }
    if options.clean ~= false then command[#command + 1] = "--clean" end
    for _, cmd in ipairs({
      "syntax on", "set termguicolors", "set noswapfile",
      "set background=" .. (options.background or "dark"),
      "colorscheme " .. (options.background == "light" and "morning" or
        "habamax"),
    }) do
      command[#command + 1] = "--cmd"
      command[#command + 1] = shell_quote(cmd)
    end
    command[#command + 1] = "--listen"
    command[#command + 1] = "127.0.0.1:" .. port
    if options.file then command[#command + 1] = shell_quote(options.file) end
    local handle = assert(io.popen(table.concat(command, " ") ..
      " >/tmp/lua-notebooks-nvim.log 2>&1 & echo $!"))
    pid = tonumber(handle:read("*l") or "")
    handle:close()
    for _ = 1, 40 do
      rpc = Rpc.connect("127.0.0.1", port)
      if rpc then break end
      os.execute("sleep 0.05")
    end
    if rpc then break end
    if pid then os.execute("kill " .. tostring(pid) .. " 2>/dev/null || true") end
    os.execute("sleep 0.1")
  end
  if rpc == nil then
    error("could not connect to nvim on port " .. tostring(port))
  end
  self.pid, self.port, self.rpc = pid, port, rpc
  self:request("nvim_ui_attach", { self.cols, self.rows,
    Msgpack.map({ ext_linegrid = true, ext_popupmenu = true,
      rgb = true }) })
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
    Msgpack.map({ ext_linegrid = true, ext_popupmenu = true,
      rgb = true }) })
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
  if cols == self.cols and rows == self.rows then return true end
  self.cols, self.rows = cols, rows
  -- Wait for the grid_resize event; clearing locally hides the current screen
  -- for a frame and used to leave the grid blank when nvim was busy.
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
