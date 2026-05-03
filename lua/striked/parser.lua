local M = {}

local function trim(text)
  return vim.trim(text or "")
end

local function normalize_space(text)
  return trim((text or ""):gsub("%s+", " "))
end

local function add_metadata_value(metadata, key, value)
  if not metadata[key] then
    metadata[key] = {}
  end

  table.insert(metadata[key], value)
end

local function split_list_values(values)
  local items = {}

  for _, value in ipairs(values or {}) do
    for part in tostring(value):gmatch("[^,]+") do
      local trimmed = trim(part)
      if trimmed ~= "" then
        table.insert(items, trimmed)
      end
    end
  end

  return items
end

local function first_value(values)
  if not values or #values == 0 then
    return nil
  end

  return values[1]
end

local function parse_completion(values)
  local raw = first_value(values)
  if not raw or raw == "" then
    return nil
  end

  local compact = raw:gsub("%s+", "")
  local number_text = compact:match("^(%-?%d+%.?%d*)%%?$")

  return {
    raw = raw,
    value = number_text and tonumber(number_text) or nil,
    percent = compact:sub(-1) == "%",
  }
end

local function parse_metadata(body)
  local metadata = {}
  local entries = {}
  local blocks = {}
  local plain_parts = {}
  local cursor = 1

  for start_idx, block, end_idx in body:gmatch("()(%[[%w_%-]+%s*::%s*.-%])()") do
    local key, value = block:match("^%[([%w_%-]+)%s*::%s*(.-)%]$")
    if key and value then
      local normalized_key = key:lower()
      local trimmed_value = trim(value)

      table.insert(plain_parts, body:sub(cursor, start_idx - 1))
      cursor = end_idx

      table.insert(blocks, block)
      add_metadata_value(metadata, normalized_key, trimmed_value)
      table.insert(entries, {
        key = normalized_key,
        name = key,
        value = trimmed_value,
        raw = block,
      })
    end
  end

  table.insert(plain_parts, body:sub(cursor))

  return {
    metadata = metadata,
    metadata_entries = entries,
    metadata_text = table.concat(blocks, " "),
    text = normalize_space(table.concat(plain_parts)),
  }
end

local function normalize_metadata(metadata)
  return {
    projects = vim.list_extend(
      split_list_values(metadata.project),
      split_list_values(metadata.projects)
    ),
    topics = vim.list_extend(
      split_list_values(metadata.topic),
      split_list_values(metadata.topics)
    ),
    date = first_value(metadata.date),
    completion = parse_completion(metadata.completion),
  }
end

function M.parse_line(line, context)
  local indent, marker, status, body = line:match("^(%s*)([-*+])%s+%[([^%]])%]%s*(.-)%s*$")
  if not status then
    return nil
  end

  local parsed_metadata = parse_metadata(body)
  local normalized = normalize_metadata(parsed_metadata.metadata)
  local item = {
    indent = indent,
    marker = marker,
    status = status,
    text = parsed_metadata.text,
    title = parsed_metadata.text,
    raw_text = body,
    raw_line = line,
    metadata = parsed_metadata.metadata,
    metadata_entries = parsed_metadata.metadata_entries,
    metadata_text = parsed_metadata.metadata_text,
    normalized = normalized,
    url = first_value(parsed_metadata.metadata.url),
  }

  if context then
    item.path = context.path
    item.relative_path = context.relative_path
    item.lnum = context.lnum
    item.col = context.col or 1
  end

  return item
end

return M
