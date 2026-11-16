--
-- Transport-agnostic remote kernel supervisor.  A front-end provides a
-- transport with send(text), receive() -> text|nil, and optionally close();
-- the supervisor speaks the same job/result protocol as the local kernels.
--
local json = require("notebook.json")

local RemoteSupervisor = {}
RemoteSupervisor.__index = RemoteSupervisor

local function encode(message)
  local ok, text = pcall(json.encode, message)
  if not ok then return nil, text end
  return text
end

function RemoteSupervisor.new(options)
  options = options or {}
  if type(options.transport) ~= "table" then
    error("remote supervisor requires a transport", 2)
  end
  local transport = options.transport
  if type(transport.send) ~= "function" or
      type(transport.receive) ~= "function" then
    error("remote transport needs send() and receive()", 2)
  end
  return setmetatable({
    transport = transport,
    kernels = {},
    pending = {},
    next_id = 1,
    on_result = options.on_result,
    on_error = options.on_error,
    capabilities = options.capabilities or {},
    connected = false,
  }, RemoteSupervisor)
end

function RemoteSupervisor:_transmit(message)
  local text, err = encode(message)
  if text == nil then return nil, err end
  local ok, result = pcall(self.transport.send, text)
  if not ok then return nil, result end
  if result == false then return nil, "remote transport rejected message" end
  return true
end

function RemoteSupervisor:open(id)
  if self.kernels[id] then return self.kernels[id] end
  local kernel = { id = id, status = "opening" }
  local ok, err = self:_transmit({ type = "open", notebook = id })
  if not ok then return nil, err end
  self.kernels[id] = kernel
  return kernel
end

function RemoteSupervisor:_request(id, job)
  local kernel = self:open(id)
  if kernel == nil then return nil, "kernel could not be opened" end
  if kernel.status ~= "running" and kernel.status ~= "opening" then
    return nil, "kernel is not running"
  end
  local request = self.next_id
  self.next_id = request + 1
  job.id = request
  job.notebook = id
  self.pending[request] = { kernel = id, job = job }
  local ok, err = self:_transmit(job)
  if not ok then
    self.pending[request] = nil
    return nil, err
  end
  return request
end

function RemoteSupervisor:run(id, code, cell)
  return self:_request(id, { type = "run", cell = cell, code = code })
end

function RemoteSupervisor:widget(id, cell, widget, event)
  return self:_request(id, {
    type = "widget", cell = cell, widget = widget, event = event,
  })
end

function RemoteSupervisor:_dispatch(message)
  if message.type == "hello" then
    self.connected = true
    self.capabilities = message.capabilities or {}
    return
  end
  if message.type == "open_ok" then
    local kernel = self.kernels[message.notebook]
    if kernel then kernel.status = "running" end
    return
  end
  if message.type == "closed" then
    if message.notebook and self.kernels[message.notebook] then
      self.kernels[message.notebook].status = "closed"
    end
    return
  end
  if message.type ~= "result" and message.type ~= "error" then
    if self.on_error then
      self.on_error(nil, "unexpected remote message: " .. tostring(message.type))
    end
    return
  end
  local pending = self.pending[message.id]
  self.pending[message.id] = nil
  if pending == nil then
    if self.on_error then
      self.on_error(nil, "remote result for unknown request " ..
        tostring(message.id))
    end
    return
  end
  if message.type == "error" then
    if self.on_error then
      self.on_error(pending.kernel, message.message or "remote kernel error")
    end
    return
  end
  if self.on_result then
    self.on_result(pending.kernel, pending.job, message)
  end
end

function RemoteSupervisor:poll()
  while true do
    local ok, text, transport_error = pcall(self.transport.receive)
    if not ok then
      if self.on_error then self.on_error(nil, text) end
      break
    end
    if text == nil then
      if transport_error ~= nil and self.on_error then
        self.on_error(nil, transport_error)
      end
      break
    end
    local decoded, message = pcall(json.decode, text)
    if not decoded then
      if self.on_error then
        self.on_error(nil, "invalid remote JSON: " .. tostring(message))
      end
    else
      self:_dispatch(message)
    end
  end
end

function RemoteSupervisor:threaderror() end

function RemoteSupervisor:stop(id)
  if self.kernels[id] == nil then return end
  self:_transmit({ type = "close", notebook = id })
  self.kernels[id] = nil
  for request, pending in pairs(self.pending) do
    if pending.kernel == id then self.pending[request] = nil end
  end
end

function RemoteSupervisor:restart(id)
  self:_transmit({ type = "restart", notebook = id })
  local kernel = self.kernels[id]
  if kernel then kernel.status = "opening" end
  return kernel
end

function RemoteSupervisor:close()
  for id in pairs(self.kernels) do
    self:_transmit({ type = "close", notebook = id })
  end
  self.kernels = {}
  self.pending = {}
  if type(self.transport.close) == "function" then
    pcall(self.transport.close)
  end
end

return RemoteSupervisor
