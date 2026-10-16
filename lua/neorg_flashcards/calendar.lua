local history = require("neorg_flashcards.history")
local schedule = require("neorg_flashcards.schedule")
local canvas = require("neorg_flashcards.ui.canvas")
local highlights = require("neorg_flashcards.highlights")
local M = {}

function M.day(epoch)
  return os.date("%Y-%m-%d", epoch)
end

function M.shift(epoch, days, months)
  local date = os.date("*t", epoch)
  return os.time({ year = date.year, month = date.month + (months or 0), day = date.day + (days or 0), hour = 12 })
end

function M.month(epoch, delta)
  local date = os.date("*t", epoch)
  return os.time({ year = date.year, month = date.month + (delta or 0), day = 1, hour = 12 })
end

function M.activity(entries)
  local days = {}
  for _, entry in ipairs(history.effective_entries(entries)) do
    if entry.epoch then
      local key = M.day(entry.epoch)
      local day = days[key]
        or {
          answers = 0,
          unique = 0,
          ids = {},
          entries = {},
          ratings = { 0, 0, 0 },
          duration_ms = 0,
          timed = 0,
          hints = 0,
        }
      days[key] = day
      day.answers = day.answers + 1
      local id = entry.card_id
      if id and not day.ids[id] then
        day.ids[id] = true
        day.unique = day.unique + 1
      end
      table.insert(day.entries, entry)
      local rating = tonumber(entry.rating)
      if day.ratings[rating] then
        day.ratings[rating] = day.ratings[rating] + 1
      end
      local duration = tonumber(entry.duration_ms)
        or (tonumber(entry.duration_seconds) and entry.duration_seconds * 1000)
      if duration and duration >= 0 then
        day.duration_ms = day.duration_ms + duration
        day.timed = day.timed + 1
      end
      if entry.hint_used or (tonumber(entry.hints_used) or 0) > 0 then
        day.hints = day.hints + 1
      end
    end
  end
  return days
end

function M.progress(entries, metadata, now)
  now = now or os.time()
  local days = M.activity(entries)
  local key = M.day(now)
  local today = days[key] or { unique = 0, answers = 0 }
  local weekday = (os.date("*t", now).wday + 5) % 7
  local active, week_unique, week_answers = 0, 0, 0
  local previous_unique, previous_answers = 0, 0
  local streak = 0
  local first = days[key] and 0 or 1
  for offset = first, first + vim.tbl_count(days) do
    if not days[M.day(M.shift(now, -offset))] then
      break
    end
    streak = streak + 1
  end
  for offset = 0, 6 do
    local day = days[M.day(M.shift(now, offset - weekday))]
    if day then
      active = active + 1
      week_unique = week_unique + day.unique
      week_answers = week_answers + day.answers
    end
    local previous = days[M.day(M.shift(now, offset - weekday - 7))]
    if previous then
      previous_unique = previous_unique + previous.unique
      previous_answers = previous_answers + previous.answers
    end
  end
  return {
    unique = today.unique,
    answers = today.answers,
    goal = metadata.goals[key] or metadata.goal,
    active_days = active,
    week_unique = week_unique,
    week_answers = week_answers,
    previous_unique = previous_unique,
    previous_answers = previous_answers,
    streak = streak,
    days = days,
  }
end

function M.scheduled(cards, selected, now, config)
  local result = {}
  local key, today = M.day(selected), M.day(now)
  for _, card in ipairs(cards) do
    local status = schedule.card_state(card, now, config.scheduling)
    if status.availability == "active" then
      if key == today and schedule.is_due(card, now, config.scheduling) then
        table.insert(result, card)
      elseif key >= today and status.due and status.due > now and M.day(status.due) == key then
        table.insert(result, card)
      end
    end
  end
  return result
end

function M.render(entries, metadata, selected, width, ascii, now, height)
  now = now or os.time()
  width = math.min(width, 39)
  local h, c = highlights.groups.desk, canvas.new(width, ascii)
  local cell = math.max(3, math.min(5, math.floor((width - 5) / 7)))
  local left = math.max(3, math.floor((width - cell * 7) / 2) + 1)
  local data = M.progress(entries, metadata, now)
  local compact = (height or 40) <= 12
  local start = M.month(selected)
  local offset = (os.date("*t", start).wday + 5) % 7
  c:box(1, 1, width, compact and 10 or 15, h.edge, os.date("%B %Y", selected):upper())
  if not compact then
    c:put(3, 3, canvas.fit("h/l day  j/k week  [/] month", width - 4), h.muted)
  end
  for index, name in ipairs({ "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" }) do
    c:put(compact and 2 or 5, left + (index - 1) * cell, name, h.muted)
  end
  local month, selected_key = os.date("%Y-%m", selected), M.day(selected)
  for index = 0, 41 do
    local epoch = M.shift(start, index - offset)
    if os.date("%Y-%m", epoch) == month then
      local key, y, x = M.day(epoch), (compact and 3 or 6) + math.floor(index / 7), left + (index % 7) * cell
      local day, target = data.days[key], metadata.goals[key]
      local marker = day and (target and target > 0 and day.unique >= target and "#" or "*") or " "
      local label = string.format("%2d", tonumber(os.date("%d", epoch)))
      if key == selected_key then
        c:put(y, x - 1, "[" .. label .. "]", h.selected)
      else
        c:put(
          y,
          x,
          label .. (key == M.day(now) and "T" or marker),
          key == M.day(now) and h.accent or (day and h.note or h.muted)
        )
      end
    end
  end
  c:put(compact and 9 or 12, 3, compact and "h/l day  j/k week  . today" or ". today   Enter inspect", h.accent)
  if not compact then
    c:put(14, 3, "* studied  # goal  T today", h.muted)
  end
  return c:finish()
end

return M
