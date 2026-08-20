local popup = require("neorg_flashcards.popup")
local schedule = require("neorg_flashcards.schedule")
local schema = require("neorg_flashcards.schema")
local stats = require("neorg_flashcards.stats")
local store = require("neorg_flashcards.store")
local util = require("neorg_flashcards.util")

local M = {}

local config = {}

local function fresh_session()
  return { total = 0, [1] = 0, [2] = 0, [3] = 0 }
end

local state = {
  cards = {},
  index = 1,
  showing_answer = false,
  label = "",
  buf = nil,
  win = nil,
  session = fresh_session(),
  on_close = nil,
}

local footer = " 1! bad  2~ mid  3✓ good  ⏎/Space flip  t⌨ type  n→ next  p← prev  e✎ edit  q× quit "

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

local function ensure_window()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    return
  end

  popup.open(state, {
    title = " Flashcards ",
    footer = footer,
    min_height = 14,
    maps = {
      { "q", M.close, "Close review" },
      { "<Esc>", M.close, "Close review" },
      { "<Space>", M.flip_or_next, "Show answer or next card" },
      { "<CR>", M.flip_or_next, "Show answer or next card" },
      { "n", M.next, "Next card" },
      { "l", M.next, "Next card" },
      { "p", M.previous, "Previous card" },
      { "h", M.previous, "Previous card" },
      { "e", M.edit_current, "Edit card" },
      { "t", M.type_answer, "Type the answer" },
      {
        "1",
        function()
          M.rate_current(1)
        end,
        "Rate bad",
      },
      {
        "2",
        function()
          M.rate_current(2)
        end,
        "Rate medium",
      },
      {
        "3",
        function()
          M.rate_current(3)
        end,
        "Rate good",
      },
    },
  })
end

local function render()
  if #state.cards == 0 then
    return
  end

  ensure_window()

  local card = state.cards[state.index]
  local front_title, front_value = schema.front(config, card)
  local stats_counts = schema.review_stats(state.cards)
  local now = os.time()
  local due_count = 0
  for _, item in ipairs(state.cards) do
    if schedule.is_due(item, now) then
      due_count = due_count + 1
    end
  end
  local label = state.label ~= "" and (state.label .. " | ") or ""
  local lines = {
    string.format(
      "* %s%d/%d | due %d | new %d | bad %d | mid %d | good %d",
      label,
      state.index,
      #state.cards,
      due_count,
      stats_counts.new,
      stats_counts.bad,
      stats_counts.medium,
      stats_counts.good
    ),
    "Source: " .. util.path_label(card.path, config.flashcards_dir),
  }

  append_field(lines, front_title, front_value, not state.showing_answer)

  if state.showing_answer then
    for _, field in ipairs(schema.reveal_fields(config, card)) do
      append_field(lines, field.title, field.value, false)
    end
  end

  popup.set_lines(state, lines)
end

function M.setup(opts)
  config = opts
end

function M.start(cards, errors, label, empty_message, opts)
  if #errors > 0 then
    util.notify(table.concat(errors, "\n"), vim.log.levels.WARN)
  end

  if #cards == 0 then
    M.close()
    util.notify(empty_message or "No valid flashcards found", vim.log.levels.WARN)
    return
  end

  if opts and opts.sort == "due" then
    table.sort(cards, function(left, right)
      return schedule.due_key(left) < schedule.due_key(right)
    end)
    state.cards = cards
  else
    state.cards = util.shuffled(cards)
  end
  state.index = 1
  state.showing_answer = false
  state.label = label or ""
  state.session = fresh_session()
  state.on_close = opts and opts.on_close or nil
  render()
end

function M.close()
  popup.close(state)

  if state.session.total > 0 then
    util.notify(
      string.format(
        "Session: %d reviewed · %d bad · %d mid · %d good",
        state.session.total,
        state.session[1],
        state.session[2],
        state.session[3]
      )
    )
  end
  state.session = fresh_session()

  local on_close = state.on_close
  state.on_close = nil
  if on_close then
    on_close()
  end
end

function M.flip_or_next()
  if #state.cards == 0 then
    return
  end

  if state.showing_answer then
    M.next()
  else
    state.showing_answer = true
    render()
  end
end

function M.next()
  if #state.cards == 0 then
    return
  end

  state.index = state.index % #state.cards + 1
  state.showing_answer = false
  render()
end

function M.previous()
  if #state.cards == 0 then
    return
  end

  state.index = ((state.index - 2) % #state.cards) + 1
  state.showing_answer = false
  render()
end

function M.rate_current(score)
  if #state.cards == 0 then
    return
  end

  local card = state.cards[state.index]
  local now = os.time()
  local updates, due = schedule.review_updates(card, score, now, config.scheduling)
  local ok, message = store.set_card_fields(card, updates, { cards = state.cards })

  if not ok then
    util.notify(message, vim.log.levels.ERROR)
    return
  end

  if message then
    util.notify(message, vim.log.levels.WARN)
  end

  stats.log_review(score)
  state.session.total = state.session.total + 1
  state.session[score] = state.session[score] + 1

  if score == 1 then
    table.insert(state.cards, math.min(state.index + 4, #state.cards + 1), card)
  end

  util.notify("Next review " .. schedule.humanize(due - now))

  M.next()
end

function M.edit_current()
  if #state.cards == 0 then
    return
  end

  -- Editing leaves the review flow entirely: no session summary, no on_close.
  local card = state.cards[state.index]
  popup.close(state)
  state.session = fresh_session()
  state.on_close = nil
  vim.cmd.edit(util.fname(card.path))
  vim.api.nvim_win_set_cursor(0, { card.start_line, 0 })
end

local function normalize_answer(text)
  return util.trim(text):lower():gsub("%s+", " ")
end

function M.type_answer()
  if #state.cards == 0 then
    return
  end

  local card = state.cards[state.index]
  local fields = schema.reveal_fields(config, card)
  if #fields == 0 then
    util.notify("This card kind has no answer fields to type against", vim.log.levels.WARN)
    return
  end

  vim.ui.input({ prompt = "Answer: " }, function(input)
    if input == nil then
      return
    end

    local answer = normalize_answer(input)
    local best_distance = math.huge
    local best_expected = ""
    for _, field in ipairs(fields) do
      for _, line in ipairs(util.value_lines(field.value)) do
        local expected = normalize_answer(line)
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

return M
