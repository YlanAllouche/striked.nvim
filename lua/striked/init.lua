local config = require("striked.config")
local actions = require("striked.actions")
local pickers = require("striked.pickers")
local query = require("striked.query")
local scanner = require("striked.scanner")

local M = {}
local runtime = {
  bootstrapped = false,
  commands_registered = false,
  mappings = {},
}

local function clear_mappings()
  for _, mapping in ipairs(runtime.mappings) do
    pcall(vim.keymap.del, mapping.mode, mapping.lhs)
  end

  runtime.mappings = {}
end

local function set_mapping(mode, lhs, rhs, desc)
  if not lhs or lhs == "" or lhs == false then
    return
  end

  vim.keymap.set(mode, lhs, rhs, { desc = desc, silent = true })
  table.insert(runtime.mappings, { mode = mode, lhs = lhs })
end

local function copy_markdown_rich_for_current_context(use_visual)
  local buffer = vim.api.nvim_get_current_buf()

  if use_visual then
    local start_line = vim.fn.getpos("'<")[2]
    local end_line = vim.fn.getpos("'>")[2]

    return M.copy_markdown_rich({
      buffer = buffer,
      line1 = math.min(start_line, end_line),
      line2 = math.max(start_line, end_line),
      use_visual = true,
    })
  end

  return M.copy_markdown_rich({
    buffer = buffer,
    line1 = 1,
    line2 = vim.api.nvim_buf_line_count(buffer),
  })
end

local function apply_mappings()
  local mappings = config.get().mappings or {}

  clear_mappings()

  if mappings.enabled == false then
    return
  end

  set_mapping("n", mappings.bookmarks, function()
    M.pick_bookmarks()
  end, "Striked bookmarks")
  set_mapping("n", mappings.copy_markdown_rich, function()
    copy_markdown_rich_for_current_context(false)
  end, "Striked rich copy buffer")
  set_mapping("x", mappings.copy_markdown_rich, function()
    copy_markdown_rich_for_current_context(true)
  end, "Striked rich copy selection")
  set_mapping("n", mappings.tasks_open, function()
    M.pick_active_tasks()
  end, "Striked active tasks")
  set_mapping("n", mappings.tasks_done, function()
    M.pick_done_tasks()
  end, "Striked done tasks")
  set_mapping("n", mappings.tasks_slash, function()
    M.pick_active_tasks()
  end, "Striked active tasks")
  set_mapping("n", mappings.tasks_question, function()
    M.pick_tasks_by_status("?")
  end, "Striked question tasks")
  set_mapping("n", mappings.tasks_n, function()
    M.pick_tasks_by_status("n")
  end, "Striked n tasks")
  set_mapping("n", mappings.focused, function()
    M.pick_focused()
  end, "Striked focused items")
  set_mapping("n", mappings.meeting_import, function()
    M.ingest_meeting_ics()
  end, "Striked import meeting")
  set_mapping("n", mappings.journal_today, function()
    M.journal_today()
  end, "Striked journal today")
  set_mapping("n", mappings.journal_tomorrow, function()
    M.journal_tomorrow()
  end, "Striked journal tomorrow")
  set_mapping("n", mappings.journal_yesterday, function()
    M.journal_yesterday()
  end, "Striked journal yesterday")
  set_mapping("n", mappings.journal_next, function()
    M.journal_next()
  end, "Striked journal next")
  set_mapping("n", mappings.journal_previous, function()
    M.journal_previous()
  end, "Striked journal previous")
  set_mapping("n", mappings.add_bookmark, function()
    M.prompt_add_bookmark()
  end, "Striked add bookmark")
end

local function register_commands()
  if runtime.commands_registered then
    return
  end

  vim.api.nvim_create_user_command("StrikedBookmarks", function()
    M.pick_bookmarks()
  end, {})

  vim.api.nvim_create_user_command("StrikedTasks", function(command_opts)
    M.pick_tasks_by_status(command_opts.args)
  end, {
    nargs = 1,
    complete = function()
      return { "@", " ", "x", "-", "l", "R", "/", "?", "n" }
    end,
  })

  vim.api.nvim_create_user_command("StrikedTasksOpen", function()
    M.pick_active_tasks()
  end, {})

  vim.api.nvim_create_user_command("StrikedTasksDone", function()
    M.pick_done_tasks()
  end, {})

  vim.api.nvim_create_user_command("StrikedTasksSlash", function()
    M.pick_active_tasks()
  end, {})

  vim.api.nvim_create_user_command("StrikedTasksQuestion", function()
    M.pick_tasks_by_status("?")
  end, {})

  vim.api.nvim_create_user_command("StrikedTasksN", function()
    M.pick_tasks_by_status("n")
  end, {})

  vim.api.nvim_create_user_command("StrikedFocused", function()
    M.pick_focused()
  end, {})

  vim.api.nvim_create_user_command("StrikedAddBookmark", function()
    M.prompt_add_bookmark()
  end, {})

  vim.api.nvim_create_user_command("StrikedNewTopic", function()
    M.prompt_create_topic()
  end, {})

  vim.api.nvim_create_user_command("StrikedNewProject", function()
    M.prompt_create_project()
  end, {})

  vim.api.nvim_create_user_command("StrikedNewSprint", function()
    M.prompt_create_sprint()
  end, {})

  vim.api.nvim_create_user_command("StrikedNewMeeting", function()
    M.prompt_create_meeting()
  end, {})

  vim.api.nvim_create_user_command("StrikedIngestMeetingIcs", function(command_opts)
    local argument = vim.trim(command_opts.args or "")
    M.ingest_meeting_ics({
      path = argument ~= "" and argument or nil,
      delete_source = command_opts.bang == false,
    })
  end, {
    nargs = "?",
    bang = true,
    complete = "file",
  })

  vim.api.nvim_create_user_command("StrikedJournal", function(command_opts)
    M.open_journal({ date = command_opts.args })
  end, { nargs = 1 })

  vim.api.nvim_create_user_command("StrikedJournalPrompt", function()
    M.prompt_journal_date()
  end, {})

  vim.api.nvim_create_user_command("StrikedJournalToday", function()
    M.journal_today()
  end, {})

  vim.api.nvim_create_user_command("StrikedJournalTomorrow", function()
    M.journal_tomorrow()
  end, {})

  vim.api.nvim_create_user_command("StrikedJournalYesterday", function()
    M.journal_yesterday()
  end, {})

  vim.api.nvim_create_user_command("StrikedJournalNext", function()
    M.journal_next()
  end, {})

  vim.api.nvim_create_user_command("StrikedJournalPrevious", function()
    M.journal_previous()
  end, {})

  vim.api.nvim_create_user_command("StrikedLog", function()
    M.prompt_build_log()
  end, {})

  vim.api.nvim_create_user_command("StrikedFocusedPrint", function()
    M.print_focused()
  end, {})

  vim.api.nvim_create_user_command("StrikedCopyMarkdownRich", function(command_opts)
    M.copy_markdown_rich({
      buffer = vim.api.nvim_get_current_buf(),
      line1 = command_opts.line1,
      line2 = command_opts.line2,
    })
  end, { range = "%" })

  vim.api.nvim_create_user_command("StrikedCopyMarkdownHtmlOnly", function(command_opts)
    M.copy_markdown_html_only({
      buffer = vim.api.nvim_get_current_buf(),
      line1 = command_opts.line1,
      line2 = command_opts.line2,
    })
  end, { range = "%" })

  vim.api.nvim_create_user_command("StrikedClipboardRich", function()
    M.upgrade_clipboard_rich()
  end, {})

  vim.api.nvim_create_user_command("StrikedClipboardHtmlOnly", function()
    M.upgrade_clipboard_html_only()
  end, {})

  runtime.commands_registered = true
end

function M.setup(opts)
  local resolved = config.setup(opts)

  M._bootstrap()
  apply_mappings()

  return resolved
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

function M.tasks_by_statuses(statuses, opts)
  return query.tasks_by_statuses(statuses, opts)
end

function M.active_tasks(opts)
  return query.active_tasks(opts)
end

function M.done_tasks(opts)
  return query.done_tasks(opts)
end

function M.items_by_field(field, value, opts)
  return query.items_by_field(field, value, opts)
end

function M.focused(opts)
  return query.focused(opts)
end

function M.items_between_dates(start_date, end_date, opts)
  return query.items_between_dates(start_date, end_date, opts)
end

function M.log_items(start_date, end_date, opts)
  return query.log_items(start_date, end_date, opts)
end

function M.pick_bookmarks(opts)
  return pickers.pick_bookmarks(opts)
end

function M.pick_active_tasks(opts)
  return pickers.pick_active_tasks(opts)
end

function M.pick_done_tasks(opts)
  return pickers.pick_done_tasks(opts)
end

function M.pick_tasks_by_status(status, opts)
  return pickers.pick_tasks_by_status(status, opts)
end

function M.pick_focused(opts)
  return pickers.pick_focused(opts)
end

function M.find_similar_bookmarks(target, opts)
  return query.find_similar_bookmarks(target, opts)
end

function M.add_bookmark(opts)
  return actions.add_bookmark(opts)
end

function M.create_note(opts)
  return actions.create_note(opts)
end

function M.create_topic(opts)
  return actions.create_topic(opts)
end

function M.create_project(opts)
  return actions.create_project(opts)
end

function M.create_sprint(opts)
  return actions.create_sprint(opts)
end

function M.create_meeting(opts)
  return actions.create_meeting(opts)
end

function M.open_journal(opts)
  return actions.open_journal(opts)
end

function M.journal_today(opts)
  return actions.journal_today(opts)
end

function M.journal_tomorrow(opts)
  return actions.journal_tomorrow(opts)
end

function M.journal_yesterday(opts)
  return actions.journal_yesterday(opts)
end

function M.journal_next(opts)
  return actions.journal_next(opts)
end

function M.journal_previous(opts)
  return actions.journal_previous(opts)
end

function M.prompt_add_bookmark(opts)
  return actions.prompt_add_bookmark(opts)
end

function M.prompt_create_note(kind, opts)
  return actions.prompt_create_note(kind, opts)
end

function M.prompt_create_topic(opts)
  return actions.prompt_create_topic(opts)
end

function M.prompt_create_project(opts)
  return actions.prompt_create_project(opts)
end

function M.prompt_create_sprint(opts)
  return actions.prompt_create_sprint(opts)
end

function M.prompt_create_meeting(opts)
  return actions.prompt_create_meeting(opts)
end

function M.ingest_meeting_ics(opts)
  return actions.ingest_meeting_ics(opts)
end

function M.prompt_journal_date(opts)
  return actions.prompt_journal_date(opts)
end

function M.build_log(opts)
  return actions.build_log(opts)
end

function M.print_focused(opts)
  return actions.print_focused(opts)
end

function M.copy_markdown_rich(opts)
  return actions.copy_markdown_rich(opts)
end

function M.copy_markdown_html_only(opts)
  return actions.copy_markdown_html_only(opts)
end

function M.upgrade_clipboard_rich(opts)
  return actions.upgrade_clipboard_rich(opts)
end

function M.upgrade_clipboard_html_only(opts)
  return actions.upgrade_clipboard_html_only(opts)
end

function M.prompt_build_log(opts)
  return actions.prompt_build_log(opts)
end

function M._bootstrap()
  if runtime.bootstrapped then
    return
  end

  config.setup(config.get())
  register_commands()
  apply_mappings()

  runtime.bootstrapped = true
end

return M
