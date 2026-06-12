local M = {}

local function trim(text)
  return vim.trim(text or "")
end

local function is_list(value)
  if type(value) ~= "table" then
    return false
  end

  local count = 0
  for key, _ in pairs(value) do
    if type(key) ~= "number" then
      return false
    end

    count = count + 1
  end

  for index = 1, count do
    if value[index] == nil then
      return false
    end
  end

  return true
end

local function sorted_keys(value)
  local keys = {}

  for key, _ in pairs(value) do
    if type(key) == "string" and key:sub(1, 2) ~= "__" then
      table.insert(keys, key)
    end
  end

  table.sort(keys)
  return keys
end

local function encode_scalar(value)
  local value_type = type(value)
  if value_type == "boolean" or value_type == "number" then
    return tostring(value)
  end

  return vim.json.encode(tostring(value or ""))
end

local function append_key_value(lines, key, value, indent)
  local prefix = string.rep(" ", indent) .. key .. ":"

  if type(value) ~= "table" then
    table.insert(lines, prefix .. " " .. encode_scalar(value))
    return
  end

  if is_list(value) then
    if #value == 0 then
      table.insert(lines, prefix .. " []")
      return
    end

    table.insert(lines, prefix)

    for _, item in ipairs(value) do
      local item_prefix = string.rep(" ", indent + 2) .. "-"

      if type(item) ~= "table" then
        table.insert(lines, item_prefix .. " " .. encode_scalar(item))
      elseif is_list(item) then
        table.insert(lines, item_prefix)

        for _, nested in ipairs(item) do
          table.insert(lines, string.rep(" ", indent + 4) .. "- " .. encode_scalar(nested))
        end
      else
        local keys = sorted_keys(item)
        if #keys == 0 then
          table.insert(lines, item_prefix .. " {}")
        else
          local first_key = keys[1]
          local first_value = item[first_key]

          if type(first_value) == "table" then
            table.insert(lines, item_prefix .. " " .. first_key .. ":")
            append_key_value(lines, first_key, first_value, indent + 4)
            lines[#lines] = lines[#lines]:gsub("^%s+" .. vim.pesc(first_key) .. ":", string.rep(" ", indent + 4) .. first_key .. ":", 1)
          else
            table.insert(lines, item_prefix .. " " .. first_key .. ": " .. encode_scalar(first_value))
          end

          for index = 2, #keys do
            append_key_value(lines, keys[index], item[keys[index]], indent + 4)
          end
        end
      end
    end

    return
  end

  local keys = sorted_keys(value)
  if #keys == 0 then
    table.insert(lines, prefix .. " {}")
    return
  end

  table.insert(lines, prefix)
  for _, nested_key in ipairs(keys) do
    append_key_value(lines, nested_key, value[nested_key], indent + 2)
  end
end

local function decode_scalar(value)
  local text = trim(value)
  if text == "" then
    return nil
  end

  if text == "true" then
    return true
  end

  if text == "false" then
    return false
  end

  local number = tonumber(text)
  if number then
    return number
  end

  if text:sub(1, 1) == '"' and text:sub(-1) == '"' then
    local ok, decoded = pcall(vim.json.decode, text)
    if ok then
      return decoded
    end
  end

  return text
end

function M.render(fields)
  local lines = { "---" }

  for _, field in ipairs(fields or {}) do
    if field and field.key then
      if field.raw == true and type(field.value) ~= "table" then
        table.insert(lines, string.format("%s: %s", field.key, tostring(field.value or "")))
      else
        append_key_value(lines, field.key, field.value, 0)
      end
    end
  end

  table.insert(lines, "---")
  table.insert(lines, "")
  return lines
end

function M.split(lines)
  lines = lines or {}
  if lines[1] ~= "---" then
    return {}, vim.deepcopy(lines), false
  end

  for index = 2, #lines do
    if lines[index] == "---" then
      local frontmatter_lines = {}
      local body_lines = {}

      for line_index = 2, index - 1 do
        table.insert(frontmatter_lines, lines[line_index])
      end

      for line_index = index + 1, #lines do
        table.insert(body_lines, lines[line_index])
      end

      return frontmatter_lines, body_lines, true
    end
  end

  return {}, vim.deepcopy(lines), false
end

function M.top_level_scalars(lines)
  local scalars = {}

  for _, line in ipairs(lines or {}) do
    if not line:match("^%s") then
      local key, value = line:match("^([^:]+):%s*(.-)%s*$")
      if key and value ~= "" then
        scalars[key] = decode_scalar(value)
      end
    end
  end

  return scalars
end

function M.read_file(path)
  local lines = vim.fn.filereadable(path) == 1 and vim.fn.readfile(path) or {}
  local frontmatter_lines, body_lines, has_frontmatter = M.split(lines)

  return {
    lines = lines,
    frontmatter_lines = frontmatter_lines,
    body_lines = body_lines,
    has_frontmatter = has_frontmatter,
    top_level_scalars = M.top_level_scalars(frontmatter_lines),
  }
end

return M
