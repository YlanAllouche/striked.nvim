local M = {}

local SECONDS_PER_DAY = 24 * 60 * 60

function M.parse(text)
  local value = vim.trim(text or "")
  local year, month, day = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if not year then
    return nil
  end

  local time = os.time({
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    hour = 12,
  })

  if not time or os.date("%Y-%m-%d", time) ~= value then
    return nil
  end

  return time
end

function M.is_valid(text)
  return M.parse(text) ~= nil
end

function M.today()
  return os.date("%Y-%m-%d")
end

function M.shift(text, days)
  local time = M.parse(text)
  if not time then
    error(string.format("striked.nvim expected an ISO date, got %q", text or ""))
  end

  return os.date("%Y-%m-%d", time + ((days or 0) * SECONDS_PER_DAY))
end

return M
