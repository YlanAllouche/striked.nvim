local config = require("striked.config")
local clipboard = require("striked.clipboard")
local frontmatter = require("striked.frontmatter")
local ics = require("striked.ics")
local parser = require("striked.parser")
local pickers = require("striked.pickers")
local dates = require("striked.dates")
local paths = require("striked.paths")
local query = require("striked.query")
local templates = require("striked.templates")

local M = {}
local uv = vim.uv or vim.loop
local attendee_category_order = { "required", "optional", "chair", "nonParticipant", "tentative", "declined", "delegated", "other" }
local rich_task_symbols = {
  [" "] = "⬜",
  ["x"] = "✅",
  ["-"] = "✅",
  ["l"] = "✅",
  ["R"] = "✅",
  ["/"] = "🟡",
  ["?"] = "❓",
  ["n"] = "📝",
}
local rich_task_done_statuses = {
  ["x"] = true,
  ["-"] = true,
  ["l"] = true,
  ["R"] = true,
}
local legacy_meeting_scalar_keys = {
  occurrenceId = true,
  joinUrl = true,
  location = true,
  seriesId = true,
  sourceKey = true,
  status = true,
}

local function trim(text)
  return vim.trim(text or "")
end

local function system_result(args, stdin)
  if vim.system then
    local result = vim.system(args, {
      stdin = stdin,
      text = true,
    }):wait()

    return {
      code = result.code,
      stdout = result.stdout or "",
      stderr = result.stderr or "",
    }
  end

  local stdout = vim.fn.system(args, stdin or "")
  return {
    code = vim.v.shell_error,
    stdout = stdout or "",
    stderr = "",
  }
end

local function listify(value)
  if value == nil then
    return {}
  end

  if type(value) ~= "table" then
    local text = trim(tostring(value))
    return text == "" and {} or { text }
  end

  local items = {}

  for _, item in ipairs(value) do
    local text = trim(tostring(item))
    if text ~= "" then
      table.insert(items, text)
    end
  end

  return items
end

local function append_metadata(parts, key, values)
  for _, value in ipairs(listify(values)) do
    table.insert(parts, string.format("[%s:: %s]", key, value))
  end
end

local function build_bookmark_line(opts)
  local title = trim(opts.title)
  local url = trim(opts.url)

  if title == "" then
    error("striked.nvim requires opts.title to add a bookmark")
  end

  if url == "" then
    error("striked.nvim requires opts.url to add a bookmark")
  end

  local parts = { string.format("- [@] %s", title) }
  append_metadata(parts, "url", { url })
  append_metadata(parts, "project", opts.project)
  append_metadata(parts, "project", opts.projects)
  append_metadata(parts, "topic", opts.topic)
  append_metadata(parts, "topic", opts.topics)
  append_metadata(parts, "date", opts.date)
  append_metadata(parts, "completion", opts.completion)

  local extra_metadata = opts.metadata or {}
  local keys = vim.tbl_keys(extra_metadata)
  table.sort(keys)

  for _, key in ipairs(keys) do
    local normalized_key = key:lower()
    if normalized_key ~= "url"
      and normalized_key ~= "project"
      and normalized_key ~= "projects"
      and normalized_key ~= "topic"
      and normalized_key ~= "topics"
      and normalized_key ~= "date"
      and normalized_key ~= "completion"
    then
      append_metadata(parts, key, extra_metadata[key])
    end
  end

  return table.concat(parts, " ")
end

local function resolve_target(opts)
  local target = {
    path = opts.path and paths.normalize(opts.path) or nil,
    buffer = opts.buffer,
    use_buffer = false,
  }

  if target.buffer == nil and not target.path then
    target.buffer = vim.api.nvim_get_current_buf()
  end

  if target.buffer then
    local raw_buffer_name = vim.api.nvim_buf_get_name(target.buffer)
    local buffer_name = raw_buffer_name ~= "" and paths.normalize(raw_buffer_name) or ""

    if buffer_name ~= "" and (not target.path or target.path == buffer_name) then
      target.path = buffer_name
      target.use_buffer = true
    end
  end

  if not target.path or target.path == "" then
    error("striked.nvim needs a file-backed buffer or opts.path to add a bookmark")
  end

  return target
end

local function insert_into_buffer(buffer, line, opts)
  local line_count = vim.api.nvim_buf_line_count(buffer)
  local first_line = vim.api.nvim_buf_get_lines(buffer, 0, 1, false)[1] or ""

  if line_count == 1 and first_line == "" then
    vim.api.nvim_buf_set_lines(buffer, 0, 1, false, { line })
    return 1
  end

  local position = opts.position or config.get().bookmark.default_position or "cursor"
  local insert_at

  if opts.lnum then
    insert_at = math.max(math.min(opts.lnum, line_count), 0)
  elseif position == "end" or buffer ~= vim.api.nvim_get_current_buf() then
    insert_at = line_count
  else
    insert_at = vim.api.nvim_win_get_cursor(0)[1]
  end

  vim.api.nvim_buf_set_lines(buffer, insert_at, insert_at, false, { line })
  return insert_at + 1
end

local function insert_into_file(path, line, opts)
  paths.ensure_parent_dir(path)
  local lines = vim.fn.filereadable(path) == 1 and vim.fn.readfile(path) or {}
  local line_count = #lines

  if line_count == 0 then
    table.insert(lines, line)
    vim.fn.writefile(lines, path)
    return 1
  end

  local position = opts.position or config.get().bookmark.default_position or "end"
  local insert_at

  if opts.lnum then
    insert_at = math.max(math.min(opts.lnum, line_count + 1), 1)
  elseif position == "cursor" then
    insert_at = line_count + 1
  else
    insert_at = line_count + 1
  end

  table.insert(lines, insert_at, line)
  vim.fn.writefile(lines, path)
  return insert_at
end

local function similar_notification(similar)
  if #similar == 0 then
    return
  end

  vim.notify(string.format("striked.nvim found %d similar bookmark(s)", #similar), vim.log.levels.INFO)
end

local function write_file(path, lines)
  paths.ensure_parent_dir(path)
  vim.fn.writefile(lines, path)
end

local function open_file(path)
  vim.cmd.edit(vim.fn.fnameescape(path))
end

local function stat_score(path)
  local stat = uv.fs_stat(path)
  if not stat then
    return 0
  end

  local function timestamp(value)
    if type(value) ~= "table" then
      return 0
    end

    return ((value.sec or 0) * 1000000000) + (value.nsec or 0)
  end

  return math.max(timestamp(stat.birthtime), timestamp(stat.mtime), timestamp(stat.ctime))
end

local function newest_ics_file(directory)
  local normalized = paths.ensure_dir(directory)
  local handle = uv.fs_scandir(normalized)
  local newest_path
  local newest_score

  if not handle then
    return nil
  end

  while true do
    local name, entry_type = uv.fs_scandir_next(handle)
    if not name then
      break
    end

    if entry_type == "file" and name:lower():match("%.ics$") then
      local path = paths.join(normalized, name)
      local score = stat_score(path)

      if not newest_score or score > newest_score then
        newest_path = path
        newest_score = score
      end
    end
  end

  return newest_path
end

local function resolve_ics_path(opts)
  local explicit_path = trim(opts.path or opts.source)
  if explicit_path ~= "" then
    local normalized = paths.normalize(explicit_path)

    if vim.fn.isdirectory(normalized) == 1 then
      local latest = newest_ics_file(normalized)
      if latest then
        return latest
      end

      error(string.format("striked.nvim could not find any .ics file in %s", normalized))
    end

    if vim.fn.filereadable(normalized) == 1 then
      return normalized
    end

    error(string.format("striked.nvim could not find ICS source: %s", normalized))
  end

  local folder = trim(opts.folder)
  local directory = folder ~= "" and paths.normalize(folder) or paths.resolve_downloads_root(opts)
  local latest = newest_ics_file(directory)

  if latest then
    return latest
  end

  error(string.format("striked.nvim could not find any .ics file in %s", directory))
end

local function meeting_files(opts)
  local directory = paths.ensure_dir(paths.note_subdir("meetings", opts))
  local files = {}
  local handle = uv.fs_scandir(directory)

  if not handle then
    return files
  end

  while true do
    local name, entry_type = uv.fs_scandir_next(handle)
    if not name then
      break
    end

    if entry_type == "file" and name:lower():match("%.md$") then
      table.insert(files, paths.join(directory, name))
    end
  end

  table.sort(files)
  return files
end

local function existing_meeting(source_key, series_id, occurrence_id, opts)
  for _, path in ipairs(meeting_files(opts)) do
    local document = frontmatter.read_file(path)
    local source = frontmatter.find_scalar(document.frontmatter_lines, "sourceKey")
    local series = frontmatter.find_scalar(document.frontmatter_lines, "seriesId")
    local occurrence = frontmatter.find_scalar(document.frontmatter_lines, "occurrenceId")

    if source == source_key then
      return path, document
    end

    if series == series_id and occurrence == occurrence_id then
      return path, document
    end
  end

  return nil, nil
end

local function field_keys(fields)
  local keys = {}

  for _, field in ipairs(fields or {}) do
    if field and field.key then
      keys[field.key] = true
    end
  end

  return keys
end

local function append_scalar_extras(fields, scalars, ignored_keys)
  local reserved = field_keys(fields)
  local extras = {}

  for key, value in pairs(scalars or {}) do
    if value ~= nil and not reserved[key] and not (ignored_keys and ignored_keys[key]) then
      table.insert(extras, key)
    end
  end

  table.sort(extras)

  for _, key in ipairs(extras) do
    table.insert(fields, { key = key, value = scalars[key] })
  end

  return fields
end

local function attendee_display(attendee)
  local name = trim(attendee.name)
  local email = trim(attendee.email)

  if name ~= "" and email ~= "" then
    return string.format("%s <%s>", name, email)
  end

  if name ~= "" then
    return name
  end

  if email ~= "" then
    return string.format("<%s>", email)
  end

  return ""
end

local function attendee_category(attendee)
  local partstat = trim(attendee.partstat):upper()
  if partstat == "TENTATIVE" then
    return "tentative"
  end

  if partstat == "DECLINED" then
    return "declined"
  end

  if partstat == "DELEGATED" then
    return "delegated"
  end

  local role = trim(attendee.role):upper()
  if role == "CHAIR" then
    return "chair"
  end

  if role == "REQ-PARTICIPANT" then
    return "required"
  end

  if role == "OPT-PARTICIPANT" then
    return "optional"
  end

  if role == "NON-PARTICIPANT" then
    return "nonParticipant"
  end

  return "other"
end

local function grouped_attendees(attendees)
  local buckets = {}

  for _, category in ipairs(attendee_category_order) do
    buckets[category] = {}
  end

  for _, attendee in ipairs(attendees or {}) do
    local label = attendee_display(attendee)
    if label ~= "" then
      table.insert(buckets[attendee_category(attendee)], label)
    end
  end

  local grouped = {}
  for _, category in ipairs(attendee_category_order) do
    if #buckets[category] > 0 then
      table.insert(grouped, { key = category, value = buckets[category] })
    end
  end

  return grouped
end

local function meeting_template_opts(imported, opts, existing_scalars, fallback_id)
  local project_override = trim(opts.project)
  local existing_project = trim(existing_scalars.project or "")

  return {
    id = trim(existing_scalars.id or fallback_id or ""),
    title = imported.display_title or imported.title,
    project = project_override ~= "" and project_override or existing_project,
    date = imported.date,
    startAt = imported.start_at,
    endAt = imported.end_at,
    fullDay = imported.full_day,
    seriesId = imported.uid,
    occurrenceId = imported.occurrence_id,
    sourceKey = imported.source_key,
    status = imported.status,
    location = imported.location,
    joinUrl = imported.join_url,
    organizer = imported.organizer,
    attendees = grouped_attendees(imported.attendees),
    teams = imported.teams,
  }
end

local function update_note_frontmatter(path, fields)
  local document = frontmatter.read_file(path)
  local lines = frontmatter.render(fields)

  for _, line in ipairs(document.body_lines) do
    table.insert(lines, line)
  end

  write_file(path, lines)
  return document
end

local function maybe_delete_source(path, opts)
  local configured = config.get().meeting or {}
  local delete_source = opts.delete_source
  if delete_source == nil then
    delete_source = configured.delete_ics_after_import ~= false
  end

  if delete_source ~= true then
    return false
  end

  if vim.fn.delete(path) ~= 0 then
    vim.notify(string.format("striked.nvim could not delete ICS file: %s", path), vim.log.levels.WARN)
    return false
  end

  return true
end

local function notify_note_updated(kind, path, opts)
  vim.notify(
    string.format("striked.nvim updated %s note at %s", kind, paths.relative_path(paths.resolve_root(opts), path)),
    vim.log.levels.INFO
  )
end

local function note_path(kind, id, opts)
  return paths.join(paths.note_subdir(templates.directory_key(kind), opts), id .. ".md")
end

local function journal_path(date, opts)
  return paths.join(paths.note_subdir("journal", opts), date .. ".md")
end

local function unique_note_id(kind, opts)
  local explicit = trim(opts.id)
  if explicit ~= "" then
    local explicit_path = note_path(kind, explicit, opts)
    if vim.fn.filereadable(explicit_path) == 1 then
      error(string.format("striked.nvim note already exists: %s", explicit_path))
    end

    return explicit
  end

  while true do
    local candidate = templates.generate_uuid()
    if vim.fn.filereadable(note_path(kind, candidate, opts)) == 0 then
      return candidate
    end
  end
end

local function notify_note_created(kind, result)
  vim.notify(string.format("striked.nvim created %s note at %s", kind, result.relative_path), vim.log.levels.INFO)
end

local function normalized_range(opts)
  local start_date = trim(opts.startDate or opts.start_date)
  local end_date = trim(opts.endDate or opts.end_date)

  if start_date == "" then
    error("striked.nvim requires a start date for log generation")
  end

  if not dates.is_valid(start_date) then
    error(string.format("striked.nvim expected a valid start date, got %q", start_date))
  end

  if end_date == "" then
    end_date = dates.today()
  elseif not dates.is_valid(end_date) then
    error(string.format("striked.nvim expected a valid end date, got %q", end_date))
  end

  if dates.compare(start_date, end_date) > 0 then
    error("striked.nvim start date must be before or equal to end date")
  end

  return start_date, end_date
end

local function list_lines(items)
  local lines = {}

  for _, item in ipairs(items) do
    local title = trim(item.title or item.text)
    if title ~= "" then
      table.insert(lines, "- " .. title)
    end
  end

  return lines
end

local function insert_lines_at_cursor(lines, opts)
  if #lines == 0 then
    vim.notify("striked.nvim found no matching items", vim.log.levels.INFO)
    return 0
  end

  local buffer = opts.buffer or vim.api.nvim_get_current_buf()
  local row = opts.row or vim.api.nvim_win_get_cursor(0)[1]
  vim.api.nvim_buf_set_lines(buffer, row - 1, row - 1, false, lines)
  return #lines
end

local function split_text_lines(text)
  return vim.split(tostring(text or ""), "\n", { plain = true, trimempty = false })
end

local function visual_region_text(buffer, line1, line2)
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_line = start_pos[2]
  local end_line = end_pos[2]

  if start_line == 0 or end_line == 0 then
    return nil
  end

  if math.min(start_line, end_line) ~= line1 or math.max(start_line, end_line) ~= line2 then
    return nil
  end

  if start_pos[3] >= vim.v.maxcol or end_pos[3] >= vim.v.maxcol then
    return nil
  end

  local sline = start_pos[2]
  local scol = start_pos[3]
  local eline = end_pos[2]
  local ecol = end_pos[3]

  if sline > eline or (sline == eline and scol > ecol) then
    sline, eline = eline, sline
    scol, ecol = ecol, scol
  end

  local chunks = vim.api.nvim_buf_get_text(buffer, sline - 1, scol - 1, eline - 1, ecol, {})
  return table.concat(chunks, "\n")
end

local function buffer_range_text(opts)
  if opts.text ~= nil then
    return tostring(opts.text)
  end

  local buffer = opts.buffer or vim.api.nvim_get_current_buf()
  local line_count = vim.api.nvim_buf_line_count(buffer)
  local line1 = math.max(opts.line1 or 1, 1)
  local line2 = math.min(opts.line2 or line_count, line_count)

  local visual_text = opts.use_visual == true and visual_region_text(buffer, line1, line2) or nil
  if visual_text ~= nil then
    return visual_text
  end

  return table.concat(vim.api.nvim_buf_get_lines(buffer, line1 - 1, line2, false), "\n")
end

local function strip_inline_metadata_fields(line)
  local stripped = tostring(line or ""):gsub("%s*%[[%w_%-]+%s*::%s*.-%]", "")
  stripped = stripped:gsub("%s+$", "")
  return stripped
end

local function markdown_link(title, url)
  local target = trim(url)
  if target == "" then
    return trim(title)
  end

  local label = trim(title)
  if label == "" then
    label = target
  end

  label = label:gsub("\\", "\\\\"):gsub("%[", "\\["):gsub("%]", "\\]")
  return string.format("[%s](<%s>)", label, target)
end

local function escape_html(text)
  local escaped = tostring(text or "")
  escaped = escaped:gsub("&", "&amp;")
  escaped = escaped:gsub("<", "&lt;")
  escaped = escaped:gsub(">", "&gt;")
  escaped = escaped:gsub('"', "&quot;")
  return escaped
end

local function escape_markdown_table_cell(text)
  local escaped = tostring(text or "")
  escaped = escaped:gsub("\r", "")
  escaped = escaped:gsub("\n", " ")
  escaped = escaped:gsub("|", "\\|")
  return escaped
end

local function trim_frontmatter_value_line(line)
  local normalized = tostring(line or "")
  if normalized:sub(1, 2) == "  " then
    normalized = normalized:sub(3)
  end

  normalized = normalized:gsub("%s+$", "")
  return normalized
end

local function frontmatter_rows(lines)
  local rows = {}
  local current

  for _, line in ipairs(lines or {}) do
    local key, value = line:match("^([^:%s][^:]-):%s*(.-)%s*$")
    if key then
      if current then
        table.insert(rows, current)
      end

      current = {
        key = trim(key),
        values = {},
      }

      if value ~= "" then
        table.insert(current.values, value)
      end
    elseif current then
      local nested = trim_frontmatter_value_line(line)
      if nested ~= "" then
        table.insert(current.values, nested)
      end
    end
  end

  if current then
    table.insert(rows, current)
  end

  return rows
end

local function render_frontmatter_markdown_table(lines)
  local rows = frontmatter_rows(lines)
  if #rows == 0 then
    return {}
  end

  local rendered = {
    "## Metadata",
    "",
    "| Field | Value |",
    "| --- | --- |",
  }

  for _, row in ipairs(rows) do
    table.insert(rendered, string.format(
      "| %s | %s |",
      escape_markdown_table_cell(row.key),
      escape_markdown_table_cell(table.concat(row.values, " ; "))
    ))
  end

  table.insert(rendered, "")
  return rendered
end

local function render_frontmatter_html_table(lines)
  local rows = frontmatter_rows(lines)
  if #rows == 0 then
    return {}
  end

  local rendered = {
    "## Metadata",
    "",
    "<table>",
    "<thead><tr><th>Field</th><th>Value</th></tr></thead>",
    "<tbody>",
  }

  for _, row in ipairs(rows) do
    local values = {}
    for _, value in ipairs(row.values) do
      table.insert(values, escape_html(value))
    end

    local value_html = table.concat(values, "<br />")
    table.insert(rendered, string.format(
      "<tr><td>%s</td><td>%s</td></tr>",
      escape_html(row.key),
      value_html
    ))
  end

  table.insert(rendered, "</tbody>")
  table.insert(rendered, "</table>")
  table.insert(rendered, "")
  return rendered
end

local function normalize_markdown_line(line)
  local item = parser.parse_line(line)
  if not item then
    return strip_inline_metadata_fields(line)
  end

  local prefix = string.format("%s%s ", item.indent or "", item.marker or "-")
  local title = trim(item.title)

  if item.status == "@" then
    return prefix .. markdown_link(title, item.url)
  end

  local symbol = rich_task_symbols[item.status]
  if symbol then
    if title == "" then
      return prefix .. symbol
    end

    if rich_task_done_statuses[item.status] then
      title = string.format("~~%s~~", title)
    end

    return string.format("%s%s %s", prefix, symbol, title)
  end

  return prefix .. title
end

local function normalize_markdown_body_lines(body_lines)
  local normalized = {}
  local fence_marker

  for _, line in ipairs(body_lines or {}) do
    local marker = line:match("^%s*([`~])%1%1+")
    if marker then
      if not fence_marker then
        fence_marker = marker
      elseif fence_marker == marker then
        fence_marker = nil
      end

      table.insert(normalized, line)
    elseif fence_marker then
      table.insert(normalized, line)
    else
      table.insert(normalized, normalize_markdown_line(line))
    end
  end

  return normalized
end

local function normalize_markdown_for_rich_clipboard(text, opts)
  local frontmatter_lines, body_lines, has_frontmatter = frontmatter.split(split_text_lines(text))
  local normalized_body = normalize_markdown_body_lines(body_lines)
  local plain_lines = vim.deepcopy(normalized_body)
  local pandoc_lines = vim.deepcopy(normalized_body)

  if opts and opts.render_frontmatter_table == true and has_frontmatter then
    plain_lines = vim.list_extend(render_frontmatter_markdown_table(frontmatter_lines), plain_lines)
    pandoc_lines = vim.list_extend(render_frontmatter_html_table(frontmatter_lines), pandoc_lines)
  end

  return {
    text = table.concat(plain_lines, "\n"),
    pandoc = table.concat(pandoc_lines, "\n"),
  }
end

local function is_full_buffer_region(opts)
  if opts.full_buffer ~= nil then
    return opts.full_buffer == true
  end

  if opts.text ~= nil then
    return false
  end

  local buffer = opts.buffer or vim.api.nvim_get_current_buf()
  local line_count = vim.api.nvim_buf_line_count(buffer)
  local line1 = math.max(opts.line1 or 1, 1)
  local line2 = math.min(opts.line2 or line_count, line_count)
  return line1 == 1 and line2 == line_count
end

local function markdown_to_html(text)
  if vim.fn.executable("pandoc") ~= 1 then
    error("striked.nvim requires pandoc to convert markdown as rich text")
  end

  local result = system_result({ "pandoc", "--from", "gfm", "--to", "html", "--wrap=none" }, text)
  if result.code ~= 0 then
    local detail = trim(result.stderr) ~= "" and trim(result.stderr) or trim(result.stdout)
    error(string.format("striked.nvim pandoc conversion failed: %s", detail ~= "" and detail or "unknown error"))
  end

  return trim(result.stdout)
end

local function html_preview_document(html)
  return table.concat({
    "<!doctype html>",
    "<html>",
    "<head>",
    '<meta charset="utf-8" />',
    "<title>striked.nvim rich copy preview</title>",
    "<style>",
    "body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; margin: 0; background: #f6f7f9; color: #111827; }",
    "main { max-width: 960px; margin: 32px auto; padding: 24px 28px; background: #ffffff; border: 1px solid #d1d5db; border-radius: 12px; box-shadow: 0 10px 30px rgba(0, 0, 0, 0.08); }",
    "p.notice { margin-top: 0; color: #374151; font-size: 14px; }",
    "table { border-collapse: collapse; width: 100%; }",
    "th, td { border: 1px solid #d1d5db; padding: 8px 10px; text-align: left; vertical-align: top; }",
    "th { background: #f3f4f6; }",
    "pre, code { font-family: 'SFMono-Regular', Consolas, monospace; }",
    "pre { background: #f3f4f6; padding: 12px; border-radius: 8px; overflow-x: auto; }",
    "blockquote { margin-left: 0; padding-left: 16px; border-left: 4px solid #d1d5db; color: #4b5563; }",
    "</style>",
    "</head>",
    "<body>",
    "<main>",
    "<p class=\"notice\"><strong>Manual fallback:</strong> copy this rendered content from the browser and paste it into Teams.</p>",
    html,
    "</main>",
    "</body>",
    "</html>",
  }, "\n")
end

local function open_html_preview(html)
  local path = vim.fn.tempname() .. ".html"
  local document = html_preview_document(html)
  local ok, err = pcall(vim.fn.writefile, vim.split(document, "\n", { plain = true, trimempty = false }), path)
  if not ok then
    return nil, string.format("striked.nvim could not write rich copy preview: %s", err)
  end

  local uri = vim.uri_from_fname(path)
  if not pickers.open_url(uri) then
    return nil, string.format("striked.nvim could not open rich copy preview: %s", path)
  end

  return {
    path = path,
    uri = uri,
  }
end

local function rich_copy_browser_fallback(html, label)
  local preview, err = open_html_preview(html)
  if not preview then
    error(err)
  end

  vim.notify(
    string.format("striked.nvim opened %s preview in the browser for manual copy: %s", label, preview.path),
    vim.log.levels.INFO
  )

  return {
    backend = "browser",
    browser_fallback = true,
    preview_path = preview.path,
    preview_uri = preview.uri,
  }
end

local function notify_rich_clipboard(label, result)
  local mode
  if result.html_only then
    mode = result.downgraded and "HTML only fallback" or "HTML only"
  else
    mode = "text + HTML"
  end

  vim.notify(string.format("striked.nvim copied %s using %s (%s)", label, result.backend, mode), vim.log.levels.INFO)
end

local function copy_markdown_region(opts)
  local source = buffer_range_text(opts)
  if trim(source) == "" then
    vim.notify("striked.nvim found no markdown to copy", vim.log.levels.INFO)
    return nil
  end

  local normalized = normalize_markdown_for_rich_clipboard(source, {
    render_frontmatter_table = is_full_buffer_region(opts),
  })
  if trim(normalized.text) == "" then
    vim.notify("striked.nvim found no markdown content after normalization", vim.log.levels.INFO)
    return nil
  end

  local html = markdown_to_html(normalized.pandoc)
  local result, err = clipboard.copy_rich({
    text = normalized.text,
    html = html,
    html_only = opts.html_only == true,
  })

  if not result then
    if not clipboard.copyq_running() then
      result = rich_copy_browser_fallback(html, "markdown")
    else
      error(err)
    end
  end

  if not result.browser_fallback then
    notify_rich_clipboard("markdown", result)
  end

  return {
    source = source,
    normalized = normalized.text,
    pandoc = normalized.pandoc,
    html = html,
    backend = result.backend,
    html_only = result.html_only,
    downgraded = result.downgraded,
    browser_fallback = result.browser_fallback,
    preview_path = result.preview_path,
    preview_uri = result.preview_uri,
  }
end

local function copy_clipboard_text(opts)
  local source, read_result = clipboard.read_text()
  if source == nil then
    error(read_result)
  end

  if trim(source) == "" then
    vim.notify("striked.nvim clipboard is empty", vim.log.levels.INFO)
    return nil
  end

  local normalized = normalize_markdown_for_rich_clipboard(source)
  if trim(normalized.text) == "" then
    vim.notify("striked.nvim found no markdown content after normalization", vim.log.levels.INFO)
    return nil
  end

  local html = markdown_to_html(normalized.pandoc)
  local result, err = clipboard.copy_rich({
    text = source,
    html = html,
    html_only = opts.html_only == true,
  })

  if not result then
    if not clipboard.copyq_running() then
      result = rich_copy_browser_fallback(html, "clipboard markdown")
    else
      error(err)
    end
  end

  if not result.browser_fallback then
    notify_rich_clipboard("clipboard markdown", result)
  end

  return {
    source = source,
    normalized = normalized.text,
    pandoc = normalized.pandoc,
    html = html,
    backend = result.backend,
    html_only = result.html_only,
    downgraded = result.downgraded,
    read_backend = read_result.backend,
    browser_fallback = result.browser_fallback,
    preview_path = result.preview_path,
    preview_uri = result.preview_uri,
  }
end

local function journal_date(text)
  local value = trim(text)
  if value == "" then
    return dates.today()
  end

  if not dates.is_valid(value) then
    error(string.format("striked.nvim expected a valid journal date, got %q", text or ""))
  end

  return value
end

local function journal_buffer_date(opts)
  local current_path = vim.api.nvim_buf_get_name(0)
  if current_path == "" then
    return nil
  end

  local relative = paths.relative_path(paths.note_subdir("journal", opts), current_path)
  if relative == paths.normalize(current_path) then
    return nil
  end

  local date = relative:match("^(%d%d%d%d%-%d%d%-%d%d)%.md$")
  if date and dates.is_valid(date) then
    return date
  end

  return nil
end

local function journal_reference_date(opts)
  return journal_date(opts.date or journal_buffer_date(opts) or dates.today())
end

local function journal_dates(opts)
  local directory = paths.ensure_dir(paths.note_subdir("journal", opts))
  local entries = {}
  local handle = uv.fs_scandir(directory)

  if not handle then
    return entries
  end

  while true do
    local name, entry_type = uv.fs_scandir_next(handle)
    if not name then
      break
    end

    if entry_type == "file" then
      local date = name:match("^(%d%d%d%d%-%d%d%-%d%d)%.md$")
      if date and dates.is_valid(date) then
        table.insert(entries, date)
      end
    end
  end

  table.sort(entries)
  return entries
end

local function existing_journal_date(reference, direction, opts)
  local entries = journal_dates(opts)
  if direction > 0 then
    for _, date in ipairs(entries) do
      if date > reference then
        return date
      end
    end
  else
    for index = #entries, 1, -1 do
      if entries[index] < reference then
        return entries[index]
      end
    end
  end

  return nil
end

function M.add_bookmark(opts)
  opts = opts or {}

  local target = resolve_target(opts)
  local line = build_bookmark_line(opts)
  local similar = query.find_similar_bookmarks({
    title = opts.title,
    url = opts.url,
  }, opts)

  if opts.on_similar then
    opts.on_similar(similar)
  end

  if opts.skip_if_similar and #similar > 0 then
    return {
      inserted = false,
      line = line,
      path = target.path,
      similar = similar,
    }
  end

  local inserted_lnum
  if target.use_buffer then
    inserted_lnum = insert_into_buffer(target.buffer, line, opts)
  else
    inserted_lnum = insert_into_file(target.path, line, opts)
  end

  local item = parser.parse_line(line, {
    path = target.path,
    relative_path = paths.relative_path(paths.resolve_root(opts), target.path),
    lnum = inserted_lnum,
    col = 1,
  })

  return {
    inserted = true,
    item = item,
    line = line,
    lnum = inserted_lnum,
    path = target.path,
    similar = similar,
  }
end

function M.create_note(opts)
  opts = opts or {}

  local kind = trim(opts.kind)
  if kind == "" then
    error("striked.nvim requires opts.kind to create a note")
  end

  paths.ensure_notes_tree(opts)

  local id = unique_note_id(kind, opts)
  local rendered = templates.render(kind, vim.tbl_extend("force", opts, { id = id }))
  local path = opts.path and paths.normalize(opts.path) or paths.join(paths.note_subdir(rendered.directory, opts), rendered.filename)

  if vim.fn.filereadable(path) == 1 and opts.overwrite ~= true then
    error(string.format("striked.nvim note already exists: %s", path))
  end

  write_file(path, rendered.lines)

  if opts.open ~= false then
    open_file(path)
  end

  return {
    kind = kind,
    id = id,
    path = path,
    relative_path = paths.relative_path(paths.resolve_root(opts), path),
    lines = rendered.lines,
  }
end

function M.ingest_meeting_ics(opts)
  opts = opts or {}

  paths.ensure_notes_tree(opts)

  local source_path = resolve_ics_path(opts)
  local imported = ics.parse_file(source_path)
  local existing_path, existing_document = existing_meeting(imported.source_key, imported.uid, imported.occurrence_id, opts)
  local result

  if existing_path then
    local existing_scalars = existing_document.top_level_scalars or {}
    local merged = meeting_template_opts(imported, opts, existing_scalars, trim(existing_scalars.id or vim.fn.fnamemodify(existing_path, ":t:r")))
    local rendered = templates.render("meeting", merged)
    local fields = append_scalar_extras(rendered.fields, existing_scalars, legacy_meeting_scalar_keys)

    update_note_frontmatter(existing_path, fields)

    result = {
      created = false,
      updated = true,
      deleted_source = false,
      source_path = source_path,
      path = existing_path,
      relative_path = paths.relative_path(paths.resolve_root(opts), existing_path),
      id = merged.id,
      meeting = imported,
    }

    notify_note_updated("meeting", existing_path, opts)
  else
    local id = unique_note_id("meeting", opts)
    local created = M.create_note(vim.tbl_extend("force", meeting_template_opts(imported, opts, {}, id), {
      kind = "meeting",
      id = id,
      open = false,
    }))

    result = {
      created = true,
      updated = false,
      deleted_source = false,
      source_path = source_path,
      path = created.path,
      relative_path = created.relative_path,
      id = created.id,
      meeting = imported,
    }

    notify_note_created("meeting", result)
  end

  result.deleted_source = maybe_delete_source(source_path, opts)

  if opts.open ~= false then
    open_file(result.path)
  end

  return result
end

function M.open_journal(opts)
  opts = opts or {}

  paths.ensure_notes_tree(opts)

  local date = journal_date(opts.date)
  local path = journal_path(date, opts)
  local created = false

  if vim.fn.filereadable(path) == 0 then
    local rendered = templates.render("journal", { date = date })
    write_file(path, rendered.lines)
    created = true
  end

  if opts.open ~= false then
    open_file(path)
  end

  local result = {
    kind = "journal",
    date = date,
    path = path,
    relative_path = paths.relative_path(paths.resolve_root(opts), path),
    created = created,
  }

  if created then
    notify_note_created("journal", result)
  end

  return result
end

function M.journal_today(opts)
  return M.open_journal(vim.tbl_extend("force", opts or {}, { date = dates.today() }))
end

function M.journal_tomorrow(opts)
  return M.open_journal(vim.tbl_extend("force", opts or {}, { date = dates.shift(journal_reference_date(opts or {}), 1) }))
end

function M.journal_yesterday(opts)
  return M.open_journal(vim.tbl_extend("force", opts or {}, { date = dates.shift(journal_reference_date(opts or {}), -1) }))
end

function M.journal_next(opts)
  opts = opts or {}

  local next_date = existing_journal_date(journal_reference_date(opts), 1, opts)
  if not next_date then
    vim.notify("striked.nvim could not find a later journal note", vim.log.levels.INFO)
    return nil
  end

  return M.open_journal(vim.tbl_extend("force", opts, { date = next_date }))
end

function M.journal_previous(opts)
  opts = opts or {}

  local previous_date = existing_journal_date(journal_reference_date(opts), -1, opts)
  if not previous_date then
    vim.notify("striked.nvim could not find an earlier journal note", vim.log.levels.INFO)
    return nil
  end

  return M.open_journal(vim.tbl_extend("force", opts, { date = previous_date }))
end

function M.create_topic(opts)
  return M.create_note(vim.tbl_extend("force", opts or {}, { kind = "topic" }))
end

function M.create_project(opts)
  return M.create_note(vim.tbl_extend("force", opts or {}, { kind = "project" }))
end

function M.create_sprint(opts)
  return M.create_note(vim.tbl_extend("force", opts or {}, { kind = "sprint" }))
end

function M.create_meeting(opts)
  return M.create_note(vim.tbl_extend("force", opts or {}, { kind = "meeting" }))
end

local function prompt_title(kind, opts, callback)
  vim.ui.input({ prompt = string.format("%s title: ", kind) }, function(title)
    title = trim(title)
    if title == "" then
      return
    end

    callback(vim.tbl_extend("force", opts, { title = title }))
  end)
end

local function prompt_sprint(opts)
  prompt_title("Sprint", opts, function(title_opts)
    vim.ui.input({ prompt = "Sprint project: " }, function(project)
      if project == nil then
        return
      end

      vim.ui.input({ prompt = "Sprint start date [today]: " }, function(start_date)
        if start_date == nil then
          return
        end

        vim.ui.input({ prompt = "Sprint end date [today]: " }, function(end_date)
          if end_date == nil then
            return
          end

          local result = M.create_sprint(vim.tbl_extend("force", title_opts, {
            project = trim(project),
            startDate = trim(start_date),
            endDate = trim(end_date),
          }))
          notify_note_created("sprint", result)
        end)
      end)
    end)
  end)
end

local function prompt_meeting(opts)
  prompt_title("Meeting", opts, function(title_opts)
    vim.ui.input({ prompt = "Meeting project: " }, function(project)
      if project == nil then
        return
      end

      vim.ui.input({ prompt = "Meeting date [today]: ", default = dates.today() }, function(date)
        if date == nil then
          return
        end

        vim.ui.input({ prompt = "Full day? [y/N]: " }, function(full_day)
          if full_day == nil then
            return
          end

          local result = M.create_meeting(vim.tbl_extend("force", title_opts, {
            project = trim(project),
            date = trim(date) ~= "" and trim(date) or dates.today(),
            fullDay = trim(full_day):lower():sub(1, 1) == "y",
            attendees = {},
          }))
          notify_note_created("meeting", result)
        end)
      end)
    end)
  end)
end

function M.prompt_create_note(kind, opts)
  opts = opts or {}
  local normalized = trim(kind):lower()

  if normalized == "sprint" then
    prompt_sprint(opts)
    return
  end

  if normalized == "meeting" then
    prompt_meeting(opts)
    return
  end

  prompt_title(normalized:gsub("^%l", string.upper), opts, function(title_opts)
    local result = M.create_note(vim.tbl_extend("force", title_opts, { kind = normalized }))
    notify_note_created(normalized, result)
  end)
end

function M.prompt_create_topic(opts)
  return M.prompt_create_note("topic", opts)
end

function M.prompt_create_project(opts)
  return M.prompt_create_note("project", opts)
end

function M.prompt_create_sprint(opts)
  return M.prompt_create_note("sprint", opts)
end

function M.prompt_create_meeting(opts)
  return M.prompt_create_note("meeting", opts)
end

function M.prompt_journal_date(opts)
  opts = opts or {}

  vim.ui.input({ prompt = "Journal date [YYYY-MM-DD]: ", default = dates.today() }, function(date)
    if date == nil then
      return
    end

    M.open_journal(vim.tbl_extend("force", opts, { date = trim(date) }))
  end)
end

function M.build_log(opts)
  opts = opts or {}

  local start_date, end_date = normalized_range(opts)
  local items = query.log_items(start_date, end_date, opts)
  local inserted = insert_lines_at_cursor(list_lines(items), opts)

  return {
    start_date = start_date,
    end_date = end_date,
    items = items,
    inserted = inserted,
  }
end

function M.print_focused(opts)
  opts = opts or {}

  local items = query.focused(opts)
  local inserted = insert_lines_at_cursor(list_lines(items), opts)

  return {
    items = items,
    inserted = inserted,
  }
end

function M.copy_markdown_rich(opts)
  return copy_markdown_region(opts or {})
end

function M.copy_markdown_html_only(opts)
  return copy_markdown_region(vim.tbl_extend("force", opts or {}, { html_only = true }))
end

function M.upgrade_clipboard_rich(opts)
  return copy_clipboard_text(opts or {})
end

function M.upgrade_clipboard_html_only(opts)
  return copy_clipboard_text(vim.tbl_extend("force", opts or {}, { html_only = true }))
end

function M.prompt_build_log(opts)
  opts = opts or {}

  vim.ui.input({ prompt = "Log start date [YYYY-MM-DD]: " }, function(start_date)
    start_date = trim(start_date)
    if start_date == "" then
      return
    end

    vim.ui.input({ prompt = "Log end date [YYYY-MM-DD, blank=today]: " }, function(end_date)
      if end_date == nil then
        return
      end

      local result = M.build_log(vim.tbl_extend("force", opts, {
        startDate = start_date,
        endDate = trim(end_date),
      }))

      vim.notify(string.format("striked.nvim inserted %d log item(s)", result.inserted), vim.log.levels.INFO)
    end)
  end)
end

function M.prompt_add_bookmark(opts)
  opts = opts or {}

  vim.ui.input({ prompt = "Bookmark URL: " }, function(url)
    url = trim(url)
    if url == "" then
      return
    end

    vim.ui.input({ prompt = "Bookmark title: " }, function(title)
      title = trim(title)
      if title == "" then
        return
      end

      local preview_similar = query.find_similar_bookmarks({ title = title, url = url }, opts)
      similar_notification(preview_similar)

      if #preview_similar > 0 and opts.show_similar_picker ~= false then
        pcall(pickers.pick_items, preview_similar, {
          kind = "bookmark",
          prompt_title = "Similar Bookmarks",
        })
      end

      local result = M.add_bookmark(vim.tbl_extend("force", opts, {
        title = title,
        url = url,
      }))

      vim.notify(string.format("striked.nvim inserted bookmark at %s:%d", result.path, result.lnum), vim.log.levels.INFO)
    end)
  end)
end

return M
