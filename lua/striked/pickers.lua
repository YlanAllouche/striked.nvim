local config = require("striked.config")
local documents = require("striked.documents")
local query = require("striked.query")

local M = {}
local uv = vim.uv or vim.loop

local function join_non_empty(parts, separator)
  local values = {}

  for _, part in ipairs(parts) do
    if part and part ~= "" then
      table.insert(values, part)
    end
  end

  return table.concat(values, separator)
end

local function short_text(text, limit)
  if not text or #text <= limit then
    return text or ""
  end

  return text:sub(1, limit - 3) .. "..."
end

local function completion_text(item)
  local completion = item.normalized and item.normalized.completion
  if not completion then
    return nil
  end

  return completion.raw
end

local function searchable_text(item)
  return table.concat({
    item.title or "",
    item.status or "",
    item.url or "",
    table.concat(item.normalized and item.normalized.projects or {}, " "),
    table.concat(item.normalized and item.normalized.topics or {}, " "),
    item.normalized and item.normalized.date or "",
    completion_text(item) or "",
    item.metadata_text or "",
    item.relative_path or item.path or "",
    item.raw_line or "",
  }, " ")
end

local function default_ordinal(item, opts)
  if type(opts.ordinal) == "function" then
    return tostring(opts.ordinal(item) or "")
  end

  return searchable_text(item)
end

local function compact_details(item, opts)
  local details = {}

  if opts.show_urls and item.url then
    table.insert(details, short_text(item.url, 48))
  end

  if item.normalized and #item.normalized.projects > 0 then
    table.insert(details, "p:" .. table.concat(item.normalized.projects, ","))
  end

  if item.normalized and #item.normalized.topics > 0 then
    table.insert(details, "t:" .. table.concat(item.normalized.topics, ","))
  end

  if item.normalized and item.normalized.date then
    table.insert(details, "d:" .. item.normalized.date)
  end

  if completion_text(item) then
    table.insert(details, "c:" .. completion_text(item))
  end

  return table.concat(details, " | ")
end

local function display_text(item, opts)
  if type(opts.display) == "function" then
    return opts.display(item)
  end

  local location = string.format("%s:%d", item.relative_path or item.path or "", item.lnum or 0)
  local details = compact_details(item, opts)

  return join_non_empty({
    string.format("[%s] %s", item.status, item.title),
    details,
    location,
  }, " | ")
end

local function open_location(entry)
  vim.cmd.edit(vim.fn.fnameescape(entry.filename))
  vim.api.nvim_win_set_cursor(0, { entry.lnum, math.max((entry.col or 1) - 1, 0) })
  vim.cmd("normal! zz")
end

local function browser_command(url)
  local sysname = (uv.os_uname() or {}).sysname
  if sysname == "Darwin" then
    return { "open", url }
  end

  local browser = vim.env.BROWSER
  if browser and browser ~= "" then
    return browser .. " " .. vim.fn.shellescape(url)
  end

  if sysname == "Linux" then
    return { "xdg-open", url }
  end

  if sysname and sysname:match("Windows") then
    return { "cmd.exe", "/c", "start", "", url }
  end

  return nil
end

function M.open_url(url)
  local target = vim.trim(tostring(url or ""))
  if target == "" then
    vim.notify("striked.nvim could not find a URL to open", vim.log.levels.WARN)
    return false
  end

  local command = browser_command(target)
  if not command then
    vim.notify("striked.nvim could not determine how to open URLs on this platform", vim.log.levels.ERROR)
    return false
  end

  local job = vim.fn.jobstart(command, { detach = true })

  if job <= 0 then
    vim.notify(string.format("striked.nvim failed to open URL: %s", target), vim.log.levels.ERROR)
    return false
  end

  return true
end

function M.open_item_url(item)
  return M.open_url(item and item.url)
end

local function telescope_deps()
  local ok_pickers, telescope_pickers = pcall(require, "telescope.pickers")
  local ok_finders, telescope_finders = pcall(require, "telescope.finders")
  local ok_actions, telescope_actions = pcall(require, "telescope.actions")
  local ok_state, action_state = pcall(require, "telescope.actions.state")
  local ok_config, telescope_config = pcall(require, "telescope.config")

  if not (ok_pickers and ok_finders and ok_actions and ok_state and ok_config) then
    error("striked.nvim requires nvim-telescope/telescope.nvim for picker commands")
  end

  return {
    pickers = telescope_pickers,
    finders = telescope_finders,
    actions = telescope_actions,
    action_state = action_state,
    values = telescope_config.values,
  }
end

function M.pick_items(items, opts)
  opts = opts or {}

  local telescope = telescope_deps()
  local picker_config = config.get().picker.telescope or {}
  local previewer = picker_config.preview == false and false or telescope.values.grep_previewer(opts)

  telescope.pickers.new(opts, {
    prompt_title = opts.prompt_title or "Striked",
    finder = telescope.finders.new_table({
      results = items,
      entry_maker = function(item)
        return {
          value = item,
          display = display_text(item, opts),
          ordinal = default_ordinal(item, opts),
          filename = item.path,
          lnum = item.lnum,
          col = item.col or 1,
          text = item.raw_line,
        }
      end,
    }),
    sorter = telescope.values.generic_sorter(opts),
    previewer = previewer,
    layout_strategy = picker_config.layout_strategy,
    sorting_strategy = picker_config.sorting_strategy,
    layout_config = picker_config.layout_config,
    attach_mappings = function(prompt_bufnr, map)
      telescope.actions.select_default:replace(function()
        local selection = telescope.action_state.get_selected_entry()
        telescope.actions.close(prompt_bufnr)

        if selection then
          open_location(selection)
        end
      end)

      local open_url_mapping = picker_config.open_url
      if open_url_mapping and opts.show_urls then
        local function open_selected_url()
          local selection = telescope.action_state.get_selected_entry()
          if not selection then
            return
          end

          telescope.actions.close(prompt_bufnr)
          M.open_item_url(selection.value)
        end

        map("i", open_url_mapping, open_selected_url)
        map("n", open_url_mapping, open_selected_url)
      end

      return true
    end,
  }):find()

  return items
end

function M.pick_bookmarks(opts)
  opts = opts or {}
  return M.pick_items(query.bookmarks(opts), vim.tbl_extend("force", opts, {
    kind = "bookmark",
    show_urls = true,
    prompt_title = opts.prompt_title or "Striked Bookmarks",
  }))
end

function M.pick_active_tasks(opts)
  opts = opts or {}
  return M.pick_items(query.active_tasks(opts), vim.tbl_extend("force", opts, {
    kind = "task",
    prompt_title = opts.prompt_title or "Striked Active Tasks",
  }))
end

function M.pick_done_tasks(opts)
  opts = opts or {}
  return M.pick_items(query.done_tasks(opts), vim.tbl_extend("force", opts, {
    kind = "task",
    prompt_title = opts.prompt_title or "Striked Done Tasks",
  }))
end

function M.pick_tasks_by_status(status, opts)
  opts = opts or {}
  return M.pick_items(query.tasks_by_status(status, opts), vim.tbl_extend("force", opts, {
    kind = "task",
    prompt_title = opts.prompt_title or string.format("Striked Tasks [%s]", status),
  }))
end

function M.pick_focused(opts)
  opts = opts or {}
  return M.pick_items(query.focused(opts), vim.tbl_extend("force", opts, {
    kind = "item",
    show_urls = true,
    prompt_title = opts.prompt_title or "Striked Focused",
  }))
end

function M.pick_meetings(opts)
  opts = opts or {}
  return M.pick_items(documents.meetings(opts), vim.tbl_extend("force", opts, {
    prompt_title = opts.prompt_title or "Striked Meetings",
    display = function(item)
      return join_non_empty({
        item.date,
        item.title,
        item.relative_path,
      }, " | ")
    end,
    ordinal = function(item)
      return table.concat({ item.date or "", item.title or "", item.relative_path or item.path or "" }, " ")
    end,
  }))
end

function M.pick_journals(opts)
  opts = opts or {}
  return M.pick_items(documents.journals(opts), vim.tbl_extend("force", opts, {
    prompt_title = opts.prompt_title or "Striked Journals",
    display = function(item)
      return join_non_empty({ item.date, item.relative_path }, " | ")
    end,
    ordinal = function(item)
      return table.concat({ item.date or "", item.relative_path or item.path or "" }, " ")
    end,
  }))
end

return M
