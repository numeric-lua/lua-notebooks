--
-- Minimal LSP server core.  Transport-independent; tests drive handle().
--
local json = require("notebook.json")
local Editor = require("notebook.editor_text")
local Scope = require("notebook.lsp.scope")

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

local function location(uri, text, start_byte)
  local before = text:sub(1, start_byte - 1)
  local line = 0
  local last_newline = 0
  for newline in before:gmatch("()\n") do
    line = line + 1
    last_newline = newline
  end
  return { uri = uri, range = {
    start = { line = line, character = start_byte - last_newline - 1 },
    ["end"] = { line = line, character = start_byte - last_newline },
  } }
end

function Server:word_at(uri, position)
  local text = self.documents[uri] and self.documents[uri].text or ""
  return Editor.word_at(text, position.line, position.character)
end

function Server:definitions(word)
  local found = {}
  for uri, document in pairs(self.documents) do
    local escaped = word:gsub("([^%w])", "%%%1")
    for start_at in document.text:gmatch("()%f[%w_]" .. escaped .. "%f[^%w_]") do
      local prefix = document.text:sub(1, start_at - 1)
      local line_start = prefix:match(".*()\n") or 0
      local current_line = document.text:sub(line_start + 1,
        start_at - 1)
      if current_line:match("local%s+$") or current_line:match("function%s+$") or
         current_line:match("^%s*$") then
        found[#found + 1] = location(uri, document.text, start_at)
      end
    end
  end
  return found
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
        referencesProvider = true,
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
    local seen = {}
    for _, word in ipairs(Editor.complete(document.text)) do
      if not seen[word] then seen[word] = true; items[#items + 1] = { label = word, kind = 1 } end
    end
    for _, other in pairs(self.documents) do
      for word in other.text:gmatch("[%a_][%w_]*") do
        if not seen[word] then seen[word] = true; items[#items + 1] = { label = word, kind = 6 } end
      end
    end
    return response(id, { isIncomplete = false, items = items })
  elseif message.method == "textDocument/hover" then
    local uri = params.textDocument and params.textDocument.uri
    local document = self.documents[uri]
    local word = document and Editor.current_word(document.text) or ""
    local info
    if document and word ~= "" then
      local absolute = Editor.offset_at(document.text, params.position.line,
        params.position.character)
      local _, _, binding = Scope.resolved_ranges(document.text, absolute, word)
      if binding then
        local line = select(2, document.text:sub(1,
          binding.token.start - 1):gsub("\n", "")) + 1
        info = "local `" .. word .. "` (line " .. line .. ")"
      end
    end
    info = info or Editor.hover(word)
    if not info then return response(id, json.null) end
    return response(id, { contents = { kind = "plaintext", value = info } })
  elseif message.method == "textDocument/definition" then
    local uri = params.textDocument and params.textDocument.uri
    local word = self:word_at(uri, params.position or {})
    local document = self.documents[uri]
    local locations = {}
    if word and document then
      local absolute = Editor.offset_at(document.text, params.position.line,
        params.position.character)
      local _, _, binding = Scope.resolved_ranges(document.text, absolute,
        word.word)
      if binding then
        locations[1] = location(uri, document.text, binding.token.start)
      else
        locations = self:definitions(word.word)
      end
    end
    if #locations == 0 then return response(id, json.null) end
    return response(id, locations)
  elseif message.method == "textDocument/references" then
    local uri = params.textDocument and params.textDocument.uri
    local word = self:word_at(uri, params.position or {})
    local document = self.documents[uri]
    local locations = {}
    if word and document then
      local absolute = Editor.offset_at(document.text, params.position.line,
        params.position.character)
      local ranges, is_local = Scope.resolved_ranges(document.text, absolute,
        word.word)
      if is_local then
        for _, range in ipairs(ranges or {}) do
          locations[#locations + 1] = location(uri, document.text,
            range.start)
        end
      else
        for other_uri, other in pairs(self.documents) do
          for _, occurrence in ipairs(Scope.occurrences(other.text,
            word.word)) do
            local _, local_binding = Scope.resolved_ranges(other.text,
              occurrence.start, word.word)
            if not local_binding then
              locations[#locations + 1] = location(other_uri, other.text,
                occurrence.start)
            end
          end
        end
      end
    end
    return response(id, locations)
  elseif message.method == "textDocument/rename" then
    local uri = params.textDocument and params.textDocument.uri
    local document = self.documents[uri]
    local word = self:word_at(uri, params.position or {})
    local new_name = params.newName
    if not document or not word or type(new_name) ~= "string" or
       not new_name:match("^[%a_][%w_]*$") then
      return error_response(id, -32602, "invalid rename")
    end
    local function add_edits(changes, target_uri, source, ranges)
      local edits = changes[target_uri] or {}
      for _, range in ipairs(ranges) do
        local start_location = location(target_uri, source, range.start)
        local end_location = location(target_uri, source, range.finish)
        edits[#edits + 1] = {
          range = { start = start_location.range.start,
            ["end"] = end_location.range["end"] },
          newText = new_name,
        }
      end
      changes[target_uri] = edits
    end
    local changes = {}
    local absolute = Editor.offset_at(document.text,
      params.position.line, params.position.character)
    local target_ranges, is_local = Scope.resolved_ranges(document.text,
      absolute, word.word)
    if is_local then
      add_edits(changes, uri, document.text, target_ranges or {})
    else
      for other_uri, other in pairs(self.documents) do
        for _, occurrence in ipairs(Scope.occurrences(other.text, word.word)) do
          local _, local_binding = Scope.resolved_ranges(other.text,
            occurrence.start, word.word)
          if not local_binding then
            add_edits(changes, other_uri, other.text, { occurrence })
          end
        end
      end
    end
    return response(id, { changes = changes })
  elseif message.method == "shutdown" then
    return response(id, json.null)
  elseif message.method == "$/cancelRequest" then
    return nil
  end
  if id ~= nil then return error_response(id, -32601, "method not found") end
  return nil
end

return Server
