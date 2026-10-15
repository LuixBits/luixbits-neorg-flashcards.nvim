local canvas = require("neorg_flashcards.ui.canvas")
local highlights = require("neorg_flashcards.highlights")
local calendar = require("neorg_flashcards.calendar")
local schedule = require("neorg_flashcards.schedule")
local M = {}

function M.render(model)
  local h, width = highlights.groups.desk, model.width
  local c = canvas.new(width, model.ascii)
  local entries = {}
  local selected = model.selected or 1
  local content_width = width >= 110 and width - 27 or width
  local tile_width = math.max(20, math.min(27, content_width - 6))
  local columns = math.max(1, math.floor((content_width - 4) / (tile_width + 3)))
  local left = math.max(2, math.floor((content_width - columns * (tile_width + 3) + 3) / 2))
  local progress = calendar.progress(model.history, model.metadata)
  local compact_goal = width < 110 and progress.goal > 0 and progress.unique >= progress.goal
  c:put(2, left, compact_goal and "[ GOAL REACHED ]" or "YOUR STUDY DESK", compact_goal and h.good or h.title)
  c:put(2, math.max(left + 20, width - 21), os.date("%a %d %b"), h.muted)
  if width < 110 then
    local goal = progress.goal > 0 and (progress.unique .. "/" .. progress.goal) or tostring(progress.unique)
    c:put(
      3,
      left,
      canvas.fit(
        string.format(
          "Today: %s cards  /  %d study day%s this week",
          goal,
          progress.active_days,
          progress.active_days == 1 and "" or "s"
        ),
        width - left
      ),
      h.accent
    )
  end

  local deck_page = 0
  for index, deck in ipairs(model.decks) do
    if deck.id == model.config.id then
      deck_page = math.floor((index - 1) / columns)
      if selected < 1 then
        selected = (index - 1) % columns + 1
      end
    end
  end
  for index = deck_page * columns + 1, math.min(#model.decks, (deck_page + 1) * columns) do
    local deck = model.decks[index]
    local x = left + (#entries % columns) * (tile_width + 3)
    local active = deck.id == model.config.id
    local edge = #entries + 1 == selected and h.selected or (active and h.accent or h.edge)
    c:put(4, x + 2, string.rep("_", tile_width - 4), h.shadow)
    c:put(5, x + 1, "/" .. canvas.pad(active and " OPEN " or "", tile_width - 4) .. "/|", edge)
    c:box(6, x, tile_width - 1, 4, edge)
    c:put(
      7,
      x + 2,
      canvas.fit((#entries + 1 == selected and "> " or "") .. deck.label, tile_width - 5),
      active and h.title or h.ink
    )
    c:put(
      8,
      x + 2,
      active and (model.ready > 0 and string.format("%d ready", model.ready) or "Caught up") or "Enter to open",
      h.muted
    )
    c:put(7, x + tile_width - 1, "|", h.shadow)
    c:put(8, x + tile_width - 1, "/", h.shadow)
    table.insert(entries, { line = 7, col = x, row = 1, kind = "deck", id = deck.id })
  end
  if #model.decks > columns then
    c:put(
      10,
      left,
      string.format("Shelf %d/%d   C choose any deck", deck_page + 1, math.ceil(#model.decks / columns)),
      h.muted
    )
  end

  local row = 12
  c:put(row, left, canvas.fit(model.label .. "  /  CATEGORY NOTES", content_width - left), h.title)
  if model.query ~= "" then
    c:put(row + 1, left, "Find: " .. model.query .. "   (Esc clears)", h.accent)
    row = row + 1
  end
  local groups = { { name = nil, label = "All due", cards = model.cards, due = model.ready, accent = "accent" } }
  for _, group in ipairs(model.groups) do
    if model.query == "" or (group.label .. " " .. group.name):lower():find(model.query:lower(), 1, true) then
      table.insert(groups, group)
    end
  end
  for index, group in ipairs(groups) do
    local x = left + ((index - 1) % columns) * (tile_width + 3)
    local y = row + 2 + math.floor((index - 1) / columns) * 7
    local active = #entries + 1 == selected
    local accent = h[group.accent] or h.note
    local edge = active and h.selected or accent
    if active then
      y = y - 1
    end
    c:box(y, x, tile_width, 5, edge)
    c:put(y + 1, x + 2, canvas.fit((active and "> " or "") .. group.label, tile_width - 4), active and h.title or h.ink)
    c:put(y + 2, x + 2, string.format("%d ready", group.due), group.due > 0 and h.accent or h.muted)
    c:put(y + 3, x + 2, string.format("%d card%s", #group.cards, #group.cards == 1 and "" or "s"), h.muted)
    c:put(y + 4, x + tile_width - 3, "/", edge)
    table.insert(entries, {
      line = y + 1,
      col = x,
      row = 2 + math.floor((index - 1) / columns),
      kind = "category",
      group = group,
      id = group.name or "@all",
    })
  end
  local bottom = row + 2 + math.ceil(#groups / columns) * 7
  local active = entries[selected]
  if active and active.group then
    local group = active.group
    local next_due = schedule.next_due(group.cards, os.time())
    local detail = group.due > 0 and "Enter to study this stack"
      or (
        next_due and "Caught up. Next review " .. schedule.humanize(next_due - os.time())
        or "No cards ready. Add a card in Overview."
      )
    c:put(bottom, left, canvas.fit(group.label .. "  /  " .. detail, width - left), h.muted)
  end

  local px, py = width >= 110 and width - 24 or left, width >= 110 and 5 or bottom + 2
  local pw = math.min(23, width - px)
  c:box(py, px, pw, 8, h.note, progress.goal > 0 and progress.unique >= progress.goal and "GOAL REACHED" or "TODAY")
  c:put(
    py + 2,
    px + 2,
    progress.goal > 0 and string.format("%d / %d cards", progress.unique, progress.goal)
      or string.format("%d card%s reviewed", progress.unique, progress.unique == 1 and "" or "s"),
    h.title
  )
  local slots = math.min(16, pw - 4)
  if progress.goal > 0 then
    local done = math.min(slots, math.floor(progress.unique / progress.goal * slots))
    c:put(py + 3, px + 2, string.rep("#", done) .. string.rep(".", slots - done), h.accent)
  end
  c:put(py + 5, px + 2, string.format("%d / 7 study days", progress.active_days), h.ink)
  c:put(py + 6, px + 2, string.format("%d day streak", progress.streak), h.muted)
  if width >= 110 then
    c:put(16, px + 5, "   _   _", h.note)
    c:put(17, px + 5, "  ( )_( )", h.note)
    c:put(18, px + 5, "   \\ | /", h.note)
    c:put(19, px + 5, "  .-----.", h.edge)
    c:put(20, px + 5, "   \\___/", h.edge)
    c:put(23, px, "One card at a time.", h.muted)
  end
  if model.error then
    c:put(math.max(bottom + 1, c.height + 1), left, canvas.fit("Metadata: " .. model.error, width - left), h.again)
  end
  if model.pending and model.pending > 0 then
    c:put(
      c.height + 1,
      left,
      canvas.fit("Progress includes " .. model.pending .. " events awaiting history delivery", width - left),
      h.hard
    )
  end
  local lines, spans = c:finish()
  return lines, spans, entries, columns, selected
end

return M
