return function(T)
  local form = require("neorg_flashcards.form")
  local presets = require("neorg_flashcards.presets")
  local review_engine = require("neorg_flashcards.review")
  local schedule = require("neorg_flashcards.schedule")
  local flashcards = require("neorg_flashcards")

  local assert_true = T.assert_true
  local assert_equal = T.assert_equal
  local assert_contains = T.assert_contains
  local current_popup = T.current_popup
  local assert_buffer_maps = T.assert_buffer_maps
  local window_footer = T.window_footer
  local decoration_text = T.decoration_text
  local fixed_now = T.fixed_now
  local config = T.config

  local cloze_path = T.collection_dir .. "/review-cloze.norg"
  vim.fn.writefile({
    "@flashcard japanese",
    "id: fc_cloze_tokyo",
    "japanese: 東京は{{c1::日本}}の首都です",
    "reading: とうきょう",
    "english: Tokyo is the capital of {{c1::Japan|country}}",
    "@end",
  }, cloze_path)
  vim.cmd.edit(vim.fn.fnameescape(cloze_path))

  vim.cmd("Flashcards review file")
  local _, cloze_front = current_popup()
  assert_contains(cloze_front, "東京は[...]の首都です", "cloze is masked before the reveal")
  assert_true(not cloze_front:find("日本", 1, true), "cloze hides the answer before the reveal")

  local typed_input = vim.ui.input
  vim.ui.input = function(_, callback)
    callback("とうきょう")
  end
  flashcards.type_answer()
  vim.ui.input = typed_input

  local _, cloze_after = current_popup()
  assert_contains(cloze_after, "東京は日本の首都です", "typed answer reveals the unwrapped cloze")
  assert_contains(cloze_after, "Tokyo is the capital of Japan", "hint cloze unwraps after the reveal")
  flashcards.close_review()
  vim.cmd("silent! bwipeout!")
  vim.fn.delete(cloze_path)

  assert_equal(
    schedule.next_due({ { values = { due = "2999-01-01 00:00" } }, { values = {} } }, fixed_now),
    schedule.parse_due("2999-01-01 00:00"),
    "next due finds the earliest future timestamp"
  )
  assert_equal(
    schedule.next_due({ { values = { due = "2020-01-01 00:00" } } }, fixed_now),
    nil,
    "next due ignores past-due cards"
  )

  local summary_path = T.collection_dir .. "/review-summary.norg"
  vim.fn.writefile({
    "@flashcard japanese",
    "id: fc_review_forest",
    "japanese: 森",
    "english: forest",
    "@end",
  }, summary_path)
  vim.cmd.edit(vim.fn.fnameescape(summary_path))

  local notifications = {}
  local notify_original = vim.notify
  vim.notify = function(message)
    table.insert(notifications, tostring(message))
  end

  vim.cmd("Flashcards review file")
  do
    local review_popup = vim.api.nvim_get_current_buf()
    assert_buffer_maps(review_popup, { "q", "?", "j", "k", "1", "2", "3" })
    assert_contains(window_footer(), "Enter/Space reveal", "question review shows its current shortcuts")

    vim.cmd("Flashcards add")
    assert_true(review_engine.is_active(), "add cannot strand an active review session")
    assert_true(review_engine.is_open(), "add leaves the active review popup intact")
    assert_equal(vim.api.nvim_get_current_buf(), review_popup, "add does not replace the review buffer")
    assert_true(not form.is_open(), "add does not open a composer over an active review")

    vim.cmd("Flashcards open")
    assert_true(review_engine.is_open(), "open leaves the active review popup intact")
    assert_equal(vim.api.nvim_get_current_buf(), review_popup, "open does not replace the review buffer")
  end

  review_engine.context_help()
  do
    local _, question_help_text = current_popup()
    assert_contains(question_help_text, "Review keys · question", "review help names the question state")
    assert_contains(question_help_text, "Reveal first, then rate Good", "question help explains rating reveal gating")
  end
  review_engine.help_close()

  review_engine.hint()
  local _, first_hint_text = current_popup()
  assert_contains(first_hint_text, "Hint 1", "review shows the first progressive hint without revealing the answer")
  local hinted_state = flashcards.get_review_state()
  assert_equal(hinted_state.hints, 1, "review state counts progressive hints")

  vim.cmd.edit(vim.fn.fnameescape(summary_path))
  assert_true(review_engine.is_active(), "manual popup replacement keeps the review session recoverable")
  assert_true(not review_engine.is_open(), "a replaced popup buffer is not reported as an open review window")
  local recovered, gated = pcall(review_engine.rate_current, 3, { require_reveal = true })
  assert_true(recovered, "review rendering recovers after its popup buffer is manually replaced")
  assert_true(review_engine.is_open(), "review recreates its popup after manual replacement")
  assert_true(not gated, "a popup rating cannot bypass answer reveal")
  local _, revealed_text = current_popup()
  assert_contains(revealed_text, "Choose a rating", "first rating key reveals the answer and interval choices")
  assert_contains(revealed_text, "1 Again", "revealed card previews the Again interval")
  assert_equal(flashcards.get_review_state().reviewed, 0, "reveal gating does not count an answer")
  assert_contains(window_footer(), "1/2/3 rate", "revealed review promotes rating shortcuts")

  local answer_type_prompted = false
  local answer_input_original = vim.ui.input
  vim.ui.input = function()
    answer_type_prompted = true
  end
  local type_mapping
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(vim.api.nvim_get_current_buf(), "n")) do
    if mapping.lhs == "t" then
      type_mapping = mapping
      break
    end
  end
  assert_true(type_mapping and type(type_mapping.callback) == "function", "typed-answer mapping remains installed")
  type_mapping.callback()
  vim.ui.input = answer_input_original
  assert_true(not answer_type_prompted, "typed-answer mapping cannot run after the answer is revealed")

  review_engine.context_help()
  do
    local _, answer_help_text = current_popup()
    assert_contains(answer_help_text, "Review keys · answer", "review help names the revealed-answer state")
    assert_contains(answer_help_text, "Rate Good", "revealed-answer help lists rating actions")
    assert_true(not answer_help_text:find("progressive hint", 1, true), "revealed-answer help omits unavailable hints")
  end
  review_engine.help_close()

  assert_true(review_engine.rate_current(3, { require_reveal = true }), "rating succeeds after reveal")
  local _, completed_text = current_popup()
  assert_contains(completed_text, "Session complete", "finite review renders an explicit completion screen")
  local completed_state = flashcards.get_review_state()
  assert_true(completed_state.completed, "finite review exposes completion state")
  assert_equal(completed_state.reviewed, 1, "completion reports the accepted rating")
  assert_equal(completed_state.remaining, 0, "completion has no implicit wraparound queue")
  assert_contains(window_footer(), "u undo", "completion footer keeps the available undo action")

  review_engine.context_help()
  do
    local _, complete_help_text = current_popup()
    assert_contains(complete_help_text, "Review keys · complete", "review help names the completion state")
    assert_contains(complete_help_text, "Undo the last rating", "completion help includes undo")
    assert_true(not complete_help_text:find("Rate Good", 1, true), "completion help omits finished rating actions")
  end
  review_engine.help_close()

  assert_true(flashcards.undo_last_rating(), "the final rating can be undone from the completion screen")
  local undo_state = flashcards.get_review_state()
  assert_true(not undo_state.completed, "undo reopens the completed queue")
  assert_equal(undo_state.reviewed, 0, "undo reverses the session counter")
  assert_equal(undo_state.remaining, 1, "undo restores the reviewed card to the queue")
  local undone_disk = table.concat(vim.fn.readfile(summary_path), "\n")
  assert_true(not undone_disk:find("score:", 1, true), "undo restores an absent score field")
  assert_true(not undone_disk:find("due:", 1, true), "undo restores an absent due field")

  assert_true(review_engine.rate_current(3, { require_reveal = true }), "the restored card can be rated again")
  flashcards.close_review()
  vim.notify = notify_original

  local summary_seen = false
  for _, message in ipairs(notifications) do
    if message:find("Session: 1 reviewed", 1, true) then
      summary_seen = true
    end
  end
  assert_true(summary_seen, "closing a review summarizes the session")
  vim.cmd("silent! bwipeout!")
  vim.fn.delete(summary_path)

  -- add_to_default goes through the form and appends to the default file; it
  -- runs last against the first collection because it writes a card into
  -- flashcards_dir/inbox.
  flashcards.add_to_default("")
  local default_form_buf = vim.api.nvim_get_current_buf()
  assert_equal(vim.bo[default_form_buf].buftype, "nofile", "add_to_default opens the form")
  assert_contains(decoration_text(default_form_buf), "inbox/cards.norg", "dashboard add shows the default destination")
  vim.api.nvim_buf_set_lines(default_form_buf, 0, -1, false, {
    "猫",
    "ねこ",
    "cat",
    "",
    "animals",
  })
  assert_true(form.save_new(), "save-and-new accepts a valid dashboard card")
  assert_true(form.is_open(), "save-and-new keeps the composer open")
  assert_equal(vim.api.nvim_win_get_cursor(0)[1], 1, "save-and-new returns to the first field")
  for index, line in ipairs(vim.api.nvim_buf_get_lines(default_form_buf, 0, -1, false)) do
    assert_equal(line, "", "save-and-new resets value " .. index)
  end
  assert_contains(decoration_text(default_form_buf), "Flashcard saved", "save-and-new keeps visible success feedback")
  assert_true(form.close(), "a clean save-and-new form closes without confirmation")

  local default_text = table.concat(vim.fn.readfile(config.default_file), "\n")
  assert_contains(default_text, "* Flashcards", "default file keeps its heading")
  assert_contains(default_text, "@flashcard japanese", "dashboard add writes a card to the default file")
  assert_contains(default_text, "japanese: 猫", "dashboard add saved the front field")
  assert_contains(default_text, "tags: animals", "dashboard add saved the tags")

  local future_dir = vim.fn.tempname()
  vim.fn.mkdir(future_dir, "p")
  vim.fn.writefile({
    "@flashcard japanese",
    "id: fc_future_tomorrow",
    "japanese: 明日",
    "english: tomorrow",
    "due: 2999-01-01 00:00",
    "@end",
  }, future_dir .. "/cards.norg")

  flashcards.setup({
    flashcards_dir = future_dir,
    default_file = future_dir .. "/cards.norg",
    default_kind = "japanese",
    schemas = presets.only("japanese"),
  })

  local hints = {}
  local hint_original = vim.notify
  vim.notify = function(message)
    table.insert(hints, tostring(message))
  end
  vim.cmd("Flashcards review due")
  vim.notify = hint_original

  local hint_seen = false
  for _, message in ipairs(hints) do
    if message:find("next at 2999-01-01", 1, true) then
      hint_seen = true
    end
  end
  assert_true(hint_seen, "empty due review hints at the next due time")
end
