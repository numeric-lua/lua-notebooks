--
-- Minimal in-process Lua language service: static diagnostics and completion.
--
local LSP = {}

local KEYWORDS = {
  "and", "break", "do", "else", "elseif", "end", "false", "for", "function",
  "goto", "if", "in", "local", "nil", "not", "or", "repeat", "return",
  "then", "true", "until", "while",
}
local BUILTINS = {
  "assert", "error", "ipairs", "loadstring", "math", "next", "pairs", "pcall",
  "print", "select", "setmetatable", "string", "table", "tonumber", "tostring",
  "type", "xpcall", "widgets", "lovr",
}

function LSP.diagnostics(source)
  local chunk, err = loadstring(source or "", "@cell")
  if chunk then return nil end
  local line = tonumber(tostring(err):match(":(%d+):")) or 1
  return { line = line, message = tostring(err) }
end

function LSP.current_word(source)
  local tail = (source or ""):match("[%a_][%w_]*$")
  return tail or ""
end

function LSP.complete(source)
  local seen, items = {}, {}
  local function add(word)
    if word == "" or seen[word] then return end
    seen[word] = true
    items[#items + 1] = word
  end
  for _, word in ipairs(KEYWORDS) do add(word) end
  for _, word in ipairs(BUILTINS) do add(word) end
  for word in (source or ""):gmatch("[%a_][%w_]*") do add(word) end
  table.sort(items)
  return items
end

return LSP
