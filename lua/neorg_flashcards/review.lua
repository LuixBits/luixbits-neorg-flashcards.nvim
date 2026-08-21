local popup = require("neorg_flashcards.popup")
local schedule = require("neorg_flashcards.schedule")
local schema = require("neorg_flashcards.schema")
local stats = require("neorg_flashcards.stats")
local store = require("neorg_flashcards.store")
local actions = require("neorg_flashcards.ui.actions")
local util = require("neorg_flashcards.util")

local M = {}

local config = {}

local function monotonic_time()
  local uv = vim.uv or vim.loop
  if uv and uv.hrtime then
    return uv.hrtime() / 1000000000
  end
  return os.time()
end

local function fresh_session(original)
  return {
    total = 0,
    [1] = 0,
    [2] = 0,
    [3] = 0,
    original = original or 0,
    requeued = 0,
    hints = 0,
    buried = 0,
    suspended = 0,
    started_at = monotonic_time(),
  }
end

local state = {
  -- `cards` is the source-card cache passed to store.set_card_fields. `queue`
  -- contains lightweight attempts, so an Again retry does not duplicate the
  -- card in the cache used for source-line adjustment.
  cards = {},
  queue = {},
  index = 1,
  showing_answer = false,
  completed = false,
  label = "",
  buf = nil,
  win = nil,
  session = fresh_session(),
  on_close = nil,
  on_review = nil,
  on_event = nil,
  last_action = nil,
  session_id = nil,
  requeued_cards = {},
  event_sequence = 0,
}

local key_help = { buf = nil, win = nil }

local function review_context()
  if state.completed then
    return "review_complete"
  end
  if state.showing_answer then
    return "review_answer"
  end
  return "review_question"
end

local function review_capabilities()
  return {
    bury = type(config.on_bury) == "function",
    suspend = type(config.on_suspend) == "function",
  }
end

local function show_shortcuts()
  return type(config.ui) ~= "table" or config.ui.show_shortcuts ~= false
end

local function shortcut_footer()
  if not show_shortcuts() then
    return ""
  end
  local width = 84
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    width = vim.api.nvim_win_get_width(state.win)
  end
  return actions.footer(review_context(), width, review_capabilities())
end

-- Masks {{cN::answer}} / {{cN::answer|hint}} cloze markers before the reveal.
local function mask_clozes(text)
  local masked = text:gsub("{{c%d+::(.-)|(.-)}}", "[%2]")
  return (masked:gsub("{{c%d+::(.-)}}", "[...]"))
end

-- After the reveal, markers unwrap to the plain answer text.
local function unmask_clozes(text)
  local plain = text:gsub("{{c%d+::(.-)|.-}}", "%1")
  return (plain:gsub("{{c%d+::(.-)}}", "%1"))
end

local function append_field(lines, title, value, masked)
  table.insert(lines, "")
  table.insert(lines, "** " .. title)
  for _, line in ipairs(util.value_lines(value)) do
    if masked then
      line = mask_clozes(line)
    else
      line = unmask_clozes(line)
    end
    table.insert(lines, line)
  end
end

local function current_attempt()
  return state.queue[state.index]
end

local function elapsed_seconds()
  return math.max(0, math.floor(monotonic_time() - state.session.started_at + 0.5))
end

local function human_duration(seconds)
  if seconds < 60 then
    return string.format("%d sec", seconds)
  end

  local minutes = math.floor(seconds / 60)
  local remainder = seconds % 60
  if minutes < 60 then
    return remainder == 0 and string.format("%d min", minutes) or string.format("%d min %d sec", minutes, remainder)
  end

  local hours = math.floor(minutes / 60)
  minutes = minutes % 60
  return minutes == 0 and string.format("%d h", hours) or string.format("%d h %d min", hours, minutes)
end

local function session_snapshot()
  return {
    active = #state.cards > 0,
    completed = state.completed,
    label = state.label,
    reviewed = state.session.total,
    remaining = #state.queue,
    requeued = state.session.requeued,
    original = state.session.original,
    ratings = {
      [1] = state.session[1],
      [2] = state.session[2],
      [3] = state.session[3],
    },
    hints = state.session.hints,
    buried = state.session.buried,
    suspended = state.session.suspended,
    showing_answer = state.showing_answer,
    index = state.index,
    elapsed_seconds = elapsed_seconds(),
    session_id = state.session_id,
  }
end

local scheduling_fields = {
  "score",
  "reviewed",
  "due",
  "interval",
  "ease",
  "reps",
  "lapses",
  "state",
}

local function scheduling_snapshot(values, updates)
  local snapshot = {}
  local included = {}
  for _, field in ipairs(scheduling_fields) do
    included[field] = true
    local value = values and values[field]
    if value ~= nil and value ~= "" then
      snapshot[field] = value
    end
  end
  for _, update in ipairs(updates or {}) do
    if update.field ~= "id" and not included[update.field] then
      local value = values and values[update.field]
      if value ~= nil and value ~= "" then
        snapshot[update.field] = value
      end
    end
  end
  return snapshot
end

local function card_reference(card)
  return {
    id = schema.card_id(card),
    path = card.path,
    start_line = card.start_line,
    kind = card.kind,
  }
end

local function next_event_id()
  state.event_sequence = state.event_sequence + 1
  return string.format("%s:%d", state.session_id or "session", state.event_sequence)
end

local function emit_event(event)
  event.session = session_snapshot()
  event.session_id = state.session_id
  event.label = state.label

  local callbacks = {}
  if type(state.on_event) == "function" then
    table.insert(callbacks, state.on_event)
  elseif type(config.on_review_event) == "function" then
    table.insert(callbacks, config.on_review_event)
  end

  -- `on_review` is the deliberately small integration point for a richer
  -- append-only history module. It only receives successfully persisted
  -- ratings (and a compensating undo event when that rating is reversed).
  if event.persisted and type(state.on_review) == "function" then
    table.insert(callbacks, state.on_review)
  elseif event.persisted and type(config.on_review) == "function" then
    table.insert(callbacks, config.on_review)
  elseif not event.persisted and type(config.on_review_pending) == "function" then
    table.insert(callbacks, config.on_review_pending)
  end

  local seen = {}
  for _, callback in ipairs(callbacks) do
    if not seen[callback] then
      seen[callback] = true
      local ok, err = pcall(callback, vim.deepcopy(event))
      if not ok then
        util.notify("Review event callback failed: " .. tostring(err), vim.log.levels.WARN)
      end
    end
  end
end

local function update_footer()
  if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
    return
  end
  pcall(vim.api.nvim_win_set_config, state.win, { footer = shortcut_footer(), footer_pos = "center" })
end

local function rate_from_popup(score)
  M.rate_current(score, { require_reveal = true })
end

local function dispatch(action_name)
  if action_name == "close" then
    M.close()
  elseif action_name == "context_help" then
    M.context_help()
  elseif action_name == "flip_or_next" then
    M.flip_or_next()
  elseif action_name == "next" then
    M.next()
  elseif action_name == "previous" then
    M.previous()
  elseif action_name == "hint" then
    M.hint()
  elseif action_name == "undo" then
    M.undo_last()
  elseif action_name == "edit" then
    M.edit_current()
  elseif action_name == "type_answer" then
    M.type_answer()
  elseif action_name == "rate_again" then
    rate_from_popup(1)
  elseif action_name == "rate_hard" then
    rate_from_popup(2)
  elseif action_name == "rate_good" then
    rate_from_popup(3)
  elseif action_name == "bury" then
    M.bury_current()
  elseif action_name == "suspend" then
    M.suspend_current()
  end
end

local function ensure_window()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    return
  end

  local maps = {}
  for _, binding in ipairs(actions.available_bindings("review", review_capabilities())) do
    local action_name = binding.action
    table.insert(maps, {
      binding.key,
      function()
        dispatch(action_name)
      end,
      binding.description,
    })
  end

  popup.open(state, {
    title = " Flashcards ",
    footer = shortcut_footer(),
    min_height = 17,
    maps = maps,
  })
end

local function interval_previews(card, now)
  local previews = {}
  for score = 1, 3 do
    local _, due = schedule.review_updates(card, score, now, config.scheduling)
    previews[score] = schedule.humanize(due - now)
  end
  return previews
end

local function hint_source(card)
  local parts = {}
  for _, field in ipairs(schema.reveal_fields(config, card)) do
    for _, line in ipairs(util.value_lines(field.value)) do
      line = util.trim(unmask_clozes(line))
      if line ~= "" then
        table.insert(parts, line)
      end
    end
  end
  return table.concat(parts, " / ")
end

local function progressive_hint(text, level)
  local chars = util.utf8_chars(text)
  if #chars == 0 then
    return ""
  end

  local shown = math.min(#chars, math.max(1, math.ceil(#chars * math.min(level, 4) / 4)))
  local result = table.concat(chars, "", 1, shown)
  local hidden = #chars - shown
  if hidden > 0 then
    result = result .. string.rep("·", math.min(hidden, 10))
    if hidden > 10 then
      result = result .. "…"
    end
  end
  return result
end

local function render_completion()
  update_footer()
  local label = state.label ~= "" and (state.label .. " | ") or ""
  local lines = {
    "* " .. label .. "Session complete ✓",
    "",
    string.format(
      "Completed %d review%s in %s",
      state.session.total,
      state.session.total == 1 and "" or "s",
      human_duration(elapsed_seconds())
    ),
    string.format(
      "Original queue %d · Requeued %d · Hints used %d",
      state.session.original,
      state.session.requeued,
      state.session.hints
    ),
    string.format("Buried %d · Suspended %d", state.session.buried, state.session.suspended),
    "",
    "** Ratings",
    string.format("1  Again  %d", state.session[1]),
    string.format("2  Hard   %d", state.session[2]),
    string.format("3  Good   %d", state.session[3]),
    "",
    "Nice work. Press u to undo the last rating, or q to return.",
  }
  popup.set_lines(state, lines)
end

local function render()
  if #state.cards == 0 then
    return
  end

  ensure_window()

  if state.completed then
    render_completion()
    return
  end

  update_footer()
  local attempt = current_attempt()
  if not attempt then
    state.completed = true
    render_completion()
    return
  end

  if not attempt.opened_at then
    attempt.opened_at = monotonic_time()
  end

  local card = attempt.card
  local front_title, front_value = schema.front(config, card)
  local planned = state.session.original + state.session.requeued
  local position = math.min(planned, state.session.total + 1)
  local label = state.label ~= "" and (state.label .. " | ") or ""
  local lines = {
    string.format(
      "* %s%d/%d | Reviewed %d · Remaining %d · Requeued %d",
      label,
      position,
      planned,
      state.session.total,
      #state.queue,
      state.session.requeued
    ),
    "Source: " .. util.path_label(card.path, config.flashcards_dir),
  }

  append_field(lines, front_title, front_value, not state.showing_answer)

  if state.showing_answer then
    for _, field in ipairs(schema.reveal_fields(config, card)) do
      append_field(lines, field.title, field.value, false)
    end

    local previews = interval_previews(card, os.time())
    table.insert(lines, "")
    table.insert(lines, "** Choose a rating")
    table.insert(lines, string.format("1 Again  %s    2 Hard  %s    3 Good  %s", previews[1], previews[2], previews[3]))
  else
    if attempt.hint_level > 0 then
      append_field(lines, "Hint " .. attempt.hint_level, progressive_hint(hint_source(card), attempt.hint_level), false)
    end
    table.insert(lines, "")
    table.insert(lines, "Reveal the answer with ⏎ or Space before rating. Press h for a hint.")
  end

  popup.set_lines(state, lines)
end

local function commit_last_action()
  if not state.last_action then
    return
  end
  if type(state.on_review) ~= "function" and type(config.on_review) ~= "function" then
    stats.log_review(state.last_action.score)
  end
  state.last_action.committed = true
  state.last_action = nil
end

local function clear_state()
  state.cards = {}
  state.queue = {}
  state.index = 1
  state.showing_answer = false
  state.completed = false
  state.label = ""
  state.session = fresh_session()
  state.on_close = nil
  state.on_review = nil
  state.on_event = nil
  state.last_action = nil
  state.session_id = nil
  state.requeued_cards = {}
  state.event_sequence = 0
end

function M.setup(opts)
  config = opts or {}
end

function M.context_help()
  local context = review_context()
  popup.open(key_help, {
    title = " " .. actions.title(context) .. " ",
    footer = " q/Esc/? close ",
    min_width = 52,
    max_width = 76,
    min_height = 12,
    max_height = 28,
    maps = {
      { "q", M.help_close, "Close review key help" },
      { "<Esc>", M.help_close, "Close review key help" },
      { "?", M.help_close, "Close review key help" },
    },
  })
  popup.set_lines(key_help, actions.help_lines(context, review_capabilities()))
end

function M.help_close()
  popup.close(key_help)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
  end
end

function M.start(cards, errors, label, empty_message, opts)
  cards = cards or {}
  errors = errors or {}
  opts = opts or {}

  if #errors > 0 then
    util.notify(table.concat(errors, "\n"), vim.log.levels.WARN)
  end

  if #cards == 0 then
    M.close()
    util.notify(empty_message or "No valid flashcards found", vim.log.levels.WARN)
    return
  end

  -- A new start replaces an existing session. Commit its final accepted rating
  -- before resetting so the legacy aggregate log cannot silently lose it.
  commit_last_action()

  local ordered
  if opts.sort == "due" then
    ordered = vim.deepcopy(cards)
    table.sort(ordered, function(left, right)
      return schedule.due_key(left) < schedule.due_key(right)
    end)
  else
    ordered = util.shuffled(cards)
  end

  state.cards = ordered
  state.queue = {}
  for _, card in ipairs(ordered) do
    table.insert(state.queue, { card = card, hint_level = 0, requeued = false })
  end
  state.index = 1
  state.showing_answer = false
  state.completed = false
  state.label = label or ""
  state.session = fresh_session(#ordered)
  state.on_close = opts.on_close
  state.on_review = opts.on_review
  state.on_event = opts.on_event
  state.last_action = nil
  state.requeued_cards = {}
  state.event_sequence = 0
  state.session_id =
    string.format("%s-%x", os.date("!%Y%m%dT%H%M%SZ"), math.floor(monotonic_time() * 1000000) % 0xffffff)
  render()
end

function M.close()
  commit_last_action()
  popup.close(key_help)
  popup.close(state)

  local snapshot = session_snapshot()
  if state.session.total > 0 then
    util.notify(
      string.format(
        "Session: %d reviewed · %d again · %d hard · %d good · %s",
        state.session.total,
        state.session[1],
        state.session[2],
        state.session[3],
        human_duration(elapsed_seconds())
      )
    )
  end

  if type(state.on_event) == "function" or type(config.on_review_event) == "function" then
    emit_event({ event = "completed", type = "session", persisted = false, summary = snapshot })
  end

  local on_close = state.on_close
  clear_state()
  if on_close then
    on_close()
  end
end

function M.flip_or_next()
  if state.completed then
    M.close()
    return
  end
  if #state.queue == 0 then
    return
  end

  if state.showing_answer then
    util.notify("Choose 1 Again, 2 Hard, or 3 Good before continuing")
    return
  end

  state.showing_answer = true
  render()
end

function M.next()
  if state.completed or #state.queue == 0 then
    return
  end

  state.index = state.index % #state.queue + 1
  state.showing_answer = false
  render()
end

function M.previous()
  if state.completed or #state.queue == 0 then
    return
  end

  state.index = ((state.index - 2) % #state.queue) + 1
  state.showing_answer = false
  render()
end

function M.hint()
  if state.completed or #state.queue == 0 then
    return
  end
  if state.showing_answer then
    util.notify("The full answer is already visible")
    return
  end

  local attempt = current_attempt()
  local source = hint_source(attempt.card)
  if source == "" then
    util.notify("This card has no answer field to hint", vim.log.levels.WARN)
    return
  end

  attempt.hint_level = math.min(4, (attempt.hint_level or 0) + 1)
  attempt.hints_used = (attempt.hints_used or 0) + 1
  state.session.hints = state.session.hints + 1
  render()
end

function M.rate_current(score, opts)
  if state.completed or #state.queue == 0 then
    return false
  end
  if score ~= 1 and score ~= 2 and score ~= 3 then
    util.notify("Rating must be 1, 2, or 3", vim.log.levels.ERROR)
    return false
  end

  opts = opts or {}
  if opts.require_reveal and not state.showing_answer then
    state.showing_answer = true
    render()
    util.notify("Answer revealed — review it, then press 1, 2, or 3 again")
    return false
  end

  -- Once another answer is accepted, the prior rating is no longer the
  -- session-level undo candidate and can enter the legacy aggregate log.
  commit_last_action()

  local attempt = current_attempt()
  local card = attempt.card
  local now = os.time()
  local updates, due = schedule.review_updates(card, score, now, config.scheduling)
  local before = scheduling_snapshot(card.values, updates)
  local previous = {}
  local reversible_updates = {}
  for _, update in ipairs(updates) do
    if update.field ~= "id" then
      previous[update.field] = card.values[update.field]
      table.insert(reversible_updates, vim.deepcopy(update))
    end
  end

  local ok, message, persisted = store.set_card_fields(card, updates, { cards = state.cards })
  if not ok then
    util.notify(message, vim.log.levels.ERROR)
    return false
  end
  if message then
    util.notify(message, vim.log.levels.WARN)
  end

  local queue_index = state.index
  table.remove(state.queue, queue_index)
  if #state.queue == 0 then
    state.index = 1
  elseif queue_index > #state.queue then
    state.index = 1
  else
    state.index = queue_index
  end

  local requeued_attempt = nil
  local marked_requeue = false
  if score == 1 and not state.requeued_cards[card] then
    requeued_attempt = { card = card, hint_level = 0, requeued = true }
    local insert_at = math.min(state.index + 3, #state.queue + 1)
    table.insert(state.queue, insert_at, requeued_attempt)
    state.requeued_cards[card] = true
    marked_requeue = true
    state.session.requeued = state.session.requeued + 1
    if #state.queue == 1 then
      state.index = 1
    end
  end

  state.session.total = state.session.total + 1
  state.session[score] = state.session[score] + 1
  local event_id = next_event_id()
  local reference = card_reference(card)
  local after = scheduling_snapshot(card.values, updates)
  state.last_action = {
    card = card,
    attempt = attempt,
    queue_index = queue_index,
    requeued_attempt = requeued_attempt,
    marked_requeue = marked_requeue,
    score = score,
    due = due,
    previous = previous,
    updates = reversible_updates,
    persisted = persisted == true,
    timestamp = now,
    duration_seconds = math.max(0, monotonic_time() - (attempt.opened_at or monotonic_time())),
    hints_used = attempt.hints_used or 0,
    event_id = event_id,
    reference = reference,
    before = before,
    after = after,
  }

  state.showing_answer = false
  state.completed = #state.queue == 0

  emit_event({
    event = "rated",
    type = "review",
    event_id = event_id,
    persisted = persisted == true,
    card_ref = reference,
    card_id = reference.id,
    path = reference.path,
    start_line = reference.start_line,
    score = score,
    rating = score,
    due = due,
    timestamp = now,
    epoch = now,
    duration_seconds = state.last_action.duration_seconds,
    duration_ms = math.floor(state.last_action.duration_seconds * 1000 + 0.5),
    hints_used = state.last_action.hints_used,
    hint_used = state.last_action.hints_used > 0,
    before = before,
    after = after,
  })

  util.notify("Next review " .. schedule.humanize(due - now))
  render()
  return true
end

function M.undo_last()
  local action = state.last_action
  if not action then
    util.notify("Nothing to undo in this session", vim.log.levels.WARN)
    return false
  end

  if type(store.restore_card_fields) ~= "function" then
    util.notify("Undo requires field-removal support from neorg_flashcards.store", vim.log.levels.ERROR)
    return false
  end

  local ok, message, persisted =
    store.restore_card_fields(action.card, action.previous, action.updates, { cards = state.cards })
  if not ok then
    util.notify("Could not undo rating: " .. tostring(message), vim.log.levels.ERROR)
    return false
  end
  if message then
    util.notify(message, vim.log.levels.WARN)
  end

  if action.requeued_attempt then
    for index, attempt in ipairs(state.queue) do
      if attempt == action.requeued_attempt then
        table.remove(state.queue, index)
        break
      end
    end
    state.session.requeued = math.max(0, state.session.requeued - 1)
  end
  if action.marked_requeue then
    state.requeued_cards[action.card] = nil
  end

  local insert_at = math.min(math.max(1, action.queue_index), #state.queue + 1)
  table.insert(state.queue, insert_at, action.attempt)
  state.index = insert_at
  state.session.total = math.max(0, state.session.total - 1)
  state.session[action.score] = math.max(0, state.session[action.score] - 1)
  state.completed = false
  state.showing_answer = true
  state.last_action = nil

  local undo_now = os.time()
  emit_event({
    event = "undo",
    type = "review",
    event_id = next_event_id(),
    undo_of = action.event_id,
    persisted = persisted == true,
    card_ref = action.reference,
    card_id = action.reference.id,
    path = action.reference.path,
    start_line = action.reference.start_line,
    score = action.score,
    rating = action.score,
    timestamp = undo_now,
    epoch = undo_now,
    original_timestamp = action.timestamp,
    original = {
      event_id = action.event_id,
      score = action.score,
      timestamp = action.timestamp,
      before = action.before,
      after = action.after,
    },
    before = action.after,
    after = scheduling_snapshot(action.card.values, action.updates),
  })

  render()
  util.notify("Last rating undone")
  return true
end

local function apply_card_action(name, callback)
  if state.completed or #state.queue == 0 or type(callback) ~= "function" then
    return false
  end

  local card = current_attempt().card
  local ok, accepted, message = pcall(callback, card, {
    session_id = state.session_id,
    label = state.label,
    action = name,
    cards = state.cards,
  })
  if not ok then
    util.notify(string.format("Could not %s card: %s", name, tostring(accepted)), vim.log.levels.ERROR)
    return false
  end
  if accepted == false then
    util.notify(message or ("Could not " .. name .. " card"), vim.log.levels.ERROR)
    return false
  end

  commit_last_action()
  for index = #state.queue, 1, -1 do
    if state.queue[index].card == card then
      table.remove(state.queue, index)
    end
  end
  if #state.queue == 0 then
    state.index = 1
    state.completed = true
  elseif state.index > #state.queue then
    state.index = 1
  end
  state.showing_answer = false
  state.session[name == "bury" and "buried" or "suspended"] = state.session[name == "bury" and "buried" or "suspended"]
    + 1

  emit_event({
    event = name == "bury" and "buried" or "suspended",
    type = "card_state",
    persisted = false,
    card_ref = card_reference(card),
    card_id = schema.card_id(card),
    path = card.path,
    start_line = card.start_line,
    timestamp = os.time(),
  })
  if message then
    util.notify(message)
  end
  render()
  return true
end

function M.bury_current()
  return apply_card_action("bury", config.on_bury)
end

function M.suspend_current()
  return apply_card_action("suspend", config.on_suspend)
end

function M.edit_current()
  if state.completed or #state.queue == 0 then
    return
  end

  -- Editing leaves the review flow entirely: no session summary, no on_close.
  commit_last_action()
  local card = current_attempt().card
  popup.close(key_help)
  popup.close(state)
  clear_state()
  if type(config.on_edit) == "function" then
    local ok, err = pcall(config.on_edit, card)
    if ok then
      return
    end
    util.notify("Could not open flashcard source: " .. tostring(err), vim.log.levels.ERROR)
  end
  vim.cmd.edit(util.fname(card.path))
  vim.api.nvim_win_set_cursor(0, { card.start_line, 0 })
end

local function normalize_answer(text)
  return util.trim(text):lower():gsub("%s+", " ")
end

function M.type_answer()
  if state.completed or #state.queue == 0 then
    return
  end

  local attempt = current_attempt()
  local card = attempt.card
  local fields = schema.reveal_fields(config, card)
  if #fields == 0 then
    util.notify("This card kind has no answer fields to type against", vim.log.levels.WARN)
    return
  end

  vim.ui.input({ prompt = "Answer: " }, function(input)
    if input == nil or current_attempt() ~= attempt then
      return
    end

    local answer = normalize_answer(input)
    local best_distance = math.huge
    local best_expected = ""
    for _, field in ipairs(fields) do
      for _, line in ipairs(util.value_lines(field.value)) do
        local expected = normalize_answer(unmask_clozes(line))
        if expected ~= "" then
          local distance = util.levenshtein(answer, expected)
          if distance < best_distance then
            best_distance = distance
            best_expected = expected
          end
        end
      end
    end

    state.showing_answer = true
    render()

    local close_enough = math.max(1, math.floor(#util.utf8_chars(best_expected) * 0.2))
    if best_distance == 0 then
      util.notify("✓ Correct")
    elseif best_distance <= close_enough then
      util.notify("≈ Close — answer: " .. best_expected)
    else
      util.notify("✗ Answer: " .. best_expected)
    end
  end)
end

-- Read-only state for UI integration and tests. Card contents stay private;
-- consumers get progress and completion information only.
function M.get_session_state()
  return session_snapshot()
end

return M
