local M = {}

local defaults = {
  file_patterns = { "*.md", "*.markdown", "*.mdx" },
  mappings = {
    enabled = true,
    bookmarks = "<leader>sb",
    tasks_open = "<leader>so",
    tasks_done = "<leader>sx",
    tasks_slash = "<leader>s/",
    tasks_question = "<leader>s?",
    tasks_n = "<leader>sn",
  },
  picker = {
    telescope = {
      layout_strategy = "flex",
      sorting_strategy = "ascending",
      layout_config = {
        prompt_position = "top",
      },
      preview = true,
    },
  },
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
