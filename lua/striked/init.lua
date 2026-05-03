local config = require("striked.config")
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

local function apply_mappings()
  local mappings = config.get().mappings or {}

  clear_mappings()

  if mappings.enabled == false then
    return
  end

  set_mapping("n", mappings.bookmarks, function()
    M.pick_bookmarks()
  end, "Striked bookmarks")
  set_mapping("n", mappings.tasks_open, function()
    M.pick_tasks_by_status(" ")
  end, "Striked open tasks")
  set_mapping("n", mappings.tasks_done, function()
    M.pick_tasks_by_status("x")
  end, "Striked done tasks")
  set_mapping("n", mappings.tasks_slash, function()
    M.pick_tasks_by_status("/")
  end, "Striked slash tasks")
  set_mapping("n", mappings.tasks_question, function()
    M.pick_tasks_by_status("?")
  end, "Striked question tasks")
  set_mapping("n", mappings.tasks_n, function()
    M.pick_tasks_by_status("n")
  end, "Striked n tasks")
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
      return { "@", " ", "x", "/", "?", "n" }
    end,
  })

  vim.api.nvim_create_user_command("StrikedTasksOpen", function()
    M.pick_tasks_by_status(" ")
  end, {})

  vim.api.nvim_create_user_command("StrikedTasksDone", function()
    M.pick_tasks_by_status("x")
  end, {})

  vim.api.nvim_create_user_command("StrikedTasksSlash", function()
    M.pick_tasks_by_status("/")
  end, {})

  vim.api.nvim_create_user_command("StrikedTasksQuestion", function()
    M.pick_tasks_by_status("?")
  end, {})

  vim.api.nvim_create_user_command("StrikedTasksN", function()
    M.pick_tasks_by_status("n")
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

function M.pick_bookmarks(opts)
  return pickers.pick_bookmarks(opts)
end

function M.pick_tasks_by_status(status, opts)
  return pickers.pick_tasks_by_status(status, opts)
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
