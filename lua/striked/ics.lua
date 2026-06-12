local M = {}

local function trim(text)
  return vim.trim(text or "")
end

local function unescape_text(text)
  local value = tostring(text or "")
    :gsub("\\N", "\n")
    :gsub("\\n", "\n")
    :gsub("\\,", ",")
    :gsub("\\;", ";")
    :gsub("\\\\", "\\")

  return value
end

local function url_decode(text)
  local value = tostring(text or "")
    :gsub("%%+", " ")
    :gsub("%%(%x%x)", function(byte)
      return string.char(tonumber(byte, 16))
    end)

  return value
end

local function unfold(lines)
  local unfolded = {}

  for _, line in ipairs(lines or {}) do
    if line:match("^[ \t]") and #unfolded > 0 then
      unfolded[#unfolded] = unfolded[#unfolded] .. line:sub(2)
    else
      table.insert(unfolded, line)
    end
  end

  return unfolded
end

local function parse_property(line)
  local head, value = line:match("^([^:]+):(.*)$")
  if not head then
    return nil
  end

  local name, params_text = head:match("^([^;]+);?(.*)$")
  local params = {}

  for param in (";" .. params_text):gmatch(";([^;]+)") do
    local key, param_value = param:match("^([^=]+)=(.*)$")
    if key then
      params[key:upper()] = unescape_text(param_value:gsub('^"(.*)"$', "%1"))
    else
      params[param:upper()] = true
    end
  end

  return name:upper(), params, value
end

local function parse_datetime(raw, params)
  local value = trim(raw)
  if value == "" then
    return nil
  end

  local date_only = params.VALUE == "DATE" or value:match("^%d%d%d%d%d%d%d%d$") ~= nil
  if date_only then
    local year, month, day = value:match("^(%d%d%d%d)(%d%d)(%d%d)$")
    if not year then
      return { raw = value, date = value, iso = value, full_day = true }
    end

    local date = string.format("%s-%s-%s", year, month, day)
    return {
      raw = value,
      date = date,
      iso = date,
      full_day = true,
      timezone = params.TZID,
    }
  end

  local year, month, day, hour, minute, second, zulu = value:match("^(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d?%d?)(Z?)$")
  if not year then
    return { raw = value, date = value, iso = value, full_day = false, timezone = params.TZID }
  end

  second = second ~= "" and second or "00"
  local date = string.format("%s-%s-%s", year, month, day)
  local iso = string.format("%sT%s:%s:%s%s", date, hour, minute, second, zulu == "Z" and "Z" or "")

  return {
    raw = value,
    date = date,
    iso = iso,
    full_day = false,
    timezone = params.TZID,
  }
end

local function parse_person(params, value)
  local email = trim((value or ""):gsub("^mailto:", ""))
  local person = {}

  if trim(params.CN or "") ~= "" then
    person.name = trim(params.CN)
  end

  if email ~= "" then
    person.email = email
  end

  if trim(params.ROLE or "") ~= "" then
    person.role = trim(params.ROLE)
  end

  return person
end

local function first_non_empty(...)
  for index = 1, select("#", ...) do
    local value = select(index, ...)
    if trim(value) ~= "" then
      return trim(value)
    end
  end

  return nil
end

local function extract_first_url(text)
  local url = tostring(text or ""):match("https://%S+")
  if not url then
    return nil
  end

  while url:match("[]>,%)]$") do
    url = url:sub(1, -2)
  end

  return trim(url)
end

local function extract_label_value(text, label)
  local value = tostring(text or ""):match(label .. ":%s*([^\n]+)")
  return first_non_empty(value)
end

local function description_details(text)
  return {
    join_url = extract_first_url(text),
    meeting_id = extract_label_value(text, "Meeting ID"),
    passcode = extract_label_value(text, "Passcode"),
    phone_conference_id = extract_label_value(text, "Phone conference ID"),
  }
end

local function html_details(html)
  local details = {}
  local original_sources = {}

  for originalsrc in tostring(html or ""):gmatch('originalsrc="([^"]+)"') do
    table.insert(original_sources, url_decode(originalsrc))
  end

  if #original_sources == 0 then
    for href in tostring(html or ""):gmatch('href="([^"]+)"') do
      table.insert(original_sources, url_decode(href))
    end
  end

  for _, url in ipairs(original_sources) do
    if not details.join_url and url:match("teams%.microsoft%.com/meet/") then
      details.join_url = url
    elseif not details.system_reference_url and url:match("teams%.microsoft%.com/.*/thread%.v2") then
      details.system_reference_url = url
    elseif not details.organizer_options_url and url:match("teams%.microsoft%.com/meetingOptions/%?") then
      details.organizer_options_url = url
      details.organizer_id = url:match("[?&]organizerId=([^&]+)")
      details.tenant_id = url:match("[?&]tenantId=([^&]+)")
      details.thread_id = url:match("[?&]threadId=([^&]+)")
    end

    if not details.thread_id then
      details.thread_id = url:match("/l/meetup%-join/([^/]+)/0")
    end
  end

  return details
end

local function merge_teams_details(description, html)
  local description_data = description_details(description)
  local html_data = html_details(html)
  local teams = {
    meetingId = first_non_empty(description_data.meeting_id),
    passcode = first_non_empty(description_data.passcode),
    phoneConferenceId = first_non_empty(description_data.phone_conference_id),
    threadId = first_non_empty(html_data.thread_id),
    tenantId = first_non_empty(html_data.tenant_id),
    organizerId = first_non_empty(html_data.organizer_id),
    systemReferenceUrl = first_non_empty(html_data.system_reference_url),
    organizerOptionsUrl = first_non_empty(html_data.organizer_options_url),
  }

  local compact = {}
  for key, value in pairs(teams) do
    if value ~= nil then
      compact[key] = value
    end
  end

  return {
    join_url = first_non_empty(description_data.join_url, html_data.join_url),
    teams = compact,
  }
end

local function compact_person(person)
  local compact = {}

  for key, value in pairs(person or {}) do
    if trim(value) ~= "" then
      compact[key] = trim(value)
    end
  end

  return compact
end

local function occurrence_title(title, date, is_occurrence)
  local normalized_title = first_non_empty(title, "Meeting")
  local normalized_date = first_non_empty(date)

  if is_occurrence and normalized_date and not normalized_title:find(normalized_date, 1, true) then
    return string.format("%s (%s)", normalized_title, normalized_date)
  end

  return normalized_title
end

function M.parse_lines(lines)
  local event = {
    attendees = {},
  }
  local in_event = false

  for _, line in ipairs(unfold(lines)) do
    if line == "BEGIN:VEVENT" then
      in_event = true
    elseif line == "END:VEVENT" then
      break
    elseif in_event then
      local name, params, value = parse_property(line)
      if name == "UID" then
        event.uid = trim(value)
      elseif name == "SUMMARY" then
        event.title = trim(unescape_text(value))
      elseif name == "LOCATION" then
        event.location = trim(unescape_text(value))
      elseif name == "STATUS" then
        event.status = trim(value):lower()
      elseif name == "DESCRIPTION" then
        event.description = unescape_text(value)
      elseif name == "X-ALT-DESC" then
        event.html_description = value
      elseif name == "DTSTART" then
        event.start = parse_datetime(value, params)
      elseif name == "DTEND" then
        event["end"] = parse_datetime(value, params)
      elseif name == "RECURRENCE-ID" then
        event.recurrence_id = parse_datetime(value, params)
      elseif name == "ORGANIZER" then
        event.organizer = compact_person(parse_person(params, value))
      elseif name == "ATTENDEE" then
        table.insert(event.attendees, compact_person(parse_person(params, value)))
      end
    end
  end

  if not event.uid or not event.start then
    error("striked.nvim could not parse a usable VEVENT from the ICS file")
  end

  local teams = merge_teams_details(event.description or "", event.html_description or "")
  local occurrence = event.recurrence_id and event.recurrence_id.raw or event.start.raw
  local is_occurrence = event.recurrence_id ~= nil

  return {
    uid = event.uid,
    occurrence_id = occurrence,
    source_key = string.format("%s::%s", event.uid, occurrence),
    title = first_non_empty(event.title, "Meeting"),
    display_title = occurrence_title(event.title, event.start.date, is_occurrence),
    date = event.start.date,
    start_at = event.start.iso,
    end_at = event["end"] and event["end"].iso or "",
    full_day = event.start.full_day == true,
    is_occurrence = is_occurrence,
    status = event.status or "",
    location = event.location or "",
    join_url = teams.join_url or "",
    organizer = next(event.organizer or {}) and event.organizer or nil,
    attendees = event.attendees,
    teams = next(teams.teams or {}) and teams.teams or nil,
    description = event.description or "",
  }
end

function M.parse_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    error(string.format("striked.nvim could not read ICS file: %s", path))
  end

  return M.parse_lines(lines)
end

return M
