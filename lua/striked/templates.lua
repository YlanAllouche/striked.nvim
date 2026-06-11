local M = {}

local seeded = false
local directories = {
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

local function yaml_string(value)
  return string.format("%q", tostring(value or ""))
end

local function frontmatter(fields)
  local lines = { "---" }

  for _, field in ipairs(fields) do
    local value = field.raw and tostring(field.value or "") or yaml_string(field.value)
    table.insert(lines, string.format("%s: %s", field.key, value))
  end

  table.insert(lines, "---")
  table.insert(lines, "")

  return lines
end

local function merge_lines(fields, body)
  local lines = frontmatter(fields)
  for _, line in ipairs(body or {}) do
    table.insert(lines, line)
  end

  return lines
end

local function today()
  return os.date("%Y-%m-%d")
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
    lines = merge_lines({
      { key = "id", value = opts.id, raw = true },
      { key = "title", value = title_required("topic", opts) },
    }, {}),
  }
end

local function render_project(opts)
  return {
    directory = directories.project,
    filename = opts.id .. ".md",
    lines = merge_lines({
      { key = "id", value = opts.id, raw = true },
      { key = "title", value = title_required("project", opts) },
    }, {}),
  }
end

local function render_sprint(opts)
  local default_date = today()
  local start_date = trim(opts.startDate or opts.start_date)
  local end_date = trim(opts.endDate or opts.end_date)

  return {
    directory = directories.sprint,
    filename = opts.id .. ".md",
    lines = merge_lines({
      { key = "id", value = opts.id, raw = true },
      { key = "title", value = title_required("sprint", opts) },
      { key = "project", value = opts.project or "" },
      { key = "startDate", value = start_date ~= "" and start_date or default_date, raw = true },
      { key = "endDate", value = end_date ~= "" and end_date or default_date, raw = true },
    }, {
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
    }),
  }
end

local renderers = {
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

  if trim(opts.id) == "" then
    error("striked.nvim requires opts.id when rendering note templates")
  end

  return renderer(opts)
end

return M
