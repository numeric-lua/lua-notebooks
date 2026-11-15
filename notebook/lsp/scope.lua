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

local KEYWORDS = {}
for word in ([[and break do else elseif end false for function if in local nil
  not or repeat return then true until while goto]]):gmatch("%S+") do
  KEYWORDS[word] = true
end

local BLOCK_OPEN = { ["function"] = true, ["if"] = true, ["for"] = true,
  ["while"] = true, ["repeat"] = true, ["do"] = true }

function Scope.analyze(source)
  local tokens = Scope.tokens(source)
  local scopes = { { bindings = {} } }
  local bindings = {}
  local references = {}

  local function add_binding(name, index, token)
    local binding = { name = name, index = index, token = token,
      scope = scopes[#scopes] }
    scopes[#scopes].bindings[#scopes[#scopes].bindings + 1] = binding
    bindings[#bindings + 1] = binding
    return binding
  end

  local function resolve(name, index)
    for scope_index = #scopes, 1, -1 do
      local found
      for _, binding in ipairs(scopes[scope_index].bindings) do
        if binding.name == name and binding.index < index and
           (found == nil or binding.index > found.index) then
          found = binding
        end
      end
      if found then return found end
    end
    return nil
  end

  for index, token in ipairs(tokens) do
    if token.kind == "word" then
      if BLOCK_OPEN[token.text] then
        scopes[#scopes + 1] = { bindings = {} }
      elseif token.text == "end" or token.text == "until" then
        if #scopes > 1 then table.remove(scopes) end
      elseif token.text == "local" then
        local next_index = index + 1
        local function skip_space(position)
          while tokens[position] and tokens[position].kind == "symbol" and
                tokens[position].text:match("%s") do
            position = position + 1
          end
          return position
        end
        next_index = skip_space(next_index)
        if tokens[next_index] and tokens[next_index].text == "function" then
          next_index = skip_space(next_index + 1)
          if tokens[next_index] and tokens[next_index].kind == "word" then
            add_binding(tokens[next_index].text, index, tokens[next_index])
          end
        else
          while tokens[next_index] and tokens[next_index].kind == "word" and
                not KEYWORDS[tokens[next_index].text] do
            add_binding(tokens[next_index].text, index, tokens[next_index])
            next_index = skip_space(next_index + 1)
            if tokens[next_index] and tokens[next_index].text == "," then
              next_index = skip_space(next_index + 1)
            else
              break
            end
          end
        end
      elseif not KEYWORDS[token.text] then
        local previous = tokens[index - 1]
        if previous == nil or (previous.text ~= "." and previous.text ~= ":") then
          references[#references + 1] = { token = token,
            binding = resolve(token.text, index) }
        end
      end
    end
  end
  return { tokens = tokens, bindings = bindings, references = references }
end

function Scope.resolved_ranges(source, byte_offset, word)
  local analysis = Scope.analyze(source)
  local target
  for _, binding in ipairs(analysis.bindings) do
    if binding.name == word and binding.token.start <= byte_offset and
       binding.token.finish >= byte_offset then target = binding; break end
  end
  if target == nil then
    for _, reference in ipairs(analysis.references) do
      if reference.token.text == word and reference.token.start <= byte_offset and
         reference.token.finish >= byte_offset then
        target = reference.binding
        break
      end
    end
  end
  if target == nil then return nil, false end
  local ranges = { { start = target.token.start, finish = target.token.finish } }
  for _, reference in ipairs(analysis.references) do
    if reference.binding == target and
       reference.token.start ~= target.token.start then
      ranges[#ranges + 1] = { start = reference.token.start,
        finish = reference.token.finish }
    end
  end
  return ranges, true
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
