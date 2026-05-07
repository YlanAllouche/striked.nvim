# striked.nvim

A Neovim plugin for scanning markdown tasks and bookmark-like entries from the current working directory.

In v1, bookmarks are regular task items whose status is `@`.

## Features

- Recursively scans the current Neovim working directory
- Parses markdown task-like lines such as `- [ ]`, `- [x]`, `- [/]`, `- [?]`, `- [n]`, and `- [@]`
- Extracts inline metadata in the form `[field:: value]`
- Exposes plain Lua APIs for scanning, querying by status, and bookmark lookup
- Provides Telescope pickers for bookmarks and status-based task views
- Supports inserting bookmarks and surfacing similar existing bookmarks first

## Requirements

- Neovim with Lua support
- [`nvim-telescope/telescope.nvim`](https://github.com/nvim-telescope/telescope.nvim) for picker commands and default mappings

The core scan and query APIs work without Telescope, but `:StrikedBookmarks`, `:StrikedTasks...`, `:StrikedAddBookmark`, and the default mappings are intended to be used with Telescope installed.

## Installation

### lazy.nvim

Typical setup:

```lua
{
  "YlanAllouche/striked.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" },
  opts = {},
}
```

If your `lazy.nvim` config uses `defaults.lazy = true`, make this a start plugin so its commands and mappings are registered automatically:

```lua
{
  "YlanAllouche/striked.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" },
  lazy = false,
  opts = {},
}
```

## Setup

Minimal setup:

```lua
require("striked").setup()
```

With options:

```lua
require("striked").setup({
  file_patterns = { "*.md", "*.markdown", "*.mdx" },
  mappings = {
    enabled = true,
    bookmarks = "<leader>sb",
    tasks_open = "<leader>so",
    tasks_done = "<leader>sx",
    tasks_slash = "<leader>s/",
    tasks_question = "<leader>s?",
    tasks_n = "<leader>sn",
    add_bookmark = "<leader>sa",
  },
  bookmark = {
    default_position = "cursor",
  },
})
```

## Supported Syntax

Task-like lines:

```markdown
- [ ] Open task
- [x] Done task
- [/] In progress task
- [?] Unclear task
- [n] Note-like task
- [@] Bookmark title [url:: https://example.com]
```

Metadata fields:

```markdown
[field:: value]
```

Recognized normalized fields:

- `project` / `projects`
- `topic` / `topics`
- `date`
- `completion`

Unknown fields are still preserved in the parsed metadata table.

## Commands

- `:StrikedBookmarks`
- `:StrikedTasks {status}`
- `:StrikedTasksOpen`
- `:StrikedTasksDone`
- `:StrikedTasksSlash`
- `:StrikedTasksQuestion`
- `:StrikedTasksN`
- `:StrikedAddBookmark`

## Default Mappings

- `<leader>sb` bookmarks
- `<leader>so` open tasks
- `<leader>sx` done tasks
- `<leader>s/` slash tasks
- `<leader>s?` question tasks
- `<leader>sn` `n` tasks
- `<leader>sa` add bookmark

Set `mappings.enabled = false` to disable them.

## Lua API

```lua
local striked = require("striked")

striked.setup(opts)
striked.scan(opts)
striked.bookmarks(opts)
striked.tasks_by_status(" ", opts)
striked.tasks_by_status("@", opts)
striked.tasks_by_status("x", opts)
striked.tasks_by_status("/", opts)
striked.tasks_by_status("?", opts)
striked.tasks_by_status("n", opts)
striked.pick_bookmarks(opts)
striked.pick_tasks_by_status(" ", opts)
striked.find_similar_bookmarks({ title = "Example", url = "https://example.com" }, opts)
striked.add_bookmark({ title = "Example", url = "https://example.com" })
striked.prompt_add_bookmark(opts)
```

The scanner always works from Neovim's current working directory unless you override `opts.cwd`.

## Local Testing

This repository includes fixtures under `markdown_test/`.

Quick local smoke test:

```bash
nvim -u NONE
```

Then in Neovim:

```vim
:set rtp+=/home/ylan/workspaces/repos/github/YlanAllouche/striked.nvim
:lua require("striked").setup()
:cd /home/ylan/workspaces/repos/github/YlanAllouche/striked.nvim/markdown_test
:StrikedBookmarks
:StrikedTasksOpen
:StrikedAddBookmark
```

If you want to test the plain Lua API directly:

```vim
:lua vim.print(#require("striked").scan())
:lua vim.print(#require("striked").bookmarks())
```
