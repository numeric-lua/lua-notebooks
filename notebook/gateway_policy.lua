-- Pure policy checks for the remote kernel gateway.
local Policy = {}

local function header(request, wanted)
  for line in (request .. "\n"):gmatch("(.-)\n") do
    local name, value = line:match("^([^:]+):%s*(.*)$")
    if name and name:lower() == wanted then
      return (value:gsub("\r$", ""))
    end
  end
  return nil
end

function Policy.authorize(request, options)
  options = options or {}
  local path = request:match("^%u+%s+([^%s]+)")
  if path == nil then return false, "malformed request" end
  if options.token ~= nil and options.token ~= "" then
    local supplied = path:match("[?&]token=([^&]+)")
    if supplied ~= options.token then return false, "invalid token" end
  end
  if options.origin ~= nil and options.origin ~= "" then
    local origin = header(request, "origin")
    if origin ~= options.origin then return false, "origin not allowed" end
  end
  if options.token_expires ~= nil then
    local now = options.now or os.time()
    if now > options.token_expires then return false, "token expired" end
  end
  return true
end

function Policy.check_frame(length, max_frame)
  if max_frame ~= nil and length > max_frame then
    return false, "frame exceeds limit"
  end
  return true
end

return Policy
