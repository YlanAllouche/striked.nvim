local M = {}

local uv = vim.uv or vim.loop

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

local SWIFT_WRITE_SCRIPT = [[
import AppKit
import Foundation

struct Payload: Decodable {
    let text: String?
    let html: String
    let html_only: Bool?
}

let data = FileHandle.standardInput.readDataToEndOfFile()
let payload = try JSONDecoder().decode(Payload.self, from: data)
let pasteboard = NSPasteboard.general

pasteboard.clearContents()

if payload.html_only != true {
    pasteboard.setString(payload.text ?? "", forType: .string)
}

pasteboard.setString(payload.html, forType: .html)
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

local function sysname()
  return (uv.os_uname() or {}).sysname or ""
end

local function is_wsl()
  local release = ((uv.os_uname() or {}).release or ""):lower()
  return vim.env.WSL_DISTRO_NAME ~= nil or release:match("microsoft") ~= nil
end

local function has_swift()
  return sysname() == "Darwin" and uv.fs_stat("/usr/bin/swift") ~= nil
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

  if executable("copyq") then
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

  if executable("copyq") then
    return { name = "copyq", kind = "copyq", dual_format = true }
  end

  if has_swift() then
    return { name = "swift", kind = "swift", dual_format = true }
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
  return "striked.nvim could not find a clipboard backend. Install CopyQ for dual-format clipboard support, or ensure a platform clipboard tool is available."
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

  local result
  if backend.kind == "copyq" then
    result = system_result({ "copyq", "eval", COPYQ_WRITE_SCRIPT }, vim.json.encode(effective))
  elseif backend.kind == "swift" then
    result = system_result({ "/usr/bin/swift", "-" }, vim.json.encode(effective))
  elseif backend.kind == "powershell" then
    result = system_result({ backend.name, "-NoProfile", "-STA", "-Command", POWERSHELL_WRITE_SCRIPT }, vim.json.encode(effective))
  elseif backend.kind == "wayland" then
    result = system_result({ "wl-copy", "--type", "text/html" }, effective.html)
  elseif backend.kind == "x11" then
    result = system_result({ "xclip", "-selection", "clipboard", "-target", "text/html" }, effective.html)
  end

  if not result or result.code ~= 0 then
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
    result = system_result({ "wl-paste", "--no-newline", "--type", "text/plain" })
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

return M
