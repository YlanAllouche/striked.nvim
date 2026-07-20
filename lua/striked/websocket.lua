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

local function apply_mask(payload, mask)
  local masked = {}
  for index = 1, #payload do
    local value = payload:byte(index)
    local mask_value = mask:byte(((index - 1) % 4) + 1)
    masked[index] = string.char(bit.bxor(value, mask_value))
  end
  return table.concat(masked)
end

local function parse_url(url)
  local host, port, path = tostring(url):match("^ws://([^:/]+):(%d+)(/.*)$")
  if not host then
    error(string.format("striked.nvim expected a ws:// URL, got %q", url))
  end

  return host, tonumber(port), path
end

local function parse_http_headers(header_text)
  local lines = vim.split(header_text, "\r\n", { plain = true, trimempty = false })
  local status_line = table.remove(lines, 1) or ""
  local code = tonumber(status_line:match("^HTTP/%d+%.%d+%s+(%d+)"))
  local headers = {}

  for _, line in ipairs(lines) do
    local key, value = line:match("^([^:]+):%s*(.-)%s*$")
    if key then
      headers[key:lower()] = value
    end
  end

  return code, headers, status_line
end

local function parse_frame(buffer)
  if #buffer < 2 then
    return nil
  end

  local first = buffer:byte(1)
  local second = buffer:byte(2)
  local fin = bit.band(first, 0x80) ~= 0
  local opcode = bit.band(first, 0x0f)
  local masked = bit.band(second, 0x80) ~= 0
  local length = bit.band(second, 0x7f)
  local index = 3

  if length == 126 then
    if #buffer < 4 then
      return nil
    end

    length = (buffer:byte(3) * 256) + buffer:byte(4)
    index = 5
  elseif length == 127 then
    if #buffer < 10 then
      return nil
    end

    length = 0
    for byte_index = 3, 10 do
      length = (length * 256) + buffer:byte(byte_index)
    end
    index = 11
  end

  local mask
  if masked then
    if #buffer < index + 3 then
      return nil
    end
    mask = buffer:sub(index, index + 3)
    index = index + 4
  end

  local end_index = index + length - 1
  if #buffer < end_index then
    return nil
  end

  local payload = length > 0 and buffer:sub(index, end_index) or ""
  if masked then
    payload = apply_mask(payload, mask)
  end

  return {
    fin = fin,
    opcode = opcode,
    payload = payload,
    bytes = end_index,
  }
end

local Client = {}
Client.__index = Client

function Client:_send_frame(opcode, payload)
  payload = payload or ""
  local mask = string.char(0x12, 0x34, 0x56, 0x78)
  local frame = string.char(bit.bor(0x80, opcode))
    .. string.char(bit.bor(0x80, #payload < 126 and #payload or (#payload < 65536 and 126 or 127)))

  if #payload >= 126 and #payload < 65536 then
    frame = string.char(bit.bor(0x80, opcode)) .. string.char(bit.bor(0x80, 126)) .. string.char(math.floor(#payload / 256), #payload % 256)
  elseif #payload >= 65536 then
    frame = string.char(bit.bor(0x80, opcode)) .. string.char(bit.bor(0x80, 127)) .. string.char(0, 0, 0, 0, math.floor(#payload / 16777216) % 256, math.floor(#payload / 65536) % 256, math.floor(#payload / 256) % 256, #payload % 256)
  end

  self.tcp:write(frame .. mask .. apply_mask(payload, mask), function(err)
    if err then
      self.state.error = err
    end
  end)
end

function Client:_handle_message(payload)
  local ok, message = pcall(vim.json.decode, payload)
  if not ok then
    self.state.last_payload = payload
    return
  end

  if message.id ~= nil then
    self.state.responses[message.id] = message
  else
    table.insert(self.state.events, message)
  end
end

function Client:_drain_buffer()
  while true do
    local frame = parse_frame(self.state.buffer)
    if not frame then
      return
    end

    self.state.buffer = self.state.buffer:sub(frame.bytes + 1)

    if frame.opcode == 0x8 then
      self.state.closed = true
      close_handle(self.tcp)
      return
    elseif frame.opcode == 0x9 then
      self:_send_frame(0xA, frame.payload)
    elseif frame.opcode == 0x1 then
      if not frame.fin then
        self.state.error = "striked.nvim does not support fragmented WebSocket messages"
        return
      end
      self:_handle_message(frame.payload)
    end
  end
end

function Client:request(method, params)
  self.state.next_id = self.state.next_id + 1
  local id = self.state.next_id
  self:_send_frame(0x1, vim.json.encode({
    id = id,
    method = method,
    params = params or {},
  }))

  local ok = vim.wait(self.timeout, function()
    return self.state.responses[id] ~= nil or self.state.error ~= nil or self.state.closed
  end, 20)

  if not ok then
    error(string.format("striked.nvim WebSocket request timed out: %s", method))
  end

  if self.state.error then
    error(string.format("striked.nvim WebSocket request failed: %s", trim(tostring(self.state.error))))
  end

  local response = self.state.responses[id]
  self.state.responses[id] = nil

  if not response then
    error(string.format("striked.nvim WebSocket closed before responding to %s", method))
  end

  if response.type == "error" then
    error(response.message or response.error or string.format("protocol error for %s", method))
  end

  if response.error then
    local detail = response.error.message or response.error.code or response.error
    error(type(detail) == "string" and detail or vim.inspect(detail))
  end

  return response.result or response
end

function Client:close()
  if self.state.closed then
    return
  end

  pcall(function()
    self:_send_frame(0x8, "")
  end)
  self.state.closed = true
  close_handle(self.tcp)
end

function M.connect(url, opts)
  opts = opts or {}

  local host, port, path = parse_url(url)
  local tcp = uv.new_tcp()
  local state = {
    handshake_done = false,
    buffer = "",
    headers = nil,
    responses = {},
    events = {},
    next_id = 0,
    error = nil,
    closed = false,
  }

  tcp:connect(host, port, function(err)
    if err then
      state.error = err
      return
    end

    local request = table.concat({
      string.format("GET %s HTTP/1.1", path),
      string.format("Host: %s:%d", host, port),
      "Upgrade: websocket",
      "Connection: Upgrade",
      "Sec-WebSocket-Version: 13",
      "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==",
      "",
      "",
    }, "\r\n")

    tcp:write(request, function(write_err)
      if write_err then
        state.error = write_err
      end
    end)
  end)

  local client = setmetatable({
    tcp = tcp,
    state = state,
    timeout = opts.timeout or 1500,
  }, Client)

  tcp:read_start(function(err, chunk)
    if err then
      state.error = err
      return
    end

    if chunk == nil then
      state.closed = true
      return
    end

    state.buffer = state.buffer .. chunk

    if not state.handshake_done then
      local header_text, rest = state.buffer:match("^(.-)\r\n\r\n(.*)$")
      if not header_text then
        return
      end

      local code, headers, status_line = parse_http_headers(header_text)
      if code ~= 101 then
        state.error = status_line
        return
      end

      state.handshake_done = true
      state.headers = headers
      state.buffer = rest or ""
    end

    client:_drain_buffer()
  end)

  local ok = vim.wait(client.timeout, function()
    return state.handshake_done or state.error ~= nil
  end, 20)

  if not ok then
    close_handle(tcp)
    error(string.format("striked.nvim WebSocket handshake timed out: %s", url))
  end

  if state.error then
    close_handle(tcp)
    error(string.format("striked.nvim WebSocket handshake failed: %s", trim(tostring(state.error))))
  end

  return client
end

return M
