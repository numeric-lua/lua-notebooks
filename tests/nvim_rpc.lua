local root = (arg and arg[0] or "tests/nvim_rpc.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Rpc = require("notebook.nvim.rpc")
local Msgpack = require("notebook.nvim.msgpack")

local port = 22000 + (os.time() % 20000)
local handle = assert(io.popen("nvim --headless --clean " ..
  "--cmd 'set noswapfile' --listen 127.0.0.1:" ..
  port .. " >/tmp/nvim-spike.log 2>&1 & echo $!"))
local pid = handle:read("*l")
handle:close()

local client
for _ = 1, 100 do
  client = Rpc.connect("127.0.0.1", port)
  if client then break end
  os.execute("sleep 0.05")
end
assert(client, "could not connect to nvim")
local info, err = client:wait(client:request("nvim_get_api_info"), 5)
assert(info, tostring(err))
assert(info[1], "api info missing channel id")
io.write("nvim channel ", tostring(info[1]), " version ",
  tostring(info[2].version.major), ".", tostring(info[2].version.minor), "\n")

local set_ok, set_err = client:wait(client:request("nvim_buf_set_lines",
  { 0, 0, -1, false, Msgpack.array({ "hello from nvim", "second line" }) }), 5)
assert(set_ok == nil and set_err == nil, tostring(set_err))
local attached, attach_err = client:wait(client:request("nvim_ui_attach",
  { 40, 10, Msgpack.map({ ext_linegrid = true, rgb = true }) }), 5)
assert(attached ~= nil or attach_err == nil, tostring(attach_err))
client.notifications = {}

client:wait(client:request("nvim_win_set_cursor", { 0, Msgpack.array({ 1, 0 }) }), 5)
client:wait(client:request("nvim_command", { "normal! zt" }), 5)
client:wait(client:request("nvim_ui_try_resize", { 41, 10 }), 5)
client:wait(client:request("nvim_command", { "redraw" }), 5)
for _ = 1, 10 do client:feed(20) end

local deadline = os.clock() + 5
local grid_lines, cursor, found
while os.clock() < deadline and not found do
  client:feed(50)
  for _, notification in ipairs(client.notifications) do
    local method, params = notification[1], notification[2]
    if method == "redraw" then
      for _, event in ipairs(params) do
        if event[1] == "grid_line" then
          grid_lines = grid_lines or {}
          for index = 2, #event do
            local line = event[index]
            local row = line[2]
            grid_lines[row] = grid_lines[row] or {}
            local cells = line[4] or {}
            for _, cell in ipairs(cells) do
              local count = cell[3] or 1
              for _ = 1, count do
                grid_lines[row][#grid_lines[row] + 1] = cell[1]
              end
            end
          end
        elseif event[1] == "grid_cursor_goto" then
          cursor = { event[3], event[4] }
        end
      end
    end
  end
  client.notifications = {}
  if grid_lines then
    for row = 0, 9 do
      if table.concat(grid_lines[row] or {}, ""):find("hello", 1, true) then
        found = true
      end
    end
  end
end
assert(grid_lines, "no grid_line events")

local text = {}
for row = 0, 9 do
  local line = table.concat(grid_lines[row] or {}, "")
  if line:find("hello", 1, true) then text[#text + 1] = line end
end
assert(#text > 0, "expected hello in grid")
print("nvim rpc ok: " .. table.concat(text, " | "):sub(1, 40))
client:request("nvim_command", { "qa!" })
client:close()
pcall(function() os.execute("kill " .. tostring(pid) .. " 2>/dev/null") end)
