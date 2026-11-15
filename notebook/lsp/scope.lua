--
-- Lightweight Lua-aware occurrence scanner.  Not a parser: it skips strings
-- and comments and excludes field/method names after . or :.
--
local Scope = {}

local function skip_long(source, index)
  local level = 1
  while level > 0 and index <= #source do
    local close = source:find("]" .. string.rep("=", level - 1) .. "]", index, true)
    if close == nil then return #source + 1 end
    index = close + level + 1
    level = level - 1
  end
  return index
end

function Scope.tokens(source)
  local tokens = {}
  local index = 1
  while index <= #source do
    local char = source:sub(index, index)
    if source:sub(index, index + 1) == "--" then
      local long = source:match("^%-%-%[(=*)%[", index)
      if long then
        local close = source:find("]" .. long .. "]", index + 4 + #long, true)
        index = close and close + 2 + #long or #source + 1
      else
        local newline = source:find("\n", index, true)
        index = newline and newline + 1 or #source + 1
      end
    elseif char == '"' or char == "'" then
      local quote = char
      index = index + 1
      while index <= #source do
        local current = source:sub(index, index)
        if current == "\\" then index = index + 2
        elseif current == quote then index = index + 1; break
        else index = index + 1 end
      end
    elseif source:match("^%[(=*)%[", index) then
      local level = source:match("^%[(=*)%[", index)
      local close = source:find("]" .. level .. "]", index + 2 + #level, true)
      index = close and close + 2 + #level or #source + 1
    elseif char:match("[%a_]") then
      local word = source:match("^[%a_][%w_]*", index)
      tokens[#tokens + 1] = { kind = "word", text = word, start = index,
        finish = index + #word - 1 }
      index = index + #word
    elseif char:match("%d") then
      local number = source:match("^%d+%.?%d*", index)
      tokens[#tokens + 1] = { kind = "number", text = number, start = index,
        finish = index + #number - 1 }
      index = index + #number
    else
      tokens[#tokens + 1] = { kind = "symbol", text = char, start = index,
        finish = index }
      index = index + 1
    end
  end
  return tokens
end

function Scope.occurrences(source, word)
  local result = {}
  local tokens = Scope.tokens(source)
  for index, token in ipairs(tokens) do
    if token.kind == "word" and token.text == word then
      local previous = tokens[index - 1]
      if previous == nil or (previous.text ~= "." and previous.text ~= ":") then
        result[#result + 1] = { start = token.start, finish = token.finish }
      end
    end
  end
  return result
end

return Scope
