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

local HOVERS = {
  print = "print(...) -> writes values to the cell output",
  pairs = "pairs(t) -> iterate key/value pairs",
  ipairs = "ipairs(t) -> iterate array indices and values",
  table = "table library: insert, remove, sort, concat, ...",
  string = "string library: format, find, sub, gsub, ...",
  math = "math library: sin, cos, floor, pi, ...",
  widgets = "kernel widget API: slider, button, checkbox, select, text, ...",
  lovr = "host API; only graphics/timer are available in user extensions",
}

function LSP.hover(word)
  if word == nil or word == "" then return nil end
  return HOVERS[word]
end

function LSP.find_definition(notebook, word)
  if word == nil or word == "" then return nil end
  for index, cell in ipairs(notebook.cells or {}) do
    if cell.kind == "code" then
      local line = 1
      for source_line in (cell.source .. "\n"):gmatch("(.-)\n") do
        if source_line:match("local%s+" .. word .. "%f[%W]") or
           source_line:match("function%s+" .. word .. "%f[%W]") or
           source_line:match("^%s*" .. word .. "%s*=") then
          return { cell = index, line = line }
        end
        line = line + 1
      end
    end
  end
  return nil
end

local function pattern_escape(text)
  return (text:gsub("([^%w])", "%%%1"))
end

function LSP.rename(notebook, old_word, new_word)
  if old_word == nil or old_word == "" or new_word == nil or new_word == "" then
    return 0
  end
  local old = pattern_escape(old_word)
  local count = 0
  for _, cell in ipairs(notebook.cells or {}) do
    if cell.kind == "code" then
      local source, replacements = cell.source:gsub(
        "%f[%w_]" .. old .. "%f[^%w_]", new_word)
      if replacements > 0 then
        cell.source = source
        cell.cursor = #source + 1
        count = count + replacements
      end
    end
  end
  return count
end

function LSP.complete_notebook(notebook, source)
  local items = LSP.complete(source)
  local seen = {}
  for _, item in ipairs(items) do seen[item] = true end
  for _, cell in ipairs(notebook.cells or {}) do
    if cell.kind == "code" then
      for word in (cell.source or ""):gmatch("[%a_][%w_]*") do
        if not seen[word] then
          seen[word] = true
          items[#items + 1] = word
        end
      end
    end
  end
  table.sort(items)
  return items
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
