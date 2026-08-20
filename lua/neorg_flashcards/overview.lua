-- Full-page dashboard: a dedicated tab with the tag-grouped card list on the
-- left and the analytics pane (streak, heatmap, forecast) on the right. Both
-- panes are scratch buffers; colors come from extmark highlights.

local popup = require("neorg_flashcards.popup")
local review = require("neorg_flashcards.review")
local schedule = require("neorg_flashcards.schedule")
local schema = require("neorg_flashcards.schema")
local stats = require("neorg_flashcards.stats")
local util = require("neorg_flashcards.util")

local M = {}

local GLYPH = "●"

local HIGHLIGHTS = {
  due = "NeorgFlashcardsDue",
  soon = "NeorgFlashcardsSoon",
  scheduled = "NeorgFlashcardsScheduled",
  new = "NeorgFlashcardsNew",
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
  tab = nil,
  cards = { buf = nil, win = nil }, -- left pane: grouped card list
  stats = { buf = nil, win = nil }, -- right pane: analytics
  groups = {},
  entries = {}, -- selectable cards in line order: { line, card, group }
  sel = 1,
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

-- Cards with several tags appear in several groups; the analytics pane counts
-- each card once.
local function unique_cards()
  local seen = {}
  local unique = {}
  for _, group in ipairs(state.groups) do
    for _, card in ipairs(group.cards) do
      if not seen[card] then
        seen[card] = true
        table.insert(unique, card)
      end
    end
  end
  return unique
end

local function selected_entry()
  return state.entries[state.sel]
end

local function status_text(card, now)
  local due = schedule.parse_due(card.values.due)
  if not due then
    return schema.card_score(card) and "due now" or "new"
  end
  if due <= now then
    return "due " .. card.values.due
  end
  if due <= now + 86400 then
    return "soon · " .. card.values.due
  end
  return card.values.due
end

-- Builds the left pane: header, legend, then one line per card grouped by
-- tag. Returns lines, highlight spans, and the selectable card entries with
-- their 1-based line numbers.
local function build_cards()
  local now = os.time()

  local total_cards = 0
  for _, group in ipairs(state.groups) do
    total_cards = total_cards + #group.cards
  end
  if total_cards == 0 then
    state.sel = 1
  else
    state.sel = math.max(1, math.min(total_cards, state.sel))
  end

  local total_due = 0
  local unique = unique_cards()
  for _, card in ipairs(unique) do
    if schedule.is_due(card, now) then
      total_due = total_due + 1
    end
  end

  local lines = {
    string.format(" %d cards · %d groups · %d due", #unique, #state.groups, total_due),
    "  " .. GLYPH .. " due   " .. GLYPH .. " soon   " .. GLYPH .. " scheduled   " .. GLYPH .. " new",
    "",
  }
  local spans = {
    { line = 1, start_col = 0, end_col = -1, hl = HIGHLIGHTS.muted },
  }
  local at = 2
  for _, key in ipairs({ "due", "soon", "scheduled", "new" }) do
    table.insert(spans, { line = 2, start_col = at, end_col = at + #GLYPH, hl = HIGHLIGHTS[key] })
    at = at + #GLYPH + #" " + #key + 3
  end

  local entries = {}
  if #state.groups == 0 then
    table.insert(lines, " No cards yet — press a to add one")
    table.insert(spans, { line = #lines, start_col = 0, end_col = -1, hl = HIGHLIGHTS.muted })
    return lines, spans, entries
  end

  for _, group in ipairs(state.groups) do
    local header = string.format(" %s · %d cards · %d due", group.name, #group.cards, group.due)
    table.insert(lines, header)
    table.insert(spans, { line = #lines, start_col = 0, end_col = -1, hl = HIGHLIGHTS.title })
    if group.due > 0 then
      table.insert(spans, {
        line = #lines,
        start_col = #header - #string.format("%d due", group.due),
        end_col = -1,
        hl = HIGHLIGHTS.due,
      })
    end

    for _, card in ipairs(group.cards) do
      local index = #entries + 1
      local selected = index == state.sel
      local marker = selected and "▸ " or "  "

      local _, front = schema.front(config, card)
      front = front:gsub("\n", " ")
      local reveal = schema.reveal_fields(config, card)[1]
      local text = front
      if reveal then
        text = text .. " — " .. util.trim(reveal.value):gsub("\n", " ")
      end

      local glyph_col = #"  " + #marker
      local line = "  " .. marker .. GLYPH .. " " .. text .. "  "
      local status_col = #line
      line = line .. status_text(card, now)
      table.insert(lines, line)

      table.insert(spans, {
        line = #lines,
        start_col = glyph_col,
        end_col = glyph_col + #GLYPH,
        hl = HIGHLIGHTS[card_visual(card, now)],
      })
      if selected then
        table.insert(spans, { line = #lines, start_col = 2, end_col = 2 + #marker, hl = HIGHLIGHTS.selected })
      end
      table.insert(spans, { line = #lines, start_col = status_col, end_col = -1, hl = HIGHLIGHTS.muted })

      table.insert(entries, { line = #lines, card = card, group = group })
    end

    table.insert(lines, "")
  end

  return lines, spans, entries
end

-- Builds the right pane from the stats section builders; the heatmap width
-- adapts to the pane.
local function build_stats()
  local width = 40
  if state.stats.win and vim.api.nvim_win_is_valid(state.stats.win) then
    width = vim.api.nvim_win_get_width(state.stats.win)
  end

  local now = os.time()
  local cards = unique_cards()
  local log_entries = stats.read_log()
  local weeks = math.max(4, math.min(20, math.floor((width - 8) / 2)))

  local lines = { " Analytics", "" }
  local spans = {
    { line = 1, start_col = 0, end_col = -1, hl = HIGHLIGHTS.heading },
  }
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

  stitch(stats.summary_section(cards, log_entries, now))
  table.insert(lines, "")
  stitch(stats.heatmap_section(log_entries, now, weeks))
  table.insert(lines, "")
  stitch(stats.forecast_section(cards, now, width))

  return lines, spans
end

local function set_pane_lines(pane, lines)
  vim.bo[pane.buf].modifiable = true
  vim.api.nvim_buf_set_lines(pane.buf, 0, -1, false, lines)
  vim.bo[pane.buf].modifiable = false
end

local function paint(pane, spans)
  vim.api.nvim_buf_clear_namespace(pane.buf, ns, 0, -1)
  for _, span in ipairs(spans) do
    vim.api.nvim_buf_add_highlight(pane.buf, ns, span.hl, span.line - 1, span.start_col, span.end_col)
  end
end

local function render_cards()
  local lines, spans, entries = build_cards()
  state.entries = entries
  set_pane_lines(state.cards, lines)
  paint(state.cards, spans)

  local entry = selected_entry()
  if entry and vim.api.nvim_win_is_valid(state.cards.win) then
    vim.api.nvim_win_set_cursor(state.cards.win, { entry.line, 0 })
  end
end

local function render_stats()
  if not (state.stats.buf and vim.api.nvim_buf_is_valid(state.stats.buf)) then
    return
  end
  local lines, spans = build_stats()
  set_pane_lines(state.stats, lines)
  paint(state.stats, spans)
end

local function render()
  render_cards()
  render_stats()
end

function M.move(delta)
  if #state.entries == 0 then
    return
  end
  state.sel = math.max(1, math.min(#state.entries, state.sel + delta))
  render_cards()
end

function M.peek()
  local entry = selected_entry()
  if not entry then
    return
  end

  local front_title, front = schema.front(config, entry.card)
  local lines = { "** " .. front_title }
  for _, line in ipairs(util.value_lines(front)) do
    table.insert(lines, line)
  end
  for _, field in ipairs(schema.reveal_fields(config, entry.card)) do
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
  M.focus_cards()
end

function M.review_group()
  local entry = selected_entry()
  if not entry then
    return
  end

  local now = os.time()
  local due = {}
  for _, card in ipairs(entry.group.cards) do
    if schedule.is_due(card, now) then
      table.insert(due, card)
    end
  end

  if #due == 0 then
    util.notify("No due cards in group: " .. entry.group.name, vim.log.levels.WARN)
    return
  end

  -- The review float opens on top of the dashboard; closing it just refreshes.
  local name = entry.group.name
  review.start(due, {}, "tag:" .. name, nil, {
    on_close = function()
      M.refresh()
    end,
  })
end

function M.edit_card()
  local entry = selected_entry()
  if not entry then
    return
  end

  local card = entry.card
  M.close()
  vim.cmd.edit(util.fname(card.path))
  vim.api.nvim_win_set_cursor(0, { card.start_line, 0 })
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
  return state.cards.win ~= nil and vim.api.nvim_win_is_valid(state.cards.win)
end

function M.focus_cards()
  if state.cards.win and vim.api.nvim_win_is_valid(state.cards.win) then
    vim.api.nvim_set_current_win(state.cards.win)
  end
end

function M.focus_stats()
  if state.stats.win and vim.api.nvim_win_is_valid(state.stats.win) then
    vim.api.nvim_set_current_win(state.stats.win)
  end
end

function M.close()
  popup.close(peek)

  for _, pane in ipairs({ state.cards, state.stats }) do
    if pane.buf and vim.api.nvim_buf_is_valid(pane.buf) then
      pcall(vim.api.nvim_buf_delete, pane.buf, { force = true })
    end
    pane.buf = nil
    pane.win = nil
  end

  if state.tab and vim.api.nvim_tabpage_is_valid(state.tab) and #vim.api.nvim_list_tabpages() > 1 then
    pcall(vim.cmd, "tabclose " .. vim.api.nvim_tabpage_get_number(state.tab))
  end
  state.tab = nil
end

local function add_card()
  if handlers.on_add then
    handlers.on_add()
  else
    util.notify("Adding cards is not configured", vim.log.levels.WARN)
  end
end

local function new_scratch()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "norg"
  vim.bo[buf].swapfile = false
  return buf
end

local function panel_width()
  return math.max(36, math.min(48, math.floor(vim.o.columns * 0.34)))
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

    state.cards.buf = new_scratch()
    state.cards.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.cards.win, state.cards.buf)
    vim.wo[state.cards.win].winbar =
      " ⏎/r review group · a add card · p peek · e edit · s stats · R refresh · q quit"
    vim.wo[state.cards.win].cursorline = true

    vim.cmd("belowright vsplit")
    state.stats.buf = new_scratch()
    state.stats.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.stats.win, state.stats.buf)
    vim.api.nvim_win_set_width(state.stats.win, panel_width())
    vim.wo[state.stats.win].winfixwidth = true
    vim.wo[state.stats.win].winbar = " analytics · s cards · q quit"

    local cards_maps = {
      { "q", M.close, "Close dashboard" },
      { "<Esc>", M.close, "Close dashboard" },
      {
        "j",
        function()
          M.move(1)
        end,
        "Next card",
      },
      {
        "<Down>",
        function()
          M.move(1)
        end,
        "Next card",
      },
      {
        "k",
        function()
          M.move(-1)
        end,
        "Previous card",
      },
      {
        "<Up>",
        function()
          M.move(-1)
        end,
        "Previous card",
      },
      { "<CR>", M.review_group, "Review due cards in group" },
      { "r", M.review_group, "Review due cards in group" },
      { "p", M.peek, "Peek at card" },
      { "e", M.edit_card, "Edit card source" },
      { "R", M.refresh, "Recollect cards" },
      { "a", add_card, "Add a flashcard" },
      { "s", M.focus_stats, "Focus the analytics pane" },
    }
    for _, map in ipairs(cards_maps) do
      vim.keymap.set("n", map[1], map[2], { buffer = state.cards.buf, silent = true, nowait = true, desc = map[3] })
    end

    local stats_maps = {
      { "q", M.close, "Close dashboard" },
      { "<Esc>", M.close, "Close dashboard" },
      { "s", M.focus_cards, "Focus the card list" },
      { "<CR>", M.focus_cards, "Focus the card list" },
      { "<Tab>", M.focus_cards, "Focus the card list" },
    }
    for _, map in ipairs(stats_maps) do
      vim.keymap.set("n", map[1], map[2], { buffer = state.stats.buf, silent = true, nowait = true, desc = map[3] })
    end

    M.focus_cards()
  end

  render()

  if opts.view == "stats" then
    M.focus_stats()
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
        if vim.api.nvim_win_is_valid(state.stats.win) then
          vim.api.nvim_win_set_width(state.stats.win, panel_width())
        end
        render()
      end
    end,
  })
end

return M
