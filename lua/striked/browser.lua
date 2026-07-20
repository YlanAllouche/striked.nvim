local config = require("striked.config")
local http = require("striked.http")
local websocket = require("striked.websocket")

local M = {}

local function trim(text)
  return vim.trim(text or "")
end

local function browser_config()
  return config.get().browser or {}
end

local function settings_for(name, opts)
  local configured = browser_config()[name] or {}
  opts = opts or {}

  return {
    name = name,
    host = opts.host or configured.host or "127.0.0.1",
    port = tonumber(opts.port or configured.port),
    timeout = tonumber(opts.timeout or browser_config().timeout or 1500),
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

local function firefox_ws_url(settings)
  return string.format("ws://%s:%d/session", settings.host, settings.port)
end

local function with_firefox_session(settings, callback)
  local client = websocket.connect(firefox_ws_url(settings), { timeout = settings.timeout })
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

local function firefox_backend(settings)
  return {
    browser = "firefox",
    protocol = "bidi",
    list_tabs = function()
      return with_firefox_session(settings, function(client)
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
          }))
        end

        return tabs
      end)
    end,
    close_tabs = function(tab_ids)
      return with_firefox_session(settings, function(client)
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

local function chromium_version(settings)
  local response = http.request({
    host = settings.host,
    port = settings.port,
    path = "/json/version",
    timeout = settings.timeout,
  })

  if response.code ~= 200 then
    error(string.format("striked.nvim Chromium discovery failed with HTTP %d", response.code))
  end

  return vim.json.decode(response.body)
end

local function chromium_browser_ws(settings)
  local version = chromium_version(settings)
  local ws_url = trim(version.webSocketDebuggerUrl)
  if ws_url == "" then
    error("striked.nvim Chromium discovery did not return a browser WebSocket URL")
  end
  return ws_url
end

local function with_chromium_client(settings, callback)
  local client = websocket.connect(chromium_browser_ws(settings), { timeout = settings.timeout })
  local ok, result = pcall(callback, client)
  client:close()

  if not ok then
    error(result)
  end

  return result
end

local function chromium_backend(settings)
  return {
    browser = "chromium",
    protocol = "cdp",
    list_tabs = function()
      return with_chromium_client(settings, function(client)
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
            }))
          end
        end

        return tabs
      end)
    end,
    close_tabs = function(tab_ids)
      return with_chromium_client(settings, function(client)
        for _, tab_id in ipairs(tab_ids or {}) do
          client:request("Target.closeTarget", { targetId = tab_id })
        end

        return true
      end)
    end,
  }
end

local function available_backends(opts)
  opts = opts or {}

  return {
    firefox_backend(settings_for("firefox", opts.firefox or opts)),
    chromium_backend(settings_for("chromium", opts.chromium or opts)),
  }
end

local function probe_backend(backend)
  local ok, tabs = pcall(backend.list_tabs)
  if ok then
    return tabs
  end

  return nil, tabs
end

function M.resolve_backend(opts)
  local failures = {}

  for _, backend in ipairs(available_backends(opts)) do
    local tabs = probe_backend(backend)
    if tabs then
      return backend
    end

    table.insert(failures, backend.browser)
  end

  error(string.format("striked.nvim could not talk to a ready browser via Firefox BiDi or Chromium CDP (%s)", table.concat(failures, ", ")))
end

function M.list_tabs(opts)
  local failures = {}

  for _, backend in ipairs(available_backends(opts)) do
    local tabs, err = probe_backend(backend)
    if tabs then
      return {
        browser = backend.browser,
        protocol = backend.protocol,
        tabs = tabs,
        close_tabs = backend.close_tabs,
      }
    end

    table.insert(failures, string.format("%s: %s", backend.browser, trim(tostring(err))))
  end

  error(string.format("striked.nvim could not talk to a ready browser via Firefox BiDi or Chromium CDP (%s)", table.concat(failures, "; ")))
end

return M
