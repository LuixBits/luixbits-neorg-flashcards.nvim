return function(T)
  local form = require("neorg_flashcards.form")
  local help = require("neorg_flashcards.help")
  local overview = require("neorg_flashcards.overview")
  local parser = require("neorg_flashcards.parser")
  local presets = require("neorg_flashcards.presets")
  local flashcards = require("neorg_flashcards")

  local assert_true = T.assert_true
  local assert_equal = T.assert_equal
  local assert_contains = T.assert_contains

  local contract_root = vim.fn.tempname()
  local contract_config = {
    flashcards_dir = contract_root .. "/cards",
    default_file = contract_root .. "/cards/inbox.norg",
    default_kind = "japanese",
    schemas = presets.only("japanese"),
  }
  assert_true(flashcards.setup(contract_config), "setup returns true after applying a valid configuration")

  assert_true(flashcards.help(), "help reports that its popup opened")
  help.close()
  assert_true(flashcards.overview(), "overview reports that its hub opened")
  assert_equal(overview.current_view(), "overview", "overview opens the requested hub page")
  overview.close()
  assert_true(flashcards.cards(), "cards reports that its hub page opened")
  assert_equal(overview.current_view(), "cards", "cards selects the Cards page")
  overview.close()
  assert_true(flashcards.stats(), "stats reports that its hub page opened")
  assert_equal(overview.current_view(), "stats", "stats selects the Stats page")
  overview.show("overview")
  overview.close()

  assert_true(flashcards.open_flashcards(), "open_flashcards reports that it selected the default file")
  assert_true(flashcards.add_kind("japanese"), "add_kind returns the form-open result")
  assert_true(form.is_open(), "a successful add_kind result corresponds to an open form")
  assert_true(form.close({ force = true }), "the add_kind fixture closes cleanly")
  assert_true(flashcards.add_to_default("japanese"), "add_to_default returns the form-open result")
  assert_true(form.is_open(), "a successful add_to_default result corresponds to an open form")
  assert_true(form.close({ force = true }), "the add_to_default fixture closes cleanly")
  vim.cmd.enew()
  assert_equal(vim.api.nvim_buf_get_name(0), "", "the default-target fixture starts outside a named file")
  assert_true(flashcards.add_kind("japanese"), "add_kind falls back from a non-file buffer")
  assert_true(form.close({ force = true }), "the fallback add fixture closes cleanly")
  assert_equal(
    vim.fs.normalize(vim.api.nvim_buf_get_name(0)),
    vim.fs.normalize(contract_config.default_file),
    "add_kind targets default_file outside a collection buffer"
  )
  assert_true(flashcards.command("add japanese"), "command returns the routed form-open result")
  assert_true(form.close({ force = true }), "the command add fixture closes cleanly")
  assert_true(not flashcards.add_kind("missing"), "an unsupported add kind returns false")

  local card_path = contract_config.flashcards_dir .. "/contract.norg"
  vim.fn.writefile({
    "@flashcard japanese",
    "id: fc_api_contract",
    "japanese: 契約",
    "reading: けいやく",
    "english: contract",
    "tags: api",
    "@end",
  }, card_path)
  vim.cmd.edit(vim.fn.fnameescape(card_path))

  local valid, cards, errors = flashcards.validate_file()
  assert_true(valid, "validate_file returns its validation status")
  assert_equal(#cards, 1, "validate_file returns the valid cards it computed")
  assert_equal(#errors, 0, "validate_file returns its diagnostics")

  assert_true(flashcards.review_file(), "review_file reports that a session opened")
  local invalid_ok, invalid_message, invalid_persisted = flashcards.rate_current(4)
  assert_true(not invalid_ok, "rate_current returns false for an invalid rating")
  assert_contains(invalid_message, "Rating must be 1, 2, or 3", "invalid ratings return a useful message")
  assert_equal(invalid_persisted, false, "invalid ratings explicitly return persisted=false")
  assert_true(flashcards.flip_or_next(), "flip_or_next reports a successful reveal")
  assert_true(not flashcards.flip_or_next(), "flip_or_next reports a rejected second reveal")
  assert_true(flashcards.next_card(), "next_card reports successful navigation")
  assert_true(flashcards.previous_card(), "previous_card reports successful navigation")
  assert_true(flashcards.hint_current(), "hint_current reports a revealed hint")

  local answer_callback
  local input_original = vim.ui.input
  vim.ui.input = function(_, callback)
    answer_callback = callback
  end
  assert_true(flashcards.type_answer(), "type_answer returns true when its prompt is launched")
  vim.ui.input = input_original
  assert_true(type(answer_callback) == "function", "type_answer launches an asynchronous input callback")

  local rated, rate_message, rate_persisted = flashcards.rate_current(3)
  assert_true(rated, "rate_current returns mutation success")
  assert_equal(rate_message, nil, "a durable rating without a warning has no mutation message")
  assert_true(rate_persisted, "rate_current reports a durable clean-buffer write")

  local undo_ok, undo_message, undo_persisted = flashcards.undo_last_rating()
  assert_true(undo_ok, "undo_last_rating returns mutation success")
  assert_equal(undo_message, nil, "a durable undo without a warning has no mutation message")
  assert_true(undo_persisted, "undo_last_rating reports a durable clean-buffer write")
  assert_true(flashcards.close_review(), "close_review reports that it closed an active session")
  assert_true(not flashcards.close_review(), "close_review returns false when no session is active")

  local missing_ok, missing_message, missing_persisted = flashcards.rate_current(3)
  assert_true(not missing_ok, "rate_current rejects a missing review session")
  assert_contains(missing_message, "No active review", "failed ratings return a useful message")
  assert_equal(missing_persisted, false, "failed ratings explicitly return persisted=false")
  local inactive_ok, inactive_message, inactive_persisted = flashcards.suspend_current()
  assert_true(not inactive_ok, "review mutations reject a missing session")
  assert_contains(inactive_message, "No active review", "failed review mutations return a useful message")
  assert_equal(inactive_persisted, false, "failed review mutations explicitly return persisted=false")

  local bury_ok, bury_message, bury_persisted = flashcards.bury_card(nil)
  assert_true(not bury_ok, "card mutations reject a missing card")
  assert_contains(bury_message, "No flashcard selected", "failed card mutations return a useful message")
  assert_equal(bury_persisted, false, "failed card mutations explicitly return persisted=false")
  local toggle_ok, toggle_message, toggle_persisted = flashcards.toggle_suspend(nil)
  assert_true(not toggle_ok, "toggle mutations reject a missing card")
  assert_contains(toggle_message, "No flashcard selected", "failed toggle mutations return a useful message")
  assert_equal(toggle_persisted, false, "failed toggle mutations explicitly return persisted=false")

  vim.api.nvim_buf_set_lines(0, 0, 0, false, { "* Unsaved note" })
  assert_true(vim.bo.modified, "the unpersisted rating fixture starts with a modified source")
  assert_true(flashcards.review_file(), "a modified source can start a review session")
  local buffered_ok, buffered_message, buffered_persisted = flashcards.rate_current(2)
  assert_true(buffered_ok, "rate_current accepts an in-memory source mutation")
  assert_contains(buffered_message, "write the file", "in-memory ratings explain how to persist them")
  assert_equal(buffered_persisted, false, "in-memory ratings explicitly return persisted=false")
  local buffered_undo_ok, buffered_undo_message, buffered_undo_persisted = flashcards.undo_last_rating()
  assert_true(buffered_undo_ok, "undo accepts an in-memory source mutation")
  assert_contains(buffered_undo_message, "write the file", "in-memory undo explains how to persist it")
  assert_equal(buffered_undo_persisted, false, "in-memory undo explicitly returns persisted=false")
  assert_true(flashcards.close_review(), "the modified-buffer review closes cleanly")
  vim.cmd("edit!")

  assert_true(flashcards.review_file(), "the card can start another review session")
  local suspend_ok, suspend_message, suspend_persisted = flashcards.suspend_current()
  assert_true(suspend_ok, "suspend_current returns mutation success")
  assert_equal(suspend_message, nil, "a durable suspension without a warning has no mutation message")
  assert_true(suspend_persisted, "suspend_current reports a durable clean-buffer write")
  assert_true(flashcards.close_review(), "the completed suspension session still closes explicitly")

  local suspended_card = parser.parse_buffer(0)[1]
  local resume_ok, resume_message, resume_persisted = flashcards.toggle_suspend(suspended_card)
  assert_true(resume_ok, "toggle_suspend returns mutation success")
  assert_equal(resume_message, nil, "a durable resume without a warning has no mutation message")
  assert_true(resume_persisted, "toggle_suspend reports a durable clean-buffer write")

  local prompt_callback
  input_original = vim.ui.input
  vim.ui.input = function(_, callback)
    prompt_callback = callback
  end
  assert_true(flashcards.review_tag(""), "review_tag returns true when its prompt is launched")
  assert_true(type(prompt_callback) == "function", "review_tag exposes completion through its callback")
  prompt_callback(nil)
  prompt_callback = nil
  assert_true(flashcards.command("review score"), "command returns asynchronous prompt initiation")
  assert_true(type(prompt_callback) == "function", "command preserves the routed prompt callback")
  prompt_callback(nil)
  vim.ui.input = input_original

  assert_true(flashcards.command("help"), "command returns the routed UI result")
  help.close()
  local history_path = contract_config.flashcards_dir .. "/reviews.jsonl"
  assert_equal(vim.fn.writefile({ "{not valid json" }, history_path, "a"), 0, "the history diagnostic fixture writes")
  local healthy, collection_cards, issues, diagnostics = flashcards.command("check")
  assert_true(healthy, "command returns the routed validation status")
  assert_true(type(collection_cards) == "table", "command preserves additional routed query values")
  assert_true(type(issues) == "table", "command preserves all routed query values")
  assert_true(type(diagnostics) == "table", "validation queries keep a stable result shape")
  assert_true(#diagnostics > 0, "collection validation returns history diagnostics")
  assert_contains(diagnostics[#diagnostics], "invalid JSON", "history diagnostics remain useful to Lua callers")
  vim.cmd("silent! cclose")
  vim.cmd.edit(vim.fn.fnameescape(card_path))
  assert_true(not flashcards.command("review missing"), "an unknown review scope returns false")
  assert_true(not flashcards.command("missing"), "an unknown command route returns false")

  assert_true(flashcards.review_file(), "edit_current_card has an active review fixture")
  assert_true(flashcards.edit_current_card(), "edit_current_card returns the composer-open result")
  assert_true(form.is_open(), "a successful edit_current_card result corresponds to an open form")
  assert_true(form.close({ force = true }), "the edit fixture closes cleanly")

  vim.cmd.edit(vim.fn.fnameescape(contract_config.default_file))
  local empty_ok, empty_cards, empty_errors = flashcards.validate_file()
  assert_true(not empty_ok, "validate_file returns false when no cards are present")
  assert_equal(#empty_cards, 0, "empty validation returns an empty card result")
  assert_equal(#empty_errors, 1, "empty validation returns its diagnostic")

  vim.cmd("silent! bwipeout!")
  overview.close()
  help.close()
  vim.fn.delete(contract_root, "rf")
  assert_true(flashcards.setup(T.config), "the shared test configuration is restored")
end
