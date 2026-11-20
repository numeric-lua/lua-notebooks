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

function Dialog.backend()
  if command_exists("zenity") then return "zenity" end
  if command_exists("kdialog") then return "kdialog" end
  if package.config:sub(1, 1) == "\\" and command_exists("powershell") then
    return "powershell"
  end
  if command_exists("osascript") then return "osascript" end
  return nil
end

function Dialog.available()
  return Dialog.backend() ~= nil
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
  local backend = Dialog.backend()
  if backend == "zenity" then
    return run("zenity --file-selection --title=" .. quote("Open notebook") ..
      " --filename=" .. quote(start .. "/"))
  elseif backend == "kdialog" then
    return run("kdialog --getopenfilename " .. quote(start) .. " '*.luanb'")
  elseif backend == "powershell" then
    local command = "Add-Type -AssemblyName System.Windows.Forms; " ..
      "$d=New-Object System.Windows.Forms.OpenFileDialog; " ..
      "$d.Filter='Lua notebooks (*.luanb)|*.luanb|All files (*.*)|*.*'; " ..
      "if($d.ShowDialog() -eq 'OK'){Write-Output $d.FileName}"
    return run("powershell -NoProfile -Command " .. quote(command))
  elseif backend == "osascript" then
    return run("osascript -e " .. quote(
      "POSIX path of (choose file with prompt \"Open notebook\")"))
  end
  return nil, "no native dialog backend"
end

function Dialog.save(default_name)
  default_name = default_name or "notebook.luanb"
  local backend = Dialog.backend()
  if backend == "zenity" then
    return run("zenity --file-selection --save --confirm-overwrite --title=" ..
      quote("Save notebook") .. " --filename=" .. quote(default_name))
  elseif backend == "kdialog" then
    return run("kdialog --getsavefilename " .. quote(default_name) .. " '*.luanb'")
  elseif backend == "powershell" then
    local command = "Add-Type -AssemblyName System.Windows.Forms; " ..
      "$d=New-Object System.Windows.Forms.SaveFileDialog; " ..
      "$d.Filter='Lua notebooks (*.luanb)|*.luanb'; " ..
      "$d.FileName=" .. quote(default_name) .. "; " ..
      "if($d.ShowDialog() -eq 'OK'){Write-Output $d.FileName}"
    return run("powershell -NoProfile -Command " .. quote(command))
  elseif backend == "osascript" then
    return run("osascript -e " .. quote(
      "POSIX path of (choose file name with prompt \"Save notebook\" default name \"" ..
      default_name .. "\")"))
  end
  return nil, "no native dialog backend"
end

return Dialog
