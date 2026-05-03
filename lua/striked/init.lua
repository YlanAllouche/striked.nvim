local config = require("striked.config")
local query = require("striked.query")
local scanner = require("striked.scanner")

local M = {}

function M.setup(opts)
  return config.setup(opts)
end

function M.scan(opts)
  return scanner.scan(opts)
end

function M.bookmarks(opts)
  return query.bookmarks(opts)
end

function M.tasks_by_status(status, opts)
  return query.tasks_by_status(status, opts)
end

return M
