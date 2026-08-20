-- Score-driven scheduling. Pure date arithmetic with an injected `now`, so the
-- module never touches the Neovim API and stays deterministic under tests.

local M = {}

M.DEFAULTS = {
  again_minutes = 10, -- score 1: see again very soon
  mid_hours = 12, -- score 2: at least twice a day
  good_days = 3, -- score 3: every few days
  starting_ease = 2.5,
  min_ease = 1.3,
  max_ease = 2.8,
}

local SECONDS_PER_DAY = 86400

local function option(opts, key)
  return (opts and opts[key]) or M.DEFAULTS[key]
end

local function round(value, decimals)
  local factor = 10 ^ decimals
  return math.floor(value * factor + 0.5) / factor
end

local function format_number(value, decimals)
  local text = string.format("%." .. decimals .. "f", value)
  if text:find("%.") then
    text = text:gsub("0+$", ""):gsub("%.$", "")
  end
  return text
end

function M.parse_due(value)
  if type(value) ~= "string" then
    return nil
  end

  local year, month, day, hour, minute = value:match("^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?) +(%d%d?):(%d%d)%s*$")
  if year then
    return os.time({
      year = tonumber(year),
      month = tonumber(month),
      day = tonumber(day),
      hour = tonumber(hour),
      min = tonumber(minute),
    })
  end

  year, month, day = value:match("^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?)%s*$")
  if year then
    return os.time({
      year = tonumber(year),
      month = tonumber(month),
      day = tonumber(day),
      hour = 0,
      min = 0,
    })
  end

  return nil
end

function M.format_due(epoch)
  return os.date("%Y-%m-%d %H:%M", epoch)
end

function M.card_state(card, opts)
  local values = (card and card.values) or {}
  local interval = tonumber(values.interval)
  if interval and interval <= 0 then
    interval = nil
  end

  return {
    interval = interval,
    ease = tonumber(values.ease) or option(opts, "starting_ease"),
  }
end

function M.is_due(card, now)
  local due = M.parse_due((card and card.values) and card.values.due)
  return due == nil or due <= now
end

function M.due_key(card)
  return M.parse_due((card and card.values) and card.values.due) or 0
end

function M.humanize(seconds)
  if seconds < 3600 then
    return string.format("in %d min", math.max(1, math.floor(seconds / 60 + 0.5)))
  end
  if seconds < SECONDS_PER_DAY then
    return string.format("in %d h", math.floor(seconds / 3600 + 0.5))
  end
  return string.format("in %d d", math.floor(seconds / SECONDS_PER_DAY + 0.5))
end

-- Returns the store.set_card_fields update list plus the due epoch for the
-- rating, following a small SM-2-style schedule.
function M.review_updates(card, score, now, opts)
  local state = M.card_state(card, opts)
  local interval
  local ease

  if score == 1 then
    interval = 0
    ease = math.max(option(opts, "min_ease"), state.ease - 0.2)
  elseif score == 2 then
    interval = state.interval and state.interval * 1.2 or option(opts, "mid_hours") / 24
    ease = state.ease
  else
    interval = state.interval and state.interval * state.ease or option(opts, "good_days")
    ease = math.min(option(opts, "max_ease"), state.ease + 0.05)
  end

  interval = round(interval, 1)
  ease = round(ease, 2)

  local due
  if interval == 0 then
    due = now + option(opts, "again_minutes") * 60
  else
    due = now + interval * SECONDS_PER_DAY
  end

  local updates = {
    { field = "score", value = tostring(score) },
    { field = "reviewed", value = os.date("%Y-%m-%d", now) },
    { field = "due", value = M.format_due(due) },
    { field = "interval", value = format_number(interval, 1) },
    { field = "ease", value = format_number(ease, 2) },
  }

  return updates, due
end

return M
