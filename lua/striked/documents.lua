local dates = require("striked.dates")
local frontmatter = require("striked.frontmatter")
local paths = require("striked.paths")

local M = {}
local uv = vim.uv or vim.loop

local function trim(text)
  return vim.trim(text or "")
end

local function collect_markdown_files(directory)
  local files = {}
  local handle = uv.fs_scandir(directory)

  if not handle then
    return files
  end

  while true do
    local name, entry_type = uv.fs_scandir_next(handle)
    if not name then
      break
    end

    if entry_type == "file" and name:lower():match("%.md$") then
      table.insert(files, paths.join(directory, name))
    end
  end

  table.sort(files)
  return files
end

local function sort_by_date_desc(items)
  table.sort(items, function(left, right)
    local left_date = trim(left.date)
    local right_date = trim(right.date)

    if dates.is_valid(left_date) and dates.is_valid(right_date) and left_date ~= right_date then
      return dates.compare(left_date, right_date) > 0
    end

    if left_date ~= right_date then
      return left_date > right_date
    end

    if left.title ~= right.title then
      return left.title < right.title
    end

    return left.path < right.path
  end)

  return items
end

function M.meetings(opts)
  opts = opts or {}

  local directory = paths.ensure_dir(paths.note_subdir("meetings", opts))
  local items = {}

  for _, path in ipairs(collect_markdown_files(directory)) do
    local document = frontmatter.read_file(path)
    local title = trim(document.top_level_scalars.title or vim.fn.fnamemodify(path, ":t:r"))
    local date = trim(document.top_level_scalars.date or "")

    table.insert(items, {
      kind = "meeting",
      title = title ~= "" and title or vim.fn.fnamemodify(path, ":t:r"),
      date = date,
      path = path,
      relative_path = paths.relative_path(paths.resolve_root(opts), path),
      lnum = 1,
      col = 1,
      raw_line = title,
    })
  end

  return sort_by_date_desc(items)
end

function M.journals(opts)
  opts = opts or {}

  local directory = paths.ensure_dir(paths.note_subdir("journal", opts))
  local items = {}

  for _, path in ipairs(collect_markdown_files(directory)) do
    local date = vim.fn.fnamemodify(path, ":t:r")
    if dates.is_valid(date) then
      table.insert(items, {
        kind = "journal",
        title = date,
        date = date,
        path = path,
        relative_path = paths.relative_path(paths.resolve_root(opts), path),
        lnum = 1,
        col = 1,
        raw_line = date,
      })
    end
  end

  return sort_by_date_desc(items)
end

return M
