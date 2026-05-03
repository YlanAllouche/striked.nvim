local config = require("striked.config")
local parser = require("striked.parser")
local pickers = require("striked.pickers")
local query = require("striked.query")

local M = {}

local function normalize_path(path)
  return vim.fs.normalize(path)
end

local function relative_path(base, path)
  local normalized_base = normalize_path(base):gsub("/$", "")
  local normalized_path = normalize_path(path)
  local prefix = normalized_base .. "/"

  if normalized_path:sub(1, #prefix) == prefix then
    return normalized_path:sub(#prefix + 1)
  end

  return normalized_path
end

local function trim(text)
  return vim.trim(text or "")
end

local function listify(value)
  if value == nil then
    return {}
  end

  if type(value) ~= "table" then
    local text = trim(tostring(value))
    return text == "" and {} or { text }
  end

  local items = {}

  for _, item in ipairs(value) do
    local text = trim(tostring(item))
    if text ~= "" then
      table.insert(items, text)
    end
  end

  return items
end

local function append_metadata(parts, key, values)
  for _, value in ipairs(listify(values)) do
    table.insert(parts, string.format("[%s:: %s]", key, value))
  end
end

local function build_bookmark_line(opts)
  local title = trim(opts.title)
  local url = trim(opts.url)

  if title == "" then
    error("striked.nvim requires opts.title to add a bookmark")
  end

  if url == "" then
    error("striked.nvim requires opts.url to add a bookmark")
  end

  local parts = { string.format("- [@] %s", title) }
  append_metadata(parts, "url", { url })
  append_metadata(parts, "project", opts.project)
  append_metadata(parts, "project", opts.projects)
  append_metadata(parts, "topic", opts.topic)
  append_metadata(parts, "topic", opts.topics)
  append_metadata(parts, "date", opts.date)
  append_metadata(parts, "completion", opts.completion)

  local extra_metadata = opts.metadata or {}
  local keys = vim.tbl_keys(extra_metadata)
  table.sort(keys)

  for _, key in ipairs(keys) do
    local normalized_key = key:lower()
    if normalized_key ~= "url"
      and normalized_key ~= "project"
      and normalized_key ~= "projects"
      and normalized_key ~= "topic"
      and normalized_key ~= "topics"
      and normalized_key ~= "date"
      and normalized_key ~= "completion"
    then
      append_metadata(parts, key, extra_metadata[key])
    end
  end

  return table.concat(parts, " ")
end

local function resolve_target(opts)
  local target = {
    path = opts.path and normalize_path(opts.path) or nil,
    buffer = opts.buffer,
    use_buffer = false,
  }

  if target.buffer == nil and not target.path then
    target.buffer = vim.api.nvim_get_current_buf()
  end

  if target.buffer then
    local raw_buffer_name = vim.api.nvim_buf_get_name(target.buffer)
    local buffer_name = raw_buffer_name ~= "" and normalize_path(raw_buffer_name) or ""

    if buffer_name ~= "" and (not target.path or target.path == buffer_name) then
      target.path = buffer_name
      target.use_buffer = true
    end
  end

  if not target.path or target.path == "" then
    error("striked.nvim needs a file-backed buffer or opts.path to add a bookmark")
  end

  return target
end

local function insert_into_buffer(buffer, line, opts)
  local line_count = vim.api.nvim_buf_line_count(buffer)
  local first_line = vim.api.nvim_buf_get_lines(buffer, 0, 1, false)[1] or ""

  if line_count == 1 and first_line == "" then
    vim.api.nvim_buf_set_lines(buffer, 0, 1, false, { line })
    return 1
  end

  local position = opts.position or config.get().bookmark.default_position or "cursor"
  local insert_at

  if opts.lnum then
    insert_at = math.max(math.min(opts.lnum, line_count), 0)
  elseif position == "end" or buffer ~= vim.api.nvim_get_current_buf() then
    insert_at = line_count
  else
    insert_at = vim.api.nvim_win_get_cursor(0)[1]
  end

  vim.api.nvim_buf_set_lines(buffer, insert_at, insert_at, false, { line })
  return insert_at + 1
end

local function insert_into_file(path, line, opts)
  local lines = vim.fn.filereadable(path) == 1 and vim.fn.readfile(path) or {}
  local line_count = #lines

  if line_count == 0 then
    table.insert(lines, line)
    vim.fn.writefile(lines, path)
    return 1
  end

  local position = opts.position or config.get().bookmark.default_position or "end"
  local insert_at

  if opts.lnum then
    insert_at = math.max(math.min(opts.lnum, line_count + 1), 1)
  elseif position == "cursor" then
    insert_at = line_count + 1
  else
    insert_at = line_count + 1
  end

  table.insert(lines, insert_at, line)
  vim.fn.writefile(lines, path)
  return insert_at
end

local function similar_notification(similar)
  if #similar == 0 then
    return
  end

  vim.notify(string.format("striked.nvim found %d similar bookmark(s)", #similar), vim.log.levels.INFO)
end

function M.add_bookmark(opts)
  opts = opts or {}

  local target = resolve_target(opts)
  local line = build_bookmark_line(opts)
  local similar = query.find_similar_bookmarks({
    title = opts.title,
    url = opts.url,
  }, opts)

  if opts.on_similar then
    opts.on_similar(similar)
  end

  if opts.skip_if_similar and #similar > 0 then
    return {
      inserted = false,
      line = line,
      path = target.path,
      similar = similar,
    }
  end

  local inserted_lnum
  if target.use_buffer then
    inserted_lnum = insert_into_buffer(target.buffer, line, opts)
  else
    inserted_lnum = insert_into_file(target.path, line, opts)
  end

  local item = parser.parse_line(line, {
    path = target.path,
    relative_path = relative_path(vim.fn.getcwd(), target.path),
    lnum = inserted_lnum,
    col = 1,
  })

  return {
    inserted = true,
    item = item,
    line = line,
    lnum = inserted_lnum,
    path = target.path,
    similar = similar,
  }
end

function M.prompt_add_bookmark(opts)
  opts = opts or {}

  vim.ui.input({ prompt = "Bookmark URL: " }, function(url)
    url = trim(url)
    if url == "" then
      return
    end

    vim.ui.input({ prompt = "Bookmark title: " }, function(title)
      title = trim(title)
      if title == "" then
        return
      end

      local preview_similar = query.find_similar_bookmarks({ title = title, url = url }, opts)
      similar_notification(preview_similar)

      if #preview_similar > 0 and opts.show_similar_picker ~= false then
        pcall(pickers.pick_items, preview_similar, {
          kind = "bookmark",
          prompt_title = "Similar Bookmarks",
        })
      end

      local result = M.add_bookmark(vim.tbl_extend("force", opts, {
        title = title,
        url = url,
      }))

      vim.notify(string.format("striked.nvim inserted bookmark at %s:%d", result.path, result.lnum), vim.log.levels.INFO)
    end)
  end)
end

return M
