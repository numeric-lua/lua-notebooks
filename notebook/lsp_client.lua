--
-- Transport-independent LSP client.  The transport sends framed bytes.
--
local json = require("notebook.json")
local Framing = require("notebook.lsp.framing")

local Client = {}
Client.__index = Client

local function hash(text)
  local value = 5381
  for index = 1, #text do
    value = (value * 33 + text:byte(index)) % 4294967296
  end
  return value
end

function Client.new(options)
  options = options or {}
  return setmetatable({
    send = options.send or function() end,
    on_diagnostics = options.on_diagnostics or function() end,
    next_id = 1,
    pending = {},
    documents = {},
    diagnostics = {},
    initialized = false,
  }, Client)
end

function Client:_transmit(message)
  self.send(Framing.encode(message))
end

function Client:request(method, params, callback)
  local id = self.next_id
  self.next_id = id + 1
  self.pending[id] = callback
  self:_transmit({ jsonrpc = "2.0", id = id, method = method, params = params })
  return id
end

function Client:notify(method, params)
  self:_transmit({ jsonrpc = "2.0", method = method, params = params })
end

function Client:initialize(root_uri)
  self:request("initialize", {
    processId = json.null, rootUri = root_uri or json.null,
    capabilities = { general = { positionEncodings = { "utf-8" } } },
  }, function(result)
    self.initialized = true
    self:notify("initialized", json.empty_object)
    if self.on_initialized then self.on_initialized(result) end
  end)
end

function Client:handle(message)
  if message.method == "textDocument/publishDiagnostics" then
    local uri = message.params.uri
    self.diagnostics[uri] = message.params.diagnostics or {}
    self.on_diagnostics(uri, self.diagnostics[uri])
  elseif message.id ~= nil and self.pending[message.id] then
    local callback = self.pending[message.id]
    self.pending[message.id] = nil
    callback(message.result, message.error)
  elseif message.id ~= nil then
    self:_transmit({
      jsonrpc = "2.0", id = message.id,
      error = { code = -32601, message = "unsupported server request" },
    })
  end
end

function Client:sync(notebook, path)
  if not self.initialized then return end
  local present = {}
  for _, cell in ipairs(notebook.cells) do
    if cell.kind == "code" then
      local uri = "luanb:///" .. path .. "?cell=" .. cell.id
      present[uri] = true
      local document = self.documents[uri]
      if document == nil then
        self.documents[uri] = { version = 1, hash = hash(cell.source) }
        self:notify("textDocument/didOpen", {
          textDocument = { uri = uri, languageId = "lua", version = 1,
            text = cell.source },
        })
      elseif document.hash ~= hash(cell.source) then
        document.version = document.version + 1
        document.hash = hash(cell.source)
        self:notify("textDocument/didChange", {
          textDocument = { uri = uri, version = document.version },
          contentChanges = { { text = cell.source } },
        })
      end
    end
  end
  for uri, document in pairs(self.documents) do
    if not present[uri] then
      self:notify("textDocument/didClose", { textDocument = { uri = uri } })
      self.documents[uri] = nil
      self.diagnostics[uri] = nil
    end
  end
end

return Client
