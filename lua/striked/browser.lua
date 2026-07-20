local config = require("striked.config")
local http = require("striked.http")
local websocket = require("striked.websocket")

local M = {}

local LOOPBACK_HOST = "127.0.0.1"

local function trim(text)
  return vim.trim(text or "")
end

local function browser_config()
  return config.get().browser or {}
end

local function browser_settings(opts)
  opts = opts or {}

  local configured = browser_config()
  local raw_ports = opts.ports or configured.ports or { 9222, 9223 }
  local ports = {}
  local seen = {}

  if opts.port ~= nil then
    raw_ports = { opts.port }
  end

  for _, value in ipairs(raw_ports) do
    local port = tonumber(value)
    if port and not seen[port] then
      seen[port] = true
      table.insert(ports, port)
    end
  end

  return {
    timeout = tonumber(opts.timeout or configured.timeout or 1500),
    ports = ports,
  }
end

local function url_title(url)
  local normalized = trim(url)
  if normalized == "" then
    return "Untitled"
  end

  local title = normalized:gsub("^https?://", "")
  title = title:gsub("/$", "")
  return title ~= "" and title or normalized
end

local function normalize_tab(tab)
  tab.title = trim(tab.title)
  tab.url = trim(tab.url)
  if tab.title == "" then
    tab.title = url_title(tab.url)
  end
  return tab
end

local function bidi_ws_url(port)
  return string.format("ws://%s:%d/session", LOOPBACK_HOST, port)
end

local function with_firefox_session(settings, port, callback)
  local client = websocket.connect(bidi_ws_url(port), { timeout = settings.timeout })
  local ok, result = pcall(function()
    client:request("session.new", { capabilities = {} })
    return callback(client)
  end)

  pcall(function()
    client:request("session.end", {})
  end)
  client:close()

  if not ok then
    error(result)
  end

  return result
end

local function firefox_title(client, context_id)
  local ok, result = pcall(function()
    return client:request("script.evaluate", {
      expression = "document.title",
      target = { context = context_id },
      awaitPromise = false,
      resultOwnership = "none",
    })
  end)

  if not ok or not result or result.type ~= "success" then
    return nil
  end

  local remote = result.result or {}
  if remote.type == "string" then
    return trim(remote.value)
  end

  return nil
end

local function firefox_backend(settings, port)
  return {
    browser = "firefox",
    protocol = "bidi",
    port = port,
    list_tabs = function()
      return with_firefox_session(settings, port, function(client)
        local tree = client:request("browsingContext.getTree", {})
        local tabs = {}

        for _, context in ipairs(tree.contexts or {}) do
          local title = firefox_title(client, context.context)
          table.insert(tabs, normalize_tab({
            id = context.context,
            title = title or context.url,
            url = context.url or "",
            browser = "firefox",
            protocol = "bidi",
            port = port,
          }))
        end

        return tabs
      end)
    end,
    close_tabs = function(tab_ids)
      return with_firefox_session(settings, port, function(client)
        for _, tab_id in ipairs(tab_ids or {}) do
          client:request("browsingContext.close", {
            context = tab_id,
            promptUnload = false,
          })
        end

        return true
      end)
    end,
  }
end

local function chromium_version(settings, port)
  local response = http.request({
    host = LOOPBACK_HOST,
    port = port,
    path = "/json/version",
    timeout = settings.timeout,
  })

  if response.code ~= 200 then
    error(string.format("striked.nvim Chromium discovery failed with HTTP %d on port %d", response.code, port))
  end

  return vim.json.decode(response.body)
end

local function chromium_browser_ws(settings, port)
  local version = chromium_version(settings, port)
  local ws_url = trim(version.webSocketDebuggerUrl)
  if ws_url == "" then
    error(string.format("striked.nvim Chromium discovery on port %d did not return a browser WebSocket URL", port))
  end
  return ws_url
end

local function with_chromium_client(settings, port, callback)
  local client = websocket.connect(chromium_browser_ws(settings, port), { timeout = settings.timeout })
  local ok, result = pcall(callback, client)
  client:close()

  if not ok then
    error(result)
  end

  return result
end

local function chromium_backend(settings, port)
  return {
    browser = "chromium",
    protocol = "cdp",
    port = port,
    list_tabs = function()
      return with_chromium_client(settings, port, function(client)
        local result = client:request("Target.getTargets", {})
        local tabs = {}

        for _, info in ipairs(result.targetInfos or {}) do
          if info.type == "page" then
            table.insert(tabs, normalize_tab({
              id = info.targetId,
              title = info.title,
              url = info.url,
              browser = "chromium",
              protocol = "cdp",
              port = port,
            }))
          end
        end

        return tabs
      end)
    end,
    close_tabs = function(tab_ids)
      return with_chromium_client(settings, port, function(client)
        for _, tab_id in ipairs(tab_ids or {}) do
          client:request("Target.closeTarget", { targetId = tab_id })
        end

        return true
      end)
    end,
  }
end

local function detect_firefox_backend(settings, port)
  local client = websocket.connect(bidi_ws_url(port), { timeout = settings.timeout })
  local ok, result = pcall(function()
    return client:request("session.status", {})
  end)
  client:close()

  if ok and result then
    return firefox_backend(settings, port)
  end

  return nil, result
end

local function detect_chromium_backend(settings, port)
  local ok, version = pcall(chromium_version, settings, port)
  if not ok then
    return nil, version
  end

  if trim(version.webSocketDebuggerUrl) == "" then
    return nil, string.format("port %d does not expose a Chromium browser WebSocket URL", port)
  end

  return chromium_backend(settings, port)
end

local function available_backends(opts)
  local settings = browser_settings(opts)
  local firefox = {}
  local chromium = {}
  local failures = {}

  for _, port in ipairs(settings.ports) do
    local firefox_backend_match, firefox_err = detect_firefox_backend(settings, port)
    if firefox_backend_match then
      table.insert(firefox, firefox_backend_match)
    else
      local chromium_backend_match, chromium_err = detect_chromium_backend(settings, port)
      if chromium_backend_match then
        table.insert(chromium, chromium_backend_match)
      else
        table.insert(failures, string.format(
          "port %d: firefox bidi: %s; chromium cdp: %s",
          port,
          trim(tostring(firefox_err)),
          trim(tostring(chromium_err))
        ))
      end
    end
  end

  return vim.list_extend(firefox, chromium), failures
end

local function probe_backend(backend)
  local ok, tabs = pcall(backend.list_tabs)
  if ok then
    return tabs
  end

  return nil, tabs
end

function M.resolve_backend(opts)
  local backends, failures = available_backends(opts)

  for _, backend in ipairs(backends) do
    local tabs = probe_backend(backend)
    if tabs then
      return backend
    end
  end

  error(string.format(
    "striked.nvim could not detect a ready Firefox BiDi or Chromium CDP browser on ports [%s]%s",
    table.concat(browser_settings(opts).ports, ", "),
    #failures > 0 and (": " .. table.concat(failures, "; ")) or ""
  ))
end

function M.list_tabs(opts)
  local backends, failures = available_backends(opts)
  local runtime_failures = vim.deepcopy(failures)

  for _, backend in ipairs(backends) do
    local tabs, err = probe_backend(backend)
    if tabs then
      return {
        browser = backend.browser,
        protocol = backend.protocol,
        port = backend.port,
        tabs = tabs,
        close_tabs = backend.close_tabs,
      }
    end

    table.insert(runtime_failures, string.format(
      "%s/%s on port %d: %s",
      backend.browser,
      backend.protocol,
      backend.port,
      trim(tostring(err))
    ))
  end

  error(string.format(
    "striked.nvim could not detect a ready Firefox BiDi or Chromium CDP browser on ports [%s]%s",
    table.concat(browser_settings(opts).ports, ", "),
    #runtime_failures > 0 and (": " .. table.concat(runtime_failures, "; ")) or ""
  ))
end

return M
