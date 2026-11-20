local root = (arg and arg[0] or "tests/nvim_input.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

_G.lovr = { system = { isKeyDown = function() return false end } }
local NvimView = require("ui.nvim")
local sent = {}
local session = {
  cols = 20, rows = 5, grid = { cols = 20, rows = 5 },
  input = function(_, keys) sent[#sent + 1] = keys end,
  request = function() return nil end,
}
local font = {
  getWidth = function() return 1 end,
  getHeight = function() return 1 end,
}
local view = NvimView.new(session, font, { size = 10 })
assert(view:keypressed("a") == false, "printable key must not be sent twice")
assert(#sent == 0)
view:textinput("a")
assert(sent[1] == "a")
view:textinput("\r\n\t")
assert(#sent == 1)
view:keypressed("escape")
assert(sent[2] == "<Esc>")
print("nvim input ok")
