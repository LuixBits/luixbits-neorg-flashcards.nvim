local popup = require("neorg_flashcards.popup")
local schedule = require("neorg_flashcards.schedule")
local schema = require("neorg_flashcards.schema")
local store = require("neorg_flashcards.store")
local util = require("neorg_flashcards.util")

local M = {}

local config = {}
local state = {
  cards = {},
  index = 1,
  showing_answer = false,
  label = "",
  buf = nil,
  win = nil,
}

local footer = " 1! bad  2~ mid  3✓ good  ⏎/Space flip  n→ next  p← prev  e✎ edit  q× quit "

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
  local stats = schema.review_stats(state.cards)
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
      stats.new,
      stats.bad,
      stats.medium,
      stats.good
    ),
    "Source: " .. util.path_label(card.path, config.flashcards_dir),
    "",
    "** " .. front_title,
    front_value,
  }

  if state.showing_answer then
    for _, field in ipairs(schema.reveal_fields(config, card)) do
      table.insert(lines, "")
      table.insert(lines, "** " .. field.title)
      table.insert(lines, field.value)
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
  render()
end

function M.close()
  popup.close(state)
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

  local card = state.cards[state.index]
  M.close()
  vim.cmd.edit(util.fname(card.path))
  vim.api.nvim_win_set_cursor(0, { card.start_line, 0 })
end

return M
