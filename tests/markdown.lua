local root = (arg and arg[0] or "tests/markdown.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Markdown = require("notebook.markdown")

assert(Markdown.preview("# Heading") == "Heading")
assert(Markdown.preview("## Nested") == "Nested")
assert(Markdown.preview("- item") == "• item")
assert(Markdown.preview("- [x] done") == "[x] done")
assert(Markdown.preview("- [ ] todo") == "[ ] todo")
assert(Markdown.preview("  * [X] upper") == "  [x] upper")
assert(Markdown.preview("  - nested") == "  • nested")
assert(Markdown.preview("    - deeper") == "    • deeper")
assert(Markdown.preview("| a | b |") == "│ a │ b │")
assert(Markdown.preview("| :--- | ---: |") == "────────────")
assert(Markdown.preview("| a \\| b | c |") == "│ a | b │ c │")
assert(Markdown.preview("_italic_ and __bold__") == "italic and bold")
assert(Markdown.preview("**bold** and *italic*") == "bold and italic")
assert(Markdown.preview("~~retired~~") == "retired")
assert(Markdown.preview("==marked==") == "marked")
assert(Markdown.preview("\\*literal\\*") == "*literal*")
assert(Markdown.preview("\\\\") == "\\")
assert(Markdown.preview("\\# not a heading") == "# not a heading")
assert(Markdown.preview("\\- not a bullet") == "- not a bullet")
assert(Markdown.preview("\\[not a link\\](x)") == "[not a link](x)")
assert(Markdown.preview("| a \\| b | c |") == "│ a | b │ c │")
assert(Markdown.preview("---") == "----------")
assert(Markdown.preview("  * * *  ") == "----------")
assert(Markdown.preview("___") == "----------")
assert(Markdown.preview("`code`") == "code")
assert(Markdown.preview("[label](https://example.com)") == "label")
print("markdown preview tests ok")

local wiki = require("notebook.markdown").preview("See [[Second kernel]]")
if wiki ~= "See Second kernel" then error("wiki preview: " .. wiki, 2) end
print("wiki preview ok")

local source = table.concat({
  "Text[^a] and **second**[^b].",
  "",
  "[^a]: first note",
  "[^b]: second *note*",
}, "\n")
local footnotes = Markdown.footnote_context(source)
assert(Markdown.preview("Text[^a] and", footnotes) == "Text[1] and",
  "first footnote reference")
assert(Markdown.preview("second[^b]", footnotes) == "second[2]",
  "second footnote reference")
assert(Markdown.preview("[^a]: first note", footnotes) == "↳ first note",
  "footnote definition preview")
assert(Markdown.preview("Text[^missing]", footnotes) == "Text[^missing]",
  "undefined footnote stays literal")
assert(Markdown.preview("\\[^a]", footnotes) == "[^a]",
  "escaped footnote stays literal")
local code_context = Markdown.footnote_context(
  "`code[^a]`\n\n```\n[^a]: hidden\n```\n\nVisible[^a]\n\n[^a]: shown")
assert(code_context.numbers.a == 1, "code footnote is not numbered")
assert(Markdown.preview("Visible[^a]", code_context) == "Visible[1]",
  "footnote after fenced code")
assert(Markdown.preview("`code[^a]`", code_context) == "code[^a]",
  "inline code keeps a footnote literal")
print("footnote preview tests ok")
