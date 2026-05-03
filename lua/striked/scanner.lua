local config = require("striked.config")
local parser = require("striked.parser")

local M = {}

local uv = vim.uv or vim.loop

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

local function glob_to_pattern(glob)
  return "^" .. vim.pesc(glob):gsub("%%%*", ".*"):gsub("%%%?", ".") .. "$"
end

local function build_matchers(patterns)
  local matchers = {}

  for _, pattern in ipairs(patterns or {}) do
    table.insert(matchers, glob_to_pattern(pattern:lower()))
  end

  return matchers
end

local function matches_any(name, matchers)
  local lowered = name:lower()

  for _, matcher in ipairs(matchers) do
    if lowered:match(matcher) then
      return true
    end
  end

  return false
end

local function collect_markdown_files(root, matchers, files)
  local handle = uv.fs_scandir(root)
  if not handle then
    return
  end

  while true do
    local name, entry_type = uv.fs_scandir_next(handle)
    if not name then
      break
    end

    local path = root .. "/" .. name

    if entry_type == "directory" then
      if name ~= ".git" then
        collect_markdown_files(path, matchers, files)
      end
    elseif entry_type == "file" and matches_any(name, matchers) then
      table.insert(files, normalize_path(path))
    end
  end
end

local function scan_file(path, cwd, items)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return
  end

  local relpath = relative_path(cwd, path)

  for lnum, line in ipairs(lines) do
    local item = parser.parse_line(line, {
      path = path,
      relative_path = relpath,
      lnum = lnum,
      col = 1,
    })

    if item then
      table.insert(items, item)
    end
  end
end

function M.scan(opts)
  opts = opts or {}

  local resolved_config = config.get()
  local cwd = normalize_path(opts.cwd or vim.fn.getcwd())
  local matchers = build_matchers(opts.file_patterns or resolved_config.file_patterns)
  local files = {}
  local items = {}

  collect_markdown_files(cwd, matchers, files)
  table.sort(files)

  for _, path in ipairs(files) do
    scan_file(path, cwd, items)
  end

  return items
end

return M
