local config = require("striked.config")
local parser = require("striked.parser")
local paths = require("striked.paths")

local M = {}

local uv = vim.uv or vim.loop

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
      table.insert(files, paths.normalize(path))
    end
  end
end

local function scan_file(path, root, items)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return
  end

  local relpath = paths.relative_path(root, path)
  local active_fence

  for lnum, line in ipairs(lines) do
    local fence = line:match("^%s*([`~][`~][`~]+)")

    if fence then
      local fence_char = fence:sub(1, 1)

      if not active_fence then
        active_fence = fence_char
      elseif active_fence == fence_char then
        active_fence = nil
      end
    elseif not active_fence then
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
end

function M.scan(opts)
  opts = opts or {}

  local resolved_config = config.get()
  local root = paths.ensure_notes_tree(opts)
  local matchers = build_matchers(opts.file_patterns or resolved_config.file_patterns)
  local files = {}
  local items = {}

  collect_markdown_files(root, matchers, files)
  table.sort(files)

  for _, path in ipairs(files) do
    scan_file(path, root, items)
  end

  return items
end

return M
