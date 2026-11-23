--
-- Minimal markdown preview transforms for notebook cells.  This is deliberately
-- not a CommonMark parser; it handles the constructs the notebook itself uses.
--
local Markdown = {}

function Markdown.preview(line)
  if line:match("^%s*([%*%-_])%s*%1%s*%1[%s%*%-_]*$") then
    return "----------"
  end
  line = line:gsub("^%s*#+%s*", "")
  local checked, task = line:match("^%s*[-*+]%s+%[([ xX])%]%s+(.*)$")
  if checked ~= nil then
    line = (checked:lower() == "x" and "[x] " or "[ ] ") .. task
  else
    line = line:gsub("^%s*[-*+]%s+", "• ")
  end
  line = line:gsub("%*%*(.-)%*%*", "%1")
  line = line:gsub("__(.-)__", "%1")
  line = line:gsub("~~(.-)~~", "%1")
  line = line:gsub("%*(.-)%*", "%1")
  line = line:gsub("`([^`]*)`", "%1")
  line = line:gsub("%[([^%]]+)%]%b()", "%1")
  line = line:gsub("%[%[([^%]]+)%]%]", "%1")
  return line
end

return Markdown
