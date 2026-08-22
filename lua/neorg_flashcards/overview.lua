-- A full-tab flashcard hub with Overview, Cards, and Stats pages. The public
-- API intentionally retains the original dashboard entry points so existing
-- integrations can move to the hub without a flag day.

local actions = require("neorg_flashcards.ui.actions")
local popup = require("neorg_flashcards.popup")
local review = require("neorg_flashcards.review")
local schedule = require("neorg_flashcards.schedule")
local schema = require("neorg_flashcards.schema")
local stats = require("neorg_flashcards.stats")
local util = require("neorg_flashcards.util")

local M = {}

local GLYPH = "●"
local PAGES = { "overview", "cards", "stats" }
local SORTS = { "due", "front", "state", "source" }

local HIGHLIGHTS = {
  due = "NeorgFlashcardsDue",
  overdue = "NeorgFlashcardsOverdue",
  soon = "NeorgFlashcardsSoon",
  scheduled = "NeorgFlashcardsScheduled",
  new = "NeorgFlashcardsNew",
  learning = "NeorgFlashcardsLearning",
  review = "NeorgFlashcardsReview",
  relearning = "NeorgFlashcardsLearning",
  suspended = "NeorgFlashcardsSuspended",
  buried = "NeorgFlashcardsBuried",
  invalid = "NeorgFlashcardsInvalid",
  active = "NeorgFlashcardsActive",
  title = "NeorgFlashcardsGroupTitle",
  muted = "NeorgFlashcardsMuted",
  selected = "NeorgFlashcardsSelected",
  heading = "NeorgFlashcardsHeading",
  accent = "NeorgFlashcardsAccent",
  action = "NeorgFlashcardsPrimaryAction",
  table_header = "NeorgFlashcardsTableHeader",
}

local config = {}
local handlers = {}
local provider = nil
local ns = vim.api.nvim_create_namespace("neorg_flashcards_hub")

local state = {
  tab = nil,
  -- These names are retained for compatibility. `cards` is the main region;
  -- `stats` is the contextual secondary region.
  cards = { buf = nil, win = nil },
  stats = { buf = nil, win = nil },
  page = "overview",
  layout = nil,
  all_cards = {},
  invalid_cards = {},
  groups = {},
  entries = {},
  sel = 1,
  card_entries = {},
  card_sel = 1,
  selected_card_key = nil,
  query = "",
  filter = "all",
  sort = "due",
  capabilities = {},
}

local peek = { buf = nil, win = nil }
local key_help = { buf = nil, win = nil }

local function define_highlights()
  vim.api.nvim_set_hl(0, HIGHLIGHTS.due, { link = "DiagnosticWarn", default = true })
  vim.api.nvim_set_hl(0, HIGHLIGHTS.overdue, { link = "DiagnosticError", default = true })
  vim.api.nvim_set_hl(0, HIGHLIGHTS.soon, { link = "DiagnosticWarn", default = true })
  vim.api.nvim_set_hl(0, HIGHLIGHTS.scheduled, { link = "DiagnosticOk", default = true })
  vim.api.nvim_set_hl(0, HIGHLIGHTS.new, { link = "DiagnosticInfo", default = true })
  vim.api.nvim_set_hl(0, HIGHLIGHTS.learning, { link = "Special", default = true })
  vim.api.nvim_set_hl(0, HIGHLIGHTS.review, { link = "Type", default = true })
  vim.api.nvim_set_hl(0, HIGHLIGHTS.suspended, { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, HIGHLIGHTS.buried, { link = "NonText", default = true })
  vim.api.nvim_set_hl(0, HIGHLIGHTS.invalid, { link = "DiagnosticError", bold = true, default = true })
  vim.api.nvim_set_hl(0, HIGHLIGHTS.active, { link = "DiagnosticOk", default = true })
  vim.api.nvim_set_hl(0, HIGHLIGHTS.title, { link = "Title", default = true })
  vim.api.nvim_set_hl(0, HIGHLIGHTS.muted, { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, HIGHLIGHTS.selected, { link = "Visual", bold = true, default = true })
  vim.api.nvim_set_hl(0, HIGHLIGHTS.heading, { link = "Title", bold = true, default = true })
  vim.api.nvim_set_hl(0, HIGHLIGHTS.accent, { link = "Special", bold = true, default = true })
  vim.api.nvim_set_hl(0, HIGHLIGHTS.action, { link = "IncSearch", bold = true, default = true })
  vim.api.nvim_set_hl(0, HIGHLIGHTS.table_header, { link = "Identifier", bold = true, default = true })
  vim.api.nvim_set_hl(0, "NeorgFlashcardsTabActive", { link = "TabLineSel", bold = true, default = true })
  vim.api.nvim_set_hl(0, "NeorgFlashcardsTabInactive", { link = "TabLine", default = true })
  vim.api.nvim_set_hl(0, "NeorgFlashcardsFooter", { link = "StatusLine", default = true })
end

local function lower(value)
  return util.trim(value):lower()
end

local function show_shortcuts()
  return type(config.ui) ~= "table" or config.ui.show_shortcuts ~= false
end

local function truthy(value)
  value = lower(value)
  return value == "1" or value == "true" or value == "yes" or value == "on"
end

local function valid_choice(value, choices, fallback)
  value = lower(value)
  for _, choice in ipairs(choices) do
    if value == choice then
      return value
    end
  end
  return fallback
end

local function day_start(epoch)
  local date = os.date("*t", epoch)
  return os.time({ year = date.year, month = date.month, day = date.day, hour = 0, min = 0, sec = 0 })
end

-- schedule.card_status is supplied by newer model versions. Keeping this
-- normalizer local lets the UI work against older checkouts and custom card
-- providers too.
local function card_status(card, now)
  local model_status = nil
  if type(schedule.card_status) == "function" then
    local ok, value = pcall(schedule.card_status, card, now)
    if ok and type(value) == "table" then
      model_status = value
    end
  end

  local values = (card and card.values) or {}
  local explicit = lower(values.state ~= "" and values.state or values.status)
  local availability = model_status and (model_status.availability or model_status.availability_state)
  availability = valid_choice(availability or explicit, { "active", "suspended", "buried" }, "active")
  if not model_status then
    if truthy(values.suspended) then
      availability = "suspended"
    elseif truthy(values.buried) then
      availability = "buried"
    end
  end

  local score = schema.card_score(card)
  local interval = tonumber(values.interval)
  local lifecycle = model_status and (model_status.lifecycle or model_status.learning_state)
  lifecycle = valid_choice(lifecycle, { "new", "learning", "review", "relearning" }, nil)
  if not lifecycle then
    if explicit == "new" or explicit == "learning" or explicit == "review" or explicit == "relearning" then
      lifecycle = explicit
    elseif not score then
      lifecycle = "new"
    elseif interval == 0 or (interval and interval < 1) then
      lifecycle = score == 1 and "relearning" or "learning"
    else
      lifecycle = "review"
    end
  end

  local due = schedule.parse_due(values.due)
  local timing = model_status and (model_status.timing or model_status.due_state)
  timing = valid_choice(timing, { "new", "due", "overdue", "soon", "scheduled" }, nil)
  if not timing then
    if not due then
      timing = lifecycle == "new" and "new" or "due"
    elseif due <= now then
      timing = due < day_start(now) and "overdue" or "due"
    elseif due <= now + 86400 then
      timing = "soon"
    else
      timing = "scheduled"
    end
  end
  if lifecycle == "new" and not due and timing == "due" then
    timing = "new"
  elseif timing == "scheduled" and due and due <= now + 86400 then
    timing = "soon"
  end

  return { lifecycle = lifecycle, timing = timing, availability = availability, due = due }
end

local function is_available(card, now)
  return card_status(card, now).availability == "active"
end

local function is_ready(card, now)
  local status = card_status(card, now)
  return status.availability == "active"
    and (status.timing == "new" or status.timing == "due" or status.timing == "overdue")
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

local function card_key(card)
  local id = util.trim(card.values and card.values.id)
  if id ~= "" then
    return id
  end
  return table.concat({ tostring(card.path or ""), tostring(card.start_line or ""), tostring(card.kind or "") }, ":")
end

local function card_front(card)
  local _, front = schema.front(config, card)
  return util.trim(front):gsub("\n", " ")
end

local function card_answer(card)
  local parts = {}
  for _, field in ipairs(schema.reveal_fields(config, card)) do
    local value = util.trim(field.value):gsub("\n", " ")
    if value ~= "" then
      table.insert(parts, value)
    end
  end
  return table.concat(parts, " · ")
end

local function card_source(card)
  return util.path_label(card.path, config.flashcards_dir)
end

local function invalid_messages(descriptor)
  if type(descriptor.messages) == "table" then
    return descriptor.messages
  elseif descriptor.messages ~= nil then
    return { tostring(descriptor.messages) }
  end
  return { "invalid flashcard block" }
end

local function invalid_source(descriptor)
  if util.trim(descriptor.source) ~= "" then
    return util.trim(descriptor.source)
  end
  local card = descriptor.card or {}
  local source = card_source(card)
  if card.start_line then
    source = source .. ":" .. tostring(card.start_line)
  end
  return source
end

local function browser_entry_key(entry)
  if entry.invalid then
    return table.concat({ "invalid", invalid_source(entry), card_key(entry.card) }, ":")
  end
  return "valid:" .. card_key(entry.card)
end

local function truncate(text, width)
  text = tostring(text or ""):gsub("[\r\n]", " ")
  width = math.max(1, width or 1)
  if vim.fn.strdisplaywidth(text) <= width then
    return text
  end
  local chars = vim.fn.strchars(text)
  while chars > 0 do
    local candidate = vim.fn.strcharpart(text, 0, chars) .. "…"
    if vim.fn.strdisplaywidth(candidate) <= width then
      return candidate
    end
    chars = chars - 1
  end
  return "…"
end

local function pad(text, width)
  text = truncate(text, width)
  return text .. string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(text)))
end

local function group_cards(cards, now)
  local by_tag = {}
  local order = {}
  for _, card in ipairs(cards or {}) do
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
    local cards_for_tag = by_tag[tag]
    table.sort(cards_for_tag, function(left, right)
      local left_due, right_due = schedule.due_key(left), schedule.due_key(right)
      if left_due ~= right_due then
        return left_due < right_due
      end
      return card_front(left) < card_front(right)
    end)
    local due = 0
    for _, card in ipairs(cards_for_tag) do
      if is_ready(card, now) then
        due = due + 1
      end
    end
    table.insert(groups, { name = tag, cards = cards_for_tag, due = due })
  end
  return groups
end

local function add_line(lines, spans, text, hl)
  table.insert(lines, text or "")
  if hl then
    table.insert(spans, { line = #lines, start_col = 0, end_col = -1, hl = hl })
  end
  return #lines
end

local function add_span(spans, line, start_col, end_col, hl)
  table.insert(spans, { line = line, start_col = start_col, end_col = end_col, hl = hl })
end

local function append_section(lines, spans, section_lines, section_spans)
  local offset = #lines
  for _, line in ipairs(section_lines or {}) do
    table.insert(lines, line)
  end
  for _, span in ipairs(section_spans or {}) do
    add_span(spans, span.line + offset, span.start_col, span.end_col, span.hl)
  end
end

local function count_states(cards, now)
  local result = {
    total = #cards,
    ready = 0,
    ready_new = 0,
    due = 0,
    overdue = 0,
    new = 0,
    learning = 0,
    review = 0,
    relearning = 0,
    scheduled = 0,
    suspended = 0,
    buried = 0,
  }
  for _, card in ipairs(cards) do
    local status = card_status(card, now)
    result[status.lifecycle] = (result[status.lifecycle] or 0) + 1
    if status.availability ~= "active" then
      result[status.availability] = (result[status.availability] or 0) + 1
    else
      if status.timing == "due" then
        result.due = result.due + 1
      elseif status.timing == "overdue" then
        result.overdue = result.overdue + 1
      elseif status.timing == "scheduled" or status.timing == "soon" then
        result.scheduled = result.scheduled + 1
      end
      if status.timing == "new" or status.timing == "due" or status.timing == "overdue" then
        result.ready = result.ready + 1
        if status.lifecycle == "new" then
          result.ready_new = result.ready_new + 1
        end
      end
    end
  end
  return result
end

local function status_label(status)
  if status.availability == "suspended" then
    return "SUSPENDED", HIGHLIGHTS.suspended
  elseif status.availability == "buried" then
    return "BURIED", HIGHLIGHTS.buried
  end
  local labels = { overdue = "OVERDUE", due = "DUE", soon = "SOON", scheduled = "SCHEDULED", new = "NEW" }
  return labels[status.timing] or status.timing:upper(), HIGHLIGHTS[status.timing] or HIGHLIGHTS.muted
end

local function status_badges(status)
  local badges = {}
  local timing, timing_hl = status_label(status)
  table.insert(badges, { text = "[" .. timing .. "]", hl = timing_hl })
  if status.availability == "active" and status.lifecycle ~= "new" then
    table.insert(badges, {
      text = "[" .. status.lifecycle:upper() .. "]",
      hl = HIGHLIGHTS[status.lifecycle] or HIGHLIGHTS.review,
    })
  end
  return badges
end

local function status_text(card, now)
  local status = card_status(card, now)
  if status.availability ~= "active" then
    return status.availability
  elseif status.timing == "new" then
    return "new"
  elseif status.timing == "due" or status.timing == "overdue" then
    return "due " .. util.trim(card.values.due)
  elseif status.timing == "soon" then
    return "soon · " .. util.trim(card.values.due)
  end
  return util.trim(card.values.due)
end

local function selected_overview_entry()
  return state.entries[state.sel]
end

local function selected_card_entry()
  return state.card_entries[state.card_sel]
end

local function selected_card_is_invalid()
  return state.page == "cards" and selected_card_entry() and selected_card_entry().invalid == true
end

local function selected_card()
  if state.page == "cards" then
    local entry = selected_card_entry()
    return entry and entry.card
  elseif state.page == "stats" then
    return nil
  end
  local entry = selected_overview_entry()
  return entry and entry.card
end

local function main_width()
  if state.cards.win and vim.api.nvim_win_is_valid(state.cards.win) then
    return vim.api.nvim_win_get_width(state.cards.win)
  end
  return math.max(40, math.floor(vim.o.columns * 0.64))
end

local function side_width()
  if state.stats.win and vim.api.nvim_win_is_valid(state.stats.win) then
    return vim.api.nvim_win_get_width(state.stats.win)
  end
  return 44
end

local function build_overview()
  local now = os.time()
  local counts = count_states(state.all_cards, now)
  local minutes = counts.ready == 0 and 0 or math.max(1, math.ceil(counts.ready / 3))
  local lines, spans, entries = {}, {}, {}

  add_line(lines, spans, " Flashcards", HIGHLIGHTS.heading)
  add_line(lines, spans, " A calm place to decide what to study next.", HIGHLIGHTS.muted)
  add_line(lines, spans, "")
  add_line(lines, spans, " TODAY", HIGHLIGHTS.title)
  local action = string.format("  ▸  REVIEW DUE   %d ready", counts.ready)
  if minutes > 0 then
    action = action .. string.format(" · about %d min", minutes)
  end
  add_line(lines, spans, action, HIGHLIGHTS.action)
  if counts.ready == 0 then
    local next_due = schedule.next_due(state.all_cards, now)
    local message = next_due and ("  You are caught up. Next card " .. schedule.humanize(next_due - now) .. ".")
      or "  You are caught up. Add a card when curiosity strikes."
    add_line(lines, spans, message, HIGHLIGHTS.scheduled)
  else
    add_line(
      lines,
      spans,
      string.format("  %d overdue · %d due today · %d new", counts.overdue, counts.due, counts.ready_new),
      HIGHLIGHTS.muted
    )
  end
  if state.capabilities.add then
    add_line(lines, spans, "     a  Add a card", HIGHLIGHTS.accent)
  end
  add_line(lines, spans, "")
  add_line(lines, spans, " COLLECTION", HIGHLIGHTS.title)
  add_line(
    lines,
    spans,
    string.format(
      "  %d cards · %d learning · %d review · %d suspended · %d buried",
      counts.total,
      counts.learning + counts.relearning,
      counts.review,
      counts.suspended,
      counts.buried
    ),
    HIGHLIGHTS.muted
  )
  add_line(
    lines,
    spans,
    "  " .. GLYPH .. " due   " .. GLYPH .. " soon   " .. GLYPH .. " scheduled   " .. GLYPH .. " new"
  )
  local legend_line = #lines
  local at = 2
  for _, key in ipairs({ "due", "soon", "scheduled", "new" }) do
    add_span(spans, legend_line, at, at + #GLYPH, HIGHLIGHTS[key])
    at = at + #GLYPH + #" " + #key + 3
  end
  add_line(lines, spans, "")

  local total_group_cards = 0
  for _, group in ipairs(state.groups) do
    total_group_cards = total_group_cards + #group.cards
  end
  state.sel = total_group_cards == 0 and 1 or math.max(1, math.min(total_group_cards, state.sel))
  if #state.groups == 0 then
    add_line(lines, spans, "  No cards yet.", HIGHLIGHTS.heading)
    add_line(
      lines,
      spans,
      state.capabilities.add and "  Press a to make the first one." or "  Add a .norg flashcard to this collection.",
      HIGHLIGHTS.muted
    )
    return lines, spans, entries
  end

  for _, group in ipairs(state.groups) do
    local header =
      string.format(" %s · %d card%s · %d due", group.name, #group.cards, #group.cards == 1 and "" or "s", group.due)
    add_line(lines, spans, header, HIGHLIGHTS.title)
    if group.due > 0 then
      add_span(spans, #lines, #header - #string.format("%d due", group.due), -1, HIGHLIGHTS.due)
    end
    for _, card in ipairs(group.cards) do
      local index = #entries + 1
      local marker = index == state.sel and "▸ " or "  "
      local text = card_front(card)
      local answer = card_answer(card)
      if answer ~= "" then
        text = text .. " — " .. answer
      end
      text = truncate(text, math.max(18, main_width() - 27))
      local glyph_col = #"  " + #marker
      local line = "  " .. marker .. GLYPH .. " " .. text .. "  "
      local status_col = #line
      line = line .. status_text(card, now)
      add_line(lines, spans, line)
      local _, visual = status_label(card_status(card, now))
      add_span(spans, #lines, glyph_col, glyph_col + #GLYPH, visual)
      if index == state.sel then
        add_span(spans, #lines, 2, 2 + #marker, HIGHLIGHTS.selected)
      end
      add_span(spans, #lines, status_col, -1, HIGHLIGHTS.muted)
      table.insert(entries, { line = #lines, card = card, group = group })
    end
    add_line(lines, spans, "")
  end
  return lines, spans, entries
end

local function build_overview_side()
  local now = os.time()
  local cards = state.all_cards
  local log_entries, log_errors = stats.read_log()
  local width = side_width()
  local weeks = math.max(4, math.min(14, math.floor((width - 8) / 2)))
  local lines, spans = {}, {}
  add_line(lines, spans, " Analytics", HIGHLIGHTS.heading)
  add_line(lines, spans, "")
  if log_errors and #log_errors > 0 then
    add_line(
      lines,
      spans,
      string.format(
        "  ⚠ %d history line%s skipped · press c to inspect",
        #log_errors,
        #log_errors == 1 and "" or "s"
      ),
      HIGHLIGHTS.overdue
    )
    add_line(lines, spans, "")
  end
  append_section(lines, spans, stats.summary_section(cards, log_entries, now))
  add_line(lines, spans, "")
  append_section(lines, spans, stats.forecast_section(cards, now, width))
  local height = state.stats.win
      and vim.api.nvim_win_is_valid(state.stats.win)
      and vim.api.nvim_win_get_height(state.stats.win)
    or 30
  if height >= 24 then
    add_line(lines, spans, "")
    append_section(lines, spans, stats.heatmap_section(log_entries, now, weeks))
  end
  add_line(lines, spans, "")
  add_line(lines, spans, " Next step", HIGHLIGHTS.title)
  local counts = count_states(cards, now)
  if counts.ready > 0 then
    add_line(
      lines,
      spans,
      string.format("  Review %d ready card%s while the queue is small.", counts.ready, counts.ready == 1 and "" or "s"),
      HIGHLIGHTS.accent
    )
  elseif counts.total == 0 then
    add_line(lines, spans, "  Add a small card you will be glad to remember.", HIGHLIGHTS.muted)
  else
    add_line(lines, spans, "  Nothing is due. Browse weak cards or enjoy the win.", HIGHLIGHTS.scheduled)
  end
  return lines, spans
end

local function searchable_text(card, now)
  local status = card_status(card, now)
  return table
    .concat({
      card_front(card),
      card_answer(card),
      card.kind or "",
      card.values.tags or "",
      card_source(card),
      card.values.due or "",
      status.lifecycle,
      status.timing,
      status.availability,
    }, " ")
    :lower()
end

local function invalid_searchable_text(descriptor)
  local card = descriptor.card or {}
  local values = {}
  for key, value in pairs(card.values or {}) do
    table.insert(values, tostring(key))
    table.insert(values, tostring(value))
  end
  table.sort(values)
  return table
    .concat({
      "invalid",
      card.kind or "",
      card.path or "",
      invalid_source(descriptor),
      table.concat(values, " "),
      table.concat(invalid_messages(descriptor), " "),
    }, " ")
    :lower()
end

local function matches_filter(card, now, filter)
  if filter == "all" then
    return true
  end
  local status = card_status(card, now)
  if filter == "ready" then
    return status.availability == "active"
      and (status.timing == "new" or status.timing == "due" or status.timing == "overdue")
  elseif filter == "due" then
    return status.availability == "active" and (status.timing == "due" or status.timing == "overdue")
  elseif filter == "scheduled" then
    return status.availability == "active" and (status.timing == "scheduled" or status.timing == "soon")
  elseif filter == "suspended" or filter == "buried" then
    return status.availability == filter
  elseif filter == "new" or filter == "learning" or filter == "review" or filter == "relearning" then
    return status.lifecycle == filter
  end
  return status.timing == filter
end

local function filtered_card_entries()
  local now = os.time()
  local result = {}
  local query = lower(state.query)
  for _, card in ipairs(state.all_cards) do
    if matches_filter(card, now, state.filter) and (query == "" or searchable_text(card, now):find(query, 1, true)) then
      table.insert(result, { card = card, invalid = false })
    end
  end
  if state.filter == "all" or state.filter == "invalid" then
    for _, descriptor in ipairs(state.invalid_cards) do
      if query == "" or invalid_searchable_text(descriptor):find(query, 1, true) then
        table.insert(result, {
          card = descriptor.card,
          invalid = true,
          messages = invalid_messages(descriptor),
          source = descriptor.source,
        })
      end
    end
  end
  table.sort(result, function(left, right)
    if left.invalid ~= right.invalid then
      return left.invalid
    elseif left.invalid then
      local left_source, right_source = invalid_source(left), invalid_source(right)
      if left_source ~= right_source then
        return left_source < right_source
      end
      return table.concat(left.messages, " ") < table.concat(right.messages, " ")
    end

    local left_card, right_card = left.card, right.card
    local left_status, right_status = card_status(left_card, now), card_status(right_card, now)
    local left_key, right_key
    if state.sort == "front" then
      left_key, right_key = card_front(left_card):lower(), card_front(right_card):lower()
    elseif state.sort == "state" then
      left_key = left_status.availability .. left_status.lifecycle .. left_status.timing
      right_key = right_status.availability .. right_status.lifecycle .. right_status.timing
    elseif state.sort == "source" then
      left_key, right_key = card_source(left_card):lower(), card_source(right_card):lower()
    else
      left_key = left_status.availability == "active" and schedule.due_key(left_card) or math.huge
      right_key = right_status.availability == "active" and schedule.due_key(right_card) or math.huge
    end
    if left_key ~= right_key then
      return left_key < right_key
    end
    return card_front(left_card):lower() < card_front(right_card):lower()
  end)
  return result
end

local function restore_card_selection(entries)
  if #entries == 0 then
    state.card_sel = 1
    state.selected_card_key = nil
    return
  end
  if state.selected_card_key then
    for index, entry in ipairs(entries) do
      if browser_entry_key(entry) == state.selected_card_key then
        state.card_sel = index
        return
      end
    end
  end
  state.card_sel = math.max(1, math.min(#entries, state.card_sel))
  state.selected_card_key = browser_entry_key(entries[state.card_sel])
end

local function build_cards_browser()
  local now = os.time()
  local browser_entries = filtered_card_entries()
  restore_card_selection(browser_entries)
  local lines, spans, entries = {}, {}, {}
  local width = main_width()
  local total_blocks = #state.all_cards + #state.invalid_cards
  add_line(lines, spans, " Cards", HIGHLIGHTS.heading)
  local scope = string.format(
    " %d shown of %d blocks · %d reviewable · %d invalid · filter: %s · sort: %s",
    #browser_entries,
    total_blocks,
    #state.all_cards,
    #state.invalid_cards,
    state.filter,
    state.sort
  )
  if state.query ~= "" then
    scope = scope .. " · search: “" .. truncate(state.query, 24) .. "”"
  end
  add_line(lines, spans, scope, HIGHLIGHTS.muted)
  add_line(lines, spans, "")
  if total_blocks == 0 then
    add_line(lines, spans, "  No cards yet", HIGHLIGHTS.heading)
    add_line(
      lines,
      spans,
      state.capabilities.add and "  Press a to create your first flashcard." or "  Add a .norg flashcard, then press R.",
      HIGHLIGHTS.muted
    )
    return lines, spans, entries
  elseif #browser_entries == 0 then
    add_line(lines, spans, "  No cards match this view", HIGHLIGHTS.heading)
    add_line(lines, spans, "  Press X or Esc to clear the search and filter.", HIGHLIGHTS.muted)
    return lines, spans, entries
  end

  local compact = width < 82
  local badge_width, due_width = 12, 16
  local front_width, answer_width
  if compact then
    front_width, answer_width = math.max(18, width - badge_width - due_width - 9), 0
  else
    answer_width = math.max(18, math.floor((width - badge_width - due_width - 12) * 0.42))
    front_width = math.max(20, width - badge_width - due_width - answer_width - 12)
  end
  local header = "    " .. pad("STATE", badge_width) .. " " .. pad("FRONT", front_width)
  if not compact then
    header = header .. " " .. pad("ANSWER", answer_width)
  end
  header = header .. " " .. pad("DUE / SOURCE", due_width)
  add_line(lines, spans, header, HIGHLIGHTS.table_header)
  add_line(lines, spans, "  " .. string.rep("─", math.max(8, math.min(width - 4, 120))), HIGHLIGHTS.muted)
  for index, entry in ipairs(browser_entries) do
    local card = entry.card
    local label, badge_hl, due, answer
    if entry.invalid then
      label, badge_hl = "[INVALID]", HIGHLIGHTS.invalid
      due = invalid_source(entry)
      answer = entry.messages[1] or "invalid flashcard block"
    else
      local status = card_status(card, now)
      local status_name
      status_name, badge_hl = status_label(status)
      label = "[" .. status_name .. "]"
      due = util.trim(card.values.due)
      answer = card_answer(card)
      if due == "" and (status.timing == "new" or status.timing == "due" or status.timing == "overdue") then
        due = "now"
      end
    end
    local marker = index == state.card_sel and "▸ " or "  "
    local front = card_front(card)
    if entry.invalid and front == "" then
      front = "@flashcard " .. tostring(card.kind or "unknown")
    end
    local line = "  " .. marker .. pad(label, badge_width) .. " " .. pad(front, front_width)
    if not compact then
      line = line .. " " .. pad(answer, answer_width)
    end
    line = line .. " " .. pad(due, due_width)
    add_line(lines, spans, line)
    local badge_col = #"  " + #marker
    add_span(spans, #lines, badge_col, badge_col + #label, badge_hl)
    if index == state.card_sel then
      add_span(spans, #lines, 2, 2 + #marker, HIGHLIGHTS.selected)
    end
    entry.line = #lines
    table.insert(entries, entry)
    if entry.invalid then
      local detail = "      source: " .. invalid_source(entry) .. " · error: " .. table.concat(entry.messages, "; ")
      add_line(lines, spans, truncate(detail, math.max(20, width - 2)), HIGHLIGHTS.invalid)
    end
  end
  return lines, spans, entries
end

local function detail_hint(status)
  if status.availability == "suspended" then
    return "Suspended cards stay out of normal review queues."
  elseif status.availability == "buried" then
    return "Buried cards are hidden until tomorrow."
  elseif status.timing == "overdue" then
    return "Overdue is a scheduling fact, not a verdict. Review it honestly."
  elseif status.lifecycle == "new" then
    return "First review: recall before revealing, then choose an honest rating."
  elseif status.lifecycle == "learning" or status.lifecycle == "relearning" then
    return "Short intervals are expected while this card settles in."
  end
  return "Try to answer before reading the back; recognition is deceptively easy."
end

local function build_card_detail()
  local entry = selected_card_entry()
  local lines, spans = {}, {}
  add_line(lines, spans, " Card details", HIGHLIGHTS.heading)
  add_line(lines, spans, "")
  if not entry then
    local no_match = state.query ~= "" or state.filter ~= "all"
    add_line(
      lines,
      spans,
      no_match and " No matching card selected." or " Select a card to inspect it.",
      HIGHLIGHTS.muted
    )
    add_line(lines, spans, " Use / to search and f to filter.", HIGHLIGHTS.muted)
    return lines, spans
  end
  local card = entry.card
  if entry.invalid then
    add_line(lines, spans, " [INVALID]", HIGHLIGHTS.invalid)
    add_line(lines, spans, " This block is visible for repair but cannot be reviewed.", HIGHLIGHTS.invalid)
    add_line(lines, spans, "")
    add_line(lines, spans, " Problems", HIGHLIGHTS.title)
    for _, message in ipairs(entry.messages) do
      add_line(
        lines,
        spans,
        "  " .. GLYPH .. " " .. truncate(message, math.max(20, side_width() - 6)),
        HIGHLIGHTS.invalid
      )
    end
    add_line(lines, spans, "")
    add_line(lines, spans, " Block", HIGHLIGHTS.title)
    add_line(lines, spans, "  Kind: " .. tostring(card.kind or "unknown"), HIGHLIGHTS.muted)
    if schema.card_id(card) then
      add_line(lines, spans, "  ID: " .. schema.card_id(card), HIGHLIGHTS.muted)
    end
    local front = card_front(card)
    if front ~= "" then
      add_line(lines, spans, "  Front: " .. truncate(front, math.max(20, side_width() - 10)), HIGHLIGHTS.muted)
    end
    add_line(lines, spans, "")
    add_line(lines, spans, " Source", HIGHLIGHTS.title)
    add_line(lines, spans, "  " .. truncate(invalid_source(entry), math.max(20, side_width() - 4)), HIGHLIGHTS.muted)
    add_line(lines, spans, "")
    add_line(lines, spans, " Repair", HIGHLIGHTS.title)
    add_line(lines, spans, "  Press e to open the block, fix the errors, then R to refresh.", HIGHLIGHTS.accent)
    if state.capabilities.delete then
      add_line(lines, spans, "  Press D to delete this exact invalid block after confirmation.", HIGHLIGHTS.muted)
    end
    return lines, spans
  end
  local status = card_status(card, os.time())
  local badge_line = " "
  for _, badge in ipairs(status_badges(status)) do
    local start_col = #badge_line
    badge_line = badge_line .. badge.text .. " "
    add_span(spans, #lines + 1, start_col, start_col + #badge.text, badge.hl)
  end
  add_line(lines, spans, badge_line)
  add_line(lines, spans, "")
  local front_title, front = schema.front(config, card)
  add_line(lines, spans, " " .. front_title, HIGHLIGHTS.title)
  for _, line in ipairs(util.value_lines(front)) do
    add_line(lines, spans, "  " .. truncate(line, math.max(20, side_width() - 4)), HIGHLIGHTS.heading)
  end
  for _, field in ipairs(schema.reveal_fields(config, card)) do
    add_line(lines, spans, "")
    add_line(lines, spans, " " .. field.title, HIGHLIGHTS.title)
    for _, line in ipairs(util.value_lines(field.value)) do
      add_line(lines, spans, "  " .. truncate(line, math.max(20, side_width() - 4)))
    end
  end
  add_line(lines, spans, "")
  add_line(lines, spans, " Scheduling", HIGHLIGHTS.title)
  add_line(lines, spans, "  Lifecycle    " .. status.lifecycle, HIGHLIGHTS.muted)
  add_line(lines, spans, "  Availability " .. status.availability, HIGHLIGHTS.muted)
  add_line(
    lines,
    spans,
    "  Due           " .. (util.trim(card.values.due) ~= "" and util.trim(card.values.due) or "now"),
    HIGHLIGHTS.muted
  )
  add_line(
    lines,
    spans,
    "  Interval      "
      .. (util.trim(card.values.interval) ~= "" and util.trim(card.values.interval) .. " days" or "—"),
    HIGHLIGHTS.muted
  )
  add_line(
    lines,
    spans,
    "  Ease          " .. (util.trim(card.values.ease) ~= "" and util.trim(card.values.ease) or "—"),
    HIGHLIGHTS.muted
  )
  add_line(
    lines,
    spans,
    "  Last rating   " .. (util.trim(card.values.score) ~= "" and util.trim(card.values.score) or "—"),
    HIGHLIGHTS.muted
  )
  add_line(lines, spans, "")
  add_line(lines, spans, " Source", HIGHLIGHTS.title)
  add_line(lines, spans, "  " .. truncate(card_source(card), math.max(20, side_width() - 4)), HIGHLIGHTS.muted)
  add_line(lines, spans, "  Tags: " .. table.concat(card_tags(card), ", "), HIGHLIGHTS.muted)
  if util.trim(card.values.id) ~= "" then
    add_line(lines, spans, "  ID: " .. util.trim(card.values.id), HIGHLIGHTS.muted)
  end
  add_line(lines, spans, "")
  add_line(lines, spans, " Hint", HIGHLIGHTS.title)
  add_line(lines, spans, "  " .. truncate(detail_hint(status), math.max(20, side_width() - 4)), HIGHLIGHTS.accent)
  if state.capabilities.delete then
    add_line(lines, spans, "")
    add_line(lines, spans, " Actions", HIGHLIGHTS.title)
    add_line(lines, spans, "  Press D to delete this card after confirmation.", HIGHLIGHTS.muted)
  end
  return lines, spans
end

local function distribution_bar(count, maximum, width)
  if count <= 0 or maximum <= 0 then
    return ""
  end
  return string.rep("█", math.max(1, math.floor(count / maximum * width + 0.5)))
end

local function build_stats_insights()
  local now = os.time()
  local counts = count_states(state.all_cards, now)
  local lines, spans = {}, {}
  add_line(lines, spans, " Study health", HIGHLIGHTS.heading)
  add_line(lines, spans, " A useful overview of the collection you have today.", HIGHLIGHTS.muted)
  add_line(lines, spans, "")
  add_line(lines, spans, " Queue", HIGHLIGHTS.title)
  add_line(
    lines,
    spans,
    string.format(
      "  Ready now     %4d  %s",
      counts.ready,
      distribution_bar(counts.ready, math.max(1, counts.total), 24)
    ),
    counts.ready > 0 and HIGHLIGHTS.due or HIGHLIGHTS.scheduled
  )
  add_line(
    lines,
    spans,
    string.format(
      "  Overdue       %4d  %s",
      counts.overdue,
      distribution_bar(counts.overdue, math.max(1, counts.total), 24)
    ),
    counts.overdue > 0 and HIGHLIGHTS.overdue or HIGHLIGHTS.muted
  )
  add_line(
    lines,
    spans,
    string.format(
      "  Scheduled     %4d  %s",
      counts.scheduled,
      distribution_bar(counts.scheduled, math.max(1, counts.total), 24)
    ),
    HIGHLIGHTS.scheduled
  )
  add_line(lines, spans, "")
  add_line(lines, spans, " Learning state", HIGHLIGHTS.title)
  add_line(lines, spans, string.format("  New           %4d", counts.new), HIGHLIGHTS.new)
  add_line(lines, spans, string.format("  Learning      %4d", counts.learning), HIGHLIGHTS.learning)
  add_line(lines, spans, string.format("  Relearning    %4d", counts.relearning), HIGHLIGHTS.learning)
  add_line(lines, spans, string.format("  Review        %4d", counts.review), HIGHLIGHTS.review)
  add_line(lines, spans, string.format("  Suspended     %4d", counts.suspended), HIGHLIGHTS.suspended)
  add_line(lines, spans, string.format("  Buried        %4d", counts.buried), HIGHLIGHTS.buried)
  local tag_counts = {}
  for _, card in ipairs(state.all_cards) do
    for _, tag in ipairs(card_tags(card)) do
      tag_counts[tag] = (tag_counts[tag] or 0) + 1
    end
  end
  local tags = {}
  for tag, count in pairs(tag_counts) do
    table.insert(tags, { tag = tag, count = count })
  end
  table.sort(tags, function(left, right)
    return left.count == right.count and left.tag < right.tag or left.count > right.count
  end)
  add_line(lines, spans, "")
  add_line(lines, spans, " Largest groups", HIGHLIGHTS.title)
  if #tags == 0 then
    add_line(lines, spans, "  No tags yet.", HIGHLIGHTS.muted)
  else
    for index = 1, math.min(8, #tags) do
      add_line(
        lines,
        spans,
        string.format("  %-22s %d", truncate(tags[index].tag, 22), tags[index].count),
        HIGHLIGHTS.muted
      )
    end
  end
  local weak = {}
  for _, card in ipairs(state.all_cards) do
    if schema.card_score(card) == 1 then
      table.insert(weak, card)
    end
  end
  add_line(lines, spans, "")
  add_line(lines, spans, " Needs attention", HIGHLIGHTS.title)
  if #weak == 0 then
    add_line(
      lines,
      spans,
      counts.total == 0 and "  Statistics appear after you add cards."
        or "  No cards currently carry the lowest rating.",
      HIGHLIGHTS.muted
    )
  else
    for index = 1, math.min(5, #weak) do
      add_line(
        lines,
        spans,
        "  " .. GLYPH .. " " .. truncate(card_front(weak[index]), math.max(20, main_width() - 8)),
        HIGHLIGHTS.overdue
      )
    end
  end
  return lines, spans
end

local function add_optional_stats_section(lines, spans, name, ...)
  if type(stats[name]) ~= "function" then
    return false
  end
  local ok, section_lines, section_spans = pcall(stats[name], ...)
  if not ok then
    return false
  end
  add_line(lines, spans, "")
  append_section(lines, spans, section_lines, section_spans)
  return true
end

local function build_full_stats()
  local now = os.time()
  local cards = state.all_cards
  local log_entries, log_errors = stats.read_log()
  local width = side_width()
  local weeks = math.max(4, math.min(20, math.floor((width - 8) / 2)))
  local lines, spans = {}, {}
  add_line(lines, spans, " Analytics", HIGHLIGHTS.heading)
  add_line(lines, spans, "")
  if log_errors and #log_errors > 0 then
    add_line(
      lines,
      spans,
      string.format(
        "  ⚠ %d history line%s skipped · press c to inspect",
        #log_errors,
        #log_errors == 1 and "" or "s"
      ),
      HIGHLIGHTS.overdue
    )
    add_line(lines, spans, "")
  end
  append_section(lines, spans, stats.summary_section(cards, log_entries, now))
  add_optional_stats_section(lines, spans, "retention_section", log_entries, now)
  add_optional_stats_section(lines, spans, "ratings_section", log_entries, now, width)
  add_optional_stats_section(lines, spans, "state_section", cards, now)
  add_line(lines, spans, "")
  append_section(lines, spans, stats.heatmap_section(log_entries, now, weeks))
  add_line(lines, spans, "")
  append_section(lines, spans, stats.forecast_section(cards, now, width))
  add_line(lines, spans, "")
  add_line(lines, spans, " About these numbers", HIGHLIGHTS.title)
  if #log_entries == 0 then
    add_line(lines, spans, "  No review history yet. Complete a review to begin the timeline.", HIGHLIGHTS.muted)
  else
    add_line(lines, spans, "  Activity is shown only since review tracking began.", HIGHLIGHTS.muted)
    add_line(lines, spans, "  Prefer trends over conclusions from one noisy day.", HIGHLIGHTS.muted)
  end
  return lines, spans
end

local function set_pane_lines(pane, lines)
  if not (pane.buf and vim.api.nvim_buf_is_valid(pane.buf)) then
    return
  end
  vim.bo[pane.buf].modifiable = true
  vim.api.nvim_buf_set_lines(pane.buf, 0, -1, false, lines)
  vim.bo[pane.buf].modifiable = false
end

local function paint(pane, spans)
  if not (pane.buf and vim.api.nvim_buf_is_valid(pane.buf)) then
    return
  end
  vim.api.nvim_buf_clear_namespace(pane.buf, ns, 0, -1)
  for _, span in ipairs(spans or {}) do
    pcall(vim.api.nvim_buf_add_highlight, pane.buf, ns, span.hl, span.line - 1, span.start_col, span.end_col)
  end
end

local function statusline_escape(text)
  return tostring(text or ""):gsub("%%", "%%%%")
end

local function tab_bar()
  local chunks = { "%#NeorgFlashcardsHeading#  Flashcards  " }
  for index, page in ipairs(PAGES) do
    local label = page:sub(1, 1):upper() .. page:sub(2)
    local hl = page == state.page and "NeorgFlashcardsTabActive" or "NeorgFlashcardsTabInactive"
    table.insert(chunks, string.format("%%#%s# %d %s ", hl, index, label))
    table.insert(chunks, "%#NeorgFlashcardsMuted# ")
  end
  return table.concat(chunks)
end

local function apply_chrome()
  local nav = tab_bar()
  for _, pane in ipairs({ state.cards, state.stats }) do
    if pane.win and vim.api.nvim_win_is_valid(pane.win) then
      local footer = " "
      if show_shortcuts() then
        footer = actions.footer(state.page, vim.api.nvim_win_get_width(pane.win), state.capabilities)
      end
      -- A global statusline (for example lualine with laststatus=3) can replace
      -- a window-local statusline after we render. Keep the page tabs in the
      -- primary pane and use the always-visible secondary winbar as the key
      -- ribbon. The statusline remains a useful fallback for simpler setups.
      if pane == state.stats and show_shortcuts() then
        vim.wo[pane.win].winbar = "%#NeorgFlashcardsFooter#" .. statusline_escape(footer)
      else
        vim.wo[pane.win].winbar = nav
      end
      vim.wo[pane.win].statusline = "%#NeorgFlashcardsFooter#" .. statusline_escape(footer)
    end
  end
end

local function render()
  if not M.is_open() then
    return
  end
  local main_lines, main_spans, side_lines, side_spans
  if state.page == "cards" then
    main_lines, main_spans, state.card_entries = build_cards_browser()
    side_lines, side_spans = build_card_detail()
  elseif state.page == "stats" then
    main_lines, main_spans = build_stats_insights()
    side_lines, side_spans = build_full_stats()
  else
    main_lines, main_spans, state.entries = build_overview()
    side_lines, side_spans = build_overview_side()
  end
  set_pane_lines(state.cards, main_lines)
  paint(state.cards, main_spans)
  set_pane_lines(state.stats, side_lines)
  paint(state.stats, side_spans)
  apply_chrome()
  local entry = state.page == "cards" and selected_card_entry()
    or (state.page == "overview" and selected_overview_entry())
  if entry and state.cards.win and vim.api.nvim_win_is_valid(state.cards.win) then
    pcall(vim.api.nvim_win_set_cursor, state.cards.win, { entry.line, 0 })
  end
end

local function call_handler(name, ...)
  local handler = handlers[name]
  if type(handler) ~= "function" then
    return false
  end
  local ok, result = pcall(handler, ...)
  if not ok then
    util.notify("Flashcard action failed: " .. tostring(result), vim.log.levels.ERROR)
  end
  return true, result
end

local function review_cards(cards, scope, empty_message)
  review.start(cards, {}, scope, empty_message, {
    sort = "due",
    on_close = function()
      M.refresh()
    end,
  })
end

function M.review_due()
  if call_handler("on_review_due") then
    return
  end
  local now = os.time()
  local due = {}
  for _, card in ipairs(state.all_cards) do
    if is_ready(card, now) then
      table.insert(due, card)
    end
  end
  local message = "No due flashcards"
  local next_due = schedule.next_due(state.all_cards, now)
  if next_due then
    message = message .. " — next at " .. schedule.format_due(next_due)
  end
  review_cards(due, "due", message)
end

function M.review_all()
  if call_handler("on_review_all") then
    return
  end
  local available = {}
  local now = os.time()
  for _, card in ipairs(state.all_cards) do
    if is_available(card, now) then
      table.insert(available, card)
    end
  end
  review_cards(available, "all", "No active flashcards")
end

function M.review_group()
  local entry = selected_overview_entry()
  if not entry then
    return
  end
  local now = os.time()
  local due = {}
  for _, card in ipairs(entry.group.cards) do
    if is_ready(card, now) then
      table.insert(due, card)
    end
  end
  if #due == 0 then
    util.notify("No due cards in group: " .. entry.group.name, vim.log.levels.WARN)
    return
  end
  review_cards(due, "tag:" .. entry.group.name, nil)
end

function M.review_selected()
  local card = selected_card()
  if not card then
    util.notify("No card selected", vim.log.levels.WARN)
    return
  end
  if selected_card_is_invalid() then
    util.notify("This block is invalid and cannot be reviewed; press e to repair it", vim.log.levels.WARN)
    return
  end
  local status = card_status(card, os.time())
  if status.availability ~= "active" then
    util.notify("This card is " .. status.availability .. "; make it active before reviewing", vim.log.levels.WARN)
    return
  end
  review_cards({ card }, "card", nil)
end

local function focused_hub_window()
  local current = vim.api.nvim_get_current_win()
  for _, pane in ipairs({ state.cards, state.stats }) do
    if pane.win and vim.api.nvim_win_is_valid(pane.win) and pane.win == current then
      return pane.win
    end
  end
  if state.page == "stats" and state.stats.win and vim.api.nvim_win_is_valid(state.stats.win) then
    return state.stats.win
  end
  if state.cards.win and vim.api.nvim_win_is_valid(state.cards.win) then
    return state.cards.win
  end
end

local function selection_for_page()
  local list, field
  if state.page == "cards" then
    list, field = state.card_entries, "card_sel"
  elseif state.page == "overview" then
    list, field = state.entries, "sel"
  end
  return list, field
end

local function select_index(list, field, index)
  if not list or not field or #list == 0 then
    return
  end
  state[field] = math.max(1, math.min(#list, index))
  if state.page == "cards" then
    state.selected_card_key = browser_entry_key(list[state.card_sel])
  end
  render()
end

local function move_window_cursor(win, delta)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end
  vim.api.nvim_win_call(win, function()
    local line_count = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
    local row = vim.api.nvim_win_get_cursor(win)[1]
    vim.api.nvim_win_set_cursor(win, { math.max(1, math.min(line_count, row + delta)), 0 })
  end)
end

local function scroll_window(win, delta)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end
  vim.api.nvim_win_call(win, function()
    local line_count = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
    local height = math.max(1, vim.api.nvim_win_get_height(win))
    local max_topline = math.max(1, line_count - height + 1)
    local view = vim.fn.winsaveview()
    view.lnum = math.max(1, math.min(line_count, view.lnum + delta))
    view.topline = math.max(1, math.min(max_topline, view.topline + delta))
    vim.fn.winrestview(view)
  end)
end

local function scroll_window_edge(win, edge)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end
  vim.api.nvim_win_call(win, function()
    local line_count = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
    local height = math.max(1, vim.api.nvim_win_get_height(win))
    local view = vim.fn.winsaveview()
    if edge == "top" then
      view.lnum, view.topline = 1, 1
    else
      view.lnum = line_count
      view.topline = math.max(1, line_count - height + 1)
    end
    vim.fn.winrestview(view)
  end)
end

local function move_selection_page(direction, win)
  local list, field = selection_for_page()
  if #list == 0 then
    return
  end
  local index = state[field]
  local current_line = (list[index] and list[index].line) or vim.api.nvim_win_get_cursor(win)[1]
  local distance = math.max(1, math.floor(vim.api.nvim_win_get_height(win) / 2))
  local target_line = current_line + direction * distance
  local target_index = index
  if direction > 0 then
    for candidate = index + 1, #list do
      target_index = candidate
      if (list[candidate].line or current_line) >= target_line then
        break
      end
    end
  else
    for candidate = index - 1, 1, -1 do
      target_index = candidate
      if (list[candidate].line or current_line) <= target_line then
        break
      end
    end
  end
  select_index(list, field, target_index)
end

function M.move(delta)
  local win = focused_hub_window()
  if not win then
    return
  end
  if state.page == "stats" or win == state.stats.win then
    move_window_cursor(win, delta)
    return
  end
  local list, field = selection_for_page()
  if not list or #list == 0 then
    return
  end
  select_index(list, field, state[field] + delta)
end

function M.scroll_page(direction)
  local win = focused_hub_window()
  if not win then
    return
  end
  direction = direction < 0 and -1 or 1
  if state.page ~= "stats" and win == state.cards.win then
    move_selection_page(direction, win)
    return
  end
  local distance = math.max(1, math.floor(vim.api.nvim_win_get_height(win) / 2))
  scroll_window(win, direction * distance)
end

function M.scroll_edge(edge)
  local win = focused_hub_window()
  if not win then
    return
  end
  edge = edge == "top" and "top" or "bottom"
  if state.page ~= "stats" and win == state.cards.win then
    local list, field = selection_for_page()
    select_index(list, field, edge == "top" and 1 or #list)
    return
  end
  scroll_window_edge(win, edge)
end

function M.peek()
  local card = selected_card()
  if not card then
    return
  end
  local entry = state.page == "cards" and selected_card_entry() or nil
  local lines = {}
  if entry and entry.invalid then
    table.insert(lines, "** [INVALID] Flashcard block")
    table.insert(lines, "This block cannot be reviewed until it is repaired.")
    table.insert(lines, "")
    table.insert(lines, "** Problems")
    for _, message in ipairs(entry.messages) do
      table.insert(lines, "- " .. message)
    end
    table.insert(lines, "")
    table.insert(lines, "Source: " .. invalid_source(entry))
  else
    local status = card_status(card, os.time())
    local front_title, front = schema.front(config, card)
    table.insert(lines, "** " .. front_title)
    for _, line in ipairs(util.value_lines(front)) do
      table.insert(lines, line)
    end
    for _, field in ipairs(schema.reveal_fields(config, card)) do
      table.insert(lines, "")
      table.insert(lines, "** " .. field.title)
      for _, line in ipairs(util.value_lines(field.value)) do
        table.insert(lines, line)
      end
    end
    table.insert(lines, "")
    table.insert(lines, string.format("State: %s · %s · %s", status.lifecycle, status.timing, status.availability))
    table.insert(lines, "Source: " .. card_source(card))
  end
  popup.open(peek, {
    title = " Card preview ",
    footer = " q/Esc close ",
    min_width = 40,
    max_width = 68,
    min_height = 8,
    max_height = 20,
    maps = {
      { "q", M.peek_close, "Close preview" },
      { "<Esc>", M.peek_close, "Close preview" },
      { "p", M.peek_close, "Close preview" },
    },
  })
  popup.set_lines(peek, lines)
end

function M.peek_close()
  popup.close(peek)
  if state.page == "stats" then
    M.focus_stats()
  else
    M.focus_cards()
  end
end

function M.context_help()
  popup.open(key_help, {
    title = " " .. state.page:sub(1, 1):upper() .. state.page:sub(2) .. " keys ",
    footer = " q/Esc close ",
    min_width = 48,
    max_width = 72,
    min_height = 12,
    max_height = 28,
    maps = {
      { "q", M.help_close, "Close key help" },
      { "<Esc>", M.help_close, "Close key help" },
      { "?", M.help_close, "Close key help" },
    },
  })
  popup.set_lines(key_help, actions.help_lines(state.page, state.capabilities))
end

function M.help_close()
  popup.close(key_help)
  if state.page == "stats" then
    M.focus_stats()
  else
    M.focus_cards()
  end
end

function M.edit_card()
  local card = selected_card()
  if not card then
    return
  end
  if call_handler("on_open_source", card) then
    return
  end
  M.close()
  vim.cmd.edit(util.fname(card.path))
  vim.api.nvim_win_set_cursor(0, { card.start_line, 0 })
end

function M.search()
  vim.ui.input({ prompt = "Search cards: ", default = state.query }, function(input)
    if input == nil or not M.is_open() then
      return
    end
    state.query = util.trim(input)
    state.card_sel, state.selected_card_key = 1, nil
    M.show("cards")
  end)
end

local FILTERS = {
  { value = "all", label = "All cards" },
  { value = "invalid", label = "Invalid blocks" },
  { value = "ready", label = "Ready now" },
  { value = "overdue", label = "Overdue" },
  { value = "due", label = "Due" },
  { value = "new", label = "New" },
  { value = "learning", label = "Learning" },
  { value = "relearning", label = "Relearning" },
  { value = "review", label = "Review" },
  { value = "scheduled", label = "Scheduled" },
  { value = "suspended", label = "Suspended" },
  { value = "buried", label = "Buried" },
}

function M.choose_filter()
  local now = os.time()
  local choices = {}
  for _, filter in ipairs(FILTERS) do
    local count = filter.value == "invalid" and #state.invalid_cards or 0
    if filter.value ~= "invalid" then
      for _, card in ipairs(state.all_cards) do
        if matches_filter(card, now, filter.value) then
          count = count + 1
        end
      end
      if filter.value == "all" then
        count = count + #state.invalid_cards
      end
    end
    table.insert(choices, { value = filter.value, label = filter.label, count = count })
  end
  vim.ui.select(choices, {
    prompt = "Card state filter",
    format_item = function(item)
      return string.format("%s %-14s %d", item.value == state.filter and "●" or " ", item.label, item.count)
    end,
  }, function(choice)
    if not choice or not M.is_open() then
      return
    end
    state.filter, state.card_sel, state.selected_card_key = choice.value, 1, nil
    M.show("cards")
  end)
end

function M.cycle_sort()
  local index = 1
  for position, value in ipairs(SORTS) do
    if value == state.sort then
      index = position
      break
    end
  end
  state.sort = SORTS[(index % #SORTS) + 1]
  render()
end

function M.clear_browser()
  state.query, state.filter, state.card_sel, state.selected_card_key = "", "all", 1, nil
  render()
end

function M.toggle_suspend()
  local card = selected_card()
  if selected_card_is_invalid() then
    util.notify("Repair this invalid block before changing its scheduling state", vim.log.levels.WARN)
    return
  end
  if card and call_handler("on_toggle_suspend", card) then
    M.refresh()
  end
end

function M.bury()
  local card = selected_card()
  if selected_card_is_invalid() then
    util.notify("Repair this invalid block before changing its scheduling state", vim.log.levels.WARN)
    return
  end
  if card and call_handler("on_bury", card) then
    M.refresh()
  end
end

local function delete_source(entry)
  if entry.invalid then
    return invalid_source(entry)
  end
  local card = entry.card or {}
  local source = card_source(card)
  if card.start_line then
    source = source .. ":" .. tostring(card.start_line)
  end
  return source
end

function M.delete_selected()
  if state.page ~= "cards" or not state.capabilities.delete then
    return false
  end

  -- Capture the physical browser entry before opening an asynchronous picker.
  -- In particular, duplicate-ID invalid cards must not be resolved by ID after
  -- the user confirms because the selection may have moved in the meantime.
  local entry = selected_card_entry()
  if not entry or not entry.card then
    util.notify("No card selected", vim.log.levels.WARN)
    return false
  end

  local card = entry.card
  local source = delete_source(entry)
  local front = card_front(card)
  if front == "" then
    front = "@flashcard " .. tostring(card.kind or "unknown")
  end
  local prompt = string.format("Delete “%s” from %s?", truncate(front, 42), source)
  local context = {
    invalid = entry.invalid == true,
    messages = vim.deepcopy(entry.messages or {}),
    source = source,
  }

  vim.ui.select({ "Cancel", "Delete card" }, { prompt = prompt }, function(choice)
    if choice ~= "Delete card" or not M.is_open() then
      return
    end
    local handled, deleted = call_handler("on_delete_card", card, context)
    if handled and deleted == true and M.is_open() then
      M.refresh()
    end
  end)
  return true
end

function M.refresh()
  if not provider or not M.is_open() then
    return
  end
  local cards, errors, invalid = provider()
  cards = cards or {}
  if errors and #errors > 0 then
    util.notify(table.concat(errors, "\n"), vim.log.levels.WARN)
  end
  state.all_cards = cards
  state.invalid_cards = invalid or {}
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

function M.current_view()
  return state.page
end

function M.show(view)
  view = lower(view)
  if view ~= "overview" and view ~= "cards" and view ~= "stats" then
    view = "overview"
  end
  state.page = view
  render()
  if view == "stats" then
    M.focus_stats()
  else
    M.focus_cards()
  end
  return view
end

local function cycle_page(delta)
  local index = 1
  for page_index, page in ipairs(PAGES) do
    if page == state.page then
      index = page_index
      break
    end
  end
  M.show(PAGES[((index - 1 + delta) % #PAGES) + 1])
end

local function dispatch(action)
  if action == "close" then
    M.close()
  elseif action == "escape" then
    if state.page == "cards" and (state.query ~= "" or state.filter ~= "all") then
      M.clear_browser()
    else
      M.close()
    end
  elseif action == "context_help" then
    M.context_help()
  elseif action == "plugin_help" then
    if not call_handler("on_help") then
      M.context_help()
    end
  elseif action == "overview" or action == "cards" or action == "stats" then
    M.show(action)
  elseif action == "next_page" then
    cycle_page(1)
  elseif action == "previous_page" then
    cycle_page(-1)
  elseif action == "next" then
    M.move(1)
  elseif action == "previous" then
    M.move(-1)
  elseif action == "scroll_down" then
    M.scroll_page(1)
  elseif action == "scroll_up" then
    M.scroll_page(-1)
  elseif action == "scroll_top" then
    M.scroll_edge("top")
  elseif action == "scroll_bottom" then
    M.scroll_edge("bottom")
  elseif action == "activate" then
    if state.page == "overview" then
      M.review_due()
    elseif state.page == "cards" then
      M.review_selected()
    else
      M.show("cards")
    end
  elseif action == "review" then
    if state.page == "overview" then
      M.review_group()
    elseif state.page == "cards" then
      M.review_selected()
    else
      M.review_due()
    end
  elseif action == "review_due" then
    M.review_due()
  elseif action == "review_all" then
    M.review_all()
  elseif action == "add" then
    call_handler("on_add")
  elseif action == "search" then
    M.search()
  elseif action == "filter" then
    M.choose_filter()
  elseif action == "sort" then
    M.cycle_sort()
  elseif action == "clear" then
    M.clear_browser()
  elseif action == "toggle_suspend" then
    M.toggle_suspend()
  elseif action == "bury" then
    M.bury()
  elseif action == "delete_card" then
    M.delete_selected()
  elseif action == "peek" then
    M.peek()
  elseif action == "open_source" then
    M.edit_card()
  elseif action == "check" then
    call_handler("on_check")
  elseif action == "migrate" then
    if call_handler("on_migrate") then
      M.refresh()
    end
  elseif action == "refresh" then
    M.refresh()
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

local function configure_window(win)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].cursorline = true
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].wrap = false
  vim.wo[win].spell = false
end

local function panel_width()
  return math.max(38, math.min(54, math.floor(vim.o.columns * 0.36)))
end

local function apply_layout()
  if not M.is_open() or not (state.stats.win and vim.api.nvim_win_is_valid(state.stats.win)) then
    return
  end
  local desired = vim.o.columns < 105 and "stacked" or "columns"
  local function rearrange()
    local current = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(state.stats.win)
    if desired == "stacked" then
      vim.wo[state.stats.win].winfixwidth = false
      vim.cmd("wincmd J")
      vim.api.nvim_win_set_height(state.stats.win, math.max(10, math.floor((vim.o.lines - 4) * 0.38)))
    else
      vim.cmd("wincmd L")
      vim.api.nvim_win_set_width(state.stats.win, panel_width())
      vim.wo[state.stats.win].winfixwidth = true
    end
    if vim.api.nvim_win_is_valid(current) then
      vim.api.nvim_set_current_win(current)
    end
  end
  if vim.api.nvim_get_current_tabpage() == state.tab then
    rearrange()
  elseif type(vim.api.nvim_tabpage_call) == "function" and state.tab and vim.api.nvim_tabpage_is_valid(state.tab) then
    vim.api.nvim_tabpage_call(state.tab, rearrange)
  end
  state.layout = desired
end

local function install_maps(buf)
  for _, binding in ipairs(actions.available_bindings("hub", state.capabilities)) do
    local action_name = binding.action
    vim.keymap.set("n", binding.key, function()
      dispatch(action_name)
    end, {
      buffer = buf,
      silent = true,
      nowait = true,
      desc = binding.description,
    })
  end
end

function M.close()
  popup.close(peek)
  popup.close(key_help)
  local hub_tab = state.tab
  for _, pane in ipairs({ state.cards, state.stats }) do
    if pane.buf and vim.api.nvim_buf_is_valid(pane.buf) then
      pcall(vim.api.nvim_buf_delete, pane.buf, { force = true })
    end
    pane.buf, pane.win = nil, nil
  end
  if hub_tab and vim.api.nvim_tabpage_is_valid(hub_tab) and #vim.api.nvim_list_tabpages() > 1 then
    pcall(vim.cmd, "tabclose " .. vim.api.nvim_tabpage_get_number(hub_tab))
  end
  state.tab, state.layout = nil, nil
end

function M.open(collect, opts)
  opts = opts or {}
  provider = collect or provider
  if not provider then
    util.notify("Flashcard collection provider is not configured", vim.log.levels.ERROR)
    return
  end
  local cards, errors, invalid = provider()
  cards = cards or {}
  if errors and #errors > 0 then
    util.notify(table.concat(errors, "\n"), vim.log.levels.WARN)
  end
  state.all_cards = cards
  state.invalid_cards = invalid or {}
  state.groups = group_cards(cards, os.time())
  state.sel = opts.sel or state.sel or 1
  state.capabilities = {
    add = type(handlers.on_add) == "function",
    help = type(handlers.on_help) == "function",
    check = type(handlers.on_check) == "function",
    migrate = type(handlers.on_migrate) == "function",
    suspend = type(handlers.on_toggle_suspend) == "function",
    bury = type(handlers.on_bury) == "function",
    delete = type(handlers.on_delete_card) == "function",
  }
  if not M.is_open() then
    vim.cmd("tabnew")
    state.tab = vim.api.nvim_get_current_tabpage()
    state.cards.buf = new_scratch()
    state.cards.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.cards.win, state.cards.buf)
    configure_window(state.cards.win)
    vim.cmd("belowright vsplit")
    state.stats.buf = new_scratch()
    state.stats.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.stats.win, state.stats.buf)
    configure_window(state.stats.win)
    install_maps(state.cards.buf)
    install_maps(state.stats.buf)
    apply_layout()
  end
  M.show(opts.view or state.page or "overview")
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
        apply_layout()
        render()
      end
    end,
  })
end

return M
