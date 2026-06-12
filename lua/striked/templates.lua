local M = {}
local dates = require("striked.dates")
local frontmatter = require("striked.frontmatter")

local seeded = false
local directories = {
  journal = "journal",
  meeting = "meetings",
  topic = "topics",
  project = "projects",
  sprint = "sprints",
}

local function trim(text)
  return vim.trim(text or "")
end

local function ensure_seeded()
  if seeded then
    return
  end

  local seed = os.time() + tonumber(tostring((vim.uv or vim.loop).hrtime()):sub(-6))
  math.randomseed(seed)
  math.random()
  math.random()
  math.random()
  seeded = true
end

local function merge_lines(fields, body)
  local lines = frontmatter.render(fields)
  for _, line in ipairs(body or {}) do
    table.insert(lines, line)
  end

  return lines
end

local function title_required(kind, opts)
  local title = trim(opts.title)
  if title == "" then
    error(string.format("striked.nvim requires opts.title to create a %s note", kind))
  end

  return title
end

local function render_topic(opts)
  return {
    directory = directories.topic,
    filename = opts.id .. ".md",
    fields = {
      { key = "id", value = opts.id, raw = true },
      { key = "title", value = title_required("topic", opts) },
    },
    body = {},
  }
end

local function render_project(opts)
  return {
    directory = directories.project,
    filename = opts.id .. ".md",
    fields = {
      { key = "id", value = opts.id, raw = true },
      { key = "title", value = title_required("project", opts) },
    },
    body = {},
  }
end

local function render_sprint(opts)
  local default_date = dates.today()
  local start_date = trim(opts.startDate or opts.start_date)
  local end_date = trim(opts.endDate or opts.end_date)

  return {
    directory = directories.sprint,
    filename = opts.id .. ".md",
    fields = {
      { key = "id", value = opts.id, raw = true },
      { key = "title", value = title_required("sprint", opts) },
      { key = "project", value = opts.project or "" },
      { key = "startDate", value = start_date ~= "" and start_date or default_date, raw = true },
      { key = "endDate", value = end_date ~= "" and end_date or default_date, raw = true },
    },
    body = {
      "# Retro",
      "",
      "## achievements",
      "",
      "## irritations",
      "",
      "## changes",
      "",
      "# Planning",
      "",
    },
  }
end

local function render_meeting(opts)
  local date = trim(opts.date)
  if date == "" then
    date = dates.today()
  elseif not dates.is_valid(date) then
    error(string.format("striked.nvim requires a valid meeting date, got %q", opts.date or ""))
  end

  local fields = {
    { key = "id", value = opts.id, raw = true },
    { key = "title", value = title_required("meeting", opts) },
    { key = "project", value = opts.project or "" },
    { key = "date", value = date, raw = true },
    { key = "startAt", value = opts.startAt or opts.start_at or "" },
    { key = "endAt", value = opts.endAt or opts.end_at or "" },
    { key = "fullDay", value = opts.fullDay == true },
  }

  if trim(opts.seriesId or opts.series_id) ~= "" then
    table.insert(fields, { key = "seriesId", value = opts.seriesId or opts.series_id })
  end

  if trim(opts.occurrenceId or opts.occurrence_id) ~= "" then
    table.insert(fields, { key = "occurrenceId", value = opts.occurrenceId or opts.occurrence_id, raw = true })
  end

  if trim(opts.sourceKey or opts.source_key) ~= "" then
    table.insert(fields, { key = "sourceKey", value = opts.sourceKey or opts.source_key })
  end

  if trim(opts.status) ~= "" then
    table.insert(fields, { key = "status", value = opts.status, raw = true })
  end

  if trim(opts.location) ~= "" then
    table.insert(fields, { key = "location", value = opts.location })
  end

  if trim(opts.joinUrl or opts.join_url) ~= "" then
    table.insert(fields, { key = "joinUrl", value = opts.joinUrl or opts.join_url })
  end

  if opts.organizer and next(opts.organizer) then
    table.insert(fields, { key = "organizer", value = opts.organizer })
  end

  table.insert(fields, { key = "attendees", value = opts.attendees or {} })

  if opts.teams and next(opts.teams) then
    table.insert(fields, { key = "teams", value = opts.teams })
  end

  return {
    directory = directories.meeting,
    filename = opts.id .. ".md",
    fields = fields,
    body = {
      "# Notes",
      "",
      "# Decisions",
      "",
      "# Actions",
      "",
    },
  }
end

local function render_journal(opts)
  local date = trim(opts.date)
  if not dates.is_valid(date) then
    error(string.format("striked.nvim requires a valid journal date, got %q", opts.date or ""))
  end

  return {
    directory = directories.journal,
    filename = date .. ".md",
    fields = {
      { key = "title", value = date },
    },
    body = {
      "# Brief",
      "",
      "## yesterday",
      "",
      "## today",
      "",
      "# Log",
      "",
      "# Tasks",
      "",
    },
  }
end

local renderers = {
  journal = render_journal,
  meeting = render_meeting,
  topic = render_topic,
  project = render_project,
  sprint = render_sprint,
}

function M.generate_uuid()
  ensure_seeded()

  return ("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"):gsub("[xy]", function(character)
    local value = math.random(0, 15)
    if character == "y" then
      value = (value % 4) + 8
    end

    return string.format("%x", value)
  end)
end

function M.directory_key(kind)
  local normalized = trim(kind):lower()
  local directory = directories[normalized]
  if not directory then
    error(string.format("striked.nvim does not support note kind %q", kind))
  end

  return directory
end

function M.render(kind, opts)
  local normalized = trim(kind):lower()
  local renderer = renderers[normalized]
  if not renderer then
    error(string.format("striked.nvim does not support note kind %q", kind))
  end

  if normalized ~= "journal" and trim(opts.id) == "" then
    error("striked.nvim requires opts.id when rendering note templates")
  end

  local rendered = renderer(opts)
  rendered.lines = merge_lines(rendered.fields, rendered.body)

  return rendered
end

return M
