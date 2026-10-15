local canvas = require("neorg_flashcards.ui.canvas")
local highlights = require("neorg_flashcards.highlights")
local M = {}

function M.render(model)
  local h, c = highlights.groups.desk, canvas.new(model.width, model.ascii)
  local compact = (model.height or 40) < 28
  local piles = model.width >= 100
  local card_width = math.max(16, math.min(86, model.width - (piles and 38 or 6)))
  if model.transition == "reveal" and model.phase and model.phase < 1 then
    card_width = math.max(20, math.floor(card_width * (0.65 + model.phase * 0.35)))
  end
  local left = math.max(2, math.floor((model.width - card_width) / 2))
  local offset = model.phase and model.phase < 1 and math.floor((1 - model.phase) * 3) or 0
  if model.transition == "again" or model.transition == "undo" then
    offset = -offset
  end
  left = math.min(model.width - card_width, left + offset)
  local heading = model.lines[1]:gsub("^%* ", ""):gsub(" | Reviewed.*$", "")
  c:put(compact and 1 or 2, 3, canvas.fit(model.deck .. "  /  " .. heading, model.width - 6), h.title)
  local summary = string.format(
    "%d unique card%s / %d answer%s / %d pending attempt%s",
    model.unique,
    model.unique == 1 and "" or "s",
    model.answers,
    model.answers == 1 and "" or "s",
    model.pending,
    model.pending == 1 and "" or "s"
  )
  c:put(compact and 2 or 3, 3, canvas.fit(summary, model.width - 6), h.muted)

  local body = {}
  for index, line in ipairs(model.lines) do
    local title = line:match("^%*%* (.*)")
    -- The old textual session header is represented by the desk heading.
    if index > 1 and (not compact or line ~= "") then
      local byte_offset = 0
      for _, chunk in ipairs(canvas.wrap(title or line, card_width - 6)) do
        table.insert(
          body,
          { text = chunk, hl = title and h.note or h.ink, source = not title and index or nil, offset = byte_offset }
        )
        byte_offset = byte_offset + #chunk
      end
    end
  end
  local top = compact and 4 or 6
  local padding = compact and 0 or 1
  local height = math.max(compact and 8 or 12, #body + padding * 2 + 2)
  if not model.ascii then
    for layer = 2, 1, -1 do
      for row = top + layer, top + height + layer - 1 do
        c:put(row, left + layer, string.rep(" ", card_width), h.ink)
      end
      c:box(top + layer, left + layer, card_width, height, h.shadow)
    end
  end
  for row = top, top + height - 1 do
    c:put(row, left, string.rep(" ", card_width), h.ink)
  end
  c:box(
    top,
    left,
    card_width,
    height,
    h.edge,
    model.completed and "SESSION COMPLETE" or (model.revealed and "ANSWER" or "QUESTION")
  )
  for index, line in ipairs(body) do
    c:put(top + padding + index, left + 3, line.text, line.hl)
  end
  -- Intersect source byte spans with each wrapped row, preserving rating
  -- colors and typed-answer differences even in a narrow terminal.
  for row, item in ipairs(body) do
    for _, span in ipairs(model.spans) do
      if item.source == span.line then
        local finish = span.end_col < 0 and #model.lines[span.line] or span.end_col
        local start = math.max(0, span.start_col - item.offset)
        finish = math.min(#item.text, finish - item.offset)
        if finish > start then
          local col = vim.fn.strdisplaywidth(item.text:sub(1, start))
          c:put(top + padding + row, left + 3 + col, item.text:sub(start + 1, finish), span.hl)
        end
      end
    end
  end
  if piles then
    local function pile(x, name, count)
      c:put(top + 2, x, name, h.muted)
      for i = 1, math.min(4, math.max(1, count)) do
        c:box(top + 4 + i, x, 12, 3, count == 0 and h.shadow or h.edge)
      end
      c:put(top + 13, x + 2, tostring(count), h.title)
    end
    pile(3, "PENDING", model.pending)
    pile(model.width - 14, "REVIEWED", model.finished)
  end
  return c:finish()
end

return M
