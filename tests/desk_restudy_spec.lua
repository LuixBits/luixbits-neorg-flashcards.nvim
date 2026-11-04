return function(T)
  local flashcards = require("neorg_flashcards")
  local overview = require("neorg_flashcards.overview")
  local review = require("neorg_flashcards.review")
  local parser = require("neorg_flashcards.parser")
  local chapters = require("neorg_flashcards.chapters")
  local presets = require("neorg_flashcards.presets")
  local equal, truth, contains = T.assert_equal, T.assert_true, T.assert_contains
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  local lines = {}
  local fixtures = {
    { "Future A", "2999-01-01 00:00", "active", "focus" },
    { "Future B", "2999-01-02 00:00", "active", "focus" },
    { "Suspended", "2020-01-01 00:00", "suspended", "focus" },
    { "Buried", "2020-01-01 00:00", "buried", "focus" },
    { "Due", "2020-01-01 00:00", "active", "mixed" },
    { "Mixed future", "2999-01-01 00:00", "active", "mixed" },
    { "Outside", "2020-01-01 00:00", "active", "other" },
    { "Inactive", "2020-01-01 00:00", "suspended", "inactive" },
  }
  for index, fixture in ipairs(fixtures) do
    vim.list_extend(lines, {
      "@flashcard japanese",
      "id: fc_restudy_" .. index,
      "japanese: " .. fixture[1],
      "english: " .. fixture[1],
      "due: " .. fixture[2],
      "availability: " .. fixture[3],
      "tags: " .. fixture[4],
      "@end",
    })
    if fixture[3] == "buried" then
      table.insert(lines, #lines, "available_at: 2999-01-01 00:00")
    end
  end
  local source = root .. "/cards.norg"
  vim.fn.writefile(lines, source)
  truth(
    T.setup({ path = root, default_card_type = "japanese", schemas = presets.only("japanese"), ui = { motion = false } })
  )
  local config = flashcards.active_collection()
  local cards, errors = parser.collect_flashcards(config)
  equal(#errors, 0, "all restudy fixtures are valid")
  truth(chapters.create(config, "A Future", { cards[1], cards[2], cards[3], cards[4] }))
  truth(chapters.create(config, "B Mixed", { cards[5], cards[6] }))
  truth(chapters.create(config, "C Empty", {}))
  truth(chapters.create(config, "D Inactive", { cards[8] }))
  flashcards.overview({ view = "desk", reset_browser = true })
  local function key(lhs)
    for _, binding in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
      if binding.lhs == lhs then
        binding.callback()
        return
      end
    end
    error("missing binding " .. lhs)
  end
  key("<CR>") -- Open the collection at All due.
  key("l") -- A Future.
  contains(T.current_tab_text(), "Enter to study again", "caught-up stacks explain manual practice")
  key("<CR>")
  truth(review.is_active(), "Enter starts a chapter with no due cards")
  equal(flashcards.get_review_state().label, "chapter: A Future")
  equal(flashcards.get_review_state().original, 2, "only active cards in the hovered chapter are included")
  contains(T.current_tab_text(), "Future A")
  review.next()
  contains(T.current_tab_text(), "Future B")
  flashcards.close_review()
  truth(vim.deep_equal(vim.fn.readfile(source), lines), "starting and leaving practice does not reschedule cards")

  key("l") -- B Mixed.
  key("<CR>")
  equal(flashcards.get_review_state().original, 1, "a stack with due cards still prioritizes those cards")
  contains(T.current_tab_text(), "Due")
  flashcards.close_review()
  key("l") -- C Empty.
  key("<CR>")
  truth(not review.is_active(), "empty chapters do not start an empty session")
  key("l") -- D Inactive.
  key("<CR>")
  truth(not review.is_active(), "suspended-only chapters stay unavailable")

  key("g") -- Switch to tags and reset to the collection box.
  key("<CR>")
  key("l") -- focus.
  key("<CR>")
  truth(review.is_active(), "Enter also restudies a caught-up tag stack")
  equal(flashcards.get_review_state().label, "tag:focus")
  equal(flashcards.get_review_state().original, 2)
  flashcards.close_review()
  key("d")
  equal(flashcards.get_review_state().label, "due")
  equal(flashcards.get_review_state().original, 2, "the due shortcut still excludes future and unavailable cards")
  contains(T.current_tab_text(), "Due")
  review.next()
  contains(T.current_tab_text(), "Outside")
  flashcards.close_review()

  -- Once the entire collection is caught up, Enter can also reopen All due
  -- as an explicit practice stack, while the due shortcut remains empty.
  local future_lines = vim.tbl_map(function(line)
    return line:gsub("due: 2020%-01%-01 00:00", "due: 2999-01-01 00:00")
  end, lines)
  vim.fn.writefile(future_lines, source)
  flashcards.overview({ view = "desk", reset_browser = true })
  key("<CR>")
  key("<CR>")
  equal(flashcards.get_review_state().label, "all")
  equal(flashcards.get_review_state().original, 5, "caught-up collection practice includes only active cards")
  flashcards.close_review()
  key("d")
  truth(not review.is_active(), "an explicit due review stays empty when nothing is due")
  overview.close()
  T.setup(T.config)
  vim.fn.delete(root, "rf")
end
