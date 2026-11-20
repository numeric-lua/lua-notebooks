local root = (arg and arg[0] or "tests/markdown.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Markdown = require("notebook.markdown")

assert(Markdown.preview("# Heading") == "Heading")
assert(Markdown.preview("## Nested") == "Nested")
assert(Markdown.preview("- item") == "• item")
assert(Markdown.preview("**bold** and *italic*") == "bold and italic")
assert(Markdown.preview("`code`") == "code")
assert(Markdown.preview("[label](https://example.com)") == "label")
print("markdown preview tests ok")

local wiki = require("notebook.markdown").preview("See [[Second kernel]]")
if wiki ~= "See Second kernel" then error("wiki preview: " .. wiki, 2) end
print("wiki preview ok")
