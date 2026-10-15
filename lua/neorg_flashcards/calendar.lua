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
  local h, c = highlights.groups.desk, canvas.new(width, ascii)
  local cell = math.max(3, math.min(7, math.floor((width - 5) / 7)))
  local left = math.max(2, math.floor((width - cell * 7) / 2))
  local data = M.progress(entries, metadata, now)
  local start = M.month(selected)
  local offset = (os.date("*t", start).wday + 5) % 7
  c:put(2, left, os.date("%B %Y", selected):upper(), h.title)
  c:put(4, left, canvas.fit("h/l day  j/k week  [/] month  . today", width - left), h.muted)
  for index, name in ipairs({ "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" }) do
    c:put(6, left + (index - 1) * cell, name, h.muted)
  end
  local chosen_month = os.date("%Y-%m", selected)
  local selected_key = M.day(selected)
  local compact = (height or 40) < 28
  local first_row, row_step = compact and 7 or 8, compact and 1 or 2
  for index = 0, 41 do
    local epoch = M.shift(start, index - offset)
    if os.date("%Y-%m", epoch) == chosen_month then
      local key, y, x = M.day(epoch), first_row + math.floor(index / 7) * row_step, left + (index % 7) * cell
      local day = data.days[key]
      local target = metadata.goals[key]
      local marker = day and (target and target > 0 and day.unique >= target and "#" or "*") or " "
      local label = string.format("%2d%s", tonumber(os.date("%d", epoch)), marker)
      if key == selected_key then
        c:put(y, x - 1, "[" .. label:sub(1, 2) .. "]", h.selected)
      else
        c:put(y, x, label, key == M.day(now) and h.accent or (day and h.note or h.muted))
      end
    end
  end
  local legend = compact and 14 or 21
  c:put(legend, left, "* studied   # goal reached", h.muted)
  c:put(legend + 2, left, string.format("THIS WEEK   %d / 7 active days", data.active_days), h.title)
  c:put(legend + 4, left, string.format("%d card-days  /  %d answers", data.week_unique, data.week_answers), h.ink)
  c:put(
    legend + 5,
    left,
    string.format("Last week: %d card-days / %d answers", data.previous_unique, data.previous_answers),
    h.muted
  )
  c:put(legend + 7, left, "Enter opens this day's cards in Overview", h.accent)
  return c:finish()
end

return M
