-- Review analytics and reusable UI section builders. Review events live in a
-- versioned JSONL ledger; the legacy tab-separated log remains readable so an
-- upgrade never throws away an existing streak.

local history = require("neorg_flashcards.history")
local schedule = require("neorg_flashcards.schedule")
local util = require("neorg_flashcards.util")

local M = {}

local WEEKS = 20
local SECONDS_PER_DAY = 86400

local HEAT = {
  [0] = "NeorgFlashcardsHeat0",
  "NeorgFlashcardsHeat1",
  "NeorgFlashcardsHeat2",
  "NeorgFlashcardsHeat3",
  "NeorgFlashcardsHeat4",
}

local config = {}

local function define_highlights()
  vim.api.nvim_set_hl(0, HEAT[0], { link = "NonText", default = true })
  vim.api.nvim_set_hl(0, HEAT[1], { fg = "#0e4429", ctermfg = 22, default = true })
  vim.api.nvim_set_hl(0, HEAT[2], { fg = "#006d32", ctermfg = 28, default = true })
  vim.api.nvim_set_hl(0, HEAT[3], { fg = "#26a641", ctermfg = 35, default = true })
  vim.api.nvim_set_hl(0, HEAT[4], { fg = "#39d353", ctermfg = 41, default = true })
end

-- Day arithmetic goes through os.date/os.time normalization (anchored at
-- noon), so DST transitions do not shift a heatmap cell into another day.
local function add_days(epoch, days)
  local date = os.date("*t", epoch)
  return os.time({
    year = date.year,
    month = date.month,
    day = date.day + days,
    hour = 12,
    min = 0,
    sec = 0,
  })
end

local function day_key(epoch)
  return os.date("%Y-%m-%d", epoch)
end

local function event_action(entry)
  return entry.event or entry.action or "rated"
end

-- Undo is kept in the append-only history as a compensating event. Collapse
-- it for user-facing analytics without mutating or rewriting the ledger.
function M.effective_entries(entries)
  local active = {}
  for _, entry in ipairs(entries or {}) do
    if event_action(entry) == "undo" then
      for index = #active, 1, -1 do
        local candidate = active[index]
        local same_event = entry.undo_of ~= nil and candidate.event_id == entry.undo_of
        local same_card = entry.card_id == nil or candidate.card_id == entry.card_id
        local same_rating = entry.rating == nil or candidate.rating == entry.rating
        if same_event or (entry.undo_of == nil and same_card and same_rating) then
          table.remove(active, index)
          break
        end
      end
    elseif entry.type == nil or entry.type == "review" then
      table.insert(active, entry)
    end
  end
  return active
end

-- Compatibility writer for callers that only have a score. New review
-- sessions use history.append() with a stable card id instead.
function M.log_review(score)
  if util.isempty(config.flashcards_dir) then
    return false
  end

  local path = history.legacy_path(config)
  local ok_mkdir = pcall(vim.fn.mkdir, vim.fn.fnamemodify(path, ":h"), "p")
  local ok_write = ok_mkdir
    and pcall(vim.fn.writefile, { os.date("%Y-%m-%d %H:%M") .. "\t" .. tostring(score) }, path, "a")
  return ok_write == true
end

function M.read_log()
  local entries, errors = history.read(config)
  return M.effective_entries(entries), errors
end

local function count_by_day(entries)
  local counts = {}
  for _, entry in ipairs(M.effective_entries(entries)) do
    if entry.epoch then
      local key = day_key(entry.epoch)
      counts[key] = (counts[key] or 0) + 1
    end
  end
  return counts
end

local function rating_counts(entries, from_epoch)
  local counts = { [1] = 0, [2] = 0, [3] = 0, total = 0 }
  for _, entry in ipairs(M.effective_entries(entries)) do
    if
      (not from_epoch or entry.epoch and entry.epoch >= from_epoch) and counts[tonumber(entry.rating or entry.score)]
    then
      local rating = tonumber(entry.rating or entry.score)
      counts[rating] = counts[rating] + 1
      counts.total = counts.total + 1
    end
  end
  return counts
end

local function median(values)
  if #values == 0 then
    return nil
  end
  table.sort(values)
  local middle = math.floor(#values / 2) + 1
  if #values % 2 == 1 then
    return values[middle]
  end
  return (values[middle - 1] + values[middle]) / 2
end

local function retention(entries, now, days)
  local counts = rating_counts(entries, now - days * SECONDS_PER_DAY)
  if counts.total == 0 then
    return nil, 0
  end
  return math.floor((counts[2] + counts[3]) / counts.total * 100 + 0.5), counts.total
end

local function current_streak(entries, now)
  local counts = count_by_day(entries)
  local start = counts[day_key(now)] and 0 or 1
  local streak = 0
  for offset = start, 3650 do
    if (counts[day_key(add_days(now, -offset))] or 0) == 0 then
      break
    end
    streak = streak + 1
  end
  return streak
end

function M.metrics(cards, entries, now)
  cards = cards or {}
  entries = M.effective_entries(entries)
  now = now or os.time()

  local result = {
    cards = #cards,
    reviews = #entries,
    today = count_by_day(entries)[day_key(now)] or 0,
    streak = current_streak(entries, now),
    due = 0,
    overdue = 0,
    new = 0,
    learning = 0,
    review = 0,
    relearning = 0,
    suspended = 0,
    buried = 0,
    leeches = 0,
    hints = 0,
  }

  for _, card in ipairs(cards) do
    local status = schedule.card_status(card, now, config.scheduling)
    result[status.lifecycle] = (result[status.lifecycle] or 0) + 1
    if status.availability == "suspended" then
      result.suspended = result.suspended + 1
    elseif status.availability == "buried" then
      result.buried = result.buried + 1
    elseif schedule.is_due(card, now) then
      result.due = result.due + 1
      if status.timing == "overdue" then
        result.overdue = result.overdue + 1
      end
    end
    if status.lapses >= (tonumber(config.leech_threshold) or 8) then
      result.leeches = result.leeches + 1
    end
  end

  local durations = {}
  for _, entry in ipairs(entries) do
    local duration = tonumber(entry.duration_ms)
    if not duration and entry.duration_seconds then
      duration = tonumber(entry.duration_seconds) * 1000
    end
    if duration and duration >= 0 then
      table.insert(durations, duration)
    end
    if entry.hint_used == true or (tonumber(entry.hints_used) or 0) > 0 then
      result.hints = result.hints + 1
    end
  end
  result.median_duration_ms = median(durations)
  result.estimated_due_minutes = result.median_duration_ms
      and result.due > 0
      and math.max(1, math.ceil(result.due * result.median_duration_ms / 60000))
    or nil
  result.retention_7, result.retention_7_count = retention(entries, now, 7)
  result.retention_30, result.retention_30_count = retention(entries, now, 30)
  result.retention_90, result.retention_90_count = retention(entries, now, 90)
  result.ratings_30 = rating_counts(entries, now - 30 * SECONDS_PER_DAY)
  return result
end

local function percentage(value, fallback)
  return value and (tostring(value) .. "%") or (fallback or "—")
end

local function span_all(lines, highlights)
  local spans = {}
  for line, hl in pairs(highlights or {}) do
    table.insert(spans, { line = line, start_col = 0, end_col = -1, hl = hl })
  end
  return lines, spans
end

-- Sections return `lines, spans` with 1-based section-relative line numbers,
-- so the hub can stitch them into narrow or wide responsive layouts.
function M.summary_section(cards, entries, now)
  local data = M.metrics(cards, entries, now)
  local estimate = data.estimated_due_minutes and (" · about " .. data.estimated_due_minutes .. " min") or ""
  return span_all({
    string.format("  %d reviews total · %d today · %d day streak", data.reviews, data.today, data.streak),
    string.format("  %d cards · %d due now%s · %d overdue", data.cards, data.due, estimate, data.overdue),
  }, { [1] = "Title", [2] = "Comment" })
end

function M.retention_section(entries, now)
  local data = M.metrics({}, entries, now)
  return span_all({
    "  Retention (Hard + Good)",
    string.format("  7 days   %-4s  %d answers", percentage(data.retention_7), data.retention_7_count),
    string.format("  30 days  %-4s  %d answers", percentage(data.retention_30), data.retention_30_count),
    string.format("  90 days  %-4s  %d answers", percentage(data.retention_90), data.retention_90_count),
  }, { [1] = "Title", [2] = "Comment", [3] = "Comment", [4] = "Comment" })
end

local function distribution_bar(count, total, width)
  if count <= 0 or total <= 0 then
    return ""
  end
  return string.rep("█", math.max(1, math.floor(count / total * width + 0.5)))
end

function M.ratings_section(entries, now, width)
  now = now or os.time()
  local recent = {}
  for _, entry in ipairs(M.effective_entries(entries)) do
    if entry.epoch and entry.epoch >= now - 30 * SECONDS_PER_DAY then
      table.insert(recent, entry)
    end
  end
  local data = M.metrics({}, recent, now)
  local counts = data.ratings_30
  local bar_width = math.max(4, math.min(20, (width or 42) - 24))
  local labels = { [1] = "Again", [2] = "Hard ", [3] = "Good " }
  local lines = { "  Answer buttons · 30 days" }
  for rating = 1, 3 do
    table.insert(
      lines,
      string.format(
        "  %d %s  %-" .. bar_width .. "s %d",
        rating,
        labels[rating],
        distribution_bar(counts[rating], counts.total, bar_width),
        counts[rating]
      )
    )
  end
  local median_text = "—"
  if data.median_duration_ms then
    median_text = data.median_duration_ms < 1000 and string.format("%d ms", math.floor(data.median_duration_ms + 0.5))
      or string.format("%.1f sec", data.median_duration_ms / 1000)
  end
  table.insert(lines, string.format("  Median answer %s · %d hint-assisted", median_text, data.hints))
  return span_all(lines, {
    [1] = "Title",
    [2] = "DiagnosticError",
    [3] = "DiagnosticWarn",
    [4] = "DiagnosticOk",
    [5] = "Comment",
  })
end

function M.state_section(cards, now)
  local data = M.metrics(cards, {}, now)
  return span_all({
    "  Card states",
    string.format(
      "  %d new · %d learning · %d review · %d relearning",
      data.new,
      data.learning,
      data.review,
      data.relearning
    ),
    string.format("  %d suspended · %d buried · %d leeches", data.suspended, data.buried, data.leeches),
  }, { [1] = "Title", [2] = "Comment", [3] = data.leeches > 0 and "DiagnosticWarn" or "Comment" })
end

local function heat_level(count)
  if count == 0 then
    return 0
  elseif count <= 2 then
    return 1
  elseif count <= 5 then
    return 2
  elseif count <= 9 then
    return 3
  end
  return 4
end

function M.heatmap_section(entries, now, weeks)
  weeks = weeks or WEEKS
  now = now or os.time()
  local noon = add_days(now, 0)
  local counts = count_by_day(entries)
  local lines = { "  Last " .. weeks .. " weeks" }
  local spans = { { line = 1, start_col = 0, end_col = -1, hl = "Title" } }

  local weekday = os.date("*t", now).wday -- 1 = Sunday
  local monday_offset = (weekday + 5) % 7
  local first_monday = add_days(noon, -monday_offset - (weeks - 1) * 7)
  local month_header = "       "
  local previous_month = nil
  local carry = 0
  for column = 0, weeks - 1 do
    local month = os.date("%b", add_days(first_monday, column * 7))
    if month ~= previous_month then
      month_header = month_header .. month
      previous_month = month
      carry = #month - 2
    else
      month_header = month_header .. string.rep(" ", math.max(0, 2 - carry))
      carry = 0
    end
  end
  table.insert(lines, month_header)
  table.insert(spans, { line = 2, start_col = 0, end_col = -1, hl = "Comment" })

  local names = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
  for row = 0, 6 do
    local line = "  " .. names[row + 1] .. "  "
    for column = 0, weeks - 1 do
      local epoch = add_days(first_monday, column * 7 + row)
      if epoch > noon then
        line = line .. "  "
      else
        local level = heat_level(counts[day_key(epoch)] or 0)
        local glyph = level == 0 and "·" or "■"
        table.insert(spans, {
          line = #lines + 1,
          start_col = #line,
          end_col = #line + #glyph,
          hl = HEAT[level],
        })
        line = line .. glyph .. " "
      end
    end
    table.insert(lines, line)
  end
  return lines, spans
end

function M.forecast_counts(cards, now, days)
  now = now or os.time()
  days = days or 7
  local noon = add_days(now, 0)
  local counts = {}
  for offset = 0, days - 1 do
    counts[offset + 1] = 0
  end

  for _, card in ipairs(cards or {}) do
    local status = schedule.card_status(card, now, config.scheduling)
    if status.availability == "active" then
      local offset = 0
      if status.due and status.due > now then
        for candidate = 0, days - 1 do
          local day_end = add_days(noon, candidate + 1) - 12 * 3600
          if status.due < day_end then
            offset = candidate
            break
          end
          offset = days
        end
      end
      if offset < days then
        counts[offset + 1] = counts[offset + 1] + 1
      end
    end
  end
  return counts
end

function M.forecast_section(cards, now, width)
  now = now or os.time()
  local noon = add_days(now, 0)
  local max_bar = math.max(4, (width or 44) - 14)
  local counts = M.forecast_counts(cards, now, 7)
  local lines = { "  Due forecast" }
  local spans = { { line = 1, start_col = 0, end_col = -1, hl = "Title" } }

  for offset = 0, 6 do
    local count = counts[offset + 1]
    local bar = string.rep("█", math.min(count, max_bar))
    local label = offset == 0 and "today" or os.date("%a %d", add_days(noon, offset))
    local line = string.format("  %-8s %s %d", label, bar, count)
    table.insert(lines, line)
    if #bar > 0 then
      local bar_start = #"  " + 9
      table.insert(spans, {
        line = #lines,
        start_col = bar_start,
        end_col = bar_start + #bar,
        hl = offset == 0 and "DiagnosticWarn" or "DiagnosticOk",
      })
    end
  end
  return lines, spans
end

function M.setup(opts)
  config = opts or {}
  history.setup(config)
  define_highlights()
end

return M
