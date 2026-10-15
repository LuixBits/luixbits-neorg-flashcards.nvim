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
  key("<CR>") -- Open box, select All due.
  key("l") -- Food note.
  key("<CR>")
  truth(review.is_active(), "a category note starts an integrated review")
  equal(flashcards.get_review_state().remaining, 2, "category stack contains both ready cards")
  key("3")
  key("3")
  equal(flashcards.get_review_state().reviewed, 0, "repeated rating keys cannot reveal and rate a question")
  key("<CR>")
  key("1")
  equal(flashcards.get_review_state().unique, 1, "Again increases unique progress once")
  equal(flashcards.get_review_state().remaining, 2, "Again leaves one finite retry pending")
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
  key("<PageDown>")
  key("<PageDown>")
  vim.cmd("redraw")
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
    goal_line and goal_line >= top and goal_line + 7 < top + vim.api.nvim_win_get_height(0) - 1,
    "the entire daily progress note can be brought above the shortcut strip"
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
