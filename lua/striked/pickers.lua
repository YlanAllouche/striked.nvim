local config = require("striked.config")
local query = require("striked.query")

local M = {}

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

local function compact_details(item, kind)
  local details = {}

  if kind == "bookmark" and item.url then
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

local function display_text(item, kind)
  local location = string.format("%s:%d", item.relative_path or item.path or "", item.lnum or 0)
  local details = compact_details(item, kind)

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

local function telescope_deps()
  local ok_pickers, telescope_pickers = pcall(require, "telescope.pickers")
  local ok_finders, telescope_finders = pcall(require, "telescope.finders")
  local ok_actions, telescope_actions = pcall(require, "telescope.actions")
  local ok_state, action_state = pcall(require, "telescope.actions.state")
  local ok_config, telescope_config = pcall(require, "telescope.config")

  if not (ok_pickers and ok_finders and ok_actions and ok_state and ok_config) then
    error("striked.nvim requires Telescope for picker commands")
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
          display = display_text(item, opts.kind),
          ordinal = searchable_text(item),
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
    attach_mappings = function(prompt_bufnr)
      telescope.actions.select_default:replace(function()
        local selection = telescope.action_state.get_selected_entry()
        telescope.actions.close(prompt_bufnr)

        if selection then
          open_location(selection)
        end
      end)

      return true
    end,
  }):find()

  return items
end

function M.pick_bookmarks(opts)
  opts = opts or {}
  return M.pick_items(query.bookmarks(opts), vim.tbl_extend("force", opts, {
    kind = "bookmark",
    prompt_title = opts.prompt_title or "Striked Bookmarks",
  }))
end

function M.pick_tasks_by_status(status, opts)
  opts = opts or {}
  return M.pick_items(query.tasks_by_status(status, opts), vim.tbl_extend("force", opts, {
    kind = "task",
    prompt_title = opts.prompt_title or string.format("Striked Tasks [%s]", status),
  }))
end

return M
