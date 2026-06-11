# striked.nvim

A Neovim plugin for scanning markdown tasks and note metadata from a shared notes root.

## Features

- Scans a configurable notes root, defaulting to `~/share/notes`
- Creates the notes root and default subfolders recursively before note and scan workflows
- Parses markdown task-like lines such as `- [ ]`, `- [x]`, `- [/]`, `- [?]`, `- [n]`, and `- [@]`
- Extracts inline metadata in the form `[field:: value]`
- Exposes Lua APIs for scanning, status filters, field-value filters, focused items, and date-range log queries
- Provides Telescope pickers for bookmarks, focused items, and status-based task views
- Adds prompt-driven note creation for topics, projects, sprints, and journals
- Adds journal navigation helpers for today, tomorrow, yesterday, next existing, and previous existing notes
- Supports inserting bookmarks and surfacing similar existing bookmarks first
- Lets bookmark and focused Telescope pickers open URLs directly with `<C-o>`

## Requirements

- Neovim with Lua support
- [`nvim-telescope/telescope.nvim`](https://github.com/nvim-telescope/telescope.nvim) for picker commands and default mappings

The core scan, query, note creation, and log APIs work without Telescope, but picker commands and default mappings expect Telescope.

## Installation

### lazy.nvim

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
  notes = {
    root = "~/share/notes",
    directories = {
      journal = "journal",
      sprints = "sprints",
      topics = "topics",
      projects = "projects",
    },
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
    journal_today = "<leader>jt",
    journal_tomorrow = "<leader>jn",
    journal_yesterday = "<leader>jy",
    add_bookmark = "<leader>sa",
  },
  picker = {
    telescope = {
      open_url = "<C-o>",
    },
  },
})
```

`notes.root` can also be overridden per call with `opts.root`.

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

Examples:

```markdown
- [ ] Open task [date:: 2026-06-11] [focus:: true]
- [x] Done task [completion:: 2026-06-11]
- [@] OpenAI docs [url:: https://platform.openai.com/docs] [project:: ai] [topic:: llm]
```

Recognized normalized fields:

- `project` / `projects`
- `topic` / `topics`
- `date`
- `completion`

Unknown fields are still preserved and queryable through the generic metadata APIs.

## Note Templates

All non-journal notes are created under the configured notes root with UUID filenames:

- `topics/<uuid>.md`
- `projects/<uuid>.md`
- `sprints/<uuid>.md`

Each non-journal note uses YAML frontmatter, with `id` as the first field.

Journal notes are the exception:

- directory: `journal/`
- filename: `YYYY-MM-DD.md`
- frontmatter: `title: "YYYY-MM-DD"`

Sprint notes always include these frontmatter fields:

- `id`
- `title`
- `project`
- `startDate`
- `endDate`

If sprint `startDate` or `endDate` is left empty in the prompt flow, it defaults to today.

## Commands

- `:StrikedBookmarks`
- `:StrikedTasks {status}`
- `:StrikedTasksOpen`
- `:StrikedTasksDone`
- `:StrikedTasksSlash`
- `:StrikedTasksQuestion`
- `:StrikedTasksN`
- `:StrikedFocused`
- `:StrikedFocusedPrint`
- `:StrikedAddBookmark`
- `:StrikedNewTopic`
- `:StrikedNewProject`
- `:StrikedNewSprint`
- `:StrikedJournal {YYYY-MM-DD}`
- `:StrikedJournalPrompt`
- `:StrikedJournalToday`
- `:StrikedJournalTomorrow`
- `:StrikedJournalYesterday`
- `:StrikedJournalNext`
- `:StrikedJournalPrevious`
- `:StrikedLog`

`StrikedTasksOpen` and `StrikedTasksSlash` both open the combined active-task view for statuses ` ` and `/`.

`StrikedTasksDone` opens the combined done-task view for statuses `x`, `-`, `l`, and `R`, with dated items shown first in reverse chronological order.

## Default Mappings

- `<leader>sb` bookmarks
- `<leader>s/` active tasks (` ` and `/` together)
- `<leader>sx` done tasks
- `<leader>s?` question tasks
- `<leader>sn` `n` tasks
- `<leader>sf` focused items
- `<leader>jt` journal today
- `<leader>jn` journal tomorrow
- `<leader>jy` journal yesterday
- `<leader>sa` add bookmark

Set `mappings.enabled = false` to disable them.

## Telescope URL Action

In the bookmarks and focused pickers, press `<C-o>` to open the selected entry's parsed `url` metadata.

Open order:

- `$BROWSER` if set
- `xdg-open` on Linux
- `open` on macOS
- `start` via `cmd.exe` on Windows

## Lua API

```lua
local striked = require("striked")

striked.setup(opts)
striked.scan(opts)
striked.bookmarks(opts)
striked.tasks_by_status(" ", opts)
striked.tasks_by_statuses({ " ", "/" }, opts)
striked.active_tasks(opts)
striked.done_tasks(opts)
striked.items_by_field("focus", "true", opts)
striked.focused(opts)
striked.items_between_dates("2026-06-01", "2026-06-30", opts)
striked.log_items("2026-06-01", "2026-06-30", opts)
striked.pick_bookmarks(opts)
striked.pick_active_tasks(opts)
striked.pick_done_tasks(opts)
striked.pick_focused(opts)
striked.find_similar_bookmarks({ title = "Example", url = "https://example.com" }, opts)
striked.add_bookmark({ title = "Example", url = "https://example.com" })
striked.prompt_add_bookmark(opts)
striked.create_topic({ title = "Example" })
striked.create_project({ title = "Example" })
striked.create_sprint({ title = "Sprint 42", project = "", startDate = "", endDate = "" })
striked.open_journal({ date = "2026-06-11" })
striked.journal_today(opts)
striked.journal_tomorrow(opts)
striked.journal_yesterday(opts)
striked.journal_next(opts)
striked.journal_previous(opts)
striked.build_log({ startDate = "2026-06-01", endDate = "2026-06-30" })
striked.print_focused(opts)
```

## Reporting

`striked.build_log()` and `:StrikedLog` collect items whose status is one of:

- ` `
- `x`
- `-`
- `l`
- `R`

The entry is included when either `[date:: YYYY-MM-DD]` or `[completion:: YYYY-MM-DD]` falls within the requested range.

The inserted output is a plain markdown list with statuses and metadata removed:

```markdown
- Open task
- Done task
```

`striked.print_focused()` and `:StrikedFocusedPrint` insert the same stripped markdown list format for all `[focus:: true]` items.

## Local Testing

This repository includes fixtures under `markdown_test/`.

Quick local smoke test:

```bash
nvim -u NONE
```

Then in Neovim:

```vim
:set rtp+=/home/ylan/workspaces/repos/github/YlanAllouche/striked.nvim
:lua require("striked").setup({ notes = { root = "/home/ylan/workspaces/repos/github/YlanAllouche/striked.nvim/markdown_test" } })
:StrikedBookmarks
:StrikedTasksSlash
:StrikedTasksDone
:StrikedFocused
:StrikedJournalToday
:StrikedLog
```

If you want to test the plain Lua API directly:

```vim
:lua vim.print(#require("striked").scan({ root = "/home/ylan/workspaces/repos/github/YlanAllouche/striked.nvim/markdown_test" }))
:lua vim.print(#require("striked").focused({ root = "/home/ylan/workspaces/repos/github/YlanAllouche/striked.nvim/markdown_test" }))
```
