--
-- Small Lua tokenizer for code-cell rendering.
--
local Highlight = {}

local KEYWORDS = {}
for word in ([[and break do else elseif end false for function if in local nil
  not or repeat return then true until while goto]]):gmatch("%S+") do
  KEYWORDS[word] = true
end

local function emit(tokens, kind, text)
  if text ~= "" then tokens[#tokens + 1] = { kind = kind, text = text } end
end

function Highlight.line(line)
  local tokens = {}
  local index = 1
  while index <= #line do
    local char = line:sub(index, index)
    local rest = line:sub(index)
    if char == "-" and rest:sub(1, 2) == "--" then
      emit(tokens, "comment", rest)
      break
    elseif char == '"' or char == "'" then
      local finish = index + 1
      while finish <= #line do
        local current = line:sub(finish, finish)
        if current == "\\" then finish = finish + 2
        elseif current == char then finish = finish + 1; break
        else finish = finish + 1 end
      end
      emit(tokens, "string", line:sub(index, finish - 1))
      index = finish
    elseif char == "[" and rest:sub(1, 2) == "[[" then
      local close = line:find("]]", index + 2, true)
      local finish = close and close + 2 or #line + 1
      emit(tokens, "string", line:sub(index, finish - 1))
      index = finish
    elseif char:match("%d") then
      local value = rest:match("^0[xX]%x+") or rest:match("^%d+%.?%d*[eE]?[+-]?%d*")
      emit(tokens, "number", value)
      index = index + #value
    elseif char:match("[%a_]") then
      local word = rest:match("^[%a_][%w_]*")
      emit(tokens, KEYWORDS[word] and "keyword" or "identifier", word)
      index = index + #word
    elseif char:match("%s") then
      local spaces = rest:match("^%s+")
      emit(tokens, "space", spaces)
      index = index + #spaces
    else
      emit(tokens, "operator", char)
      index = index + 1
    end
  end
  return tokens
end

return Highlight
