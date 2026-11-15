--
-- Lightweight Lua type inference for editor completion.  It is intentionally a
-- static subset: literals, tables, local/field assignments, table constructors,
-- builtin modules, and unknown function calls.
--
local Types = {}

local function tokenize(source)
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
      local start = index
      index = index + 1
      while index <= #source do
        local current = source:sub(index, index)
        if current == "\\" then index = index + 2
        elseif current == quote then index = index + 1; break
        else index = index + 1 end
      end
      tokens[#tokens + 1] = { kind = "string", text = source:sub(start, index - 1),
        start = start, finish = index - 1 }
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

local function new_type(kind, name)
  return { kind = kind, name = name, fields = {} }
end

local function function_type(returns, params)
  local t = new_type("function")
  t.returns = returns or new_type("unknown")
  t.params = params
  return t
end

local function table_type(fields)
  local t = new_type("table")
  for name, field in pairs(fields or {}) do t.fields[name] = field end
  return t
end

local function unknown()
  return new_type("unknown")
end

local NUMBER = new_type("number")
local STRING = new_type("string")
local BOOLEAN = new_type("boolean")
local NIL = new_type("nil")
local ANY = unknown()

local GLOBALS = {}
local function global(name, t) GLOBALS[name] = t end
local function module(name, fields)
  local t = new_type("table", name)
  for field, value in pairs(fields) do
    t.fields[field] = {
      type = value,
      kind = value.kind == "function" and "method" or "field",
    }
  end
  GLOBALS[name] = t
end
local function number_function() return function_type(NUMBER) end
local function string_function() return function_type(STRING) end

for _, name in ipairs({ "print", "error", "assert", "collectgarbage" }) do
  global(name, function_type(NIL))
end
global("type", function_type(STRING))
global("tostring", function_type(STRING))
global("tonumber", function_type(NUMBER))
global("pairs", function_type(ANY))
global("ipairs", function_type(ANY))
global("next", function_type(ANY))
global("select", function_type(ANY))
global("pcall", function_type(ANY))
global("require", function_type(ANY))

local STRING_FIELDS = {}
for _, name in ipairs({ "byte", "char", "dump", "find", "format", "gmatch",
  "gsub", "len", "lower", "match", "rep", "reverse", "sub", "upper" }) do
  STRING_FIELDS[name] = string_function()
end
STRING_FIELDS.gmatch = function_type(ANY)
STRING_FIELDS.find = function_type(ANY)
module("string", STRING_FIELDS)
STRING.fields = GLOBALS.string.fields

local TABLE_FIELDS = {}
for _, name in ipairs({ "concat", "insert", "move", "pack", "remove", "sort",
  "unpack" }) do
  TABLE_FIELDS[name] = function_type(ANY)
end
TABLE_FIELDS.concat = string_function()
module("table", TABLE_FIELDS)

local MATH_FIELDS = {}
for _, name in ipairs({ "abs", "acos", "asin", "atan", "ceil", "cos", "deg",
  "exp", "floor", "fmod", "log", "max", "min", "rad", "random", "sin", "sqrt",
  "tan" }) do
  MATH_FIELDS[name] = number_function()
end
MATH_FIELDS.pi = NUMBER
MATH_FIELDS.huge = NUMBER
MATH_FIELDS.randomseed = function_type(NIL)
module("math", MATH_FIELDS)

local WIDGET_FIELDS = {}
for _, name in ipairs({ "slider", "button", "checkbox", "select", "text",
  "number", "progress", "label", "shader" }) do
  WIDGET_FIELDS[name] = function_type(ANY)
end
module("widgets", WIDGET_FIELDS)

local KEYWORDS = {}
for word in ([[and break do else elseif end false for function if in local nil
  not or repeat return then true until while goto]]):gmatch("%S+") do
  KEYWORDS[word] = true
end

local Analyzer = {}
Analyzer.__index = Analyzer

local function is_space(token)
  return token and token.kind == "symbol" and token.text:match("%s")
end

local function skip_space(an, index)
  while is_space(an.tokens[index]) do index = index + 1 end
  return index
end

local function visible_scope(an, index)
  return an.scope_at[index] or an.root
end

function Analyzer:lookup(name, index)
  local scope = visible_scope(self, index)
  while scope do
    local symbol = scope.symbols[name]
    if symbol and symbol.declared <= index then return symbol end
    scope = scope.parent
  end
  local global_type = GLOBALS[name]
  if global_type then
    return { name = name, type = global_type, global = true, declared = 0 }
  end
end

function Analyzer:type_of_symbol(symbol, index)
  if symbol == nil then return unknown() end
  if symbol.global then return symbol.type end
  local result = unknown()
  for _, assignment in ipairs(symbol.assignments or {}) do
    if assignment.index <= index then result = assignment.type end
  end
  return result
end

function Analyzer:declare(name, index, type, token)
  local scope = visible_scope(self, index)
  local existing = scope.symbols[name]
  if existing == nil then
    existing = { name = name, declared = index, scope = scope,
      assignments = {}, token = token }
    scope.symbols[name] = existing
  end
  existing.assignments[#existing.assignments + 1] = { index = index,
    type = type or unknown() }
  return existing
end

function Analyzer:assign(name, index, type)
  local symbol = self:lookup(name, index)
  if symbol == nil or symbol.global then
    -- New globals are inferred but do not leak outside the completion pass.
    symbol = { name = name, declared = 0, global = true, assignments = {} }
    GLOBALS[name] = type
  end
  symbol.assignments[#symbol.assignments + 1] = { index = index, type = type }
end

function Analyzer:field_type(receiver, field)
  if receiver == nil or receiver.kind == "unknown" then return unknown() end
  local value = receiver.fields and receiver.fields[field]
  if value and value.type then return value.type end
  return value or unknown()
end

function Analyzer:parse_table(index)
  local t = table_type({})
  local fields = t.fields
  index = index + 1
  while self.tokens[index] do
    index = skip_space(self, index)
    local token = self.tokens[index]
    if token.text == "}" then return t, index + 1 end
    if token.text == "," or token.text == ";" then
      index = index + 1
    elseif token.kind == "word" and self.tokens[skip_space(self, index + 1)].text == "=" then
      local field_token = token
      index = skip_space(self, index + 1) + 1
      local value, next_index = self:parse_expression(index)
      fields[field_token.text] = { type = value, token = field_token,
        kind = value.kind == "function" and "method" or "field" }
      index = next_index
    else
      local value, next_index = self:parse_expression(index)
      fields[#fields + 1] = { type = value }
      index = next_index
    end
  end
  return t, index
end

function Analyzer:parse_function(index)
  local depth = 0
  index = index + 1
  while self.tokens[index] do
    local word = self.tokens[index].text
    if word == "function" or word == "if" or word == "for" or word == "while" or
       word == "repeat" then
      depth = depth + 1
    elseif word == "end" or word == "until" then
      depth = depth - 1
      if depth <= 0 then return function_type(), index + 1 end
    end
    index = index + 1
  end
  return function_type(), index
end

function Analyzer:parse_primary(index)
  index = skip_space(self, index)
  local token = self.tokens[index]
  if token == nil then return unknown(), index end
  if token.kind == "number" then return NUMBER, index + 1 end
  if token.kind == "string" then return STRING, index + 1 end
  if token.text == "nil" then return NIL, index + 1 end
  if token.text == "true" or token.text == "false" then
    return BOOLEAN, index + 1
  end
  if token.text == "{" then return self:parse_table(index) end
  if token.text == "function" then return self:parse_function(index) end
  if token.text == "(" then
    local value, next_index = self:parse_expression(index + 1)
    next_index = skip_space(self, next_index)
    if self.tokens[next_index] and self.tokens[next_index].text == ")" then
      next_index = next_index + 1
    end
    return value, next_index
  end
  if token.text == "-" or token.text == "not" or token.text == "#" then
    local _, next_index = self:parse_primary(index + 1)
    return token.text == "not" and BOOLEAN or NUMBER, next_index
  end
  if token.kind == "word" then
    local symbol = self:lookup(token.text, index)
    if symbol then return self:type_of_symbol(symbol, index), index + 1 end
    return unknown(), index + 1
  end
  return unknown(), index + 1
end

function Analyzer:parse_postfix(index, value)
  while self.tokens[index] do
    index = skip_space(self, index)
    local token = self.tokens[index]
    if token == nil then break end
    if token.text == "." then
      local field = self.tokens[skip_space(self, index + 1)]
      if field == nil then break end
      value = self:field_type(value, field.text)
      index = skip_space(self, index + 1) + 1
    elseif token.text == ":" then
      local method = self.tokens[skip_space(self, index + 1)]
      if method == nil then break end
      value = self:field_type(value, method.text)
      index = skip_space(self, index + 1) + 1
    elseif token.text == "[" then
      local key, next_index = self:parse_expression(index + 1)
      next_index = skip_space(self, next_index)
      if self.tokens[next_index] and self.tokens[next_index].text == "]" then
        next_index = next_index + 1
      end
      value = key.kind == "string" and self:field_type(value, key.value) or
        unknown()
      index = next_index
    elseif token.text == "(" then
      local depth = 1
      local next_index = index + 1
      while self.tokens[next_index] and depth > 0 do
        local current = self.tokens[next_index].text
        if current == "(" then depth = depth + 1
        elseif current == ")" then depth = depth - 1 end
        next_index = next_index + 1
      end
      local returns = value.kind == "function" and value.returns or unknown()
      if value.kind == "table" and value.fields then
        local call = value.fields.__call
        if call and call.type and call.type.kind == "function" then
          returns = call.type.returns
        end
      end
      value = returns or unknown()
      index = next_index
    else
      break
    end
  end
  return value, index
end

function Analyzer:parse_expression(index)
  local value, next_index = self:parse_primary(index)
  value, next_index = self:parse_postfix(next_index, value)
  while self.tokens[next_index] do
    local token = self.tokens[next_index]
    if token.text == ".." then
      local _, after = self:parse_primary(next_index + 1)
      value = STRING
      next_index = after
    elseif token.text == "==" or token.text == "~=" or token.text == "<" or
           token.text == ">" or token.text == "<=" or token.text == ">=" or
           token.text == "and" or token.text == "or" then
      local _, after = self:parse_primary(next_index + 1)
      value = (token.text == "and" or token.text == "or") and value or BOOLEAN
      next_index = after
    elseif token.text == "+" or token.text == "-" or token.text == "*" or
           token.text == "/" or token.text == "%" or token.text == "^" then
      local _, after = self:parse_primary(next_index + 1)
      value = NUMBER
      next_index = after
    else
      break
    end
  end
  return value, next_index
end

function Types.analyze(source)
  local an = setmetatable({ tokens = tokenize(source), scope_at = {},
    scopes = {}, root = nil }, Analyzer)
  local root = { symbols = {}, parent = nil }
  an.root = root
  an.scopes[1] = root
  local expected_do = false

  local function current() return an.scopes[#an.scopes] end
  local function push()
    local scope = { symbols = {}, parent = current() }
    an.scopes[#an.scopes + 1] = scope
  end
  local function pop()
    if #an.scopes > 1 then table.remove(an.scopes) end
  end

  local function parse_target(index)
    index = skip_space(an, index)
    local token = an.tokens[index]
    if token == nil or token.kind ~= "word" then return nil end
    local chain = { token }
    index = index + 1
    while an.tokens[index] do
      index = skip_space(an, index)
      local dot = an.tokens[index]
      if dot == nil or (dot.text ~= "." and dot.text ~= ":") then break end
      local field = an.tokens[skip_space(an, index + 1)]
      if field == nil or field.kind ~= "word" then break end
      chain[#chain + 1] = field
      index = skip_space(an, index + 1) + 1
    end
    return chain, index
  end

  local index = 1
  while index <= #an.tokens do
    an.scope_at[index] = current()
    local token = an.tokens[index]
    if token.kind == "word" then
      if token.text == "if" then push()
      elseif token.text == "elseif" or token.text == "else" then
        if #an.scopes > 1 then
          pop(); push()
        end
      elseif token.text == "function" then
        push()
        local position = skip_space(an, index + 1)
        if an.tokens[position] and an.tokens[position].text ~= "(" and
           an.tokens[position].kind == "word" then
          an:declare(an.tokens[position].text, index,
            function_type(), an.tokens[position])
          position = skip_space(an, position + 1)
        end
        if an.tokens[position] and an.tokens[position].text == "(" then
          position = position + 1
          while an.tokens[position] and an.tokens[position].text ~= ")" do
            if an.tokens[position].kind == "word" then
              an:declare(an.tokens[position].text, index,
                unknown(), an.tokens[position])
            end
            position = position + 1
          end
        end
      elseif token.text == "for" or token.text == "while" then
        push(); expected_do = true
        if token.text == "for" then
          local position = skip_space(an, index + 1)
          while an.tokens[position] and an.tokens[position].text ~= "=" and
                an.tokens[position].text ~= "in" do
            if an.tokens[position].kind == "word" then
              an:declare(an.tokens[position].text, index, unknown(),
                an.tokens[position])
            end
            position = position + 1
          end
        end
      elseif token.text == "do" then
        if expected_do then expected_do = false else push() end
      elseif token.text == "repeat" then push()
      elseif token.text == "until" or token.text == "end" then pop()
      elseif token.text == "local" then
        local position = skip_space(an, index + 1)
        local names = {}
        while an.tokens[position] and an.tokens[position].kind == "word" and
              an.tokens[position].text ~= "function" do
          names[#names + 1] = an.tokens[position]
          an:declare(an.tokens[position].text, index, unknown(),
            an.tokens[position])
          position = skip_space(an, position + 1)
          if an.tokens[position] and an.tokens[position].text == "," then
            position = skip_space(an, position + 1)
          else
            break
          end
        end
        if an.tokens[position] and an.tokens[position].text == "function" then
          local name = an.tokens[skip_space(an, position + 1)]
          if name and name.kind == "word" then
            an:declare(name.text, index, function_type(), name)
          end
        elseif an.tokens[position] and an.tokens[position].text == "=" then
          position = skip_space(an, position + 1)
          for _, name in ipairs(names) do
            local value, next_index = an:parse_expression(position)
            local symbol = an:lookup(name.text, index)
            if symbol then
              symbol.assignments[#symbol.assignments + 1] = { index = index,
                type = value }
            end
            position = next_index
            position = skip_space(an, position)
            if an.tokens[position] and an.tokens[position].text == "," then
              position = skip_space(an, position + 1)
            else
              break
            end
          end
        end
      elseif not KEYWORDS[token.text] then
        local chain, after = parse_target(index)
        if chain then
          after = skip_space(an, after)
          if an.tokens[after] and an.tokens[after].text == "=" and
             (an.tokens[after + 1] == nil or
              an.tokens[after + 1].text ~= "=") then
            local value = an:parse_expression(after + 1)
            if #chain == 1 then
              an:assign(chain[1].text, index, value)
            else
              local symbol = an:lookup(chain[1].text, index)
              local target = symbol and an:type_of_symbol(symbol, index)
              for field_index = 2, #chain - 1 do
                target = an:field_type(target, chain[field_index].text)
              end
              if target and target.fields then
                local field = chain[#chain]
                local existing = target.fields[field.text]
                target.fields[field.text] = { type = value,
                  token = existing and existing.token or field,
                  kind = value.kind == "function" and "method" or "field" }
              end
            end
            index = after
          end
        end
      end
    end
    index = index + 1
  end
  return an
end

local function token_index_at(an, offset)
  local best = 1
  for index, token in ipairs(an.tokens) do
    if token.start <= offset then best = index else break end
  end
  return best
end

local function token_at(an, offset)
  local index = token_index_at(an, offset)
  local token = an.tokens[index]
  if token and token.start <= offset and token.finish >= offset then return token, index end
end

local function receiver_before(an, dot_index)
  local before = dot_index - 1
  while before > 0 and is_space(an.tokens[before]) do before = before - 1 end
  local parts = {}
  while before > 0 do
    local current = an.tokens[before]
    if current.kind ~= "word" then break end
    table.insert(parts, 1, current.text)
    before = before - 1
    while before > 0 and is_space(an.tokens[before]) do before = before - 1 end
    if before > 0 and (an.tokens[before].text == "." or
       an.tokens[before].text == ":") then
      before = before - 1
      while before > 0 and is_space(an.tokens[before]) do before = before - 1 end
    else
      break
    end
  end
  if #parts == 0 then return nil end
  return parts
end

function Types.completion_context(source, offset)
  local an = Types.analyze(source)
  local index = token_index_at(an, offset)
  local previous = index
  while previous > 0 and is_space(an.tokens[previous]) do previous = previous - 1 end
  local token = an.tokens[previous]
  if token == nil or (token.text ~= "." and token.text ~= ":") then return nil end
  local parts = receiver_before(an, previous)
  if parts == nil then return nil end
  return an, index, parts, token.text == ":"
end

function Types.complete(source, offset)
  local an, index, receiver, method = Types.completion_context(source, offset)
  if not an then return nil end
  local symbol = an:lookup(receiver[1], index)
  local current = symbol and an:type_of_symbol(symbol, index) or GLOBALS[receiver[1]]
  for field_index = 2, #receiver do
    current = an:field_type(current, receiver[field_index])
  end
  if current == nil or current.fields == nil then return {} end
  local items = {}
  for name, field in pairs(current.fields) do
    if not method or field.kind == "method" or field.type.kind == "function" then
      items[#items + 1] = { label = name,
        kind = field.kind == "method" and 2 or
          (field.type.kind == "function" and 3 or 5),
        detail = field.type.kind }
    end
  end
  table.sort(items, function(a, b) return a.label < b.label end)
  return items
end

function Types.symbols(source, offset)
  local an = Types.analyze(source)
  local index = token_index_at(an, offset)
  local scope = visible_scope(an, index)
  local seen, items = {}, {}
  while scope do
    for name, symbol in pairs(scope.symbols) do
      if not seen[name] and symbol.declared <= index then
        seen[name] = true
        local value = an:type_of_symbol(symbol, index)
        items[#items + 1] = { label = name, kind = 3, detail = value.kind }
      end
    end
    scope = scope.parent
  end
  for name, value in pairs(GLOBALS) do
    if not seen[name] then
      seen[name] = true
      items[#items + 1] = { label = name, kind = 6, detail = value.kind }
    end
  end
  table.sort(items, function(a, b) return a.label < b.label end)
  return items
end

function Types.field_occurrences(source, name, declaration_start)
  local an = Types.analyze(source)
  local result = {}
  for _, token in ipairs(an.tokens) do
    if token.kind == "word" and token.text == name then
      if token.start == declaration_start then
        result[#result + 1] = { start = token.start, finish = token.finish }
      else
        local resolved = Types.resolve(source, token.start)
        if resolved and resolved.declaration and
           resolved.declaration.start == declaration_start then
          result[#result + 1] = { start = token.start, finish = token.finish }
        end
      end
    end
  end
  return result
end

function Types.resolve(source, offset)
  local an = Types.analyze(source)
  local token, index = token_at(an, offset)
  if token == nil then return nil end
  local previous = index - 1
  while previous > 0 and is_space(an.tokens[previous]) do previous = previous - 1 end
  if previous > 0 and (an.tokens[previous].text == "." or
     an.tokens[previous].text == ":") then
    local receiver = receiver_before(an, previous)
    if receiver == nil then return nil end
    local symbol = an:lookup(receiver[1], index)
    local current = symbol and an:type_of_symbol(symbol, index) or
      GLOBALS[receiver[1]]
    for field_index = 2, #receiver do
      current = an:field_type(current, receiver[field_index])
    end
    local field = current and current.fields and current.fields[token.text]
    if field then
      return { name = token.text, type = field.type, field = field,
        token = token, declaration = field.token, receiver = current }
    end
    return nil
  end
  local symbol = an:lookup(token.text, index)
  if symbol then
    local value = an:type_of_symbol(symbol, index)
    return { name = token.text, type = value, token = token,
      declaration = symbol.token }
  end
  return nil
end

return Types
