-- Score-driven scheduling. Pure date arithmetic with an injected `now`, so the
-- module never touches the Neovim API and stays deterministic under tests.

local M = {}

M.DEFAULTS = {
  again_minutes = 10, -- score 1: see again very soon
  hard_hours = 6, -- score 2: first retry later the same day
  good_days = 3, -- score 3: every few days
  starting_ease = 2.5,
  min_ease = 1.3,
  max_ease = 2.8,
  max_interval_days = 365,
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

local function nonnegative_integer(value, fallback)
  value = tonumber(value)
  if not value or value < 0 then
    return fallback or 0
  end
  return math.floor(value)
end

local function clamp(value, minimum, maximum)
  return math.min(maximum, math.max(minimum, value))
end

local function explicit_lifecycle(values)
  local value = tostring(values.lifecycle or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if value == "new" or value == "learning" or value == "review" or value == "relearning" then
    return value
  end
  return nil
end

local function inferred_reps(values)
  return nonnegative_integer(values.reps)
end

local function lifecycle_for(values, interval, reps, lapses)
  local explicit = explicit_lifecycle(values)
  if explicit then
    return explicit
  end
  if reps == 0 then
    return "new"
  end
  if not interval then
    return lapses > 0 and "relearning" or "learning"
  end
  return "review"
end

local function availability_for(values, now)
  local availability = tostring(values.availability or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local available_at = M.parse_due(values.available_at)

  if availability == "active" then
    return "active", available_at
  elseif availability == "suspended" then
    return "suspended", nil
  elseif availability == "buried" then
    if available_at and available_at <= now then
      return "active", available_at
    end
    return "buried", available_at
  end

  return "active", available_at
end

local function start_of_day(now)
  local date = os.date("*t", now)
  return os.time({
    year = date.year,
    month = date.month,
    day = date.day,
    hour = 0,
    min = 0,
    sec = 0,
  })
end

function M.parse_due(value)
  if type(value) ~= "string" then
    return nil
  end

  local function local_epoch(year, month, day, hour, minute)
    year = tonumber(year)
    month = tonumber(month)
    day = tonumber(day)
    hour = tonumber(hour)
    minute = tonumber(minute)

    if
      not year
      or year < 1
      or not month
      or month < 1
      or month > 12
      or not day
      or day < 1
      or day > 31
      or not hour
      or hour < 0
      or hour > 23
      or not minute
      or minute < 0
      or minute > 59
    then
      return nil
    end

    local ok, epoch = pcall(os.time, {
      year = year,
      month = month,
      day = day,
      hour = hour,
      min = minute,
      sec = 0,
    })
    if not ok or not epoch then
      return nil
    end

    -- os.time normalizes values such as February 30 or 25:00. Only accept a
    -- local timestamp when converting it back produces the exact input.
    local date_ok, roundtrip = pcall(os.date, "*t", epoch)
    if
      not date_ok
      or type(roundtrip) ~= "table"
      or roundtrip.year ~= year
      or roundtrip.month ~= month
      or roundtrip.day ~= day
      or roundtrip.hour ~= hour
      or roundtrip.min ~= minute
    then
      return nil
    end

    return epoch
  end

  local year, month, day, hour, minute = value:match("^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?) +(%d%d?):(%d%d)%s*$")
  if year then
    return local_epoch(year, month, day, hour, minute)
  end

  year, month, day = value:match("^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?)%s*$")
  if year then
    return local_epoch(year, month, day, 0, 0)
  end

  return nil
end

function M.format_due(epoch)
  return os.date("%Y-%m-%d %H:%M", epoch)
end

function M.card_state(card, now, opts)
  local values = (card and card.values) or {}
  now = now or os.time()
  local interval = tonumber(values.interval)
  if interval and interval <= 0 then
    interval = nil
  elseif interval then
    interval = math.min(interval, option(opts, "max_interval_days"))
  end

  local due = M.parse_due(values.due)
  local reps = inferred_reps(values)
  local lapses = nonnegative_integer(values.lapses)
  local availability, available_at = availability_for(values, now)
  local timing
  if not due then
    timing = "due"
  elseif due > now then
    timing = "scheduled"
  elseif due < start_of_day(now) then
    timing = "overdue"
  else
    timing = "due"
  end

  return {
    interval = interval,
    ease = clamp(
      tonumber(values.ease) or option(opts, "starting_ease"),
      option(opts, "min_ease"),
      option(opts, "max_ease")
    ),
    reps = reps,
    lapses = lapses,
    lifecycle = lifecycle_for(values, interval, reps, lapses),
    timing = timing,
    availability = availability,
    due = due,
    available_at = available_at,
  }
end

function M.is_available(card, now)
  return M.card_state(card, now).availability == "active"
end

function M.is_due(card, now)
  now = now or os.time()
  local state = M.card_state(card, now)
  return state.availability == "active" and (state.due == nil or state.due <= now)
end

function M.due_key(card)
  return M.parse_due((card and card.values) and card.values.due) or 0
end

-- Earliest future due epoch across the collection, for "next review at" hints.
function M.next_due(cards, now)
  now = now or os.time()
  local best = nil
  for _, card in ipairs(cards or {}) do
    local state = M.card_state(card, now)
    if state.availability ~= "suspended" then
      local due = state.due
      if state.availability == "buried" and state.available_at then
        due = math.max(due or now, state.available_at)
      elseif state.availability ~= "active" then
        due = nil
      end
      if due and due > now and (not best or due < best) then
        best = due
      end
    end
  end
  return best
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
  if score ~= 1 and score ~= 2 and score ~= 3 then
    error("rating must be 1, 2, or 3")
  end
  local state = M.card_state(card, now, opts)
  local interval
  local ease

  if score == 1 then
    interval = 0
    ease = math.max(option(opts, "min_ease"), state.ease - 0.2)
  elseif score == 2 then
    interval = state.interval and state.interval * 1.2 or option(opts, "hard_hours") / 24
    ease = state.ease
  else
    interval = state.interval and state.interval * state.ease or option(opts, "good_days")
    ease = math.min(option(opts, "max_ease"), state.ease + 0.05)
  end
  interval = math.min(interval, option(opts, "max_interval_days"))

  -- Sub-day intervals retain enough precision for custom hour values; the due
  -- timestamp itself is always calculated from the unrounded interval.
  local due_interval = interval
  local interval_decimals = interval < 1 and 6 or 1
  interval = round(interval, interval_decimals)
  ease = round(ease, 2)

  local due
  if interval == 0 then
    due = now + option(opts, "again_minutes") * 60
  else
    due = now + due_interval * SECONDS_PER_DAY
  end

  local updates = {
    { field = "score", value = tostring(score) },
    { field = "reviewed", value = os.date("%Y-%m-%d", now) },
    { field = "due", value = M.format_due(due) },
    { field = "interval", value = format_number(interval, interval_decimals) },
    { field = "ease", value = format_number(ease, 2) },
  }

  local lapses = state.lapses
  if score == 1 and state.lifecycle == "review" then
    lapses = lapses + 1
  end

  local lifecycle
  if score == 1 then
    lifecycle = (state.lifecycle == "new" or state.lifecycle == "learning") and "learning" or "relearning"
  elseif score == 2 and interval < 1 then
    lifecycle = state.lifecycle == "relearning" and "relearning" or "learning"
  else
    lifecycle = "review"
  end

  table.insert(updates, { field = "reps", value = tostring(state.reps + 1) })
  table.insert(updates, { field = "lapses", value = tostring(lapses) })
  table.insert(updates, { field = "lifecycle", value = lifecycle })

  return updates, due
end

return M
