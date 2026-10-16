return function(T)
  local flashcards = require("neorg_flashcards")
  local overview = require("neorg_flashcards.overview")
  local review = require("neorg_flashcards.review")
  local motion = require("neorg_flashcards.ui.motion")
  local history = require("neorg_flashcards.history")
  local stats = require("neorg_flashcards.stats")
  local presets = require("neorg_flashcards.presets")
  local equal, truth, contains = T.assert_equal, T.assert_true, T.assert_contains
  local root = vim.fn.tempname()
  vim.fn.mkdir(root .. "/demo", "p")
  vim.fn.writefile({
    "@flashcard japanese",
    "id: fc_motion_one",
    "japanese: 水",
    "english: water",
    "tags: food",
    "@end",
    "@flashcard japanese",
    "id: fc_motion_two",
    "japanese: 茶",
    "english: tea",
    "tags: food",
    "@end",
  }, root .. "/demo/cards.norg")
  local opts = {
    default_collection = "demo",
    deck_registry = root .. "/decks.json",
    ui = { motion = true },
    collections = {
      demo = {
        label = "日本語",
        path = root .. "/demo",
        default_card_type = "japanese",
        schemas = presets.only("japanese"),
      },
    },
  }
  truth(flashcards.setup(opts))
  local columns, lines = vim.o.columns, vim.o.lines
  vim.o.columns, vim.o.lines = 80, 24
  truth(flashcards.desk())
  local function key(lhs)
    for _, binding in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
      if binding.lhs == lhs then
        binding.callback()
        return
      end
    end
    error("missing binding " .. lhs)
  end
  key("g") -- Switch chapter notes to tags.
  key("<CR>") -- Open box, select All due.
  key("l") -- Food note.
  key("<CR>")
  truth(review.is_active(), "a category note starts an integrated review")
  local function source_outside_card()
    local source_row, card_row
    for row, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      if line:find("Source: cards.norg", 1, true) then
        source_row = row
      end
      if line:find(" QUESTION ", 1, true) or line:find(" ANSWER ", 1, true) then
        card_row = row
      end
    end
    truth(source_row and card_row and source_row < card_row, "the source stays in workspace chrome, outside the card")
  end
  source_outside_card()
  equal(flashcards.get_review_state().remaining, 2, "category stack contains both ready cards")
  key("3")
  key("3")
  equal(flashcards.get_review_state().reviewed, 0, "repeated rating keys cannot reveal and rate a question")
  key("<CR>")
  source_outside_card()
  key("1")
  equal(flashcards.get_review_state().unique, 1, "Again increases unique progress once")
  equal(flashcards.get_review_state().remaining, 2, "Again leaves one finite retry pending")
  local _, retry_text = T.current_popup()
  contains(retry_text, "Pending 2", "pending includes the queued retry")
  contains(retry_text, "Finished 0 of 2", "a retried card is not counted as finished")
  contains(retry_text, "Again 1", "compact sessions retain rating totals")
  truth(vim.wait(400, function()
    return not motion.active("review")
  end))
  vim.o.columns, vim.o.lines = 150, 40
  vim.api.nvim_exec_autocmds("VimResized", {})
  local _, stacks = T.current_popup()
  contains(stacks, "Unseen      1", "the pending pile distinguishes unseen cards")
  contains(stacks, "Retry       1", "the pending pile includes the finite retry")
  contains(stacks, "Again       1", "the reviewed pile shows actual rating totals")
  contains(stacks, "0 cards finished", "the pile does not count a pending retry as finished")
  source_outside_card()
  vim.o.columns, vim.o.lines = 80, 24
  vim.api.nvim_exec_autocmds("VimResized", {})
  key("3")
  equal(flashcards.get_review_state().reviewed, 1, "a queued key cannot rate an unseen next card")
  key("<CR>")
  key("3")
  key("<CR>")
  key("3")
  local complete = flashcards.get_review_state()
  truth(complete.completed, "the finite stack reaches its receipt")
  equal(complete.unique, 2, "three answers on two cards yield two unique cards")
  equal(complete.reviewed, 3, "the receipt counts answers separately")
  truth(
    vim.wait(400, function()
      return not motion.active("review")
    end),
    "completed desk animations settle"
  )
  key("u")
  truth(not flashcards.get_review_state().completed, "undo reopens the finished stack")
  equal(flashcards.get_review_state().unique, 2, "undoing a retry retains the earlier answer's unique count")
  key("<CR>")
  key("3")
  key("s")
  equal(overview.current_view(), "stats", "receipt opens Stats in the existing workspace")
  truth(not motion.active("review"), "leaving review cancels its animation")
  key("<CR>")
  equal(overview.current_view(), "overview", "calendar selection drills into Overview")
  contains(T.current_tab_text(), "Reviewed ", "the day filter identifies its date")
  contains(T.current_tab_text(), "2 shown", "calendar drilldown shows unique current cards")

  -- Pending delivery contributes once; an undo in the outbox reduces it.
  local config = flashcards.active_collection()
  local event = {
    version = 1,
    type = "review",
    event = "rated",
    event_id = "desk-pending",
    card_id = "fc_pending",
    rating = 1,
    epoch = os.time(),
    collection_id = "demo",
  }
  truth(history.write_outbox(config, { event }))
  local progress, errors, count = stats.read_progress()
  equal(#errors, 0, "progress reads valid pending history")
  equal(count, 1, "outbox progress is explicitly provisional")
  local unique = require("neorg_flashcards.calendar").progress(progress, { goals = {}, goal = 20 }).unique
  equal(unique, 3, "pending delivery appears in daily progress")
  truth(history.append(event, config))
  progress, errors, count = stats.read_progress()
  equal(#errors, 0, "delivered progress remains readable")
  equal(count, 0, "an already delivered outbox event is deduplicated")
  equal(
    require("neorg_flashcards.calendar").progress(progress, { goals = {}, goal = 20 }).unique,
    3,
    "replay never doubles goal progress"
  )
  truth(history.remove_outbox(config, { event }))

  -- A short terminal must be able to reach the progress note after the last
  -- category. Paging used to stop at that category with the goal offscreen.
  vim.o.columns, vim.o.lines = 60, 20
  vim.api.nvim_exec_autocmds("VimResized", {})
  overview.show("desk")
  key("G")
  for _ = 1, 3 do
    key("<PageDown>")
    vim.cmd("redraw")
  end
  local goal_line
  for index, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if line:find("TODAY", 1, true) then
      goal_line = index
      break
    end
  end
  local top = vim.fn.winsaveview().topline
  truth(top > 1, "paging continues past the last category")
  truth(
    goal_line and goal_line >= top and goal_line + 7 < top + vim.fn.winheight(0) - 1,
    string.format(
      "the entire daily progress note fits above the strip (goal %s, top %d, height %d)",
      tostring(goal_line),
      top,
      vim.fn.winheight(0)
    )
  )

  for _, size in ipairs({ { 60, 20 }, { 80, 24 }, { 140, 45 } }) do
    vim.o.columns, vim.o.lines = size[1], size[2]
    vim.api.nvim_exec_autocmds("VimResized", {})
    for _, page in ipairs({ "desk", "overview", "stats", "desk" }) do
      overview.show(page)
      truth(overview.is_open(), "workspace survives resizing and switching to " .. page)
    end
  end
  local input, select = vim.ui.input, vim.ui.select
  local answers = { "science", "Science", root .. "/science" }
  vim.ui.input = function(_, callback)
    callback(table.remove(answers, 1))
  end
  vim.ui.select = function(items, _, callback)
    if vim.tbl_contains(items, "New deck") then
      callback("New deck")
    else
      callback("question_answer")
    end
  end
  overview.show("overview")
  key("m")
  equal(flashcards.active_collection().id, "science", "the deck wizard creates, reloads, and selects the new deck")
  truth(overview.is_open(), "creating a deck keeps the workspace intact")
  local stale_management
  vim.ui.select = function(_, _, callback)
    stale_management = callback
  end
  key("m")
  overview.close()
  flashcards.overview()
  local prompted = false
  vim.ui.input = function()
    prompted = true
  end
  stale_management("Daily goal")
  truth(not prompted, "management prompts expire when their workspace closes")
  vim.ui.input, vim.ui.select = input, select
  overview.close()
  truth(flashcards.setup(opts), "registry decks survive a complete setup reload")
  truth(flashcards.select_collection("science"), "a registered deck can be selected after reload")
  vim.o.columns, vim.o.lines = columns, lines
  T.setup(T.config)
  vim.fn.delete(root, "rf")
end
