--
-- Minimal markdown preview transforms for notebook cells.  This is deliberately
-- not a CommonMark parser; it handles the constructs the notebook itself uses.
--
local Markdown = {}

function Markdown.preview(line)
  line = line:gsub("^%s*#+%s*", "")
  line = line:gsub("^%s*[-*+]%s+", "• ")
  line = line:gsub("%*%*(.-)%*%*", "%1")
  line = line:gsub("__(.-)__", "%1")
  line = line:gsub("%*(.-)%*", "%1")
  line = line:gsub("`([^`]*)`", "%1")
  line = line:gsub("%[([^%]]+)%]%b()", "%1")
  line = line:gsub("%[%[([^%]]+)%]%]", "%1")
  return line
end

return Markdown
