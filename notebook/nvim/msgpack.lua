--
-- Minimal MessagePack codec for Neovim RPC.  Pure Lua 5.1/JIT.
--
local Msgpack = {}

local ARRAY = { __msgpack_array = true }
function Msgpack.array(values)
  values = values or {}
  return setmetatable(values, ARRAY)
end
function Msgpack.map(values)
  return values or {}
end

local function is_array(value)
  if getmetatable(value) == ARRAY then return true end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
    count = count + 1
  end
  return count > 0 and count == #value
end

local function pack_uint(out, value, bytes)
  for index = bytes, 1, -1 do
    out[#out + 1] = string.char(math.floor(value / 256 ^ (index - 1)) % 256)
  end
end

local function pack_u32(value)
  return string.char(math.floor(value / 16777216) % 256,
    math.floor(value / 65536) % 256, math.floor(value / 256) % 256,
    value % 256)
end

local function pack_double(value)
  if value ~= value then return "\127\248\0\0\0\0\0\0" end
  if value == math.huge then return "\127\240\0\0\0\0\0\0" end
  if value == -math.huge then return "\255\240\0\0\0\0\0\0" end
  local sign = 0
  if value < 0 then sign = 1; value = -value end
  if value == 0 then return string.rep("\0", 8) end
  local mantissa, exponent = math.frexp(value)
  exponent = exponent + 1022
  local fraction = math.floor((mantissa * 2 - 1) * 2 ^ 52)
  local high = sign * 2147483648 + exponent * 1048576 +
    math.floor(fraction / 4294967296)
  local low = fraction % 4294967296
  return pack_u32(high) .. pack_u32(low)
end

local function unpack_u32(data, position)
  local a, b, c, d = data:byte(position, position + 3)
  return ((a * 256 + b) * 256 + c) * 256 + d
end

local function unpack_double(data, position)
  local high = unpack_u32(data, position)
  local low = unpack_u32(data, position + 4)
  local sign = high >= 2147483648 and -1 or 1
  if sign < 0 then high = high - 2147483648 end
  local exponent = math.floor(high / 1048576)
  local fraction = (high % 1048576) * 4294967296 + low
  if exponent == 0 and fraction == 0 then return sign * 0 end
  return sign * math.ldexp(fraction / 2 ^ 52 + 1, exponent - 1023)
end

local function pack_int(out, value)
  if value >= 0 then
    if value < 128 then out[#out + 1] = string.char(value)
    elseif value < 256 then out[#out + 1] = "\204" .. string.char(value)
    elseif value < 65536 then out[#out + 1] = "\205"; pack_uint(out, value, 2)
    elseif value < 4294967296 then out[#out + 1] = "\206"; pack_uint(out, value, 4)
    else out[#out + 1] = "\207"; pack_uint(out, value, 8) end
    return
  end
  if value >= -32 then out[#out + 1] = string.char(256 + value)
  elseif value >= -128 then out[#out + 1] = "\208" .. string.char(256 + value)
  elseif value >= -32768 then out[#out + 1] = "\209"; pack_uint(out, value + 65536, 2)
  elseif value >= -2147483648 then out[#out + 1] = "\210"; pack_uint(out, value + 4294967296, 4)
  else out[#out + 1] = "\211"; pack_uint(out, value + 18446744073709551616, 8) end
end

function Msgpack.encode(value, out)
  out = out or {}
  local kind = type(value)
  if value == nil then out[#out + 1] = "\192"
  elseif kind == "boolean" then out[#out + 1] = value and "\195" or "\194"
  elseif kind == "number" then
    if value % 1 == 0 and value >= -9223372036854775808 and
       value <= 9223372036854775807 then pack_int(out, value)
    else out[#out + 1] = "\203" .. pack_double(value) end
  elseif kind == "string" then
    local length = #value
    if length < 32 then out[#out + 1] = string.char(0xa0 + length)
    elseif length < 256 then out[#out + 1] = "\217" .. string.char(length)
    elseif length < 65536 then out[#out + 1] = "\218"; pack_uint(out, length, 2)
    else out[#out + 1] = "\219"; pack_uint(out, length, 4) end
    out[#out + 1] = value
  elseif kind == "table" then
    if is_array(value) then
      local count = #value
      if count < 16 then out[#out + 1] = string.char(0x90 + count)
      elseif count < 65536 then out[#out + 1] = "\220"; pack_uint(out, count, 2)
      else out[#out + 1] = "\221"; pack_uint(out, count, 4) end
      for index = 1, count do Msgpack.encode(value[index], out) end
    else
      local count = 0
      for _ in pairs(value) do count = count + 1 end
      if count < 16 then out[#out + 1] = string.char(0x80 + count)
      elseif count < 65536 then out[#out + 1] = "\222"; pack_uint(out, count, 2)
      else out[#out + 1] = "\223"; pack_uint(out, count, 4) end
      for key, item in pairs(value) do
        Msgpack.encode(key, out); Msgpack.encode(item, out)
      end
    end
  else
    error("msgpack cannot encode " .. kind)
  end
  return table.concat(out)
end

local function read_uint(data, position, bytes)
  local value = 0
  for index = 1, bytes do value = value * 256 + data:byte(position + index - 1) end
  return value, position + bytes
end

function Msgpack.decode(data, position)
  position = position or 1
  local byte = data:byte(position)
  if byte == nil then return nil, position end
  if byte <= 0x7f then return byte, position + 1
  elseif byte >= 0xe0 then return byte - 256, position + 1
  elseif byte >= 0x80 and byte <= 0x8f then return Msgpack._map(data, position + 1, byte - 0x80)
  elseif byte >= 0x90 and byte <= 0x9f then return Msgpack._array(data, position + 1, byte - 0x90)
  elseif byte >= 0xa0 and byte <= 0xbf then
    local length = byte - 0xa0
    return data:sub(position + 1, position + length), position + 1 + length
  elseif byte == 0xc0 then return nil, position + 1
  elseif byte == 0xc2 then return false, position + 1
  elseif byte == 0xc3 then return true, position + 1
  elseif byte == 0xc4 or byte == 0xd9 then
    local length; length, position = read_uint(data, position + 1, 1)
    return data:sub(position, position + length - 1), position + length
  elseif byte == 0xc5 or byte == 0xda then
    local length; length, position = read_uint(data, position + 1, 2)
    return data:sub(position, position + length - 1), position + length
  elseif byte == 0xc6 or byte == 0xdb then
    local length; length, position = read_uint(data, position + 1, 4)
    return data:sub(position, position + length - 1), position + length
  elseif byte == 0xcc then return data:byte(position + 1), position + 2
  elseif byte == 0xcd then return read_uint(data, position + 1, 2)
  elseif byte == 0xce then return read_uint(data, position + 1, 4)
  elseif byte == 0xcf then return read_uint(data, position + 1, 8)
  elseif byte == 0xd0 then return data:byte(position + 1) - 256, position + 2
  elseif byte == 0xd1 then
    local value; value, position = read_uint(data, position + 1, 2)
    return value >= 32768 and value - 65536 or value, position
  elseif byte == 0xd2 then
    local value; value, position = read_uint(data, position + 1, 4)
    return value >= 2147483648 and value - 4294967296 or value, position
  elseif byte == 0xd3 then
    local high = read_uint(data, position + 1, 4)
    local low = read_uint(data, position + 5, 4)
    return high * 4294967296 + low - (high >= 2147483648 and 18446744073709551616 or 0), position + 9
  elseif byte == 0xca then
    local bits = unpack_u32(data, position + 1)
    local sign = bits >= 2147483648 and -1 or 1
    local exponent = math.floor((bits % 2147483648) / 8388608)
    local fraction = bits % 8388608
    if exponent == 0 then
      return sign * math.ldexp(fraction, -149), position + 5
    end
    return sign * math.ldexp(fraction + 8388608, exponent - 150), position + 5
  elseif byte == 0xcb then
    return unpack_double(data, position + 1), position + 9
  elseif byte == 0xdc then
    local count; count, position = read_uint(data, position + 1, 2)
    return Msgpack._array(data, position, count)
  elseif byte == 0xdd then
    local count; count, position = read_uint(data, position + 1, 4)
    return Msgpack._array(data, position, count)
  elseif byte == 0xde then
    local count; count, position = read_uint(data, position + 1, 2)
    return Msgpack._map(data, position, count)
  elseif byte == 0xdf then
    local count; count, position = read_uint(data, position + 1, 4)
    return Msgpack._map(data, position, count)
  elseif byte == 0xd4 or byte == 0xd5 or byte == 0xd6 or byte == 0xd7 or
         byte == 0xd8 or byte == 0xc7 or byte == 0xc8 or byte == 0xc9 then
    local length = ({ [0xd4] = 1, [0xd5] = 2, [0xd6] = 4, [0xd7] = 8,
      [0xd8] = 16 })[byte]
    local ext_type
    if length == nil then
      local bytes = byte == 0xc7 and 1 or byte == 0xc8 and 2 or 4
      length, position = read_uint(data, position + 1, bytes)
    end
    ext_type = data:byte(position); position = position + 1
    local payload = data:sub(position, position + length - 1)
    return { __ext = ext_type, data = payload }, position + length
  end
  error("unsupported msgpack byte " .. tostring(byte))
end

function Msgpack._array(data, position, count)
  local values = Msgpack.array()
  for index = 1, count do
    local value; value, position = Msgpack.decode(data, position)
    if position == nil or position > #data + 1 then
      error("incomplete msgpack array")
    end
    values[index] = value
  end
  return values, position
end

function Msgpack._map(data, position, count)
  local values = {}
  for _ = 1, count do
    local key, value
    key, position = Msgpack.decode(data, position)
    if key == nil or position == nil or position > #data + 1 then
      error("incomplete msgpack map")
    end
    value, position = Msgpack.decode(data, position)
    if position == nil or position > #data + 1 then
      error("incomplete msgpack map")
    end
    values[key] = value
  end
  return values, position
end

return Msgpack
