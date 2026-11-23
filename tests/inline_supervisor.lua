local root = (arg and arg[0] or "tests/inline_supervisor.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local Inline = require("notebook.inline_supervisor")
local passed, failed = 0, 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1; io.write(".")
  else failed = failed + 1
    io.write("F\n  " .. name .. ": " .. tostring(err) .. "\n")
  end
end
local function eq(a, b)
  if a ~= b then error(tostring(a) .. " ~= " .. tostring(b), 2) end
end

test("queues and polls one job", function()
  local seen
  local supervisor = Inline.new({
    on_result = function(id, request, message) seen = { id, request, message } end,
  })
  local request = supervisor:run("nb", "return 2 + 2", "1:1")
  eq(type(request), "number")
  eq(seen, nil)
  supervisor:poll()
  eq(seen[1], "nb")
  eq(seen[2].job.code, "return 2 + 2")
  eq(seen[3].value, "4")
  supervisor:close()
end)

test("reports cell errors in results", function()
  local result
  local supervisor = Inline.new({
    on_result = function(_, _, message) result = message end,
  })
  supervisor:run("nb", "error('bad')", "1:1")
  supervisor:poll()
  eq(result.ok, false)
  eq(result.value:find("bad") ~= nil, true)
  eq(supervisor.kernels.nb.status, "running")
end)

test("restarts a kernel", function()
  local supervisor = Inline.new()
  supervisor:run("nb", "x = 7", "1:1")
  supervisor:poll()
  supervisor:restart("nb")
  supervisor:run("nb", "return x", "1:2")
  local result
  supervisor.on_result = function(_, _, msg) result = msg end
  supervisor:poll()
  eq(result.value, nil)
  supervisor:close()
end)

test("stops a kernel and drops its pending work", function()
  local supervisor = Inline.new()
  supervisor:open("a")
  supervisor:open("b")
  local request = supervisor:run("a", "return 1", "1:1")
  supervisor:stop("a")
  eq(supervisor.kernels.a, nil)
  eq(supervisor.pending[request], nil)
  eq(supervisor.kernels.b ~= nil, true)
  eq(#supervisor.queue, 0)
  supervisor:close()
end)

io.write(string.format("\n%d inline tests, %d passed, %d failed\n",
  passed + failed, passed, failed))
if failed > 0 then os.exit(1) end
