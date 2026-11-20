-- Optional native file dialogs via desktop helpers.  No dependency is
-- required: callers must check available() first.
local Dialog = {}

local function command_exists(name)
  local ok = os.execute("command -v " .. name .. " >/dev/null 2>&1")
  return ok == 0 or ok == true
end

local function quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

function Dialog.available()
  return command_exists("zenity") or command_exists("kdialog")
end

local function run(command)
  local pipe = io.popen(command, "r")
  if pipe == nil then return nil, "dialog failed to start" end
  local value = pipe:read("*l")
  local ok = pipe:close()
  if not ok or value == nil or value == "" then return nil, "cancelled" end
  return value
end

function Dialog.open(start)
  start = start or os.getenv("HOME") or "."
  if command_exists("zenity") then
    return run("zenity --file-selection --title=" .. quote("Open notebook") ..
      " --filename=" .. quote(start .. "/"))
  elseif command_exists("kdialog") then
    return run("kdialog --getopenfilename " .. quote(start) ..
      " '*.luanb'")
  end
  return nil, "no native dialog backend (zenity/kdialog)"
end

function Dialog.save(default_name)
  default_name = default_name or "notebook.luanb"
  if command_exists("zenity") then
    return run("zenity --file-selection --save --confirm-overwrite --title=" ..
      quote("Save notebook") .. " --filename=" .. quote(default_name))
  elseif command_exists("kdialog") then
    return run("kdialog --getsavefilename " .. quote(default_name) ..
      " '*.luanb'")
  end
  return nil, "no native dialog backend (zenity/kdialog)"
end

return Dialog
