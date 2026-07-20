# striked.nvim

A Neovim plugin for scanning markdown tasks and note metadata from a shared notes root.

## Features

- Scans a configurable notes root, defaulting to `~/share/notes`
- Creates the notes root and default subfolders recursively before note and scan workflows
- Parses markdown task-like lines such as `- [ ]`, `- [x]`, `- [/]`, `- [?]`, `- [n]`, and `- [@]`
- Extracts inline metadata in the form `[field:: value]`
- Exposes Lua APIs for scanning, status filters, field-value filters, focused items, and date-range log queries
- Provides Telescope pickers for bookmarks, focused items, status-based task views, meetings, journals, and browser tabs
- Adds prompt-driven note creation for topics, projects, sprints, meetings, and journals
- Adds journal navigation helpers for today, tomorrow, yesterday, next existing, and previous existing notes
- Imports manually exported Teams/Outlook `.ics` files into meeting notes
- Supports inserting bookmarks and surfacing similar existing bookmarks first
- Lets bookmark, focused, and browser tab Telescope pickers open URLs directly with `<C-o>`
- Adds a richer markdown clipboard flow for markdown-to-Teams paste workflows, including metadata badges and Teams-safe H1 rendering
- Adds explicit HTML preview commands for current markdown and clipboard markdown

## Requirements

- Neovim with Lua support
- [`nvim-telescope/telescope.nvim`](https://github.com/nvim-telescope/telescope.nvim) for picker commands and default mappings

The core scan, query, note creation, and log APIs work without Telescope, but picker commands and default mappings expect Telescope.

For the rich clipboard proof of concept, `pandoc` is required.

Clipboard backends:

- Linux: `copyq` is recommended for `text/plain + text/html`; on Wayland, `python3-gi` with GTK4 is also supported for dual-format clipboard publishing
- macOS: a checked-in `/usr/bin/swift` helper is used to publish plain text plus HTML; `copyq` is not required
- Windows and WSL: `powershell(.exe)` is used to publish plain text plus HTML

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
  browser = {
    timeout = 1500,
    ports = { 9222, 9223 },
  },
  rich_markdown = {
    teams_h1 = true,
    render_metadata = true,
  },
  mappings = {
    enabled = true,
    bookmarks = "<leader>sb",
    copy_markdown_rich = "<leader>jY",
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
    journal_next = "<leader>jN",
    journal_previous = "<leader>jP",
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

Browser defaults:

- Browser ports default to `9222` and `9223`
- striked probes those ports on `127.0.0.1`
- if a port answers as Firefox BiDi, that backend is preferred
- otherwise, if a port answers as Chromium CDP, that backend is used

If your browsers use different ports, override `browser.ports` in setup.

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

- `meetings/<uuid>.md`
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

Meeting notes include:

- `id`
- `title`
- `project`
- `date`
- `startAt`
- `endAt`
- `detail`
- `attendees`

Imported meeting metadata such as `fullDay`, `seriesId`, `occurrenceId`, `sourceKey`, `status`, `location`, `joinUrl`, `organizer`, and Teams-specific fields live under `detail:`.

Attendees are grouped for readability under categories such as:

- `required`
- `optional`
- `chair`
- `nonParticipant`
- `tentative`
- `declined`
- `delegated`
- `other`

Empty attendee buckets are omitted.

Imported recurring meeting occurrences append the occurrence date to the note title, for example `Weekly Sync (2026-06-22)`.

## Commands

- `:StrikedBookmarks`
- `:StrikedTasks {status}`
- `:StrikedTasksOpen`
- `:StrikedTasksDone`
- `:StrikedTasksSlash`
- `:StrikedTasksQuestion`
- `:StrikedTasksN`
- `:StrikedFocused`
- `:StrikedMeetings`
- `:StrikedJournals`
- `:StrikedBrowserTabs`
- `:StrikedFocusedPrint`
- `:StrikedAddBookmark`
- `:StrikedNewTopic`
- `:StrikedNewProject`
- `:StrikedNewSprint`
- `:StrikedNewMeeting`
- `:StrikedIngestMeetingIcs[!] [path-or-folder]`
- `:StrikedJournal {YYYY-MM-DD}`
- `:StrikedJournalPrompt`
- `:StrikedJournalToday`
- `:StrikedJournalTomorrow`
- `:StrikedJournalYesterday`
- `:StrikedJournalNext`
- `:StrikedJournalPrevious`
- `:StrikedLog`
- `:'<,'>StrikedCopyMarkdownRich`
- `:'<,'>StrikedCopyMarkdownHtmlOnly`
- `:StrikedClipboardRich`
- `:StrikedClipboardHtmlOnly`
- `:'<,'>StrikedPreviewMarkdownHtml`
- `:StrikedPreviewClipboardHtml`

`StrikedTasksOpen` and `StrikedTasksSlash` both open the combined active-task view for statuses ` ` and `/`.

`StrikedTasksDone` opens the combined done-task view for statuses `x`, `-`, `l`, and `R`, with dated items shown first in reverse chronological order.

## Default Mappings

- `<leader>sb` bookmarks
- `<leader>jY` rich copy selected markdown, or whole buffer in normal mode
- `<leader>s/` active tasks (` ` and `/` together)
- `<leader>sx` done tasks
- `<leader>s?` question tasks
- `<leader>sn` `n` tasks
- `<leader>sf` focused items
- `<leader>jm` import latest meeting ICS
- `<leader>jt` journal today
- `<leader>jn` journal tomorrow
- `<leader>jy` journal yesterday
- `<leader>jN` journal next
- `<leader>jP` journal previous
- `<leader>sa` add bookmark

Set `mappings.enabled = false` to disable them.

## Telescope URL Action

In the bookmarks, focused, and browser tabs pickers, press `<C-o>` to open the selected entry's parsed `url` metadata.

Open order:

- `open` on macOS
- `$BROWSER` if set
- `xdg-open` on Linux
- `start` via `cmd.exe` on Windows

## Meetings And Journals Pickers

- `:StrikedMeetings` lists meeting notes as `date | title | path`
- `:StrikedJournals` lists journal pages as `date | path`
- selecting an entry opens the matching note

## Browser Tabs Picker

`:StrikedBrowserTabs` probes browsers in this order:

- Firefox over WebDriver BiDi
- Chromium over CDP

Picker actions:

- `Enter` inserts the selected tab, or all multi-selected tabs, as bookmarks in the current buffer and keeps the browser tabs open
- `<C-d>` inserts the selected tab(s) as bookmarks and then closes those browser tabs
- `<C-o>` opens the selected tab URL locally

Inserted browser bookmarks include:

- `[@]` bookmark status
- title
- `url`
- today’s `[date:: YYYY-MM-DD]`

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
striked.meetings(opts)
striked.journals(opts)
striked.items_between_dates("2026-06-01", "2026-06-30", opts)
striked.log_items("2026-06-01", "2026-06-30", opts)
striked.pick_bookmarks(opts)
striked.pick_active_tasks(opts)
striked.pick_done_tasks(opts)
striked.pick_focused(opts)
striked.pick_meetings(opts)
striked.pick_journals(opts)
striked.pick_browser_tabs(opts)
striked.find_similar_bookmarks({ title = "Example", url = "https://example.com" }, opts)
striked.add_bookmark({ title = "Example", url = "https://example.com" })
striked.prompt_add_bookmark(opts)
striked.create_topic({ title = "Example" })
striked.create_project({ title = "Example" })
striked.create_sprint({ title = "Sprint 42", project = "", startDate = "", endDate = "" })
striked.create_meeting({ title = "Weekly Sync", project = "", date = "2026-06-22", fullDay = false, attendees = {} })
striked.ingest_meeting_ics({ path = "~/Downloads/invite.ics", delete_source = true, open = true })
striked.open_journal({ date = "2026-06-11" })
striked.journal_today(opts)
striked.journal_tomorrow(opts)
striked.journal_yesterday(opts)
striked.journal_next(opts)
striked.journal_previous(opts)
striked.build_log({ startDate = "2026-06-01", endDate = "2026-06-30" })
striked.print_focused(opts)
striked.copy_markdown_rich({ line1 = 1, line2 = 20 })
striked.copy_markdown_html_only({ line1 = 1, line2 = 20 })
striked.preview_markdown_html({ line1 = 1, line2 = 20 })
striked.upgrade_clipboard_rich()
striked.upgrade_clipboard_html_only()
striked.preview_clipboard_html()
```

## Meeting Import

`striked.ingest_meeting_ics()` accepts either:

- `path` to a specific `.ics` file
- `path` to a directory
- `folder` to a directory
- no source at all, in which case it uses `~/Downloads`

When a directory is used, the importer selects the newest `.ics` file by created/modified time.

Default behavior:

- import the selected `.ics`
- create or update a meeting note under `meetings/`
- open the created or updated note in the current buffer
- delete the consumed `.ics`

Options:

- `open = false` keeps the current buffer unchanged
- `delete_source = false` preserves the consumed `.ics`

For the command form, `:StrikedIngestMeetingIcs!` is the keep-source variant.

If the importer sees the same meeting occurrence again, it finds the existing note through `UID + RECURRENCE-ID` and updates only the frontmatter, leaving the note body untouched.

`X-ALT-DESC` is used as a fallback to improve Teams metadata extraction when the plain `DESCRIPTION` does not contain everything needed.

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

## Rich Clipboard

Proof-of-concept commands:

- `:'<,'>StrikedCopyMarkdownRich` converts the selected markdown line range, or the whole buffer when no range is given, to HTML with `pandoc` and publishes both plain text and HTML to the system clipboard when a dual-format backend is available
- `:'<,'>StrikedCopyMarkdownHtmlOnly` does the same conversion but publishes HTML only
- `:StrikedClipboardRich` reads the current system clipboard text, converts it with `pandoc`, then republishes it as rich clipboard content while preserving the original plain-text payload
- `:StrikedClipboardHtmlOnly` upgrades the current clipboard text to HTML only

Default shortcut:

- `<leader>jY` copies the visual selection as rich markdown in visual mode, or the whole current buffer in normal mode

When rich clipboard publishing fails and `copyq` is not running, striked falls back to writing a temporary HTML preview file and opening it in the browser so the rendered content can still be copied manually into Teams.

Current normalization before `pandoc`:

- strips YAML frontmatter
- renders inline metadata as emoji badges by default for tags, dates, completion, focus, and active state
- maps custom task states such as `- [ ]`, `- [x]`, `- [-]`, `- [/]`, `- [?]`, `- [n]`, `- [l]`, and `- [R]` to emoji bullets, with done-like states rendered as strikethrough text for the task title only
- converts bookmark items such as `- [@] Title [url:: ...]` to `🔖` links while preserving rendered metadata badges
- when copying the whole buffer, renders YAML frontmatter as a metadata table before the body content
- when `rich_markdown.teams_h1 = true`, renders `# H1` lines as bold `🔷` paragraphs instead of HTML `<h1>` headings for better Teams paste results

Default task symbols:

- ` ` -> `📌`
- `x` -> `✅`
- `-` -> `🛑`
- `/` -> `🚧`
- `l` -> `📜`
- `R` -> `🏆`
- `?` -> `❓`
- `n` -> `📝`
- `@` -> `🔖`

Set `rich_markdown.render_metadata = false` if you want the older stripped-metadata behavior.

## HTML Preview

- `:'<,'>StrikedPreviewMarkdownHtml` renders the selected range, or the whole buffer, into a temporary HTML file and opens it in the browser
- `:StrikedPreviewClipboardHtml` reads clipboard text, renders it as markdown HTML, and opens that preview in the browser

If a dual-format clipboard backend is unavailable, the default rich-copy commands report that explicitly. Use the `HtmlOnly` variants when you intentionally want an HTML-only clipboard payload.

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
:StrikedIngestMeetingIcs!
:StrikedJournalToday
:StrikedLog
```

If you want to test the plain Lua API directly:

```vim
:lua vim.print(#require("striked").scan({ root = "/home/ylan/workspaces/repos/github/YlanAllouche/striked.nvim/markdown_test" }))
:lua vim.print(#require("striked").focused({ root = "/home/ylan/workspaces/repos/github/YlanAllouche/striked.nvim/markdown_test" }))
```
