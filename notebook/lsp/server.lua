--
-- Minimal LSP server core.  Transport-independent; tests drive handle().
--
local json = require("notebook.json")
local Editor = require("notebook.editor_text")

local Server = {}
Server.__index = Server

local function response(id, result)
  return { jsonrpc = "2.0", id = id, result = result or json.null }
end

local function error_response(id, code, message)
  return { jsonrpc = "2.0", id = id, error = { code = code, message = message } }
end

local function position_after(text, line, character)
  local current_line, offset = 0, 1
  while offset <= #text and current_line < line do
    local newline = text:find("\n", offset, true)
    if newline == nil then return #text + 1 end
    offset = newline + 1
    current_line = current_line + 1
  end
  return math.min(#text + 1, offset + character)
end

function Server.new(options)
  options = options or {}
  return setmetatable({
    initialized = false,
    ready = false,
    shutdown = false,
    documents = {},
    publish = options.publish or function() end,
    log = options.log or function() end,
  }, Server)
end

function Server:diagnostics_notification(uri, text)
  local diagnostic = Editor.diagnostics(text)
  local items = {}
  if diagnostic then
    local line = math.max(0, (diagnostic.line or 1) - 1)
    items[1] = {
      range = {
        start = { line = line, character = 0 },
        ["end"] = { line = line + 1, character = 0 },
      },
      severity = 1,
      source = "lua-notebooks",
      code = "syntax",
      message = diagnostic.message,
    }
  end
  self.publish({
    jsonrpc = "2.0", method = "textDocument/publishDiagnostics",
    params = { uri = uri, diagnostics = items },
  })
end

function Server:handle(message)
  if message == nil or message.jsonrpc ~= "2.0" or type(message.method) ~= "string" then
    return error_response(message and message.id or json.null, -32600,
      "invalid request")
  end
  local id = message.id
  local params = message.params or {}
  if message.method == "initialize" then
    if self.initialized then return error_response(id, -32600, "already initialized") end
    self.initialized = true
    return response(id, {
      capabilities = {
        positionEncoding = "utf-16",
        textDocumentSync = { openClose = true, change = 1 },
        completionProvider = { triggerCharacters = { ".", ":" } },
        hoverProvider = true,
        definitionProvider = true,
        renameProvider = { prepareProvider = false },
      },
      serverInfo = { name = "lua-notebooks-lsp", version = "0.1.0" },
    })
  elseif message.method == "initialized" then
    self.ready = true
    return nil
  elseif message.method == "shutdown" then
    self.shutdown = true
    return response(id, json.null)
  elseif message.method == "exit" then
    return nil
  end
  if not self.initialized then
    return id ~= nil and error_response(id, -32002, "server not initialized") or nil
  end
  if self.shutdown then
    return id ~= nil and error_response(id, -32600, "server is shutting down") or nil
  end
  if message.method == "textDocument/didOpen" then
    local document = params.textDocument or {}
    self.documents[document.uri] = { text = document.text or "", version = document.version or 1 }
    self:diagnostics_notification(document.uri, document.text or "")
    return nil
  elseif message.method == "textDocument/didChange" then
    local identifier = params.textDocument or {}
    local document = self.documents[identifier.uri]
    if document == nil then return nil end
    local changes = params.contentChanges or {}
    if changes[#changes] then document.text = changes[#changes].text or document.text end
    document.version = identifier.version or document.version + 1
    self:diagnostics_notification(identifier.uri, document.text)
    return nil
  elseif message.method == "textDocument/didClose" then
    local uri = params.textDocument and params.textDocument.uri
    if uri then self.documents[uri] = nil; self.publish({jsonrpc="2.0", method="textDocument/publishDiagnostics", params={uri=uri, diagnostics={}}}) end
    return nil
  elseif message.method == "textDocument/completion" then
    local document = self.documents[params.textDocument and params.textDocument.uri]
    if document == nil then return response(id, { isIncomplete = false, items = {} }) end
    local items = {}
    for _, word in ipairs(Editor.complete(document.text)) do
      items[#items + 1] = { label = word, kind = 1 }
    end
    return response(id, { isIncomplete = false, items = items })
  elseif message.method == "textDocument/hover" then
    local document = self.documents[params.textDocument and params.textDocument.uri]
    local word = document and Editor.current_word(document.text) or ""
    local info = Editor.hover(word)
    if not info then return response(id, json.null) end
    return response(id, { contents = { kind = "plaintext", value = info } })
  elseif message.method == "textDocument/definition" then
    return response(id, json.null)
  elseif message.method == "textDocument/rename" then
    return error_response(id, -32601, "rename is not implemented by the protocol server yet")
  elseif message.method == "shutdown" then
    return response(id, json.null)
  elseif message.method == "$/cancelRequest" then
    return nil
  end
  if id ~= nil then return error_response(id, -32601, "method not found") end
  return nil
end

return Server
