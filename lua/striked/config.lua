local M = {}

local defaults = {
  file_patterns = { "*.md", "*.markdown", "*.mdx" },
}

local state = {
  options = vim.deepcopy(defaults),
}

function M.defaults()
  return vim.deepcopy(defaults)
end

function M.setup(opts)
  state.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  return state.options
end

function M.get()
  return state.options
end

return M
