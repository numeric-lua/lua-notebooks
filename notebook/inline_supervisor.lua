--
-- Inline kernel supervisor for web/WASM, where LÖVR threads and processes are
-- unavailable.  Jobs are queued and executed one per poll on the host thread.
--
local Engine = require("kernel.engine")

local InlineSupervisor = {}
InlineSupervisor.__index = InlineSupervisor

function InlineSupervisor.new(options)
  options = options or {}
  return setmetatable({
    kernels = {},
    pending = {},
    queue = {},
    next_id = 1,
    on_result = options.on_result,
    on_error = options.on_error,
  }, InlineSupervisor)
end

function InlineSupervisor:open(id)
  if self.kernels[id] then return self.kernels[id] end
  local kernel = { id = id, engine = Engine.new(), status = "running" }
  self.kernels[id] = kernel
  return kernel
end

function InlineSupervisor:_request(id, job)
  local kernel = self:open(id)
  if kernel.status ~= "running" then
    return nil, "kernel is not running"
  end
  local request = self.next_id
  self.next_id = request + 1
  job.id = request
  self.pending[request] = { kernel = id, job = job }
  self.queue[#self.queue + 1] = { id = id, job = job }
  return request
end

function InlineSupervisor:run(id, code, cell)
  return self:_request(id, { cell = cell, code = code })
end

function InlineSupervisor:widget(id, cell, widget, event)
  return self:_request(id, { cell = cell, widget = widget, event = event })
end

function InlineSupervisor:poll()
  local entry = table.remove(self.queue, 1)
  if entry == nil then return end
  local kernel = self.kernels[entry.id]
  local request = self.pending[entry.job.id]
  if kernel == nil or kernel.status ~= "running" then
    self.pending[entry.job.id] = nil
    if self.on_error then self.on_error(entry.id, "kernel is not running") end
    return
  end
  local ok, message = pcall(kernel.engine.run, kernel.engine, entry.job)
  self.pending[entry.job.id] = nil
  if not ok then
    if self.on_error then self.on_error(entry.id, tostring(message)) end
    return
  end
  if self.on_result then self.on_result(entry.id, request, message) end
end

function InlineSupervisor:threaderror() end

function InlineSupervisor:stop(id)
  self.kernels[id] = nil
end

function InlineSupervisor:restart(id)
  self:stop(id)
  local kernel = self:open(id)
  kernel.engine:reset()
  return kernel
end

function InlineSupervisor:close()
  self.kernels = {}
  self.pending = {}
  self.queue = {}
end

return InlineSupervisor
