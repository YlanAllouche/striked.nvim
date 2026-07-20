local M = {}
local uv = vim.uv or vim.loop

local function trim(text)
  return vim.trim(text or "")
end

local function close_handle(handle)
  if handle and not handle:is_closing() then
    handle:close()
  end
end

local function parse_headers(header_text)
  local header_lines = vim.split(header_text, "\r\n", { plain = true, trimempty = false })
  local status_line = table.remove(header_lines, 1) or ""
  local code = tonumber(status_line:match("^HTTP/%d+%.%d+%s+(%d+)%s*"))
  if not code then
    error(string.format("striked.nvim could not parse HTTP status line: %s", status_line))
  end

  local headers = {}
  for _, line in ipairs(header_lines) do
    local key, value = line:match("^([^:]+):%s*(.-)%s*$")
    if key then
      headers[key:lower()] = value
    end
  end

  return code, headers, status_line
end

local function parse_response(raw)
  local header_text, body = raw:match("^(.-)\r\n\r\n(.*)$")
  if not header_text then
    error("striked.nvim received an invalid HTTP response")
  end

  local code, headers, status_line = parse_headers(header_text)
  return {
    code = code,
    headers = headers,
    body = body,
    status_line = status_line,
  }
end

function M.request(opts)
  opts = opts or {}

  local host = opts.host or "127.0.0.1"
  local port = assert(tonumber(opts.port), "striked.nvim HTTP request needs opts.port")
  local method = opts.method or "GET"
  local path = opts.path or "/"
  local body = opts.body or ""
  local timeout = opts.timeout or 1500
  local headers = vim.tbl_extend("force", {
    Host = host,
    Connection = "close",
  }, opts.headers or {})

  if body ~= "" and headers["Content-Length"] == nil and headers["content-length"] == nil then
    headers["Content-Length"] = tostring(#body)
  end

  local request_lines = { string.format("%s %s HTTP/1.1", method, path) }
  for key, value in pairs(headers) do
    table.insert(request_lines, string.format("%s: %s", key, value))
  end
  table.insert(request_lines, "")
  table.insert(request_lines, body)

  local tcp = uv.new_tcp()
  local state = {
    done = false,
    error = nil,
    raw = "",
    content_length = nil,
    headers_complete = false,
  }

  local function fail(message)
    state.error = message
    state.done = true
  end

  local function update_completion()
    if state.done or not state.headers_complete then
      return
    end

    local header_text, response_body = state.raw:match("^(.-)\r\n\r\n(.*)$")
    if not header_text then
      return
    end

    if state.content_length == nil then
      local _, parsed_headers = parse_headers(header_text)
      state.content_length = tonumber(parsed_headers["content-length"])
      if state.content_length == nil then
        fail(string.format("striked.nvim HTTP response from %s:%d did not include Content-Length", host, port))
        return
      end
    end

    if #response_body >= state.content_length then
      state.done = true
    end
  end

  tcp:connect(host, port, function(err)
    if err then
      fail(err)
      return
    end

    tcp:write(table.concat(request_lines, "\r\n"), function(write_err)
      if write_err then
        fail(write_err)
      end
    end)
  end)

  tcp:read_start(function(err, chunk)
    if err then
      if trim(tostring(err)) == "EOF" then
        update_completion()
        if not state.done then
          fail(string.format("striked.nvim HTTP response from %s:%d closed before all bytes arrived", host, port))
        end
        return
      end

      fail(err)
      return
    end

    if type(chunk) ~= "string" or chunk == "" then
      return
    end

    state.raw = state.raw .. chunk
    if not state.headers_complete and state.raw:find("\r\n\r\n", 1, true) then
      state.headers_complete = true
    end

    update_completion()
  end)

  local ok = vim.wait(timeout, function()
    return state.done or state.error ~= nil
  end, 20)

  close_handle(tcp)

  if not ok then
    error(string.format("striked.nvim HTTP request to %s:%d timed out", host, port))
  end

  if state.error then
    error(string.format("striked.nvim HTTP request to %s:%d failed: %s", host, port, trim(tostring(state.error))))
  end

  return parse_response(state.raw)
end

return M
