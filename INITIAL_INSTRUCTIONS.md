# striked.nvim Initial Instructions

This document is the source of truth for the next conversation in this repository.

## Current State

- The repository is intentionally empty.
- Do not assume any existing plugin structure, tests, or dependencies.
- Nothing has been implemented yet.

## Project Goal

Build a Neovim Lua plugin that scans markdown files recursively from the current Neovim working directory, parses task-like lines and bookmark-like lines, exposes the results through a Lua API, and provides default Telescope-based pickers for the common use cases.

## Core Model

- A parsed item is a task-like markdown line.
- Bookmarks are not a separate syntax in v1.
- A bookmark is any task-like item whose status is `@`.
- All parsed items should be available through the same core API.
- Bookmark listings should be derived from the core parsed items.

## Scan Scope

- v1 only scans recursively from Neovim `CWD`.
- Do not implement a separate current-buffer-folder scan mode in v1.
- Default file scope should be markdown-like files only.
- Recommended default patterns:
  - `*.md`
  - `*.markdown`
  - optionally `*.mdx`

## Supported Task Statuses

The parser should support generic single-character statuses, but the first version must provide first-class filtering helpers and picker entry points for:

- `@`
- ` ` (single space)
- `x`
- `/`
- `?`
- `n`

## Syntax Expectations

### Task-like line

Examples:

```markdown
- [ ] Open task
- [x] Done task
- [/] In progress task
- [?] Unclear task
- [n] Note-like task
- [@] Bookmark title [url:: https://example.com]
```

### Metadata

Metadata should be parsed from inline fields with the existing striked-style convention:

```markdown
[field:: value]
```

Examples:

```markdown
- [@] OpenAI docs [url:: https://platform.openai.com/docs] [project:: ai] [topic:: llm]
- [ ] Finish parser [completion:: 80] [date:: 2026-05-03]
```

Repeated metadata fields should be preserved and exposed in a useful way.

## Metadata Requirements

The parser should extract all metadata generically, but the first version must specially recognize and normalize:

- `project`
- `projects`
- `topic`
- `topics`
- `date`
- `completion`

### Normalization expectations

- `project` and `projects` should normalize to a consistent list-like representation.
- `topic` and `topics` should normalize to a consistent list-like representation.
- `date` should be extracted in a stable raw form first; extra normalization can be added if it remains simple.
- `completion` should be parsed in a basic useful way, for example `80` or `80%`.
- Unknown metadata fields must still remain accessible in the generic metadata table.

## Public Lua API Expectations

The plugin should expose plain Lua APIs first. Telescope integration should be layered on top of those APIs, not the other way around.

Expected high-level API shape:

```lua
require("striked").setup(opts)
require("striked").scan()
require("striked").bookmarks()
require("striked").tasks_by_status(" ")
require("striked").tasks_by_status("@")
require("striked").tasks_by_status("x")
require("striked").tasks_by_status("/")
require("striked").tasks_by_status("?")
require("striked").tasks_by_status("n")
require("striked").pick_bookmarks()
require("striked").pick_tasks_by_status(" ")
require("striked").add_bookmark(opts)
```

The API names can be adjusted slightly during implementation if there is a strong reason, but the capabilities above must exist.

## Picker Expectations

- Default picker UX should use Telescope if available.
- Pickers should support previewing the real source file at the correct line.
- The previewer should jump directly to the matched entry location.
- Picker entries should be compact to read but still rich to search.

### Search behavior

If Telescope allows hidden searchable content through the entry `ordinal`, use that.

The searchable content for an item should include as much useful information as possible, even if it is not all shown in the visual display:

- item text/title
- status
- URL
- project/projects
- topic/topics
- date
- completion
- raw metadata text when useful
- file path

### Bookmark picker behavior

Do not split bookmarks into separate pickers just because one view emphasizes title and another emphasizes URL.

Preferred v1 behavior:

- one bookmark picker
- compact display
- searchable by both title and URL
- searchable by parsed metadata as well

## Bookmark Insertion Expectations

The plugin should support adding bookmarks through Lua and later through picker-driven actions.

Default inserted format:

```markdown
- [@] Title [url:: https://example.com]
```

Optional metadata may be appended when available:

```markdown
- [@] Title [url:: https://example.com] [project:: ai] [topic:: llm] [date:: 2026-05-03]
```

Before insertion, the plugin should be able to surface similar existing bookmarks.

Similarity can initially stay simple and practical:

- exact URL match
- normalized URL match
- same hostname/domain
- title overlap or substring match

## Commands And Default Mappings

The plugin should eventually expose commands and default mappings for the common flows.

Expected command set:

- `:StrikedBookmarks`
- `:StrikedTasks {status}`
- `:StrikedTasksOpen`
- `:StrikedTasksDone`
- `:StrikedTasksSlash`
- `:StrikedTasksQuestion`
- `:StrikedTasksN`
- `:StrikedAddBookmark`

Expected default mapping intent:

- bookmarks picker
- open tasks picker
- done tasks picker
- slash tasks picker
- question tasks picker
- n-status tasks picker
- add bookmark action

The exact keybindings may be decided during implementation, but they must remain configurable and disable-able.

## Recommended Internal Structure

This layout is recommended, but can be adapted if a better structure emerges during implementation:

```text
lua/striked/init.lua
lua/striked/config.lua
lua/striked/parser.lua
lua/striked/scanner.lua
lua/striked/query.lua
lua/striked/pickers.lua
lua/striked/actions.lua
plugin/striked.lua
```

## Required Test Fixture Folder

Add a dedicated folder at the repository root named:

```text
markdown_test/
```

This folder is required for future work.

Purpose:

- store markdown fixtures and examples
- run parser/scanner tests against predictable sample files
- manually verify pickers and search behavior using known markdown inputs
- keep development and testing focused on fixture content instead of arbitrary repository files

Important expectations for `markdown_test/`:

- it will contain markdown example files
- examples should include tasks for each preset status
- examples should include bookmarks with URLs and metadata
- examples should include repeated metadata fields
- examples should include enough variety to verify Telescope search behavior

When implementation begins, test and debug flows should rely on `markdown_test/` as the main local fixture set.

## Non-Goals For The First Coding Pass

- no separate non-CWD scan mode
- no separate bookmark storage model beyond status `@`
- no attempt at full markdown parsing
- no wiki-link parsing in v1
- no async complexity unless the synchronous version is clearly too slow
- no implementation before agreeing on the initial plugin skeleton and API boundaries

## Suggested First Implementation Order

When coding starts in the next conversation, the recommended order is:

1. Create the plugin skeleton and setup/config layer.
2. Implement the line parser for task-like items and inline metadata.
3. Implement recursive CWD scanning over markdown files.
4. Implement plain Lua query APIs for bookmarks and status filters.
5. Implement Telescope pickers on top of the query APIs.
6. Implement bookmark insertion and similar-bookmark matching.
7. Add test fixtures under `markdown_test/` and validate behavior against them.

## Final Instruction For The Next Conversation

Use this document as the only context baseline.

The next conversation should begin by implementing the plugin from scratch in this repository, following the constraints and priorities described above.
