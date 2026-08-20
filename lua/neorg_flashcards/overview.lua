-- Tag-grouped overview canvas. Cards are painted as one colored glyph each,
-- boxed per tag; the layout math is pure and the Neovim side is a scratch
-- buffer plus extmark highlights, like a miniature of the roomplan rasterizer.

local popup = require("neorg_flashcards.popup")
local review = require("neorg_flashcards.review")
local schedule = require("neorg_flashcards.schedule")
local schema = require("neorg_flashcards.schema")
local stats = require("neorg_flashcards.stats")
local util = require("neorg_flashcards.util")

local M = {}

local GLYPHS_PER_ROW = 8
local GLYPH = "●"
local GLYPH_BYTES = #GLYPH
local BOX_GAP = 2

local HIGHLIGHTS = {
  due = "NeorgFlashcardsDue",
  soon = "NeorgFlashcardsSoon",
  scheduled = "NeorgFlashcardsScheduled",
  new = "NeorgFlashcardsNew",
  border = "NeorgFlashcardsBorder",
  title = "NeorgFlashcardsGroupTitle",
  muted = "NeorgFlashcardsMuted",
  selected = "NeorgFlashcardsSelected",
  heading = "NeorgFlashcardsHeading",
}

local config = {}
local handlers = {}
local provider = nil
local ns = vim.api.nvim_create_namespace("neorg_flashcards_overview")

local state = {
  buf = nil,
  win = nil,
  tab = nil,
  groups = {},
  cells = {},
  sel = 1,
  analytics_line = nil,
}

local peek = {
  buf = nil,
  win = nil,
}

local function define_highlights()
  vim.api.nvim_set_hl(0, HIGHLIGHTS.due, { link = "DiagnosticError", default = true })
  vim.api.nvim_set_hl(0, HIGHLIGHTS.soon, { link = "DiagnosticWarn", default = true })
  vim.api.nvim_set_hl(0, HIGHLIGHTS.scheduled, { link = "DiagnosticOk", default = true })
  vim.api.nvim_set_hl(0, HIGHLIGHTS.new, { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, HIGHLIGHTS.border, { link = "FloatBorder", default = true })
  vim.api.nvim_set_hl(0, HIGHLIGHTS.title, { link = "Title", default = true })
  vim.api.nvim_set_hl(0, HIGHLIGHTS.muted, { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, HIGHLIGHTS.selected, { reverse = true, bold = true, default = true })
  vim.api.nvim_set_hl(0, HIGHLIGHTS.heading, { link = "Title", default = true })
end

local function card_visual(card, now)
  local due = schedule.parse_due(card.values.due)
  if not due then
    return schema.card_score(card) and "due" or "new"
  end
  if due <= now then
    return "due"
  end
  if due <= now + 86400 then
    return "soon"
  end
  return "scheduled"
end

local function card_tags(card)
  local tags = {}
  for tag in util.trim(card.values.tags):gsub(",", " "):gmatch("%S+") do
    table.insert(tags, tag:lower())
  end
  if #tags == 0 then
    return { "untagged" }
  end
  return tags
end

local function group_cards(cards, now)
  local by_tag = {}
  local order = {}

  for _, card in ipairs(cards) do
    for _, tag in ipairs(card_tags(card)) do
      if not by_tag[tag] then
        by_tag[tag] = {}
        table.insert(order, tag)
      end
      table.insert(by_tag[tag], card)
    end
  end

  table.sort(order, function(left, right)
    if left == "untagged" then
      return false
    end
    if right == "untagged" then
      return true
    end
    return left < right
  end)

  local groups = {}
  for _, tag in ipairs(order) do
    local group_cards_list = by_tag[tag]
    table.sort(group_cards_list, function(left, right)
      local left_key = schedule.due_key(left)
      local right_key = schedule.due_key(right)
      if left_key ~= right_key then
        return left_key < right_key
      end
      local _, left_front = schema.front(config, left)
      local _, right_front = schema.front(config, right)
      return left_front < right_front
    end)

    local due = 0
    for _, card in ipairs(group_cards_list) do
      if schedule.is_due(card, now) then
        due = due + 1
      end
    end

    table.insert(groups, { name = tag, cards = group_cards_list, due = due })
  end

  return groups
end

-- Renders one group box; returns its lines, relative highlight spans, relative
-- card cells, its display width, and a blank interior line for row padding.
local function render_box(group, now)
  local count = string.format("%d/%d", group.due, #group.cards)
  local title_left = " " .. group.name
  local glyph_row_width = GLYPHS_PER_ROW * 2 - 1
  local inner = math.max(glyph_row_width, vim.fn.strdisplaywidth(title_left) + vim.fn.strdisplaywidth(count) + 1)

  local lines = {}
  local spans = {}
  local cells = {}

  -- Every box line is painted border-colored first; content spans overlay it.
  local function push(line)
    table.insert(lines, line)
    table.insert(spans, { line = #lines, start_col = 0, end_col = -1, hl = HIGHLIGHTS.border })
  end

  push("╭" .. string.rep("─", inner) .. "╮")

  local title_pad = math.max(1, inner - vim.fn.strdisplaywidth(title_left) - vim.fn.strdisplaywidth(count))
  local title_line = "│" .. title_left .. string.rep(" ", title_pad) .. count .. "│"
  push(title_line)
  -- The border glyphs are 3 bytes wide, so content columns shift accordingly.
  table.insert(spans, { line = 2, start_col = 3, end_col = 3 + #title_left, hl = HIGHLIGHTS.title })
  table.insert(spans, {
    line = 2,
    start_col = #title_line - 3 - #count,
    end_col = #title_line - 3,
    hl = group.due > 0 and HIGHLIGHTS.due or HIGHLIGHTS.muted,
  })

  for row = 0, math.floor((#group.cards - 1) / GLYPHS_PER_ROW) do
    local parts = {}
    for column = 0, GLYPHS_PER_ROW - 1 do
      local card = group.cards[row * GLYPHS_PER_ROW + column + 1]
      if not card then
        break
      end
      table.insert(parts, GLYPH)

      local byte_col = 3 + column * (GLYPH_BYTES + 1)
      table.insert(spans, {
        line = 3 + row,
        start_col = byte_col,
        end_col = byte_col + GLYPH_BYTES,
        hl = HIGHLIGHTS[card_visual(card, now)],
      })
      table.insert(cells, { line = 3 + row, byte_col = byte_col, card = card, group = group })
    end

    local glyphs = table.concat(parts, " ")
    push("│" .. glyphs .. string.rep(" ", inner - vim.fn.strdisplaywidth(glyphs)) .. "│")
  end

  push("╰" .. string.rep("─", inner) .. "╯")

  return lines, spans, cells, inner + 2, "│" .. string.rep(" ", inner) .. "│"
end

local function selected_cell()
  return state.cells[state.sel]
end

local function preview_line(cell)
  if not cell then
    return "  No cards yet — :NeorgFlashcardAdd to create one"
  end

  local _, front = schema.front(config, cell.card)
  front = front:gsub("\n", " ")
  return string.format("  ▸ %s  ·  %s", front, cell.group.name)
end

local function build()
  local now = os.time()
  local width = M.is_open() and vim.api.nvim_win_get_width(state.win) or 80

  -- Build the box body first so the header preview can reference the freshly
  -- computed cells (the selection is clamped against the new cell list).
  local body_lines = {}
  local body_spans = {}
  local body_cells = {}

  local row_boxes = {}
  local row_width = 0
  local function flush_row()
    if #row_boxes == 0 then
      return
    end

    local height = 0
    for _, box in ipairs(row_boxes) do
      height = math.max(height, #box.lines)
    end

    -- Box borders and glyphs are multi-byte, so each box's byte offset varies
    -- per line; record it while stitching instead of assuming display columns.
    local base = #body_lines
    for offset = 1, height do
      local line = " "
      for box_index, box in ipairs(row_boxes) do
        local segment = box.lines[offset]
        if not segment then
          segment = offset == height and box.bottom or box.blank
        end
        segment = segment .. string.rep(" ", box.width - vim.fn.strdisplaywidth(segment))
        if box_index > 1 then
          line = line .. string.rep(" ", BOX_GAP)
        end
        box.x_per_line[offset] = #line
        if offset > #box.lines then
          -- Fill segment of a shorter box; keep its border color consistent.
          table.insert(body_spans, {
            line = base + offset,
            start_col = #line,
            end_col = #line + #segment,
            hl = HIGHLIGHTS.border,
          })
        end
        line = line .. segment
      end
      table.insert(body_lines, line)
    end

    for _, box in ipairs(row_boxes) do
      for _, span in ipairs(box.spans) do
        local x = box.x_per_line[span.line]
        table.insert(body_spans, {
          line = base + span.line,
          start_col = span.start_col + x,
          end_col = span.end_col == -1 and -1 or span.end_col + x,
          hl = span.hl,
        })
      end
      for _, cell in ipairs(box.cells) do
        table.insert(body_cells, {
          line = base + cell.line,
          byte_col = cell.byte_col + box.x_per_line[cell.line],
          card = cell.card,
          group = cell.group,
        })
      end
    end

    table.insert(body_lines, "")
    row_boxes = {}
    row_width = 0
  end

  for _, group in ipairs(state.groups) do
    local box_lines, box_spans, box_cells, box_width, blank = render_box(group, now)
    if row_width > 0 and row_width + BOX_GAP + box_width > width - 2 then
      flush_row()
    end
    table.insert(row_boxes, {
      lines = box_lines,
      spans = box_spans,
      cells = box_cells,
      bottom = box_lines[#box_lines],
      blank = blank,
      width = box_width,
      x_per_line = {},
    })
    row_width = row_width == 0 and box_width or row_width + BOX_GAP + box_width
  end
  flush_row()

  if #body_cells == 0 then
    state.sel = 1
  else
    state.sel = math.max(1, math.min(#body_cells, state.sel))
  end
  local selected = body_cells[state.sel]

  -- Header: unique-card count (cards with several tags appear in several
  -- groups), the selected-card preview, and the color legend.
  local total_due = 0
  local seen = {}
  local unique = {}
  for _, group in ipairs(state.groups) do
    for _, card in ipairs(group.cards) do
      if not seen[card] then
        seen[card] = true
        table.insert(unique, card)
        if schedule.is_due(card, now) then
          total_due = total_due + 1
        end
      end
    end
  end

  local header_offset = 4
  local lines = {
    string.format("  %d cards · %d groups · %d due", #unique, #state.groups, total_due),
    preview_line(selected),
    string.format("  %s due   %s soon   %s scheduled   %s new", GLYPH, GLYPH, GLYPH, GLYPH),
    "",
  }
  local spans = {
    { line = 1, start_col = 0, end_col = -1, hl = HIGHLIGHTS.muted },
  }
  if selected then
    table.insert(spans, { line = 2, start_col = 2, end_col = 5, hl = HIGHLIGHTS.title })
    table.insert(spans, {
      line = selected.line + header_offset,
      start_col = selected.byte_col,
      end_col = selected.byte_col + GLYPH_BYTES,
      hl = HIGHLIGHTS.selected,
    })
  end
  local at = 2
  for _, key in ipairs({ "due", "soon", "scheduled", "new" }) do
    table.insert(spans, { line = 3, start_col = at, end_col = at + GLYPH_BYTES, hl = HIGHLIGHTS[key] })
    at = at + GLYPH_BYTES + #" " + #key + 3
  end

  local cells = {}
  for _, span in ipairs(body_spans) do
    span.line = span.line + header_offset
    table.insert(spans, span)
  end
  for _, cell in ipairs(body_cells) do
    cell.line = cell.line + header_offset
    table.insert(cells, cell)
  end
  for _, line in ipairs(body_lines) do
    table.insert(lines, line)
  end

  -- Analytics section below the canvas, composed from the stats builders.
  local function stitch(section_lines, section_spans)
    local offset = #lines
    for _, line in ipairs(section_lines) do
      table.insert(lines, line)
    end
    for _, span in ipairs(section_spans) do
      table.insert(spans, {
        line = span.line + offset,
        start_col = span.start_col,
        end_col = span.end_col,
        hl = span.hl,
      })
    end
  end

  table.insert(lines, "")
  table.insert(lines, "  Analytics")
  state.analytics_line = #lines
  table.insert(spans, { line = #lines, start_col = 0, end_col = -1, hl = HIGHLIGHTS.heading })
  table.insert(lines, "")

  local entries = stats.read_log()
  stitch(stats.summary_section(unique, entries, now))
  table.insert(lines, "")
  stitch(stats.heatmap_section(entries, now))
  table.insert(lines, "")
  stitch(stats.forecast_section(unique, now))

  return lines, spans, cells
end

local function render()
  local lines, spans, cells = build()
  state.cells = cells

  popup.set_lines(state, lines)
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, span in ipairs(spans) do
    vim.api.nvim_buf_add_highlight(state.buf, ns, span.hl, span.line - 1, span.start_col, span.end_col)
  end

  local cell = selected_cell()
  if cell then
    vim.api.nvim_win_set_cursor(state.win, { cell.line, cell.byte_col })
  end
end

function M.move(delta)
  if #state.cells == 0 then
    return
  end
  state.sel = math.max(1, math.min(#state.cells, state.sel + delta))
  render()
end

function M.move_vertical(direction)
  local cell = selected_cell()
  if not cell then
    return
  end

  local best_index
  local best_distance
  for index, candidate in ipairs(state.cells) do
    local row_delta = (candidate.line - cell.line) * direction
    if row_delta > 0 then
      local distance = math.abs(candidate.byte_col - cell.byte_col) + row_delta * 0.001
      if not best_distance or distance < best_distance then
        best_distance = distance
        best_index = index
      end
    end
  end

  if best_index then
    state.sel = best_index
    render()
  end
end

function M.peek()
  local cell = selected_cell()
  if not cell then
    return
  end

  local front_title, front = schema.front(config, cell.card)
  local lines = { "** " .. front_title }
  for _, line in ipairs(util.value_lines(front)) do
    table.insert(lines, line)
  end
  for _, field in ipairs(schema.reveal_fields(config, cell.card)) do
    table.insert(lines, "")
    table.insert(lines, "** " .. field.title)
    for _, line in ipairs(util.value_lines(field.value)) do
      table.insert(lines, line)
    end
  end

  popup.open(peek, {
    title = " Peek ",
    footer = " q/Esc close ",
    min_width = 40,
    max_width = 64,
    min_height = 8,
    max_height = 18,
    maps = {
      { "q", M.peek_close, "Close peek" },
      { "<Esc>", M.peek_close, "Close peek" },
      { "p", M.peek_close, "Close peek" },
    },
  })
  popup.set_lines(peek, lines)
end

function M.peek_close()
  popup.close(peek)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
  end
end

function M.review_group()
  local cell = selected_cell()
  if not cell then
    return
  end

  local now = os.time()
  local due = {}
  for _, card in ipairs(cell.group.cards) do
    if schedule.is_due(card, now) then
      table.insert(due, card)
    end
  end

  if #due == 0 then
    util.notify("No due cards in group: " .. cell.group.name, vim.log.levels.WARN)
    return
  end

  -- The review float opens on top of the hub; closing it just refreshes.
  local name = cell.group.name
  review.start(due, {}, "tag:" .. name, nil, {
    on_close = function()
      M.refresh()
    end,
  })
end

function M.edit_card()
  local cell = selected_cell()
  if not cell then
    return
  end

  M.close()
  vim.cmd.edit(util.fname(cell.card.path))
  vim.api.nvim_win_set_cursor(0, { cell.card.start_line, 0 })
end

function M.refresh()
  if not provider or not M.is_open() then
    return
  end

  local cards, errors = provider()
  if errors and #errors > 0 then
    util.notify(table.concat(errors, "\n"), vim.log.levels.WARN)
  end
  state.groups = group_cards(cards, os.time())
  render()
end

function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

function M.close()
  popup.close(peek)

  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  state.buf = nil
  state.win = nil

  if state.tab and vim.api.nvim_tabpage_is_valid(state.tab) and #vim.api.nvim_list_tabpages() > 1 then
    pcall(vim.cmd, "tabclose " .. vim.api.nvim_tabpage_get_number(state.tab))
  end
  state.tab = nil
end

function M.jump_stats()
  if M.is_open() and state.analytics_line then
    vim.api.nvim_win_set_cursor(state.win, { state.analytics_line, 0 })
  end
end

local function move_by(delta)
  return function()
    M.move(delta)
  end
end

local function move_vertically(direction)
  return function()
    M.move_vertical(direction)
  end
end

local function add_card()
  if handlers.on_add then
    handlers.on_add()
  else
    util.notify("Adding cards is not configured", vim.log.levels.WARN)
  end
end

function M.open(collect, opts)
  opts = opts or {}
  provider = collect
  local cards, errors = collect()
  if errors and #errors > 0 then
    util.notify(table.concat(errors, "\n"), vim.log.levels.WARN)
  end

  state.groups = group_cards(cards, os.time())
  state.sel = opts.sel or 1

  if not M.is_open() then
    vim.cmd("tabnew")
    state.tab = vim.api.nvim_get_current_tabpage()
    state.win = vim.api.nvim_get_current_win()

    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = "norg"
    vim.bo[buf].swapfile = false
    state.buf = buf
    vim.api.nvim_win_set_buf(state.win, buf)

    vim.wo[state.win].winbar = " ⏎ review group · a add card · p peek · e edit · R refresh · s stats · q quit"

    local maps = {
      { "q", M.close, "Close overview" },
      { "<Esc>", M.close, "Close overview" },
      { "h", move_by(-1), "Previous card" },
      { "<Left>", move_by(-1), "Previous card" },
      { "l", move_by(1), "Next card" },
      { "<Right>", move_by(1), "Next card" },
      { "j", move_vertically(1), "Card below" },
      { "<Down>", move_vertically(1), "Card below" },
      { "k", move_vertically(-1), "Card above" },
      { "<Up>", move_vertically(-1), "Card above" },
      { "<CR>", M.review_group, "Review due cards in group" },
      { "r", M.review_group, "Review due cards in group" },
      { "p", M.peek, "Peek at card" },
      { "e", M.edit_card, "Edit card source" },
      { "R", M.refresh, "Recollect cards" },
      { "a", add_card, "Add a flashcard" },
      { "s", M.jump_stats, "Jump to analytics" },
    }
    for _, map in ipairs(maps) do
      vim.keymap.set("n", map[1], map[2], { buffer = buf, silent = true, nowait = true, desc = map[3] })
    end
  end

  render()

  if opts.view == "stats" then
    M.jump_stats()
  end
end

function M.setup(opts, extra_handlers)
  config = opts or {}
  handlers = extra_handlers or {}
  define_highlights()

  local group = vim.api.nvim_create_augroup("neorg_flashcards_overview", { clear = true })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if M.is_open() then
        render()
      end
    end,
  })
end

return M
