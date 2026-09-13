return function(T)
  local flashcards = require("neorg_flashcards")
  local history = require("neorg_flashcards.history")
  local overview = require("neorg_flashcards.overview")
  local parser = require("neorg_flashcards.parser")
  local presets = require("neorg_flashcards.presets")

  local assert_true = T.assert_true
  local assert_equal = T.assert_equal
  local assert_contains = T.assert_contains

  local test_root = vim.fn.tempname()
  local cards_path = test_root .. "/cards.norg"
  local typed_path = test_root .. "/typed.norg"
  local config = {
    id = "clinic",
    label = "Clinic test",
    path = test_root,
    default_file = cards_path,
    default_card_type = "japanese",
    schemas = presets.only("japanese"),
    leech_threshold = 8,
  }
  vim.fn.mkdir(test_root, "p")
  vim.fn.writefile({
    "@flashcard japanese",
    "id: fc_clinic_struggling",
    "japanese: 難しい",
    "reading: むずかしい",
    "english: difficult",
    "score: 1",
    "lapses: 8",
    "@end",
    "@flashcard japanese",
    "id: fc_clinic_steady",
    "japanese: 易しい",
    "reading: やさしい",
    "english: easy",
    "score: 3",
    "@end",
  }, cards_path)
  assert_true(T.setup(config, "clinic"), "the clinic fixture is configured")

  local cards = parser.collect_flashcards(config)
  local struggling
  for _, card in ipairs(cards) do
    if card.values.id == "fc_clinic_struggling" then
      struggling = card
      break
    end
  end
  assert_true(struggling ~= nil, "the clinic card parses")

  local now = os.time()
  for index, rating in ipairs({ 1, 2, 1 }) do
    local event = assert(history.new_event(struggling, rating, now - (4 - index) * 60, {
      event_id = "clinic-review-" .. index,
      card_type = "japanese",
      hint_used = index < 3,
      due = now + (rating == 2 and 6 * 3600 or 10 * 60),
    }))
    assert_true(history.append(event, config), "the clinic review fixture is appended")
  end

  vim.cmd("Flashcards cards")
  local select_original = vim.ui.select
  local clinic_choice
  vim.ui.select = function(items, _, callback)
    for _, item in ipairs(items) do
      if item.value == "clinic" then
        clinic_choice = item
        callback(item)
        return
      end
    end
  end
  overview.choose_filter()
  vim.ui.select = select_original
  assert_true(clinic_choice ~= nil, "Card clinic is available through the existing Cards filter")
  assert_equal(clinic_choice.count, 1, "the clinic picker previews its current card count")

  local clinic_text = T.current_tab_text()
  assert_contains(clinic_text, "Card clinic · Clinic test", "the Cards page names the active clinic view")
  assert_contains(clinic_text, "難しい", "the clinic keeps the struggling card")
  assert_true(not clinic_text:find("易しい", 1, true), "the clinic leaves a steady card out")
  assert_contains(clinic_text, "Why it is here", "the clinic explains its evidence")
  assert_contains(clinic_text, "8 lapses", "the clinic reports the leech signal")
  assert_contains(clinic_text, "2 of the last 3 reviews were Again", "the clinic reports repeated misses")
  assert_contains(clinic_text, "2 of the last 3 reviews used hints", "the clinic reports repeated hint use")
  assert_contains(clinic_text, "Recall trail · newest on the right", "card details include a compact recall trail")
  assert_contains(clinic_text, "1 ─── 2 ─── 1", "the recall trail keeps chronological rating order")

  vim.cmd("Flashcards stats")
  local stats_text = T.current_tab_text()
  assert_contains(stats_text, "Needs attention", "Stats shares the clinic signal")
  assert_contains(stats_text, "難しい · 8 lapses", "Stats names the card and its strongest reason")
  assert_contains(stats_text, "f → Card clinic", "Stats points back to the existing Cards workflow")
  overview.close()

  vim.fn.writefile({
    "@flashcard japanese",
    "id: fc_typed_private",
    "japanese: 東京",
    "reading: とうきょう",
    "english: Tokyo",
    "@end",
  }, typed_path)
  vim.cmd.edit(vim.fn.fnameescape(typed_path))
  assert_true(flashcards.review_file(), "the typed-answer fixture starts a review")
  local input_original = vim.ui.input
  vim.fn.histadd("input", "とうきょ")
  local function typed_history_count()
    local count = 0
    for history_number = 1, vim.fn.histnr("input") do
      if vim.fn.histget("input", history_number) == "とうきょ" then
        count = count + 1
      end
    end
    return count
  end
  local preexisting_answer_count = typed_history_count()
  vim.ui.input = function(_, callback)
    vim.fn.histadd("input", "とうきょ")
    callback("とうきょ")
  end
  assert_true(flashcards.type_answer(), "typed answering is enabled by the Japanese card type")
  vim.ui.input = input_original
  assert_equal(
    vim.fn.histget("input", -1),
    "とうきょ",
    "a matching input-history entry from before the prompt is preserved"
  )
  assert_equal(typed_history_count(), preexisting_answer_count, "the prompt does not retain an extra history entry")
  for history_number = vim.fn.histnr("input"), 1, -1 do
    if vim.fn.histget("input", history_number) == "とうきょ" then
      vim.fn.histdel("input", history_number)
      break
    end
  end

  local review_buf, review_text = T.current_popup()
  assert_contains(review_text, "Typed answer  ≈ Close", "a near miss gets restrained feedback")
  assert_contains(review_text, "Yours   とうきょ·", "missing text is visible without relying on color")
  assert_contains(review_text, "Answer  とうきょう", "the expected answer is aligned underneath")
  local diff_groups = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(review_buf, -1, 0, -1, { details = true })) do
    local group = (mark[4] or {}).hl_group
    if group then
      diff_groups[group] = true
    end
  end
  assert_true(diff_groups.NeorgFlashcardsAgain, "the entered difference uses the configured Again color")
  assert_true(diff_groups.NeorgFlashcardsGood, "the expected difference uses the configured Good color")

  local private_answer = "nfc-private-" .. tostring((vim.uv or vim.loop).hrtime())
  input_original = vim.ui.input
  vim.ui.input = function(_, callback)
    vim.fn.histadd("input", private_answer)
    callback(private_answer)
  end
  assert_true(flashcards.type_answer(), "a second typed attempt can replace the session-local feedback")
  vim.ui.input = input_original
  for history_number = 1, vim.fn.histnr("input") do
    assert_true(
      vim.fn.histget("input", history_number) ~= private_answer,
      "a newly typed answer is removed from Neovim input history"
    )
  end
  assert_true(flashcards.rate_current(3), "typed feedback never chooses the rating for the user")
  assert_true(flashcards.close_review(), "the typed-answer review closes cleanly")

  local entries, history_errors = history.read(config)
  assert_equal(#history_errors, 0, "typed-answer review history remains readable")
  local encoded = vim.json.encode(entries)
  assert_true(not encoded:find("とうきょ", 1, true), "typed answer text is not stored in review history")
  assert_true(not encoded:find("typed_answer", 1, true), "typed comparison details remain session-local")

  vim.cmd("silent! bwipeout!")
  T.setup(T.config)
  assert_true(flashcards.overview({ view = "overview", reset_browser = true }), "the shared hub state is restored")
  overview.close()
  vim.fn.delete(test_root, "rf")
end
