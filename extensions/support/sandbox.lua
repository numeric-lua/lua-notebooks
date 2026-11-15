--
-- Host side of T2: execute a user Lua extension once in a bubblewrap child,
-- then register only its static display-list result.  The child has no host
-- filesystem, home, network, or graphics access.
--
local json = require("notebook.json")
local DisplayList = require("extensions.support.display_list")

local Sandbox = {}

local function quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

function Sandbox.available()
  local ok = os.execute("command -v bwrap >/dev/null 2>&1")
  return ok == 0 or ok == true
end

function Sandbox.run(source_path, id, root)
  root = root or "."
  local stamp = string.format("/tmp/lua-notebooks-ext-%d-%s", os.time(),
    tostring(id):gsub("[^%w_-]", "_"))
  os.execute("rm -rf " .. quote(stamp))
  os.execute("mkdir -p " .. quote(stamp .. "/notebook"))
  os.execute("cp " .. quote(source_path) .. " " .. quote(stamp .. "/user.lua"))
  os.execute("cp " .. quote(root .. "/extensions/support/sandbox_worker.lua") .. " " ..
    quote(stamp .. "/worker.lua"))
  os.execute("cp " .. quote(root .. "/notebook/json.lua") .. " " ..
    quote(stamp .. "/notebook/json.lua"))
  local command = table.concat({
    "timeout 3 bwrap",
    "--unshare-all --die-with-parent --new-session --clearenv",
    "--ro-bind /usr /usr --ro-bind /lib /lib --ro-bind /lib64 /lib64",
    "--ro-bind " .. quote(stamp) .. " /app",
    "--proc /proc --dev /dev --tmpfs /tmp --chdir /app",
    "/usr/bin/sh -c " .. quote(
      "ulimit -v 262144 2>/dev/null || true; " ..
      "ulimit -t 3 2>/dev/null || true; " ..
      "exec /usr/bin/luajit /app/worker.lua /app/user.lua 2>/tmp/ext.err"),
  }, " ")
  local pipe = assert(io.popen(command, "r"))
  local output = pipe:read("*a") or ""
  local ok = pipe:close()
  os.execute("rm -rf " .. quote(stamp))
  if not ok then return nil, "sandbox child failed" end
  local decoded, value = pcall(json.decode, output)
  if not decoded or type(value) ~= "table" then
    return nil, "sandbox returned invalid JSON"
  end
  if not value.ok then return nil, tostring(value.error) end
  value.descriptor.id = id
  local descriptor, err = DisplayList.validate(value.descriptor, source_path)
  if descriptor == nil then return nil, err end
  descriptor.id = id
  descriptor.tier = "sandboxed"
  return descriptor
end

return Sandbox
