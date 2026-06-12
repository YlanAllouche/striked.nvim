local M = {}

local defaults = {
  file_patterns = { "*.md", "*.markdown", "*.mdx" },
  notes = {
    root = "~/share/notes",
    directories = {
      journal = "journal",
      meetings = "meetings",
      sprints = "sprints",
      topics = "topics",
      projects = "projects",
    },
  },
  meeting = {
    downloads_root = "~/Downloads",
    delete_ics_after_import = true,
  },
  mappings = {
    enabled = true,
    bookmarks = "<leader>sb",
    tasks_open = false,
    tasks_done = "<leader>sx",
    tasks_slash = "<leader>s/",
    tasks_question = "<leader>s?",
    tasks_n = "<leader>sn",
    focused = "<leader>sf",
    meeting_import = "<leader>jm",
    journal_today = "<leader>jt",
    journal_tomorrow = "<leader>jn",
    journal_yesterday = "<leader>jy",
    add_bookmark = "<leader>sa",
  },
  bookmark = {
    default_position = "cursor",
  },
  picker = {
    telescope = {
      layout_strategy = "flex",
      sorting_strategy = "ascending",
      open_url = "<C-o>",
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
