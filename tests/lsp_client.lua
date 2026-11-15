local root = (arg and arg[0] or "tests/lsp_client.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local json = require("notebook.json")
local Framing = require("notebook.lsp.framing")
local Server = require("notebook.lsp.server")
local Client = require("notebook.lsp_client")
local Notebook = require("notebook.model")

local client
local server = Server.new({
  publish = function(message) client:handle(message) end,
})
client = Client.new({
  send = function(bytes)
    local messages = Framing.new_decoder():feed(bytes)
    for _, message in ipairs(messages) do
      local response = server:handle(message)
      if response then client:handle(response) end
    end
  end,
})
local initialized, diagnostics
client.on_initialized = function() initialized = true end
client.on_diagnostics = function(uri, items) diagnostics = items end
client:initialize("luanb:///")
assert(initialized, "initialize did not complete")
local notebook = Notebook.new({ name = "test.luanb", cells = {
  { kind = "code", source = "if then" },
  { kind = "markdown", source = "# heading" },
} })
client:sync(notebook, "notebooks/test.luanb")
assert(diagnostics and diagnostics[1], "missing diagnostics")
assert(diagnostics[1].severity == 1)
local completion
client:request("textDocument/completion", {
  textDocument = { uri = "luanb:///notebooks/test.luanb?cell=" .. notebook.cells[1].id },
  position = { line = 0, character = 0 },
}, function(result) completion = result end)
assert(completion and #completion.items > 3, "completion failed")
print("lsp client tests ok")
