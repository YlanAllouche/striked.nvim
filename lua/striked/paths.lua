local config = require("striked.config")

local M = {}

local function expanded_path(path)
  local text = tostring(path or "")
  if text == "" then
    return text
  end

  return vim.fn.expand(text)
end

function M.normalize(path)
  local expanded = expanded_path(path)
  if expanded == "" then
    return expanded
  end

  return vim.fs.normalize(vim.fn.fnamemodify(expanded, ":p"))
end

function M.join(...)
  local parts = { ... }
  local path = table.remove(parts, 1) or ""

  for _, part in ipairs(parts) do
    local text = tostring(part or "")
    if text ~= "" then
      if path == "" then
        path = text
      else
        path = path:gsub("/+$", "") .. "/" .. text:gsub("^/+", "")
      end
    end
  end

  return M.normalize(path)
end

function M.relative_path(base, path)
  local normalized_base = M.normalize(base):gsub("/+$", "")
  local normalized_path = M.normalize(path)
  local prefix = normalized_base .. "/"

  if normalized_path:sub(1, #prefix) == prefix then
    return normalized_path:sub(#prefix + 1)
  end

  return normalized_path
end

function M.ensure_dir(path)
  local normalized = M.normalize(path)
  if normalized == "" then
    return normalized
  end

  vim.fn.mkdir(normalized, "p")
  return normalized
end

function M.ensure_parent_dir(path)
  return M.ensure_dir(vim.fn.fnamemodify(M.normalize(path), ":h"))
end

function M.resolve_downloads_root(opts)
  opts = opts or {}

  local configured = config.get().meeting or {}
  local root = opts.folder or opts.downloads_root or configured.downloads_root or "~/Downloads"

  return M.normalize(root)
end

function M.resolve_root(opts)
  opts = opts or {}

  local configured = config.get().notes or {}
  local root = opts.root or opts.notes_root or opts.cwd or configured.root or "~/share/notes"

  return M.normalize(root)
end

function M.note_subdir(kind, opts)
  local directories = (config.get().notes or {}).directories or {}
  local root = M.resolve_root(opts)
  local relative = directories[kind] or kind

  return M.join(root, relative)
end

function M.ensure_notes_tree(opts)
  local directories = (config.get().notes or {}).directories or {}
  local root = M.ensure_dir(M.resolve_root(opts))

  for _, relative in pairs(directories) do
    M.ensure_dir(M.join(root, relative))
  end

  return root
end

return M
