local canvas = require("neorg_flashcards.ui.canvas")
local calendar = require("neorg_flashcards.calendar")
local stats = require("neorg_flashcards.stats")
local highlights = require("neorg_flashcards.highlights")
local M = {}

function M.render(model)
  local h, c = highlights.groups.desk, canvas.new(model.width, model.ascii)
  local now, width = model.now or os.time(), model.width
  local wide = width >= 86
  local short = (model.height or 40) < 26
  local column = wide and math.floor((width - 5) / 2) or width - 4
  local right = column + 4
  -- Preserve source byte spans when a section wraps in a smaller terminal.
  local function section(y, x, w, lines, spans)
    for index, line in ipairs(lines) do
      local offset = 0
      for _, text in ipairs(canvas.wrap(line, w)) do
        c:put(y, x, text, h.ink)
        for _, span in ipairs(spans or {}) do
          if span.line == index then
            local start = math.max(0, span.start_col - offset)
            local finish = math.min(#text, (span.end_col < 0 and #line or span.end_col) - offset)
            if finish > start then
              c:put(y, x + vim.fn.strdisplaywidth(text:sub(1, start)), text:sub(start + 1, finish), span.hl)
            end
          end
        end
        offset, y = offset + #text, y + 1
      end
    end
    return y + 1
  end
  c:put(1, 2, "Analytics · " .. model.label, h.title)
  local y = section(short and 2 or 3, 1, width, stats.summary_section(model.cards, model.history, now))
  local progress = calendar.progress(model.progress, model.metadata, now)
  local goal = progress.goal > 0 and (progress.unique .. " / " .. progress.goal) or tostring(progress.unique)
  local week = string.format("THIS WEEK   %d / 7 active days", progress.active_days)
  if wide and not short then
    section(y, 2, 39, calendar.render(model.progress, model.metadata, model.date, 39, model.ascii, now))
    local x, available = 44, width - 45
    local w = available >= 76 and math.floor((available - 3) / 2) or available
    c:box(y, x, w, 15, h.edge, "PROGRESS")
    c:put(y + 2, x + 2, canvas.fit("Today   " .. goal .. " cards", w - 4), h.title)
    c:put(y + 3, x + 2, string.format("%d answers   %d day streak", progress.answers, progress.streak), h.muted)
    c:put(y + 5, x + 2, canvas.fit(week, w - 4), h.title)
    c:put(y + 7, x + 2, string.format("%d card-days / %d answers", progress.week_unique, progress.week_answers), h.ink)
    c:put(y + 9, x + 2, "LAST WEEK", h.muted)
    c:put(
      y + 10,
      x + 2,
      string.format("%d card-days / %d answers", progress.previous_unique, progress.previous_answers),
      h.muted
    )
    c:put(y + 12, x + 2, canvas.fit("Card-days count each card once per day.", w - 4), h.muted)
    if available >= 76 then
      local qx, qw = x + w + 3, available - w - 3
      local counts = stats.metrics(model.cards, model.history, now)
      c:box(y, qx, qw, 15, h.edge, "QUEUE")
      for index, item in ipairs({
        { "Ready now", counts.due, h.title },
        { "Overdue", counts.overdue, h.again },
        { "New", counts.new, h.ink },
        { "Learning", counts.learning + counts.relearning, h.hard },
        { "Review", counts.review, h.good },
        { "Suspended", counts.suspended, h.muted },
        { "Buried", counts.buried, h.muted },
      }) do
        c:put(y + index + 1, qx + 2, string.format("%-14s %d", item[1], item[2]), item[3])
      end
      c:put(y + 12, qx + 2, "d  Study due cards", h.accent)
    end
    y = y + 17
  elseif short then
    c:put(4, 2, canvas.fit("Today " .. goal .. " cards  /  " .. week, width - 3), h.title)
    y = section(5, 2, 39, calendar.render(model.progress, model.metadata, model.date, 39, model.ascii, now, 10))
  else
    c:put(y, 2, "Today  " .. goal .. " cards   /   " .. progress.answers .. " answers", h.title)
    c:put(y + 1, 2, week, h.muted)
    y = section(y + 3, 2, 39, calendar.render(model.progress, model.metadata, model.date, 39, model.ascii, now))
  end
  if #model.errors > 0 then
    c:put(y, 2, "History needs repair: " .. #model.errors .. " lines skipped. c inspect", h.again)
    y = y + 2
  end
  local left_y = section(y, 1, column, stats.ratings_section(model.history, now, column))
  left_y = section(left_y, 1, column, stats.retention_section(model.history, now))
  left_y = section(left_y, 1, column, stats.state_section(model.cards, now))
  local weeks = math.max(4, math.min(20, math.floor((column - 8) / 2)))
  left_y = section(left_y, 1, column, stats.heatmap_section(model.history, now, weeks))
  local right_y =
    section(wide and y or left_y, wide and right or 1, column, stats.forecast_section(model.cards, now, column))
  section(right_y, wide and right or 1, column, model.health_lines, model.health_spans)
  c:put(c.height + 2, 2, "Activity covers recorded reviews. Forecasts change when you rate cards.", h.muted)
  return c:finish()
end

return M
