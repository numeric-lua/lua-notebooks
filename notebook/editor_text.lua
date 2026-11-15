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

local function pattern_escape(text)
  return (text:gsub("([^%w])", "%%%1"))
end

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

function LSP.find(source, pattern)
  local ok, start_at = pcall(string.find, source, pattern)
  if ok then return start_at end
  return source:find(pattern, 1, true)
end

function LSP.substitute_pattern(source, pattern, replacement, global)
  local ok, result, count = pcall(string.gsub, source, pattern, replacement)
  if not ok then return source, 0 end
  if global or count == 0 then return result, count end
  local start_at = LSP.find(source, pattern)
  if start_at == nil then return source, 0 end
  local _, finish = string.find(source, pattern)
  return source:sub(1, start_at - 1) .. replacement ..
    source:sub(finish + 1), 1
end

function LSP.substitute(source, old_text, new_text, global)
  if old_text == nil or old_text == "" then return source, 0 end
  if global then
    local escaped = pattern_escape(old_text)
    return source:gsub(escaped, new_text)
  end
  local start_at = source:find(old_text, 1, true)
  if start_at == nil then return source, 0 end
  return source:sub(1, start_at - 1) .. new_text ..
    source:sub(start_at + #old_text), 1
end

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

function LSP.offset_at(text, line, character)
  local current = 1
  for _ = 1, line do
    local newline = text:find("\n", current, true)
    if newline == nil then return #text + 1 end
    current = newline + 1
  end
  return current + (character or 0)
end

function LSP.word_at(text, line, character)
  local current = 1
  for _ = 1, line do
    local newline = text:find("\n", current, true)
    if newline == nil then current = #text + 1; break end
    current = newline + 1
  end
  local next_newline = text:find("\n", current, true)
  local line_text = text:sub(current, (next_newline or #text + 1) - 1)
  local byte = math.min(character, #line_text)
  local start_at = byte + 1
  while start_at > 1 and line_text:sub(start_at - 1, start_at - 1):match("[%w_]") do
    start_at = start_at - 1
  end
  local end_at = byte + 1
  while end_at <= #line_text and line_text:sub(end_at, end_at):match("[%w_]") do
    end_at = end_at + 1
  end
  if end_at <= start_at then return nil end
  return {
    word = line_text:sub(start_at, end_at - 1),
    start = start_at - 1,
    finish = end_at - 1,
    line_text = line_text,
  }
end

function LSP.occurrences(text, word)
  local result = {}
  local escaped = word:gsub("([^%w])", "%%%1")
  local position = 1
  while true do
    local start_at, end_at = text:find("%f[%w_]" .. escaped .. "%f[^%w_]", position)
    if start_at == nil then break end
    result[#result + 1] = { start = start_at, finish = end_at }
    position = end_at + 1
  end
  return result
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
