return function(T)
  local identity = require("neorg_flashcards.identity")
  local parser = require("neorg_flashcards.parser")
  local presets = require("neorg_flashcards.presets")
  local schema = require("neorg_flashcards.schema")
  local actions = require("neorg_flashcards.ui.actions")
  local flashcards = require("neorg_flashcards")

  local assert_true = T.assert_true
  local assert_equal = T.assert_equal
  local assert_contains = T.assert_contains
  local canonical_path = T.canonical_path
  local current_popup = T.current_popup
  local assert_buffer_maps = T.assert_buffer_maps

  local test_root = vim.fn.tempname()
  local config = {
    flashcards_dir = test_root .. "/flashcards",
    default_file = test_root .. "/flashcards/inbox/cards.norg",
    default_kind = "japanese",
    schemas = presets.only("japanese", "chinese"),
  }

  flashcards.setup(config)

  local function highlight_link(name)
    return vim.api.nvim_get_hl(0, { name = name, link = true }).link
  end
  assert_equal(highlight_link("NeorgFlashcardsAgain"), "DiagnosticError", "Again has a safe default highlight")
  assert_equal(highlight_link("NeorgFlashcardsHard"), "DiagnosticWarn", "Hard has a safe default highlight")
  assert_equal(highlight_link("NeorgFlashcardsGood"), "DiagnosticOk", "Good has a safe default highlight")
  local highlighted_config = vim.tbl_deep_extend("force", vim.deepcopy(config), {
    ui = { rating_highlights = { hard = { link = "Special" } } },
  })
  flashcards.setup(highlighted_config)
  assert_equal(highlight_link("NeorgFlashcardsHard"), "Special", "rating highlight overrides are applied")
  assert_equal(
    highlight_link("NeorgFlashcardsAgain"),
    "DiagnosticError",
    "partial highlight overrides keep default links"
  )
  local exact_color_config = vim.tbl_deep_extend("force", vim.deepcopy(config), {
    ui = { rating_highlights = { again = { fg = "#ff5f5f", bold = true } } },
  })
  flashcards.setup(exact_color_config)
  local exact_again = vim.api.nvim_get_hl(0, { name = "NeorgFlashcardsAgain" })
  assert_equal(exact_again.fg, tonumber("ff5f5f", 16), "exact rating colors can override a theme")
  assert_true(exact_again.bold, "exact rating color attributes are applied")
  vim.api.nvim_exec_autocmds("ColorScheme", {})
  exact_again = vim.api.nvim_get_hl(0, { name = "NeorgFlashcardsAgain" })
  assert_equal(exact_again.fg, tonumber("ff5f5f", 16), "rating overrides survive colorscheme reloads")
  flashcards.setup(config)

  assert_equal(vim.fn.exists(":Flashcards"), 2, "Flashcards is registered")
  for _, command in ipairs({
    "NeorgFlashcardOpen",
    "NeorgFlashcardAdd",
    "NeorgFlashcardAddJapanese",
    "NeorgFlashcardInsertJapanese",
    "NeorgFlashcardHelp",
    "NeorgFlashcardReview",
    "NeorgFlashcardReviewDue",
    "NeorgFlashcardReviewFile",
    "NeorgFlashcardReviewTag",
    "NeorgFlashcardReviewScore",
    "NeorgFlashcardOverview",
    "NeorgFlashcardStats",
    "NeorgFlashcardValidate",
  }) do
    assert_equal(vim.fn.exists(":" .. command), 0, command .. " is no longer registered")
  end
  assert_equal(vim.fn.maparg("<leader>ncr", "n"), "", "setup does not create global keymaps")

  do
    local actions = require("neorg_flashcards.ui.actions")
    local cards_footer = actions.footer("cards", 80, { suspend = true, bury = true })
    assert_contains(cards_footer, "? keys", "Cards footer keeps contextual help visible")
    local narrow_footer = actions.footer("cards", 38, { suspend = true, bury = true })
    assert_true(vim.fn.strdisplaywidth(narrow_footer) <= 38, "compact shortcut hints fit the narrowest pane")
    assert_contains(narrow_footer, "? keys", "narrow shortcut hints retain help")
    assert_contains(narrow_footer, "j/k navigate", "narrow Cards hints retain focused-pane navigation")
    local narrow_stats_footer = actions.footer("stats", 38, {})
    assert_true(vim.fn.strdisplaywidth(narrow_stats_footer) <= 38, "Stats shortcut hints fit the narrowest pane")
    assert_contains(narrow_stats_footer, "j/k scroll", "narrow Stats hints explain how to scroll")
    local delete_footer = actions.footer("cards", 54, { delete = true })
    assert_contains(delete_footer, "D delete", "standard Cards ribbon exposes confirmed deletion")
    local delete_help = table.concat(actions.help_lines("cards", { delete = true }), "\n")
    assert_contains(delete_help, "D", "Cards help shows the deletion key")
    assert_contains(delete_help, "Delete the selected card after confirmation", "Cards help explains safe deletion")
    local stats_help = table.concat(actions.help_lines("stats", {}), "\n")
    assert_contains(stats_help, "Ctrl-D / PageDown", "Stats help exposes half-page scrolling")
    assert_contains(stats_help, "gg", "Stats help exposes top navigation")
    assert_contains(stats_help, "G", "Stats help exposes bottom navigation")
    local hub_keys = {}
    for _, binding in ipairs(actions.available_bindings("hub", { suspend = true, bury = true, delete = true })) do
      hub_keys[binding.key] = true
    end
    for _, key in ipairs({ "<C-d>", "<C-u>", "<PageDown>", "<PageUp>", "<C-w>w", "gg", "G" }) do
      assert_true(hub_keys[key], "hub scrolling mapping is registered: " .. key)
    end
    assert_true(hub_keys.D, "Cards deletion mapping is registered when supported")
  end

  vim.cmd("Flashcards help")
  local help_popup, help_text = current_popup()
  assert_contains(help_text, "Files: .norg (Neorg itself is optional)", "help explains the file and Neorg relationship")
  assert_buffer_maps(help_popup, { "q" })
  require("neorg_flashcards.help").close()
  assert_true(not vim.api.nvim_buf_is_valid(help_popup), "closing help wipes its scratch buffer")

  vim.cmd("Flashcards open")
  assert_equal(
    canonical_path(vim.api.nvim_buf_get_name(0)),
    canonical_path(config.default_file),
    "open command selects the configured default file"
  )
  assert_equal(vim.fn.filereadable(config.default_file), 1, "open command creates nested default-file directories")
  assert_contains(
    table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"),
    "* Flashcards",
    "new default file has a heading"
  )
  vim.cmd("silent! bwipeout!")

  local japanese_lines = {
    "@flashcard japanese",
    "id: fc_japanese_study",
    "japanese: 勉強",
    "reading: べんきょう",
    "english: study",
    "tags: jlpt vocab",
    "@end",
  }

  local japanese_cards = parser.parse_lines(japanese_lines, "japanese.norg")
  assert_equal(#japanese_cards, 1, "parses one Japanese card")

  local valid_japanese, japanese_errors = parser.valid_cards(config, japanese_cards)
  assert_equal(#japanese_errors, 0, "Japanese card validates")
  assert_equal(#valid_japanese, 1, "Japanese card is valid")

  local front_title, front_value = schema.front(config, valid_japanese[1])
  assert_equal(front_title, "Japanese", "Japanese front title")
  assert_equal(front_value, "勉強", "Japanese front value")

  local chinese_lines = {
    "@flashcard chinese",
    "id: fc_chinese_study",
    "chinese: 学习",
    "pinyin: xuexi",
    "english: study",
    "@end",
  }

  local chinese_cards = parser.parse_lines(chinese_lines, "chinese.norg")
  local valid_chinese, chinese_errors = parser.valid_cards(config, chinese_cards)
  assert_equal(#chinese_errors, 0, "Chinese card validates")
  assert_equal(#valid_chinese, 1, "Chinese card is valid")

  front_title, front_value = schema.front(config, valid_chinese[1])
  assert_equal(front_title, "Chinese", "Chinese front title")
  assert_equal(front_value, "学习", "Chinese front value")

  local reveal = schema.reveal_fields(config, valid_chinese[1])
  assert_equal(reveal[1].title, "Pinyin", "Chinese pinyin is revealed first")
  assert_equal(reveal[2].title, "English", "Chinese English is revealed")

  local japanese_fields = schema.composer_fields(config, "japanese")
  assert_equal(japanese_fields[1].title, "Japanese", "composer schema exposes the field title")
  assert_equal(japanese_fields[1].placeholder, "e.g. 猫", "composer schema exposes field placeholders")
  assert_contains(japanese_fields[1].help, "written in Japanese", "composer schema exposes field help")

  do
    local created_lines = schema.card_lines(config, "japanese", {
      japanese = "新しい",
      reading = "あたらしい",
      english = "new",
    })
    local created_card = parser.parse_lines(created_lines, "created.norg")[1]
    assert_true(created_card.id ~= nil, "new card blocks receive a stable ID")
    assert_true(identity.is_valid(created_card.id), "generated card IDs satisfy the public ID contract")
    assert_equal(schema.card_id(created_card), created_card.id, "schema and parser expose the same stable card ID")
  end

  local unsupported_cards = parser.parse_lines(japanese_lines, "unsupported.norg")
  local valid_unsupported, unsupported_errors = parser.valid_cards({ schemas = {} }, unsupported_cards)
  assert_equal(#valid_unsupported, 0, "unsupported language is invalid")
  assert_contains(unsupported_errors[1], "unsupported flashcard kind", "unsupported error is explicit")

  local again_filter = schema.score_filter("again")
  assert_true(again_filter ~= nil, "Again score filter exists")
  assert_true(again_filter.matches({ values = { score = "1" } }), "Again matches score 1")
  assert_true(not again_filter.matches({ values = { score = "2" } }), "Again rejects score 2")
  assert_equal(schema.score_filter("2").label, "hard", "numeric score 2 resolves to Hard")
  assert_equal(schema.score_filter("good").label, "good", "Good is the canonical score 3 label")
  local review_stats = schema.review_stats({
    { values = {} },
    { values = { score = "1" } },
    { values = { score = "2" } },
    { values = { score = "3" } },
  })
  assert_equal(review_stats.new, 1, "review stats count new cards")
  assert_equal(review_stats.again, 1, "review stats use the Again label")
  assert_equal(review_stats.hard, 1, "review stats use the Hard label")
  assert_equal(review_stats.good, 1, "review stats use the Good label")

  do
    local duplicate_card = parser.parse_lines({
      "@flashcard japanese",
      "id: fc_duplicate_field",
      "japanese: 重複",
      "english: first",
      "english: second",
      "@end",
    }, "duplicate-field.norg")[1]
    local duplicate_valid, duplicate_errors = parser.valid_cards(config, { duplicate_card })
    assert_equal(#duplicate_valid, 0, "cards with duplicate fields are quarantined")
    assert_contains(duplicate_errors[1], "duplicate field: english", "duplicate field validation names the field")
  end

  do
    local non_table_ok, non_table_error = pcall(flashcards.setup, "not a table")
    assert_true(not non_table_ok, "setup rejects non-table options")
    assert_contains(non_table_error, "options must be a table", "non-table setup errors are explicit")

    local function rejected_setup(overrides, expected)
      local candidate = vim.deepcopy(config)
      for key, value in pairs(overrides) do
        candidate[key] = vim.deepcopy(value)
      end
      local ok, err = pcall(flashcards.setup, candidate)
      assert_true(not ok, "setup rejects " .. expected)
      assert_contains(err, expected, "setup explains the invalid configuration")
    end

    rejected_setup({ default_file = test_root .. "/outside.norg" }, "default_file must be inside flashcards_dir")
    rejected_setup(
      { history_file = test_root .. "/outside.jsonl" },
      "review history destination must be inside flashcards_dir"
    )
    rejected_setup(
      { history_file = config.default_file },
      "review history destination must be a .jsonl file separate from card sources"
    )
    rejected_setup(
      { history_file = config.flashcards_dir .. "/history.txt" },
      "review history destination must be a .jsonl file separate from card sources"
    )
    local linked_history = config.flashcards_dir .. "/reviews-link.jsonl"
    local linked, link_error = (vim.uv or vim.loop).fs_symlink(config.default_file, linked_history)
    assert_true(linked, "history collision symlink is created: " .. tostring(link_error))
    rejected_setup(
      { history_file = linked_history },
      "review history destination must be a .jsonl file separate from card sources"
    )
    local default_collision_root = test_root .. "/default-history-collision"
    local default_collision_cards = default_collision_root .. "/cards.norg"
    vim.fn.mkdir(default_collision_root, "p")
    vim.fn.writefile({ "* cards" }, default_collision_cards)
    local default_linked, default_link_error = (vim.uv or vim.loop).fs_symlink(
      default_collision_cards,
      default_collision_root .. "/reviews.jsonl"
    )
    assert_true(default_linked, "default history collision symlink is created: " .. tostring(default_link_error))
    rejected_setup({
      flashcards_dir = default_collision_root,
      default_file = default_collision_cards,
    }, "review history destination must be a .jsonl file separate from card sources")
    local hardlink_root = test_root .. "/hardlink-history-collision"
    local hardlink_cards = hardlink_root .. "/cards.norg"
    vim.fn.mkdir(hardlink_root, "p")
    vim.fn.writefile({ "* cards" }, hardlink_cards)
    local hardlinked, hardlink_error = (vim.uv or vim.loop).fs_link(hardlink_cards, hardlink_root .. "/reviews.jsonl")
    assert_true(hardlinked, "history collision hard link is created: " .. tostring(hardlink_error))
    rejected_setup({
      flashcards_dir = hardlink_root,
      default_file = hardlink_cards,
    }, "review history destination must be separate from default_file")
    rejected_setup({ default_file = 42 }, "default_file must be a string")
    rejected_setup({ history_file = false }, "history_file must be a string")
    rejected_setup({ schemas = {} }, "at least one card schema is required")
    rejected_setup({ default_kind = "missing" }, "default_kind does not name a configured schema")
    rejected_setup({ scheduling = { hard_hours = 0 } }, "scheduling.hard_hours must be a positive finite number")
    rejected_setup({ leech_threshold = 1.5 }, "leech_threshold must be a positive integer")
    rejected_setup({ schedulng = {} }, "unknown setup option: schedulng")
    rejected_setup({ on_review = true }, "on_review must be a function")
    rejected_setup({ on_edit = function() end }, "unknown setup option: on_edit")

    local misspelled_scheduling = vim.deepcopy(config)
    misspelled_scheduling.scheduling = { hard_hors = 6 }
    rejected_setup({ scheduling = misspelled_scheduling.scheduling }, "unknown scheduling option: hard_hors")

    local malformed_schema = vim.deepcopy(config.schemas.japanese)
    malformed_schema.front = "missing"
    malformed_schema.fields[1].key = "score"
    rejected_setup({ schemas = { japanese = malformed_schema } }, "reserved by the scheduler")

    local removed_form_option = vim.deepcopy(config.schemas.japanese)
    removed_form_option.fields[1].prompt = false
    rejected_setup({ schemas = { japanese = removed_form_option } }, "contains a removed composer option")

    local misspelled_field_option = vim.deepcopy(config.schemas.japanese)
    misspelled_field_option.fields[1].placehoder = "typo"
    rejected_setup({ schemas = { japanese = misspelled_field_option } }, "unknown japanese field japanese option")

    local original_cwd = vim.fn.getcwd()
    local absolute_relative_root = test_root .. "/relative-collection"
    local relative_root = vim.fn.fnamemodify(absolute_relative_root, ":.")
    local relative_ok, relative_error = pcall(function()
      flashcards.setup({
        flashcards_dir = relative_root,
        default_file = relative_root .. "/cards.norg",
        default_kind = "japanese",
        schemas = presets.only("japanese"),
      })
      vim.cmd("cd /")
      vim.cmd("Flashcards open")
      assert_equal(
        canonical_path(vim.api.nvim_buf_get_name(0)),
        canonical_path(absolute_relative_root .. "/cards.norg"),
        "setup freezes relative paths before the working directory changes"
      )
      vim.cmd("silent! bwipeout!")
    end)
    vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
    assert_true(relative_ok, "relative path setup remains stable after :cd: " .. tostring(relative_error))
    flashcards.setup(config)
  end

  T.test_root = test_root
  T.config = config
end
