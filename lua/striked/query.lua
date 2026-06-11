local dates = require("striked.dates")
local scanner = require("striked.scanner")

local M = {}

local field_aliases = {
  project = { "project", "projects" },
  projects = { "project", "projects" },
  topic = { "topic", "topics" },
  topics = { "topic", "topics" },
}
local done_like_statuses = { "x", "-", "l", "R" }

local function trim(text)
  return vim.trim(text or "")
end

local function normalize_url(url)
  if not url or url == "" then
    return nil
  end

  local value = trim(url):gsub("#.*$", "")
  local scheme, remainder = value:match("^([%w+.-]+)://(.+)$")

  if not scheme then
    return value:gsub("/+$", "")
  end

  local host, suffix = remainder:match("^([^/%?#]+)(.*)$")
  if not host then
    return value:gsub("/+$", "")
  end

  return string.format("%s://%s%s", scheme:lower(), host:lower(), suffix):gsub("/+$", "")
end

local function hostname(url)
  if not url or url == "" then
    return nil
  end

  local host = url:match("^[%w+.-]+://([^/%?#]+)") or url:match("^([^/%?#]+)")
  return host and host:lower() or nil
end

local function normalize_title(title)
  return trim((title or ""):lower():gsub("[^%w%s]", " "):gsub("%s+", " "))
end

local function title_overlap(left, right)
  local left_words = {}
  local overlap = 0

  for word in left:gmatch("%S+") do
    if #word > 2 then
      left_words[word] = true
    end
  end

  for word in right:gmatch("%S+") do
    if left_words[word] then
      overlap = overlap + 1
      left_words[word] = nil
    end
  end

  return overlap
end

local function scan_items(opts)
  if opts and opts.items then
    return opts.items
  end

  return scanner.scan(opts)
end

local function field_names(field)
  local normalized = trim(tostring(field or "")):lower()
  return field_aliases[normalized] or { normalized }
end

local function metadata_values(item, field)
  local values = {}
  local seen = {}

  for _, name in ipairs(field_names(field)) do
    for _, value in ipairs(item.metadata and item.metadata[name] or {}) do
      local raw = trim(tostring(value))

      for part in raw:gmatch("[^,]+") do
        local entry = trim(part)
        local lowered = entry:lower()

        if entry ~= "" and not seen[lowered] then
          seen[lowered] = true
          table.insert(values, entry)
        end
      end

      local lowered_raw = raw:lower()
      if raw ~= "" and not seen[lowered_raw] then
        seen[lowered_raw] = true
        table.insert(values, raw)
      end
    end
  end

  return values
end

local function matches_metadata(item, field, value)
  local expected = trim(tostring(value or "")):lower()
  if expected == "" then
    return false
  end

  for _, item_value in ipairs(metadata_values(item, field)) do
    if item_value:lower() == expected then
      return true
    end
  end

  return false
end

local function date_values(item)
  local values = {}

  for _, field in ipairs({ "date", "completion" }) do
    for _, value in ipairs(metadata_values(item, field)) do
      if dates.is_valid(value) then
        table.insert(values, value)
      end
    end
  end

  return values
end

local function item_date(item)
  for _, field in ipairs({ "completion", "date" }) do
    for _, value in ipairs(metadata_values(item, field)) do
      if dates.is_valid(value) then
        return value
      end
    end
  end

  return nil
end

function M.filter_items(predicate, opts)
  local items = scan_items(opts)
  local matches = {}

  for _, item in ipairs(items) do
    if predicate(item) then
      table.insert(matches, item)
    end
  end

  return matches
end

function M.tasks_by_status(status, opts)
  return M.filter_items(function(item)
    return item.status == status
  end, opts)
end

function M.tasks_by_statuses(statuses, opts)
  local allowed = {}

  for _, status in ipairs(statuses or {}) do
    allowed[status] = true
  end

  return M.filter_items(function(item)
    return allowed[item.status] == true
  end, opts)
end

function M.active_tasks(opts)
  return M.tasks_by_statuses({ "/", " " }, opts)
end

function M.done_tasks(opts)
  local matches = M.tasks_by_statuses(done_like_statuses, opts)

  table.sort(matches, function(left, right)
    local left_date = item_date(left)
    local right_date = item_date(right)

    if left_date and right_date and left_date ~= right_date then
      return dates.compare(left_date, right_date) > 0
    end

    if left_date ~= right_date then
      return left_date ~= nil
    end

    if left.path ~= right.path then
      return left.path < right.path
    end

    return (left.lnum or 0) < (right.lnum or 0)
  end)

  return matches
end

function M.bookmarks(opts)
  return M.tasks_by_status("@", opts)
end

function M.metadata_values(item, field)
  return metadata_values(item, field)
end

function M.items_by_field(field, value, opts)
  return M.filter_items(function(item)
    return matches_metadata(item, field, value)
  end, opts)
end

function M.focused(opts)
  return M.items_by_field("focus", "true", opts)
end

function M.item_date(item)
  return item_date(item)
end

function M.items_between_dates(start_date, end_date, opts)
  return M.filter_items(function(item)
    for _, value in ipairs(date_values(item)) do
      if dates.in_range(value, start_date, end_date) then
        return true
      end
    end

    return false
  end, opts)
end

function M.log_items(start_date, end_date, opts)
  local allowed = {
    [" "] = true,
    x = true,
    ["-"] = true,
    l = true,
    R = true,
  }

  return M.filter_items(function(item)
    if not allowed[item.status] then
      return false
    end

    for _, value in ipairs(date_values(item)) do
      if dates.in_range(value, start_date, end_date) then
        return true
      end
    end

    return false
  end, opts)
end

function M.find_similar_bookmarks(target, opts)
  local matches = {}
  local target_url = normalize_url(target.url)
  local target_host = hostname(target.url)
  local target_title = normalize_title(target.title)

  for _, item in ipairs(M.bookmarks(opts)) do
    local reasons = {}
    local score = 0
    local item_url = normalize_url(item.url)
    local item_host = hostname(item.url)
    local item_title = normalize_title(item.title)

    if target.url and item.url and trim(target.url) == trim(item.url) then
      table.insert(reasons, "exact URL match")
      score = score + 100
    elseif target_url and item_url and target_url == item_url then
      table.insert(reasons, "normalized URL match")
      score = score + 90
    end

    if target_host and item_host and target_host == item_host then
      table.insert(reasons, "same hostname")
      score = score + 30
    end

    if target_title ~= "" and item_title ~= "" then
      if target_title == item_title then
        table.insert(reasons, "exact title match")
        score = score + 25
      elseif target_title:find(item_title, 1, true) or item_title:find(target_title, 1, true) then
        table.insert(reasons, "title substring match")
        score = score + 15
      else
        local overlap = title_overlap(target_title, item_title)
        if overlap > 0 then
          table.insert(reasons, string.format("shared title words (%d)", overlap))
          score = score + math.min(overlap * 5, 20)
        end
      end
    end

    if score > 0 then
      local match = vim.deepcopy(item)
      match.similarity = {
        score = score,
        reasons = reasons,
      }
      table.insert(matches, match)
    end
  end

  table.sort(matches, function(left, right)
    if left.similarity.score ~= right.similarity.score then
      return left.similarity.score > right.similarity.score
    end

    if left.path ~= right.path then
      return left.path < right.path
    end

    return (left.lnum or 0) < (right.lnum or 0)
  end)

  return matches
end

return M
