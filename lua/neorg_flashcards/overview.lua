-- The shared workspace shell and functional card browser.

local actions = require("neorg_flashcards.ui.actions")
local card_insights = require("neorg_flashcards.card_insights")
local highlights = require("neorg_flashcards.highlights")
local popup = require("neorg_flashcards.popup")
local review = require("neorg_flashcards.review")
local schedule = require("neorg_flashcards.schedule")
local schema = require("neorg_flashcards.schema")
local stats = require("neorg_flashcards.stats")
local util = require("neorg_flashcards.util")
local window = require("neorg_flashcards.ui.window")

local desk = require("neorg_flashcards.ui.desk")
local metadata = require("neorg_flashcards.metadata")
local chapters = require("neorg_flashcards.chapters")
local calendar = require("neorg_flashcards.calendar")

local M = {}
local apply_layout

local GLYPH = "●"
local PAGES = { "desk", "overview", "stats" }
local SORTS = { "due", "front", "state", "source" }
local filter_label

local HIGHLIGHTS = vim.tbl_extend("force", {}, highlights.groups.hub, highlights.groups.rating)

local config = {}
local handlers = {}
local provider = nil
local ns = vim.api.nvim_create_namespace("neorg_flashcards_hub")

local state = {
  generation = 0,
  tab = nil,
  main = { buf = nil, win = nil },
  side = { buf = nil, win = nil },
  page = "desk",
  layout = nil,
  all_cards = {},
  invalid_cards = {},
  groups = {},
  history_entries = {},
  history_errors = {},
  insights = { by_card = {}, by_id = {}, attention = {} },
  entries = {},
  sel = 1,
  card_entries = {},
  card_sel = 1,
  browser_level = "collections",
  chapter_id = nil,
  desk_grouping = "chapters",
  selected_card_key = nil,
  query = "",
  filter = "all",
  sort = "due",
  capabilities = {},
  closing = false,
  metadata = metadata.defaults(),
  desk_query = "",
  columns = 1,
  date = os.time(),
  day_filter = nil,
}

local peek = { buf = nil, win = nil }
local key_help = { buf = nil, win = nil }

local function hub_token()
  return {
    generation = state.generation,
    tab = state.tab,
    main_buf = state.main.buf,
  }
end

local function same_hub(token)
  return token ~= nil
    and token.generation == state.generation
    and token.tab == state.tab
    and token.main_buf == state.main.buf
    and M.is_open()
end

local function lower(value)
  return util.trim(value):lower()
end

local function show_shortcuts()
  return type(config.ui) ~= "table" or config.ui.show_shortcuts ~= false
end

local function collection_label()
  return state.metadata.label or (util.trim(config.label) ~= "" and util.trim(config.label) or (config.id or "Deck"))
end

local function card_state(card, now)
  return schedule.card_state(card, now, config.scheduling)
end

local function is_available(card, now)
  return card_state(card, now).availability == "active"
end

local function is_ready(card, now)
  local status = card_state(card, now)
  return status.availability == "active" and (status.timing == "due" or status.timing == "overdue")
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
  return util.path_label(card.path, config.path)
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
  if entry.kind then
    return entry.kind .. ":" .. tostring(entry.id or "all")
  end
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
  state.metadata, state.metadata_error = metadata.load(config)
  return metadata.groups(cards, state.metadata, config, now)
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
    local status = card_state(card, now)
    result[status.lifecycle] = (result[status.lifecycle] or 0) + 1
    if status.availability ~= "active" then
      result[status.availability] = (result[status.availability] or 0) + 1
    else
      if status.timing == "due" then
        result.due = result.due + 1
      elseif status.timing == "overdue" then
        result.overdue = result.overdue + 1
      elseif status.timing == "scheduled" then
        result.scheduled = result.scheduled + 1
      end
      if status.timing == "due" or status.timing == "overdue" then
        result.ready = result.ready + 1
        if status.lifecycle == "new" then
          result.ready_new = result.ready_new + 1
        end
      end
    end
  end
  return result
end

local function refresh_history_insights()
  local entries, errors = stats.read_history()
  state.history_entries = entries or {}
  state.history_errors = errors or {}
  state.progress_entries, state.progress_errors, state.pending_events = stats.read_progress()
  state.insights = card_insights.build(config, state.all_cards, state.history_entries)
end

local function status_label(status)
  if status.availability == "suspended" then
    return "SUSPENDED", HIGHLIGHTS.suspended
  elseif status.availability == "buried" then
    return "BURIED", HIGHLIGHTS.buried
  end
  local labels = { overdue = "OVERDUE", due = "DUE", scheduled = "SCHEDULED" }
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

local function selected_overview_entry()
  return state.entries[state.sel]
end

local function selected_card_entry()
  return state.card_entries[state.card_sel]
end

local function selected_card_is_invalid()
  return state.page == "overview" and selected_card_entry() and selected_card_entry().invalid == true
end

local function selected_card_is_unclosed()
  local entry = state.page == "overview" and selected_card_entry() or nil
  return entry and entry.card and entry.card.closed == false or false
end

local function selected_card()
  if state.page == "overview" then
    local entry = selected_card_entry()
    return entry and entry.card
  elseif state.page == "stats" then
    return nil
  end
  local entry = selected_overview_entry()
  return entry and entry.card
end

local function current_action_state()
  local action_state = vim.deepcopy(state.capabilities)
  local card = selected_card()
  local invalid = selected_card_is_invalid()
  if state.page == "overview" then
    local availability = card and not invalid and card_state(card, os.time()).availability or nil
    action_state.review_selected = card ~= nil and not invalid and availability == "active"
  end
  if state.page == "overview" and not card then
    action_state.suspend, action_state.bury = false, false
    local entry = selected_card_entry()
    action_state.delete = action_state.manage
      and entry ~= nil
      and (entry.kind == "deck" or (entry.kind == "chapter" and entry.id ~= nil and entry.id ~= ""))
    action_state.review_selected = entry and entry.group and #entry.group.cards > 0 or false
  elseif invalid then
    action_state.suspend, action_state.bury = false, false
  end
  if selected_card_is_unclosed() then
    action_state.delete = false
  end
  if card and not invalid then
    action_state.selected_availability = card_state(card, os.time()).availability
  end
  action_state.move_card = card ~= nil and not invalid and action_state.manage
  action_state.selection_kind = state.page == "overview" and selected_card_entry() and selected_card_entry().kind
    or "card"
  return action_state
end

local function main_width()
  if state.main.win and vim.api.nvim_win_is_valid(state.main.win) then
    return vim.api.nvim_win_get_width(state.main.win)
  end
  return math.max(40, math.floor(vim.o.columns * 0.64))
end

local function side_width()
  if state.side.win and vim.api.nvim_win_is_valid(state.side.win) then
    return vim.api.nvim_win_get_width(state.side.win)
  end
  return 44
end

local function searchable_text(card, now)
  local status = card_state(card, now)
  local card_schema = schema.for_kind(config, card.kind) or {}
  return table
    .concat({
      card_front(card),
      card_answer(card),
      card.kind or "",
      card_schema.label or "",
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
  if state.chapter_id ~= nil and chapters.id(state.metadata, card) ~= state.chapter_id then
    return false
  end
  if filter == "day" then
    return state.day_filter and state.day_filter[card_key(card)] == true
  elseif filter:sub(1, 4) == "tag:" then
    local tag = filter:sub(5)
    return tag == "" and #metadata.tags(card) == 0 or schema.card_has_tag(card, tag)
  elseif filter == "all" then
    return true
  elseif filter == "clinic" then
    local insight = state.insights.by_card[card]
    return insight and insight.needs_attention or false
  elseif filter:sub(1, 5) == "type:" then
    return card.kind == filter:sub(6)
  end
  local status = card_state(card, now)
  if filter == "ready" then
    return status.availability == "active" and (status.timing == "due" or status.timing == "overdue")
  elseif filter == "due" then
    return status.availability == "active" and (status.timing == "due" or status.timing == "overdue")
  elseif filter == "scheduled" then
    return status.availability == "active" and status.timing == "scheduled"
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
      if
        (state.chapter_id == nil or chapters.id(state.metadata, descriptor.card) == state.chapter_id)
        and (query == "" or invalid_searchable_text(descriptor):find(query, 1, true))
      then
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
    local left_status, right_status = card_state(left_card, now), card_state(right_card, now)
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

local function chapter_label()
  if state.chapter_id == nil then
    return "All cards"
  end
  local chapter = state.metadata.chapters[state.chapter_id]
  return chapter and chapter.label or "Unfiled"
end

local function build_library_browser()
  local entries, lines, spans = {}, {}, {}
  local collections_view = state.browser_level == "collections"
  local title = collections_view and ("Overview · " .. collection_label() .. " / Collections")
    or ("Collections / " .. collection_label() .. " / Chapters")
  add_line(lines, spans, " " .. title, HIGHLIGHTS.heading)
  add_line(lines, spans, " Enter/l open   h back   a add   e rename   D remove   m manage", HIGHLIGHTS.muted)
  add_line(lines, spans, "")
  if collections_view then
    for _, deck_ in
      ipairs(
        type(handlers.on_decks) == "function" and handlers.on_decks()
          or { { id = config.id, label = collection_label() } }
      )
    do
      table.insert(
        entries,
        { kind = "deck", id = deck_.id, label = deck_.label, path = deck_.path, owned = deck_.owned }
      )
    end
  else
    table.insert(entries, {
      kind = "chapter",
      label = "All cards",
      group = {
        cards = state.all_cards,
        due = count_states(state.all_cards, os.time()).ready,
      },
    })
    for _, group in ipairs(chapters.groups(state.all_cards, state.metadata, config, os.time())) do
      table.insert(entries, { kind = "chapter", id = group.name, label = group.label, group = group })
    end
  end
  if collections_view and not state.selected_card_key then
    state.selected_card_key = "deck:" .. config.id
  end
  restore_card_selection(entries)
  local width = main_width()
  add_line(
    lines,
    spans,
    "   " .. pad(collections_view and "COLLECTION" or "CHAPTER", math.max(12, width - 32)) .. "  CARDS   READY",
    HIGHLIGHTS.table_header
  )
  add_line(lines, spans, " " .. string.rep(config.ui.ascii and "-" or "─", math.max(1, width - 2)), HIGHLIGHTS.muted)
  for index, entry in ipairs(entries) do
    local count, ready = "", ""
    if entry.group then
      count, ready = tostring(#entry.group.cards), tostring(entry.group.due)
    elseif entry.id == config.id then
      count, ready = tostring(#state.all_cards), tostring(count_states(state.all_cards, os.time()).ready)
    end
    local text = (index == state.card_sel and " > " or "   ")
      .. pad(entry.label, math.max(12, width - 32))
      .. "  "
      .. pad(count, 7)
      .. " "
      .. ready
    entry.line =
      add_line(lines, spans, text, index == state.card_sel and highlights.groups.desk.selected or HIGHLIGHTS.title)
  end
  if state.metadata_error then
    add_line(lines, spans, " Metadata: " .. state.metadata_error, HIGHLIGHTS.invalid)
  end
  return lines, spans, entries
end

local function build_library_detail(entry)
  local lines, spans = {}, {}
  if not entry then
    return { " No selection" }, spans
  end
  add_line(lines, spans, " " .. entry.label, HIGHLIGHTS.heading)
  add_line(lines, spans, "")
  if entry.kind == "deck" then
    add_line(lines, spans, " Collection", HIGHLIGHTS.title)
    add_line(lines, spans, " " .. (entry.path or config.path), HIGHLIGHTS.muted)
    add_line(lines, spans, "")
    add_line(lines, spans, " Enter  Browse chapters")
    add_line(lines, spans, " a      New collection")
    add_line(lines, spans, " e      Rename display label")
    add_line(lines, spans, " m      Collection settings")
    add_line(lines, spans, " D      Detach collection")
    if entry.owned then
      add_line(lines, spans, "")
      add_line(lines, spans, " Configured collection: edit its path and card types in setup().", HIGHLIGHTS.muted)
    end
  else
    local counts = count_states(entry.group.cards, os.time())
    add_line(lines, spans, string.format(" %d cards   %d ready", counts.total, counts.ready), HIGHLIGHTS.title)
    add_line(
      lines,
      spans,
      string.format(" %d scheduled   %d suspended", counts.scheduled, counts.suspended),
      HIGHLIGHTS.muted
    )
    add_line(lines, spans, "")
    add_line(lines, spans, " Enter  Browse cards")
    add_line(lines, spans, " r      Study this chapter")
    add_line(lines, spans, " a      Add card here")
    add_line(lines, spans, " n      New chapter")
    if entry.id and entry.id ~= "" then
      add_line(lines, spans, " e      Rename chapter")
      add_line(lines, spans, " D      Remove chapter")
    end
    add_line(lines, spans, " m      Manage / chapter from tag")
    if entry.id == "" then
      add_line(lines, spans, "")
      add_line(lines, spans, " Cards without a chapter appear here. Use M on a card to move it.", HIGHLIGHTS.muted)
    end
  end
  return lines, spans
end

local function build_cards_browser()
  local now = os.time()
  local browser_entries = filtered_card_entries()
  restore_card_selection(browser_entries)
  local lines, spans, entries = {}, {}, {}
  local width = main_width()
  local total_blocks = #state.all_cards + #state.invalid_cards
  local page_title = state.filter == "clinic" and " Needs attention / Card clinic" or " Overview"
  add_line(lines, spans, page_title .. " · " .. collection_label() .. " / " .. chapter_label(), HIGHLIGHTS.heading)
  local scope = string.format(
    " %d shown of %d blocks · %d reviewable · %d invalid · filter: %s · sort: %s",
    #browser_entries,
    total_blocks,
    #state.all_cards,
    #state.invalid_cards,
    filter_label(state.filter),
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
    add_line(
      lines,
      spans,
      state.filter == "clinic" and "  Nothing needs attention" or "  No cards match this view",
      HIGHLIGHTS.heading
    )
    add_line(
      lines,
      spans,
      state.filter == "clinic" and "  Recent reviews look steady. Press X or Esc to see every card."
        or "  Press X or Esc to clear the search and filter.",
      HIGHLIGHTS.muted
    )
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
      local status = card_state(card, now)
      local status_name
      status_name, badge_hl = status_label(status)
      label = "[" .. status_name .. "]"
      due = util.trim(card.values.due)
      answer = card_answer(card)
      if due == "" and (status.timing == "due" or status.timing == "overdue") then
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

local function short_interval(seconds)
  seconds = tonumber(seconds)
  if not seconds then
    return "—"
  elseif seconds < 3600 then
    return string.format("%dm", math.max(1, math.floor(seconds / 60 + 0.5)))
  elseif seconds < 86400 then
    return string.format("%dh", math.max(1, math.floor(seconds / 3600 + 0.5)))
  end
  return string.format("%dd", math.max(1, math.floor(seconds / 86400 + 0.5)))
end

local function append_recall_trail(lines, spans, insight)
  add_line(lines, spans, "")
  add_line(lines, spans, " Recall trail · newest on the right", HIGHLIGHTS.title)
  local trail = card_insights.recall_trail(insight, side_width() < 44 and 4 or 6, config.scheduling)
  if #trail == 0 then
    add_line(lines, spans, "  No reviews yet", HIGHLIGHTS.muted)
    return
  end

  local rating_line = "  "
  local rating_positions = {}
  local intervals = {}
  for index, step in ipairs(trail) do
    if index > 1 then
      rating_line = rating_line .. " ─── "
    end
    local start_col = #rating_line
    rating_line = rating_line .. tostring(step.rating)
    table.insert(rating_positions, { start_col = start_col, rating = step.rating })
    table.insert(intervals, short_interval(step.interval_seconds))
  end
  add_line(lines, spans, rating_line)
  local rating_line_number = #lines
  local rating_highlights = {
    [1] = HIGHLIGHTS.again,
    [2] = HIGHLIGHTS.hard,
    [3] = HIGHLIGHTS.good,
  }
  for _, position in ipairs(rating_positions) do
    add_span(
      spans,
      rating_line_number,
      position.start_col,
      position.start_col + 1,
      rating_highlights[position.rating] or HIGHLIGHTS.muted
    )
  end
  add_line(lines, spans, "  " .. table.concat(intervals, "     "), HIGHLIGHTS.muted)
end

local function build_card_detail()
  local entry = state.page == "overview" and selected_card_entry() or nil
  local lines, spans = {}, {}
  add_line(lines, spans, " Card details", HIGHLIGHTS.heading)
  add_line(lines, spans, "")
  if entry and entry.kind then
    return build_library_detail(entry)
  end
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
    local invalid_schema = schema.for_kind(config, card.kind)
    add_line(
      lines,
      spans,
      "  Card type: " .. (invalid_schema and invalid_schema.label or tostring(card.kind or "unknown")),
      HIGHLIGHTS.muted
    )
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
    if selected_card_is_unclosed() then
      add_line(lines, spans, "  Add the missing @end before deleting this block.", HIGHLIGHTS.muted)
    elseif state.capabilities.delete then
      add_line(lines, spans, "  Press D to delete this exact invalid block after confirmation.", HIGHLIGHTS.muted)
      add_line(lines, spans, "  Unloaded sources keep a recoverable .flashcards-backup copy.", HIGHLIGHTS.muted)
    end
    return lines, spans
  end
  local status = card_state(card, os.time())
  local card_schema = schema.for_kind(config, card.kind) or {}
  local insight = state.insights.by_card[card] or { reviews = {}, reasons = {} }
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
  add_line(lines, spans, "  Card type    " .. (card_schema.label or card.kind), HIGHLIGHTS.muted)
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
  if #insight.reasons > 0 then
    add_line(lines, spans, "")
    add_line(lines, spans, " Why it is here", HIGHLIGHTS.title)
    for _, reason in ipairs(insight.reasons) do
      add_line(
        lines,
        spans,
        "  " .. GLYPH .. " " .. truncate(reason.message, math.max(20, side_width() - 6)),
        HIGHLIGHTS.overdue
      )
    end
  end
  append_recall_trail(lines, spans, insight)
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
  if state.capabilities.suspend or state.capabilities.bury or state.capabilities.delete then
    add_line(lines, spans, "")
    add_line(lines, spans, " Actions", HIGHLIGHTS.title)
    if state.capabilities.suspend then
      local suspend_label = status.availability == "suspended" and "resume this card" or "suspend this card"
      add_line(lines, spans, "  x  " .. suspend_label, HIGHLIGHTS.muted)
    end
    if state.capabilities.bury then
      local bury_label = status.availability == "buried" and "unbury this card" or "bury this card until tomorrow"
      add_line(lines, spans, "  b  " .. bury_label, HIGHLIGHTS.muted)
    end
    if state.capabilities.delete then
      add_line(lines, spans, "  D  delete this card after confirmation", HIGHLIGHTS.muted)
      add_line(lines, spans, "     unloaded source: keep a recoverable .flashcards-backup copy", HIGHLIGHTS.muted)
    end
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
  local attention = state.insights.attention or {}
  add_line(lines, spans, "")
  add_line(lines, spans, " Needs attention", HIGHLIGHTS.title)
  if #attention == 0 then
    add_line(
      lines,
      spans,
      counts.total == 0 and "  Statistics appear after you add cards." or "  No cards need attention right now.",
      HIGHLIGHTS.muted
    )
  else
    for index = 1, math.min(5, #attention) do
      local insight = attention[index]
      local reason = insight.reasons[1] and insight.reasons[1].message or "recent reviews"
      add_line(
        lines,
        spans,
        "  " .. GLYPH .. " " .. truncate(card_front(insight.card) .. " · " .. reason, math.max(20, main_width() - 8)),
        HIGHLIGHTS.overdue
      )
    end
    add_line(lines, spans, "  Open Cards and choose f → Card clinic to work through them.", HIGHLIGHTS.muted)
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
  local log_entries, log_errors = state.history_entries, state.history_errors
  local width = side_width()
  local weeks = math.max(4, math.min(20, math.floor((width - 8) / 2)))
  local lines, spans = {}, {}
  add_line(lines, spans, " Analytics · " .. collection_label(), HIGHLIGHTS.heading)
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
  local chunks = { "%#" .. HIGHLIGHTS.heading .. "#  " .. statusline_escape(collection_label()) .. "  " }
  for index, page in ipairs(PAGES) do
    local label = page:sub(1, 1):upper() .. page:sub(2)
    local hl = page == state.page and HIGHLIGHTS.tab_active or HIGHLIGHTS.tab_inactive
    table.insert(chunks, string.format("%%#%s# %s%s ", hl, review.is_active() and "" or (index .. " "), label))
    table.insert(chunks, "%#" .. HIGHLIGHTS.muted .. "# ")
  end
  return table.concat(chunks)
end

local function apply_chrome()
  local nav = tab_bar()
  local action_state = current_action_state()
  for _, pane in ipairs({ state.main, state.side }) do
    if pane.win and vim.api.nvim_win_is_valid(pane.win) then
      window.configure(pane.win)
      local footer = " "
      if show_shortcuts() then
        footer = actions.footer(state.page, vim.api.nvim_win_get_width(pane.win), action_state)
      end
      -- Keep one shortcut ribbon. Window statuslines may be replaced by the
      -- user's global statusline, so they are decorative separators only.
      if pane == state.side and state.page == "desk" then
        vim.wo[pane.win].winbar = ""
      elseif pane == state.side and show_shortcuts() then
        vim.wo[pane.win].winbar = "%#" .. HIGHLIGHTS.footer .. "#" .. statusline_escape(footer)
      else
        vim.wo[pane.win].winbar = nav
      end
      vim.wo[pane.win].statusline = "%#Normal# "
      -- Calendar details include explanations and source labels. Keep them
      -- readable in the narrow sidebar without changing the canvas layout.
      vim.wo[pane.win].wrap = pane == state.side and state.page == "stats"
      vim.wo[pane.win].linebreak = true
      vim.wo[pane.win].breakindent = true
    end
  end
end

local function day_detail()
  local key = calendar.day(state.date)
  local today = calendar.day(os.time())
  local days = calendar.activity(state.progress_entries)
  local day = days[key]
  local lines = { " " .. os.date("%A %d %B", state.date), "" }
  if state.pending_events > 0 then
    table.insert(lines, "  Provisional: " .. state.pending_events .. " events awaiting history delivery")
  end
  if key <= today then
    local unique, answers = day and day.unique or 0, day and day.answers or 0
    table.insert(
      lines,
      string.format(
        "  %d unique card%s / %d answer%s",
        unique,
        unique == 1 and "" or "s",
        answers,
        answers == 1 and "" or "s"
      )
    )
    if day then
      table.insert(lines, string.format("  Again %d / Hard %d / Good %d", unpack(day.ratings)))
      table.insert(
        lines,
        day.timed > 0
            and string.format(
              "  %.1f min recorded answer time (%d/%d timed)",
              day.duration_ms / 60000,
              day.timed,
              day.answers
            )
          or "  Answer time unavailable"
      )
      table.insert(lines, string.format("  Hints used on %d answer%s", day.hints, day.hints == 1 and "" or "s"))
      local goal = state.metadata.goals[key]
      if goal and goal > 0 then
        table.insert(
          lines,
          string.format("  Daily goal: %d / %d%s", day.unique, goal, day.unique >= goal and "  [REACHED]" or "")
        )
      end
      table.insert(lines, "")
      local by_id = {}
      for _, card in ipairs(state.all_cards) do
        by_id[card_key(card)] = card
      end
      local ids = vim.tbl_keys(day.ids)
      table.sort(ids)
      for index = 1, math.min(5, #ids) do
        local card = by_id[ids[index]]
        local label = ids[index] .. " (source unavailable)"
        if card then
          local _, front = schema.front(config, card)
          label = front:gsub("\n", " ")
        end
        table.insert(lines, "  " .. label)
      end
      if #ids > 5 then
        table.insert(lines, "  + " .. (#ids - 5) .. " more in Overview")
      end
    end
  end
  if key >= today then
    local scheduled = #calendar.scheduled(state.all_cards, state.date, os.time(), config)
    table.insert(lines, "")
    table.insert(lines, string.format("  %d card%s currently scheduled", scheduled, scheduled == 1 and "" or "s"))
    table.insert(lines, "  Schedule snapshot; future ratings can change it.")
  end
  table.insert(lines, "")
  table.insert(lines, "  Enter: inspect this day's cards in Overview")
  table.insert(lines, "")
  local full, spans = build_stats_insights()
  local more, more_spans = build_full_stats()
  append_section(full, spans, more, more_spans)
  local offset = #lines
  vim.list_extend(lines, full)
  for _, span in ipairs(spans) do
    span.line = span.line + offset
  end
  return lines, spans
end

local function render()
  if not M.is_open() then
    return
  end
  local main_lines, main_spans, side_lines, side_spans
  if state.page == "overview" then
    if state.browser_level == "cards" then
      main_lines, main_spans, state.card_entries = build_cards_browser()
    else
      main_lines, main_spans, state.card_entries = build_library_browser()
    end
    side_lines, side_spans = build_card_detail()
  elseif state.page == "stats" then
    main_lines, main_spans = calendar.render(
      state.progress_entries,
      state.metadata,
      state.date,
      main_width(),
      config.ui.ascii,
      nil,
      vim.api.nvim_win_get_height(state.main.win)
    )
    side_lines, side_spans = day_detail()
  else
    local counts = count_states(state.all_cards, os.time())
    local decks = type(handlers.on_decks) == "function" and handlers.on_decks()
      or { { id = config.id, label = collection_label() } }
    main_lines, main_spans, state.entries, state.columns, state.sel = desk.render({
      width = main_width(),
      height = vim.fn.winheight(state.main.win),
      ascii = config.ui.ascii,
      selected = state.sel,
      decks = decks,
      config = config,
      cards = state.all_cards,
      groups = state.desk_grouping == "tags" and state.groups
        or chapters.groups(state.all_cards, state.metadata, config, os.time()),
      grouping = state.desk_grouping,
      ready = counts.ready,
      label = collection_label(),
      query = state.desk_query,
      history = state.progress_entries,
      pending = state.pending_events,
      metadata = state.metadata,
      error = state.metadata_error,
    })
    side_lines, side_spans =
      {
        review.is_active() and " Review in progress. q returns to the desk." or (show_shortcuts() and actions.footer("desk", main_width(), current_action_state()) or ""),
      }, {}
  end
  set_pane_lines(state.main, main_lines)
  paint(state.main, main_spans)
  set_pane_lines(state.side, side_lines)
  paint(state.side, side_spans)
  apply_chrome()
  local entry = state.page == "overview" and selected_card_entry()
    or (state.page == "desk" and selected_overview_entry())
  if entry and state.main.win and vim.api.nvim_win_is_valid(state.main.win) then
    pcall(vim.api.nvim_win_set_cursor, state.main.win, { entry.line, entry.col and entry.col - 1 or 0 })
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
  if entry and entry.kind == "deck" then
    call_handler("on_select_deck", entry.id)
    state.sel = 1
    for _, item in ipairs(state.entries) do
      if item.kind == "deck" then
        state.sel = state.sel + 1
      end
    end
    render()
    return
  end
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
    util.notify("Caught up: " .. entry.group.label .. ". Use A to review all active cards.", vim.log.levels.WARN)
    return
  end
  local tag = entry.group.name
  review_cards(
    due,
    entry.group.chapter and ("chapter: " .. entry.group.label)
      or (tag == "" and "untagged" or (tag and "tag:" .. tag or "due")),
    nil
  )
end

function M.review_selected()
  local entry = selected_card_entry()
  if state.page == "overview" and entry and entry.group then
    local due = vim.tbl_filter(function(card)
      return is_ready(card, os.time())
    end, entry.group.cards)
    review_cards(due, entry.label, "No due cards in " .. entry.label)
    return
  end
  local card = selected_card()
  if not card then
    util.notify("No card selected", vim.log.levels.WARN)
    return
  end
  if selected_card_is_invalid() then
    util.notify("This block is invalid and cannot be reviewed; press e to repair it", vim.log.levels.WARN)
    return
  end
  local status = card_state(card, os.time())
  if status.availability ~= "active" then
    util.notify("This card is " .. status.availability .. "; make it active before reviewing", vim.log.levels.WARN)
    return
  end
  review_cards({ card }, "card", nil)
end

local function focused_hub_window()
  local current = vim.api.nvim_get_current_win()
  for _, pane in ipairs({ state.main, state.side }) do
    if pane.win and vim.api.nvim_win_is_valid(pane.win) and pane.win == current then
      return pane.win
    end
  end
  if state.page == "stats" and state.side.win and vim.api.nvim_win_is_valid(state.side.win) then
    return state.side.win
  end
  if state.main.win and vim.api.nvim_win_is_valid(state.main.win) then
    return state.main.win
  end
end

local function selection_for_page()
  local list, field
  if state.page == "overview" then
    list, field = state.card_entries, "card_sel"
  elseif state.page == "desk" then
    list, field = state.entries, "sel"
  end
  return list, field
end

local function select_index(list, field, index)
  if not list or not field or #list == 0 then
    return
  end
  state[field] = math.max(1, math.min(#list, index))
  if state.page == "overview" then
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
    if vim.wo[win].wrap then
      vim.cmd.normal({ args = { tostring(math.abs(delta)) .. string.char(delta > 0 and 5 or 25) }, bang = true })
      return
    end
    local line_count = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
    -- winheight() excludes the winbar; the API height includes that row.
    local height = math.max(1, vim.fn.winheight(0))
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
    if vim.wo[win].wrap then
      vim.cmd.normal({ args = { edge == "top" and "ggzt" or "Gzb" }, bang = true })
      return
    end
    local line_count = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
    local height = math.max(1, vim.fn.winheight(0))
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
  -- At the end of a shelf, leave the viewport intact so repeated paging can
  -- reach the progress note below the last selectable item.
  if target_index ~= index then
    select_index(list, field, target_index)
  end
end

function M.move(delta)
  local win = focused_hub_window()
  if not win then
    return
  end
  if state.page == "stats" and win == state.main.win then
    state.date = calendar.shift(state.date, delta * 7)
    render()
    return
  end
  if win == state.side.win then
    move_window_cursor(win, delta)
    return
  end
  local list, field = selection_for_page()
  if not list or #list == 0 then
    return
  end
  if state.page == "desk" then
    local current = list[state[field]]
    local target, distance = state[field], math.huge
    for index, entry in ipairs(list) do
      if current and entry.row == current.row + delta and math.abs(entry.col - current.col) < distance then
        target, distance = index, math.abs(entry.col - current.col)
      end
    end
    select_index(list, field, target)
  else
    select_index(list, field, state[field] + delta)
  end
end

function M.scroll_page(direction)
  local win = focused_hub_window()
  if not win then
    return
  end
  direction = direction < 0 and -1 or 1
  if state.page ~= "stats" and win == state.main.win then
    local selected = state.sel
    move_selection_page(direction, win)
    if state.page ~= "desk" or state.sel ~= selected then
      return
    end
    -- Once the shelf ends, continue into the goal and status notes below it.
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
  if state.page ~= "stats" and win == state.main.win then
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
  local entry = state.page == "overview" and selected_card_entry() or nil
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
    local status = card_state(card, os.time())
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
    M.focus_side()
  else
    M.focus_main()
  end
end

function M.context_help()
  popup.open(key_help, {
    title = " " .. state.page:sub(1, 1):upper() .. state.page:sub(2) .. " keys ",
    footer = actions.help_footer(),
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
  popup.set_lines(key_help, actions.help_lines(state.page, current_action_state()))
end

function M.help_close()
  popup.close(key_help)
  if state.page == "stats" then
    M.focus_side()
  else
    M.focus_main()
  end
end

function M.edit_card()
  local entry = state.page == "overview" and selected_card_entry() or nil
  local card = entry and entry.card or selected_card()
  if not card then
    return
  end
  if
    call_handler("on_edit", card, {
      cards = state.all_cards,
      invalid = entry and entry.invalid == true,
    })
  then
    return
  end
  M.close()
  vim.cmd.edit(util.fname(card.path))
  vim.api.nvim_win_set_cursor(0, { card.start_line, 0 })
end

function M.search()
  local token = hub_token()
  vim.ui.input({ prompt = "Search cards: ", default = state.query }, function(input)
    if input == nil or not same_hub(token) then
      return
    end
    state.browser_level = "cards"
    state.query = util.trim(input)
    state.card_sel, state.selected_card_key = 1, nil
    M.show("overview")
  end)
end

local FILTERS = {
  { value = "all", label = "All cards" },
  { value = "clinic", label = "Needs attention (Card Clinic)" },
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

filter_label = function(value)
  if value == "day" then
    return (calendar.day(state.date) > calendar.day(os.time()) and "Scheduled " or "Reviewed ")
      .. calendar.day(state.date)
      .. (calendar.day(state.date) > calendar.day(os.time()) and " (schedule snapshot)" or "")
  elseif value:sub(1, 4) == "tag:" then
    local tag = value:sub(5)
    local settings = state.metadata.categories[tag] or {}
    return "Category · " .. (settings.label or (tag == "" and "Untagged" or tag))
  end
  if value:sub(1, 5) == "type:" then
    local id = value:sub(6)
    local card_schema = schema.for_kind(config, id)
    return "Type · " .. (card_schema and card_schema.label or id)
  end
  for _, filter in ipairs(FILTERS) do
    if filter.value == value then
      return filter.label
    end
  end
  return value
end

function M.choose_filter()
  local token = hub_token()
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
  local kinds = vim.tbl_keys(config.schemas or {})
  table.sort(kinds)
  for _, kind in ipairs(kinds) do
    local count = 0
    for _, card in ipairs(state.all_cards) do
      if card.kind == kind then
        count = count + 1
      end
    end
    table.insert(choices, { value = "type:" .. kind, label = filter_label("type:" .. kind), count = count })
  end
  vim.ui.select(choices, {
    prompt = "Card view",
    format_item = function(item)
      return string.format("%s %-14s %d", item.value == state.filter and "●" or " ", item.label, item.count)
    end,
  }, function(choice)
    if not choice or not same_hub(token) then
      return
    end
    state.browser_level = "cards"
    state.filter, state.card_sel, state.selected_card_key = choice.value, 1, nil
    M.show("overview")
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
  if state.page ~= "overview" or not state.capabilities.delete then
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
  if selected_card_is_unclosed() then
    util.notify("Add the missing @end before deleting this flashcard", vim.log.levels.WARN)
    return false
  end

  local card = entry.card
  local source = delete_source(entry)
  local front = card_front(card)
  if front == "" then
    front = "@flashcard " .. tostring(card.kind or "unknown")
  end
  local prompt = string.format(
    "Delete “%s” from %s? Unloaded sources keep %s.flashcards-backup.",
    truncate(front, 42),
    source,
    card.path
  )
  local context = {
    invalid = entry.invalid == true,
    messages = vim.deepcopy(entry.messages or {}),
    source = source,
  }
  local token = hub_token()

  vim.ui.select({ "Cancel", "Delete card" }, { prompt = prompt }, function(choice)
    if choice ~= "Delete card" or not same_hub(token) then
      return
    end
    local handled, deleted = call_handler("on_delete_card", card, context)
    if handled and deleted == true and same_hub(token) then
      M.refresh()
    end
  end)
  return true
end

function M.refresh()
  if not provider or not M.is_open() then
    return
  end
  local cards, _, invalid = provider()
  cards = cards or {}
  state.all_cards = cards
  state.invalid_cards = invalid or {}
  state.groups = group_cards(cards, os.time())
  refresh_history_insights()
  render()
end

function M.is_open()
  return state.tab ~= nil
    and vim.api.nvim_tabpage_is_valid(state.tab)
    and state.main.buf ~= nil
    and vim.api.nvim_buf_is_valid(state.main.buf)
    and state.main.win ~= nil
    and vim.api.nvim_win_is_valid(state.main.win)
    and vim.api.nvim_win_get_buf(state.main.win) == state.main.buf
    and state.side.buf ~= nil
    and vim.api.nvim_buf_is_valid(state.side.buf)
    and state.side.win ~= nil
    and vim.api.nvim_win_is_valid(state.side.win)
    and vim.api.nvim_win_get_buf(state.side.win) == state.side.buf
end

function M.is_focused()
  if not M.is_open() or vim.api.nvim_get_current_tabpage() ~= state.tab then
    return false
  end
  local current = vim.api.nvim_get_current_win()
  return current == state.main.win or current == state.side.win
end

function M.focus_main()
  if state.main.win and vim.api.nvim_win_is_valid(state.main.win) then
    vim.api.nvim_set_current_win(state.main.win)
  end
end

function M.focus_side()
  if state.page == "desk" then
    M.focus_main()
    return
  end
  if state.side.win and vim.api.nvim_win_is_valid(state.side.win) then
    vim.api.nvim_set_current_win(state.side.win)
  end
end

function M.focus_other_pane()
  local current = vim.api.nvim_get_current_win()
  if current == state.main.win then
    M.focus_side()
  else
    M.focus_main()
  end
end

function M.review_host()
  if M.is_open() and vim.api.nvim_get_current_tabpage() == state.tab then
    M.show("desk")
    return state.main.win
  end
end

function M.current_view()
  return state.page
end

function M.show(view)
  view = lower(view)
  if view == "cards" then
    view = "overview"
  end
  if view ~= "desk" and view ~= "overview" and view ~= "stats" then
    view = "desk"
  end
  state.page = view
  apply_layout()
  render()
  M.focus_main()
  if view ~= "desk" then
    vim.api.nvim_win_call(state.main.win, function()
      vim.fn.winrestview({ lnum = view == "stats" and 1 or vim.api.nvim_win_get_cursor(0)[1], col = 0, topline = 1 })
    end)
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

local function reset_library(level, chapter)
  state.browser_level, state.chapter_id = level, chapter
  state.card_sel, state.selected_card_key = 1, nil
  state.query, state.filter = "", "all"
  render()
end

local function library_open()
  local entry = selected_card_entry()
  if not entry then
    return
  end
  if entry.kind == "deck" then
    if entry.id ~= config.id then
      call_handler("on_select_deck", entry.id)
    end
    reset_library("chapters")
  elseif entry.kind == "chapter" then
    reset_library("cards", entry.id)
  else
    M.review_selected()
  end
end

local function library_back()
  reset_library(state.browser_level == "cards" and "chapters" or "collections")
end

local function manage_selection(action)
  local entry = state.page == "overview" and selected_card_entry() or nil
  if entry and entry.kind == "deck" and entry.id ~= config.id then
    call_handler("on_select_deck", entry.id)
    reset_library("collections")
  end
  local token = hub_token()
  call_handler("on_manage", function()
    return same_hub(token)
  end, {
    chapter = entry and entry.kind == "chapter" and entry.id or state.chapter_id,
    card = entry and entry.card,
  }, action)
end

local function dispatch(action)
  if review.is_active() then
    util.notify("Finish or close the active review before navigating the workspace", vim.log.levels.WARN)
    return false
  end
  if not actions.is_available("hub", action, state.page, current_action_state()) then
    return false
  end
  if action == "left" or action == "right" then
    local direction = action == "left" and -1 or 1
    if state.page == "stats" then
      state.date = calendar.shift(state.date, direction)
      render()
    elseif state.page == "desk" then
      select_index(state.entries, "sel", state.sel + direction)
    elseif direction < 0 then
      library_back()
    else
      library_open()
    end
  elseif action == "month_previous" or action == "month_next" then
    state.date = calendar.month(state.date, action == "month_previous" and -1 or 1)
    render()
  elseif action == "today" then
    state.date = os.time()
    render()
  elseif action == "manage" then
    manage_selection()
  elseif action == "new_chapter" then
    manage_selection("New chapter")
  elseif action == "move_card" then
    manage_selection("Move card to chapter")
  elseif action == "category" and state.page == "desk" then
    state.desk_grouping = state.desk_grouping == "chapters" and "tags" or "chapters"
    state.sel, state.desk_query = 1, ""
    render()
  elseif action == "category" then
    local token = hub_token()
    local choices = { { label = "All cards", filter = "all" } }
    for _, group in ipairs(state.groups) do
      table.insert(choices, { label = group.label, filter = "tag:" .. group.name })
    end
    vim.ui.select(choices, {
      prompt = "Category",
      format_item = function(item)
        return item.label
      end,
    }, function(choice)
      if choice and same_hub(token) then
        state.browser_level, state.chapter_id = "cards", nil
        state.filter = choice.filter
        state.day_filter = nil
        render()
      end
    end)
  elseif action == "close" then
    M.close()
  elseif action == "escape" then
    if state.page == "desk" and state.desk_query ~= "" then
      state.desk_query = ""
      state.sel = 1
      render()
    elseif state.page == "overview" and (state.query ~= "" or state.filter ~= "all") then
      M.clear_browser()
    elseif state.page == "overview" and state.browser_level ~= "collections" then
      library_back()
    else
      M.close()
    end
  elseif action == "context_help" then
    M.context_help()
  elseif action == "plugin_help" then
    if not call_handler("on_help") then
      M.context_help()
    end
  elseif action == "collection" then
    call_handler("on_collection")
  elseif action == "desk" or action == "overview" or action == "stats" then
    M.show(action)
  elseif action == "next_page" then
    cycle_page(1)
  elseif action == "previous_page" then
    cycle_page(-1)
  elseif action == "next" then
    M.move(1)
  elseif action == "previous" then
    M.move(-1)
  elseif action == "focus_other_pane" then
    M.focus_other_pane()
  elseif action == "scroll_down" then
    M.scroll_page(1)
  elseif action == "scroll_up" then
    M.scroll_page(-1)
  elseif action == "scroll_top" then
    M.scroll_edge("top")
  elseif action == "scroll_bottom" then
    M.scroll_edge("bottom")
  elseif action == "activate" then
    if state.page == "desk" then
      M.review_group()
    elseif state.page == "overview" then
      library_open()
    else
      local day = calendar.activity(state.progress_entries)[calendar.day(state.date)]
      state.day_filter = day and vim.deepcopy(day.ids) or {}
      if calendar.day(state.date) > calendar.day(os.time()) then
        for _, card in ipairs(calendar.scheduled(state.all_cards, state.date, os.time(), config)) do
          state.day_filter[card_key(card)] = true
        end
      end
      state.browser_level, state.chapter_id = "cards", nil
      state.filter = "day"
      state.query = ""
      M.show("overview")
    end
  elseif action == "review" then
    if state.page == "desk" then
      M.review_group()
    elseif state.page == "overview" then
      M.review_selected()
    else
      M.review_due()
    end
  elseif action == "review_due" then
    M.review_due()
  elseif action == "review_all" then
    M.review_all()
  elseif action == "add" then
    local entry = state.page == "desk" and selected_overview_entry() or selected_card_entry()
    if state.page == "overview" and state.browser_level == "collections" then
      manage_selection("New deck")
    else
      local group = entry and entry.group
      local chapter = group and group.chapter and group.name or state.chapter_id
      if state.page == "overview" and entry and entry.kind == "chapter" then
        chapter = entry.id
      end
      local tag = state.page == "desk" and state.desk_grouping == "tags" and group and group.name
        or (state.page == "overview" and state.filter:sub(1, 4) == "tag:" and state.filter:sub(5))
      call_handler("on_add", tag or nil, chapter)
    end
  elseif action == "search" then
    if state.page == "desk" then
      local token = hub_token()
      vim.ui.input({ prompt = "Find " .. state.desk_grouping .. ": ", default = state.desk_query }, function(value)
        if value ~= nil and same_hub(token) then
          state.desk_query = value
          state.sel = 1
          render()
        end
      end)
    else
      M.search()
    end
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
    local entry = selected_card_entry()
    if entry and entry.kind then
      manage_selection(entry.kind == "deck" and "Detach UI-created deck" or "Remove chapter")
    else
      M.delete_selected()
    end
  elseif action == "peek" then
    M.peek()
  elseif action == "edit_card" then
    local entry = state.page == "overview" and selected_card_entry()
    if entry and entry.kind then
      manage_selection(entry.kind == "deck" and "Deck label" or "Rename chapter")
    else
      M.edit_card()
    end
  elseif action == "check" then
    call_handler("on_check")
  elseif action == "refresh" then
    M.refresh()
  end
  return true
end

local function new_scratch()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "neorg_flashcards"
  vim.bo[buf].swapfile = false
  return buf
end

local function configure_window(win)
  window.configure(win)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].cursorline = true
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].wrap = false
  vim.wo[win].spell = false
  vim.wo[win].fillchars = "eob: "
end

local function panel_width()
  return math.max(38, math.min(54, math.floor(vim.o.columns * 0.36)))
end

apply_layout = function()
  if not M.is_open() then
    return
  end
  local desired = state.page == "desk" and "desk" or (vim.o.columns < 105 and "stacked" or "columns")
  local function rearrange()
    local current = vim.api.nvim_get_current_win()
    state.relayout = true
    local floating = vim.api.nvim_win_get_config(state.side.win).relative ~= ""
    if desired == "desk" then
      if not floating then
        vim.bo[state.side.buf].bufhidden = "hide"
        local previous = state.side.win
        state.side.win = nil
        vim.api.nvim_win_close(previous, true)
        state.side.win = vim.api.nvim_open_win(state.side.buf, false, {
          relative = "win",
          win = state.main.win,
          row = math.max(0, vim.api.nvim_win_get_height(state.main.win) - 2),
          col = 0,
          width = vim.api.nvim_win_get_width(state.main.win),
          height = 2,
          style = "minimal",
          focusable = false,
          zindex = 40,
        })
        vim.wo[state.side.win].winbar = ""
        vim.api.nvim_win_set_config(state.side.win, {
          relative = "win",
          win = state.main.win,
          row = math.max(0, vim.api.nvim_win_get_height(state.main.win) - 1),
          col = 0,
          height = 1,
        })
      else
        vim.api.nvim_win_set_config(state.side.win, {
          relative = "win",
          win = state.main.win,
          col = 0,
          row = math.max(0, vim.api.nvim_win_get_height(state.main.win) - 1),
          width = vim.api.nvim_win_get_width(state.main.win),
        })
      end
      vim.wo[state.side.win].winhighlight = "NormalFloat:Normal"
    else
      if floating then
        local previous = state.side.win
        state.side.win = nil
        vim.api.nvim_win_close(previous, true)
        vim.api.nvim_set_current_win(state.main.win)
        vim.cmd("belowright vsplit")
        state.side.win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(state.side.win, state.side.buf)
        configure_window(state.side.win)
      end
      vim.api.nvim_set_current_win(state.side.win)
      vim.wo[state.side.win].winfixheight = false
      if desired == "stacked" then
        vim.wo[state.side.win].winfixwidth = false
        vim.cmd("wincmd J")
        vim.api.nvim_win_set_height(
          state.side.win,
          state.page == "stats" and 5 or math.max(5, math.floor((vim.o.lines - 4) * 0.38))
        )
      else
        vim.cmd("wincmd L")
        vim.api.nvim_win_set_width(state.side.win, panel_width())
        vim.wo[state.side.win].winfixwidth = true
      end
    end
    vim.wo[state.main.win].cursorline = state.page == "overview"
    state.relayout = false
    if vim.api.nvim_win_is_valid(current) then
      vim.api.nvim_set_current_win(current)
    else
      M.focus_main()
    end
  end
  if vim.api.nvim_get_current_tabpage() == state.tab then
    rearrange()
  elseif type(vim.api.nvim_tabpage_call) == "function" then
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
  if state.closing then
    return
  end
  state.closing = true
  state.generation = state.generation + 1
  popup.close(peek)
  popup.close(key_help)
  local hub_tab = state.tab
  -- Neovim 0.10/0.11 can crash when deleting a background tab's last split
  -- while a window-relative float still refers to it. Close the strip first.
  if
    state.side.win
    and vim.api.nvim_win_is_valid(state.side.win)
    and vim.api.nvim_win_get_config(state.side.win).relative ~= ""
  then
    pcall(vim.api.nvim_win_close, state.side.win, true)
    state.side.win = nil
  end
  for _, pane in ipairs({ state.side, state.main }) do
    if pane.buf and vim.api.nvim_buf_is_valid(pane.buf) then
      pcall(vim.api.nvim_buf_delete, pane.buf, { force = true })
    end
    pane.buf, pane.win = nil, nil
  end
  if hub_tab and vim.api.nvim_tabpage_is_valid(hub_tab) and #vim.api.nvim_list_tabpages() > 1 then
    pcall(vim.cmd, "tabclose " .. vim.api.nvim_tabpage_get_number(hub_tab))
  end
  state.tab, state.layout = nil, nil
  state.closing = false
end

function M.open(collect, opts)
  opts = opts or {}
  state.generation = state.generation + 1
  provider = collect or provider
  if not provider then
    util.notify("Flashcard collection provider is not configured", vim.log.levels.ERROR)
    return false
  end
  local cards, errors, invalid = provider()
  cards = cards or {}
  if errors and #errors > 0 then
    util.notify(table.concat(errors, "\n"), vim.log.levels.WARN)
  end
  state.all_cards = cards
  state.invalid_cards = invalid or {}
  state.groups = group_cards(cards, os.time())
  refresh_history_insights()
  if opts.reset_browser then
    state.sel = 1
    state.card_sel = 1
    state.selected_card_key = nil
    state.query = ""
    state.desk_query = ""
    state.desk_grouping = "chapters"
    state.filter = "all"
    state.browser_level = opts.browser_level or state.browser_level or "collections"
    state.chapter_id = nil
    state.sort = "due"
  end
  state.browser_level = opts.browser_level or state.browser_level
  state.sel = opts.sel or state.sel or 1
  if opts.reset_browser or not M.is_open() then
    state.sel = 0 -- Resolve the active deck within the visible shelf at render time.
  end
  state.capabilities = {
    manage = type(handlers.on_manage) == "function",
    move_card = type(handlers.on_manage) == "function",
    add = type(handlers.on_add) == "function",
    collection = type(handlers.on_collection) == "function",
    help = type(handlers.on_help) == "function",
    check = type(handlers.on_check) == "function",
    suspend = type(handlers.on_toggle_suspend) == "function",
    bury = type(handlers.on_bury) == "function",
    delete = type(handlers.on_delete_card) == "function",
    review_selected = true,
  }
  if not M.is_open() and (state.tab or state.main.buf or state.side.buf) then
    M.close()
  end
  if not M.is_open() then
    vim.cmd("tabnew")
    state.tab = vim.api.nvim_get_current_tabpage()
    state.main.buf = new_scratch()
    state.main.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.main.win, state.main.buf)
    configure_window(state.main.win)
    vim.cmd("belowright vsplit")
    state.side.buf = new_scratch()
    state.side.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.side.win, state.side.buf)
    configure_window(state.side.win)
    install_maps(state.main.buf)
    install_maps(state.side.buf)
    apply_layout()
  end
  M.show(opts.view or state.page or "desk")
  return M.is_open()
end

function M.setup(opts, extra_handlers)
  config = opts or {}
  handlers = extra_handlers or {}
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
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
      local closed_win = tonumber(args.match)
      if state.relayout or state.closing or (closed_win ~= state.main.win and closed_win ~= state.side.win) then
        return
      end
      local hub_tab = state.tab
      vim.schedule(function()
        if not state.closing and state.tab == hub_tab then
          M.close()
        end
      end)
    end,
  })
end

return M
