local root = (arg and arg[0] or "tests/nvim_escape.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
_G.lovr = { system = { isKeyDown = function() return false end,
  getMousePosition = function() return 0, 0 end } }
local UI = require("ui.notebook")

local hidden = false
local forwarded = nil
local app = {
  show_nvim = true,
  nvim_session = { grid = { mode = "normal" } },
  nvim_view = { keypressed = function(_, key) forwarded = key end },
  hide_nvim = function(self) hidden = true; self.show_nvim = false end,
}
local ui = UI.new(app)
ui:keypressed("escape")
assert(hidden, "Esc in normal mode should return to notebook")
assert(forwarded == nil)

hidden, forwarded = false, nil
app.show_nvim = true
app.nvim_session.grid.mode = "insert"
ui:keypressed("escape")
assert(not hidden, "Esc in insert mode should stay in Neovim")
assert(forwarded == "escape")
print("nvim escape ok")

local text_calls = {}
app.show_nvim = true
app.nvim_session.grid.mode = "normal"
app.nvim_view.textinput = function(_, value) text_calls[#text_calls + 1] = value end
_G.lovr.timer = { getTime = function() return 100 end }
ui.suppress_textinput_until = 100.1
ui:textinput("i")
assert(#text_calls == 0, "opening i must be swallowed")
ui:textinput("i")
assert(text_calls[1] == "i", "next i must enter insert")
print("nvim opening key ok")
