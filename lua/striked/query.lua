local scanner = require("striked.scanner")

local M = {}

local function scan_items(opts)
  if opts and opts.items then
    return opts.items
  end

  return scanner.scan(opts)
end

function M.tasks_by_status(status, opts)
  local items = scan_items(opts)
  local matches = {}

  for _, item in ipairs(items) do
    if item.status == status then
      table.insert(matches, item)
    end
  end

  return matches
end

function M.bookmarks(opts)
  return M.tasks_by_status("@", opts)
end

return M
