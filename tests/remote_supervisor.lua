local root = (arg and arg[0] or "tests/remote_supervisor.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local json = require("notebook.json")
local Engine = require("kernel.engine")
local Remote = require("notebook.remote_supervisor")

local passed, failed = 0, 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1; io.write(".")
  else
    failed = failed + 1
    io.write("F\n  " .. name .. ": " .. tostring(err) .. "\n")
  end
end
local function eq(a, b)
  if a ~= b then error(tostring(a) .. " ~= " .. tostring(b), 2) end
end

local function fake_transport()
  local sent, incoming = {}, {}
  return {
    sent = sent,
    incoming = incoming,
    send = function(text) sent[#sent + 1] = text end,
    receive = function() return table.remove(incoming, 1) end,
  }
end

local function service(transport, engines)
  while #transport.sent > 0 do
    local message = json.decode(table.remove(transport.sent, 1))
    local engine = engines[message.notebook]
    if message.type == "open" then
      engines[message.notebook] = Engine.new()
      transport.incoming[#transport.incoming + 1] = json.encode({
        type = "open_ok", notebook = message.notebook,
      })
    elseif message.type == "run" then
      local result = engine:run(message)
      result.type = "result"
      transport.incoming[#transport.incoming + 1] = json.encode(result)
    elseif message.type == "widget" then
      local result = engine:run(message)
      result.type = "result"
      transport.incoming[#transport.incoming + 1] = json.encode(result)
    end
  end
end

test("opens and executes a remote cell", function()
  local transport = fake_transport()
  local engines = {}
  local seen
  local remote = Remote.new({ transport = transport,
    on_result = function(id, job, message) seen = { id, job, message } end,
  })
  local request = remote:run("nb", "print('remote'); return 6 * 7", "1:1")
  eq(type(request), "number")
  service(transport, engines)
  remote:poll()
  eq(seen[1], "nb")
  eq(seen[3].ok, true)
  eq(seen[3].output, "remote")
  eq(seen[3].value, "42")
  remote:close()
end)

test("isolates remote notebooks", function()
  local transport = fake_transport()
  local engines = {}
  local results = {}
  local remote = Remote.new({ transport = transport,
    on_result = function(_, _, message) results[#results + 1] = message end,
  })
  remote:run("a", "x = 8", "1:1")
  remote:run("b", "return x", "1:1")
  service(transport, engines)
  remote:poll()
  eq(results[1].ok, true)
  eq(results[2].value, nil)
  remote:close()
end)

test("reports malformed transport messages", function()
  local transport = fake_transport()
  local error_message
  local remote = Remote.new({ transport = transport,
    on_error = function(_, message) error_message = message end,
  })
  transport.incoming[1] = "{not json"
  remote:poll()
  eq(error_message:find("invalid remote JSON") ~= nil, true)
  remote:close()
end)

test("stops a notebook and drops pending work", function()
  local transport = fake_transport()
  local remote = Remote.new({ transport = transport })
  remote:run("a", "return 1", "1:1")
  remote:run("b", "return 2", "1:1")
  remote:stop("a")
  eq(remote.kernels.a, nil)
  eq(remote.kernels.b ~= nil, true)
  for _, pending in pairs(remote.pending) do
    eq(pending.kernel ~= "a", true)
  end
  local closed = false
  for _, text in ipairs(transport.sent) do
    local message = json.decode(text)
    if message.type == "close" and message.notebook == "a" then closed = true end
  end
  eq(closed, true)
  remote:close()
end)

io.write(string.format("\n%d remote tests, %d passed, %d failed\n",
  passed + failed, passed, failed))
if failed > 0 then os.exit(1) end
