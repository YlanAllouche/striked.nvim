local M = {}

local uv = vim.uv or vim.loop
local module_source = debug.getinfo(1, "S").source
local module_path = module_source:sub(1, 1) == "@" and module_source:sub(2) or module_source
local plugin_root = vim.fn.fnamemodify(module_path, ":h:h:h")
local wayland_helper_path = plugin_root .. "/python/striked_wayland_clipboard.py"
local macos_helper_path = plugin_root .. "/swift/striked_macos_clipboard.swift"
local WAYLAND_HELPER_TIMEOUT_SECONDS = 300
local wayland_helper_pid
local wayland_helper_available

local COPYQ_WRITE_SCRIPT = [[
var payload = JSON.parse(str(input()))
var item = {}
if (payload.html_only !== true) {
  item[mimeText] = payload.text || ''
}
item[mimeHtml] = payload.html || ''
copy(item)
]]

local COPYQ_READ_SCRIPT = [[
print(str(clipboard()))
]]

local POWERSHELL_WRITE_SCRIPT = [[
$payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
Add-Type -AssemblyName System.Windows.Forms

function New-CfHtml([string]$Fragment) {
  $prefix = '<html><body><!--StartFragment-->'
  $suffix = '<!--EndFragment--></body></html>'
  $html = $prefix + $Fragment + $suffix
  $encoding = [System.Text.Encoding]::UTF8
  $headerTemplate = "Version:1.0`r`nStartHTML:{0}`r`nEndHTML:{1}`r`nStartFragment:{2}`r`nEndFragment:{3}`r`n"
  $dummyHeader = $headerTemplate -f ('0' * 10), ('0' * 10), ('0' * 10), ('0' * 10)

  $startHtml = $encoding.GetByteCount($dummyHeader)
  $startFragment = $startHtml + $encoding.GetByteCount($prefix)
  $endFragment = $startFragment + $encoding.GetByteCount($Fragment)
  $endHtml = $startHtml + $encoding.GetByteCount($html)

  return ($headerTemplate -f $startHtml.ToString('0000000000'), $endHtml.ToString('0000000000'), $startFragment.ToString('0000000000'), $endFragment.ToString('0000000000')) + $html
}

$data = New-Object System.Windows.Forms.DataObject

if (-not $payload.html_only) {
  $data.SetData([System.Windows.Forms.DataFormats]::UnicodeText, [string]$payload.text)
}

$data.SetData([System.Windows.Forms.DataFormats]::Html, (New-CfHtml([string]$payload.html)))
[System.Windows.Forms.Clipboard]::SetDataObject($data, $true)
]]

local POWERSHELL_READ_SCRIPT = [[
Add-Type -AssemblyName System.Windows.Forms
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$text = [System.Windows.Forms.Clipboard]::GetText([System.Windows.Forms.TextDataFormat]::UnicodeText)
[Console]::Write($text)
]]

local function executable(command)
  return vim.fn.executable(command) == 1
end

local function trim(text)
  return vim.trim(text or "")
end

local function system_result(args, stdin)
  if vim.system then
    local result = vim.system(args, {
      stdin = stdin,
      text = true,
    }):wait()

    return {
      code = result.code,
      stdout = result.stdout or "",
      stderr = result.stderr or "",
    }
  end

  local stdout = vim.fn.system(args, stdin or "")
  return {
    code = vim.v.shell_error,
    stdout = stdout or "",
    stderr = "",
  }
end

local function copyq_running()
  if not executable("copyq") then
    return false
  end

  return system_result({ "copyq", "eval", "1" }).code == 0
end

local function sysname()
  return (uv.os_uname() or {}).sysname or ""
end

local function is_wsl()
  local release = ((uv.os_uname() or {}).release or ""):lower()
  return vim.env.WSL_DISTRO_NAME ~= nil or release:match("microsoft") ~= nil
end

local function is_wayland()
  return not is_wsl() and vim.env.WAYLAND_DISPLAY ~= nil and vim.env.WAYLAND_DISPLAY ~= ""
end

local function has_swift()
  return sysname() == "Darwin" and uv.fs_stat("/usr/bin/swift") ~= nil and uv.fs_stat(macos_helper_path) ~= nil
end

local function close_handle(handle)
  if handle and not handle:is_closing() then
    handle:close()
  end
end

local function has_wayland_helper()
  if wayland_helper_available ~= nil then
    return wayland_helper_available
  end

  if not is_wayland() or not executable("python3") or uv.fs_stat(wayland_helper_path) == nil then
    wayland_helper_available = false
    return false
  end

  local result = system_result({
    "python3",
    "-c",
    "import gi; gi.require_version('Gtk', '4.0'); gi.require_version('Gdk', '4.0'); from gi.repository import Gtk, Gdk, GLib",
  })
  wayland_helper_available = result.code == 0
  return wayland_helper_available
end

local function stop_wayland_helper()
  if not wayland_helper_pid then
    return
  end

  pcall(uv.kill, wayland_helper_pid, (uv.constants and uv.constants.SIGTERM) or 15)
  wayland_helper_pid = nil
end

local function spawn_wayland_helper(payload)
  stop_wayland_helper()

  local stdin = uv.new_pipe(false)
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)
  local handle
  local state = {
    pid = nil,
    ready = false,
    exited = false,
    stderr = "",
    stdout = "",
    spawn_error = nil,
  }

  handle, state.pid = uv.spawn("python3", {
    args = { wayland_helper_path },
    stdio = { stdin, stdout, stderr },
    detached = true,
  }, function(code, signal)
    state.exited = true
    state.code = code
    state.signal = signal
    close_handle(stdin)
    close_handle(stdout)
    close_handle(stderr)
    close_handle(handle)
  end)

  if not handle then
    close_handle(stdin)
    close_handle(stdout)
    close_handle(stderr)
    return nil, "striked.nvim could not start the Wayland clipboard helper"
  end

  stdout:read_start(function(err, data)
    if err then
      state.spawn_error = err
      return
    end

    if data then
      state.stdout = state.stdout .. data
      if state.stdout:find("READY", 1, true) then
        state.ready = true
      end
    end
  end)

  stderr:read_start(function(err, data)
    if err then
      state.spawn_error = err
      return
    end

    if data then
      state.stderr = state.stderr .. data
    end
  end)

  stdin:write(vim.json.encode(vim.tbl_extend("force", payload, {
    timeout_seconds = WAYLAND_HELPER_TIMEOUT_SECONDS,
  })))
  stdin:shutdown(function()
    close_handle(stdin)
  end)

  local ok = vim.wait(1500, function()
    return state.ready or state.exited or state.spawn_error ~= nil
  end, 20)

  if not ok or not state.ready then
    if state.pid then
      pcall(uv.kill, state.pid, (uv.constants and uv.constants.SIGTERM) or 15)
    end

    close_handle(stdin)
    close_handle(stdout)
    close_handle(stderr)
    close_handle(handle)

    local detail = trim(state.stderr)
    if detail == "" then
      detail = trim(state.stdout)
    end
    if detail == "" and state.spawn_error then
      detail = tostring(state.spawn_error)
    end
    if detail == "" then
      detail = "timeout while waiting for the clipboard helper"
    end

    return nil, string.format("striked.nvim clipboard copy failed: %s", detail)
  end

  wayland_helper_pid = state.pid
  stdout:read_stop()
  stderr:read_stop()
  close_handle(stdout)
  close_handle(stderr)
  close_handle(handle)

  return {
    code = 0,
    stdout = state.stdout,
    stderr = state.stderr,
  }
end

local function powershell_command()
  if is_wsl() then
    if executable("powershell.exe") then
      return "powershell.exe"
    end

    if executable("pwsh.exe") then
      return "pwsh.exe"
    end

    return nil
  end

  if sysname():match("Windows") then
    if executable("powershell.exe") then
      return "powershell.exe"
    end

    if executable("powershell") then
      return "powershell"
    end

    if executable("pwsh.exe") then
      return "pwsh.exe"
    end

    if executable("pwsh") then
      return "pwsh"
    end
  end

  return nil
end

local function read_backend()
  local powershell = powershell_command()
  if powershell then
    return { name = powershell, kind = "powershell" }
  end

  if copyq_running() then
    return { name = "copyq", kind = "copyq" }
  end

  if sysname() == "Darwin" and executable("pbpaste") then
    return { name = "pbpaste", kind = "pbpaste" }
  end

  if executable("wl-paste") then
    return { name = "wl-paste", kind = "wayland" }
  end

  if executable("xclip") then
    return { name = "xclip", kind = "x11" }
  end

  return nil
end

local function write_backend()
  local powershell = powershell_command()
  if powershell then
    return { name = powershell, kind = "powershell", dual_format = true }
  end

  if copyq_running() then
    return { name = "copyq", kind = "copyq", dual_format = true }
  end

  if has_swift() then
    return { name = "swift", kind = "swift", dual_format = true }
  end

  if has_wayland_helper() then
    return { name = "python3-gtk", kind = "wayland_helper", dual_format = true }
  end

  if executable("wl-copy") then
    return { name = "wl-copy", kind = "wayland", dual_format = false }
  end

  if executable("xclip") then
    return { name = "xclip", kind = "x11", dual_format = false }
  end

  return nil
end

local function backend_error_message()
  return "striked.nvim could not find a clipboard backend. Install CopyQ, or ensure a supported platform clipboard tool is available."
end

local function command_error(result, description)
  local detail = trim(result.stderr) ~= "" and trim(result.stderr) or trim(result.stdout)
  if detail == "" then
    return string.format("striked.nvim %s failed", description)
  end

  return string.format("striked.nvim %s failed: %s", description, detail)
end

function M.copy_rich(payload)
  payload = payload or {}

  local backend = write_backend()
  if not backend then
    return nil, backend_error_message()
  end

  local effective = {
    text = tostring(payload.text or ""),
    html = tostring(payload.html or ""),
    html_only = payload.html_only == true or backend.dual_format ~= true,
  }

  if payload.html_only ~= true and backend.dual_format ~= true then
    return nil, string.format(
      "striked.nvim rich copy needs a dual-format clipboard backend. Install CopyQ, or use the HtmlOnly command with %s.",
      backend.name
    )
  end

  local result
  local helper_err
  if backend.kind == "copyq" then
    result = system_result({ "copyq", "eval", COPYQ_WRITE_SCRIPT }, vim.json.encode(effective))
  elseif backend.kind == "swift" then
    result = system_result({ "/usr/bin/swift", macos_helper_path }, vim.json.encode(effective))
  elseif backend.kind == "powershell" then
    result = system_result({ backend.name, "-NoProfile", "-STA", "-Command", POWERSHELL_WRITE_SCRIPT }, vim.json.encode(effective))
  elseif backend.kind == "wayland_helper" then
    result, helper_err = spawn_wayland_helper(effective)
  elseif backend.kind == "wayland" then
    result = system_result({ "wl-copy", "--type", "text/html" }, effective.html)
  elseif backend.kind == "x11" then
    result = system_result({ "xclip", "-selection", "clipboard", "-target", "text/html" }, effective.html)
  end

  if not result or result.code ~= 0 then
    if helper_err then
      return nil, helper_err
    end

    return nil, command_error(result or { stdout = "", stderr = "", code = -1 }, "clipboard copy")
  end

  return {
    backend = backend.name,
    requested_html_only = payload.html_only == true,
    html_only = effective.html_only,
    downgraded = payload.html_only ~= true and backend.dual_format ~= true,
    dual_format = effective.html_only ~= true,
  }
end

function M.read_text()
  local backend = read_backend()
  if not backend then
    return nil, backend_error_message()
  end

  local result
  if backend.kind == "powershell" then
    result = system_result({ backend.name, "-NoProfile", "-STA", "-Command", POWERSHELL_READ_SCRIPT })
  elseif backend.kind == "copyq" then
    result = system_result({ "copyq", "eval", COPYQ_READ_SCRIPT })
  elseif backend.kind == "pbpaste" then
    result = system_result({ "pbpaste" })
  elseif backend.kind == "wayland" then
    result = system_result({ "wl-paste", "--no-newline", "--type", "text" })
  elseif backend.kind == "x11" then
    result = system_result({ "xclip", "-selection", "clipboard", "-o" })
  end

  if not result or result.code ~= 0 then
    return nil, command_error(result or { stdout = "", stderr = "", code = -1 }, "clipboard read")
  end

  return result.stdout or "", {
    backend = backend.name,
  }
end

function M.copyq_running()
  return copyq_running()
end

return M
