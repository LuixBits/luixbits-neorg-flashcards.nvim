-- Review log and stats popup: per-day review counts rendered as a
-- GitHub-style heatmap, a streak counter, and a 7-day due forecast.

local popup = require("neorg_flashcards.popup")
local schedule = require("neorg_flashcards.schedule")
local schema = require("neorg_flashcards.schema")
local util = require("neorg_flashcards.util")

local M = {}

local WEEKS = 20

local HEAT = {
  [0] = "NeorgFlashcardsHeat0",
  "NeorgFlashcardsHeat1",
  "NeorgFlashcardsHeat2",
  "NeorgFlashcardsHeat3",
  "NeorgFlashcardsHeat4",
}

local config = {}
local ns = vim.api.nvim_create_namespace("neorg_flashcards_stats")

local state = {
  buf = nil,
  win = nil,
}

local function define_highlights()
  vim.api.nvim_set_hl(0, HEAT[0], { link = "NonText", default = true })
  vim.api.nvim_set_hl(0, HEAT[1], { fg = "#0e4429", ctermfg = 22, default = true })
  vim.api.nvim_set_hl(0, HEAT[2], { fg = "#006d32", ctermfg = 28, default = true })
  vim.api.nvim_set_hl(0, HEAT[3], { fg = "#26a641", ctermfg = 35, default = true })
  vim.api.nvim_set_hl(0, HEAT[4], { fg = "#39d353", ctermfg = 41, default = true })
end

local function log_path()
  return config.flashcards_dir .. "/reviews.log"
end

-- Day arithmetic goes through os.date/os.time normalization (anchored at noon)
-- so DST transitions never shift a cell into the wrong calendar day.
local function add_days(epoch, days)
  local date = os.date("*t", epoch)
  return os.time({
    year = date.year,
    month = date.month,
    day = date.day + days,
    hour = 12,
  })
end

local function day_key(epoch)
  return os.date("%Y-%m-%d", epoch)
end

function M.log_review(score)
  if util.isempty(config.flashcards_dir) then
    return
  end

  pcall(vim.fn.mkdir, config.flashcards_dir, "p")
  pcall(vim.fn.writefile, { os.date("%Y-%m-%d %H:%M") .. "\t" .. tostring(score) }, log_path(), "a")
end

function M.read_log()
  local ok, lines = pcall(vim.fn.readfile, log_path())
  if not ok then
    return {}
  end

  local entries = {}
  for _, line in ipairs(lines) do
    local stamp, score = line:match("^(%d%d%d%d%-%d%d?%-%d%d? +%d%d?:%d%d)%s*\t?(%d)$")
    local epoch = stamp and schedule.parse_due(stamp)
    if epoch then
      table.insert(entries, { epoch = epoch, score = tonumber(score) })
    end
  end
  return entries
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

function M.close()
  popup.close(state)
end

function M.open(cards)
  local now = os.time()
  local noon = add_days(now, 0)
  local today_key = day_key(now)

  local counts = {}
  local total_reviews = 0
  for _, entry in ipairs(M.read_log()) do
    local key = day_key(entry.epoch)
    counts[key] = (counts[key] or 0) + 1
    total_reviews = total_reviews + 1
  end

  local streak = 0
  for offset = 0, 3650 do
    local count = counts[day_key(add_days(noon, -offset))] or 0
    if count > 0 then
      streak = streak + 1
    elseif offset > 0 then
      break
    end
  end

  local due_now = 0
  local score_counts = { new = 0, [1] = 0, [2] = 0, [3] = 0 }
  for _, card in ipairs(cards) do
    if schedule.is_due(card, now) then
      due_now = due_now + 1
    end
    local score = schema.card_score(card)
    if score then
      score_counts[score] = score_counts[score] + 1
    else
      score_counts.new = score_counts.new + 1
    end
  end

  local lines = {}
  local spans = {}
  local function push(line, hl)
    table.insert(lines, line)
    if hl then
      table.insert(spans, { line = #lines, start_col = 0, end_col = -1, hl = hl })
    end
  end

  push(
    string.format("  %d reviews total · %d today · %d day streak", total_reviews, counts[today_key] or 0, streak),
    "Title"
  )
  push(
    string.format(
      "  %d cards · %d due now · %d new · %d bad · %d mid · %d good",
      #cards,
      due_now,
      score_counts.new,
      score_counts[1],
      score_counts[2],
      score_counts[3]
    ),
    "Comment"
  )
  push("")

  -- Heatmap, oldest week on the left. Columns are weeks, rows are weekdays.
  push("  Last " .. WEEKS .. " weeks", "Title")
  local weekday = os.date("*t", now).wday -- 1 = Sunday
  local monday_offset = (weekday + 5) % 7
  local first_monday = add_days(noon, -monday_offset - (WEEKS - 1) * 7)

  local month_header = "       "
  local previous_month = nil
  local carry = 0
  for column = 0, WEEKS - 1 do
    local month = os.date("%b", add_days(first_monday, column * 7))
    if month ~= previous_month then
      month_header = month_header .. month
      previous_month = month
      carry = #month - 2 -- extra label chars absorbed by the next same-month column
    else
      month_header = month_header .. string.rep(" ", 2 - carry)
      carry = 0
    end
  end
  push(month_header, "Comment")

  local weekday_names = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
  for row = 0, 6 do
    local line = "  " .. weekday_names[row + 1] .. "  "
    for column = 0, WEEKS - 1 do
      local cell_epoch = add_days(first_monday, column * 7 + row)
      if cell_epoch > noon then
        line = line .. "  "
      else
        local count = counts[day_key(cell_epoch)] or 0
        local level = heat_level(count)
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
    push(line)
  end
  push("")

  push("  Due forecast", "Title")
  for offset = 0, 6 do
    local day_start = add_days(noon, offset) - 12 * 3600
    local day_end = add_days(noon, offset + 1) - 12 * 3600
    local count = 0
    for _, card in ipairs(cards) do
      local due = schedule.parse_due(card.values.due)
      if due and due >= day_start and due < day_end then
        count = count + 1
      end
    end
    local bar = string.rep("█", math.min(count, 30))
    local label = offset == 0 and "today" or os.date("%a %d", day_start + 12 * 3600)
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

  popup.open(state, {
    title = " Flashcard stats ",
    footer = " q quit ",
    width = math.min(72, math.max(56, vim.o.columns - 8)),
    height = math.min(#lines, math.max(12, vim.o.lines - 5)),
    maps = {
      { "q", M.close, "Close stats" },
      { "<Esc>", M.close, "Close stats" },
    },
  })

  popup.set_lines(state, lines)
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, span in ipairs(spans) do
    vim.api.nvim_buf_add_highlight(state.buf, ns, span.hl, span.line - 1, span.start_col, span.end_col)
  end
end

function M.setup(opts)
  config = opts or {}
  define_highlights()
end

return M
