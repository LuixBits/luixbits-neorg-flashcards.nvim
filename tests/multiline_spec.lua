return function(T)
  local highlights = require("neorg_flashcards.highlights")
  local parser = require("neorg_flashcards.parser")
  local presets = require("neorg_flashcards.presets")
  local schedule = require("neorg_flashcards.schedule")
  local schema = require("neorg_flashcards.schema")
  local store = require("neorg_flashcards.store")

  local assert_true = T.assert_true
  local assert_equal = T.assert_equal
  local assert_contains = T.assert_contains

  local test_root = vim.fn.tempname()
  vim.fn.mkdir(test_root, "p")
  local config = {
    path = test_root,
    default_file = test_root .. "/cards.norg",
    default_card_type = "question_answer",
    schemas = presets.only(
      "question_answer",
      "term_definition",
      "code_output",
      "japanese",
      "japanese_production",
      "japanese_kanji",
      "japanese_sentence",
      "chinese"
    ),
    scheduling = vim.deepcopy(schedule.DEFAULTS),
    history_file = test_root .. "/reviews.jsonl",
    leech_threshold = 8,
    ui = vim.tbl_deep_extend("force", { show_shortcuts = true }, vim.deepcopy(highlights.defaults)),
  }

  local config_errors = schema.validate_collection(config)
  assert_equal(#config_errors, 0, "all bundled card types satisfy the schema contract")

  local question_fields = schema.composer_fields(config, "question_answer")
  assert_true(question_fields[1].multiline, "question-and-answer questions allow long text")
  assert_true(question_fields[2].multiline, "question-and-answer answers allow long text")
  assert_true(not question_fields[2].typed_answer, "long generic answers do not promise typed checking")

  local japanese_fields = schema.composer_fields(config, "japanese")
  assert_true(japanese_fields[2].typed_answer, "Japanese readings opt into typed answers")
  assert_true(japanese_fields[3].typed_answer, "Japanese meanings opt into typed answers")
  assert_true(japanese_fields[4].multiline, "Japanese notes allow long context")

  local kanji_fields = schema.composer_fields(config, "japanese_kanji")
  assert_true(not kanji_fields[2].typed_answer, "kanji reading lists do not pretend to be one exact answer")
  assert_true(not kanji_fields[3].typed_answer, "kanji meaning lists stay reveal-only")
  local sentence_fields = schema.composer_fields(config, "japanese_sentence")
  assert_true(not sentence_fields[3].typed_answer, "long sentence translations stay reveal-only")

  local known_presets, unknown_error = pcall(presets.only, "japanese", "definitely_missing")
  assert_true(not known_presets, "a misspelled preset fails instead of silently disappearing")
  assert_contains(unknown_error, "unknown flashcard preset: definitely_missing", "preset errors name the typo")

  for _, kind in ipairs({
    "question_answer",
    "term_definition",
    "code_output",
    "japanese",
    "japanese_production",
    "japanese_kanji",
    "japanese_sentence",
    "chinese",
  }) do
    assert_true(config.schemas[kind] ~= nil, "bundled preset is available: " .. kind)
  end

  local block_lines = {
    "@flashcard question_answer",
    "id: fc_multiline_parse",
    "question: Why keep an explicit block marker?",
    "answer: |",
    "  First line.",
    "    Two value spaces survive.",
    "  field: this remains answer text",
    "  @end",
    "  ",
    "  Last line.",
    "notes: short note",
    "tags: parser syntax",
    "@end",
  }
  local block_card = parser.parse_lines(block_lines, "multiline.norg")[1]
  assert_true(block_card.closed, "an indented @end remains block content")
  assert_equal(block_card.end_line, #block_lines, "only the outer @end closes the card")
  assert_equal(
    block_card.values.answer,
    "First line.\n  Two value spaces survive.\nfield: this remains answer text\n@end\n\nLast line.",
    "the parser strips only the two-space block container"
  )
  assert_true(block_card.multiline_fields.answer, "the parser records explicit block fields")
  local valid_block, block_errors = parser.valid_cards(config, { block_card })
  assert_equal(#block_errors, 0, "a declared multiline field validates")
  assert_equal(#valid_block, 1, "the explicit multiline card remains reviewable")

  local front_title, front_value = schema.front(config, block_card)
  assert_equal(front_title, "Question", "generic cards use their declared front title")
  assert_equal(front_value, "Why keep an explicit block marker?", "generic cards expose their declared front")
  local revealed = schema.reveal_fields(config, block_card)
  assert_equal(revealed[1].value, block_card.values.answer, "revealed fields retain multiline content")

  local indented_lines = {
    "  @flashcard question_answer",
    "  id: fc_multiline_indented",
    "  question: Can a card live below an indented Neorg node?",
    "  answer: |",
    "    Yes.",
    "      Value indentation survives.",
    "    @end",
    "  tags: parser syntax",
    "  @end",
  }
  local indented_card = parser.parse_lines(indented_lines, "indented.norg")[1]
  assert_true(indented_card.closed, "an indented card closes at its own directive indentation")
  assert_equal(indented_card.indent, "  ", "the parser remembers the card's source indentation")
  assert_equal(
    indented_card.values.answer,
    "Yes.\n  Value indentation survives.\n@end",
    "block content stays relative to an indented card"
  )
  assert_equal(indented_card.values.tags, "parser syntax", "fields align with the indented card directive")

  local literal_pipe = parser.parse_lines({
    "@flashcard question_answer",
    "id: fc_literal_pipe",
    "question: What is the symbol?",
    "answer: |",
    "  |",
    "@end",
  }, "literal-pipe.norg")[1]
  assert_equal(literal_pipe.values.answer, "|", "a literal pipe has an unambiguous block representation")

  local generated = schema.card_lines(config, "question_answer", {
    id = "fc_multiline_generated",
    question = "Why two spaces?",
    answer = "line one\n  nested indentation\nkey: still content\n@end\n",
    tags = "format",
  })
  assert_contains(
    table.concat(generated, "\n"),
    "answer: |\n  line one\n    nested indentation\n  key: still content\n  @end\n  \ntags: format",
    "serialization uses a two-space container for every block line"
  )
  local generated_card = parser.parse_lines(generated, "generated.norg")[1]
  assert_equal(
    generated_card.values.answer,
    "line one\n  nested indentation\nkey: still content\n@end\n",
    "multiline serialization round trips without changing value indentation"
  )

  local scalar = schema.card_lines(config, "term_definition", {
    id = "fc_scalar_unchanged",
    term = "idempotent",
    definition = "Applying it twice has the same effect.",
  })
  assert_contains(
    table.concat(scalar, "\n"),
    "definition: Applying it twice has the same effect.",
    "single-line values keep the scalar card syntax"
  )
  assert_true(
    not table.concat(scalar, "\n"):find("definition: |", 1, true),
    "scalar syntax does not gain a block marker"
  )

  local indented_path = test_root .. "/indented.norg"
  vim.fn.writefile(indented_lines, indented_path)
  local stored_indented = parser.parse_file(indented_path)[1]
  local indented_ok, indented_message = store.set_card_fields(stored_indented, {
    { field = "answer", value = "Updated.\n  Still nested." },
    { field = "tags", value = "updated" },
  }, { cards = { stored_indented } })
  assert_true(indented_ok, indented_message)
  assert_contains(
    table.concat(vim.fn.readfile(indented_path), "\n"),
    "  answer: |\n    Updated.\n      Still nested.\n  tags: updated\n  @end",
    "store updates keep every field relative to the card directive"
  )
  local reparsed_indented = parser.parse_file(indented_path)[1]
  assert_equal(reparsed_indented.values.answer, "Updated.\n  Still nested.", "indented store updates round trip")

  local disallowed = parser.parse_lines({
    "@flashcard japanese",
    "id: fc_multiline_disallowed",
    "japanese: |",
    "  猫",
    "english: cat",
    "@end",
  }, "disallowed.norg")[1]
  local _, disallowed_errors = parser.valid_cards(config, { disallowed })
  assert_contains(
    table.concat(disallowed_errors, "\n"),
    "field does not allow multiline values: japanese",
    "a schema must opt each multiline field in"
  )

  local multiline_system = parser.parse_lines({
    "@flashcard question_answer",
    "id: fc_multiline_system",
    "question: System fields?",
    "answer: Never multiline.",
    "due: |",
    "  2026-09-01",
    "@end",
  }, "multiline-system.norg")[1]
  local _, system_errors = parser.valid_cards(config, { multiline_system })
  assert_contains(
    table.concat(system_errors, "\n"),
    "field does not allow multiline values: due",
    "scheduler fields never accept block values"
  )

  local implicit = parser.parse_lines({
    "@flashcard question_answer",
    "id: fc_implicit_continuation",
    "question: Is an old continuation accepted?",
    "answer: No",
    "This line has no explicit block marker.",
    "@end",
  }, "implicit.norg")[1]
  local _, implicit_errors = parser.valid_cards(config, { implicit })
  assert_contains(
    table.concat(implicit_errors, "\n"),
    "use an explicit `field: |` block",
    "implicit continuation text remains invalid instead of being guessed"
  )

  local invalid_multiline_option = vim.deepcopy(config)
  invalid_multiline_option.schemas.question_answer.fields[1].multiline = "yes"
  assert_contains(
    table.concat(schema.validate_collection(invalid_multiline_option), "\n"),
    "question_answer field question.multiline must be a boolean",
    "schema validation rejects a non-boolean multiline option"
  )

  local invalid_typed_answer = vim.deepcopy(config)
  invalid_typed_answer.schemas.question_answer.fields[1].typed_answer = true
  assert_contains(
    table.concat(schema.validate_collection(invalid_typed_answer), "\n"),
    "question_answer field question.typed_answer requires reveal = true",
    "typed answers must also be revealed answers"
  )

  local invalid_typed_answer_type = vim.deepcopy(config)
  invalid_typed_answer_type.schemas.question_answer.fields[2].typed_answer = "yes"
  assert_contains(
    table.concat(schema.validate_collection(invalid_typed_answer_type), "\n"),
    "question_answer field answer.typed_answer must be a boolean",
    "schema validation rejects a non-boolean typed-answer option"
  )

  local store_path = test_root .. "/store.norg"
  vim.fn.writefile({
    "@flashcard question_answer",
    "id: fc_multiline_store_first",
    "question: Which tags are real?",
    "answer: |",
    "  old first line",
    "  tags: answer content",
    "  @end",
    "tags: old-tag",
    "@end",
    "",
    "@flashcard term_definition",
    "id: fc_multiline_store_second",
    "term: second card",
    "definition: stays put",
    "@end",
  }, store_path)

  local stored_cards = parser.parse_file(store_path)
  local stored_valid, stored_errors = parser.valid_cards(config, stored_cards)
  assert_equal(#stored_errors, 0, "store fixtures begin as valid cards")
  assert_equal(#stored_valid, 2, "store fixtures include both cards")
  local first, second = stored_valid[1], stored_valid[2]
  local second_start = second.start_line

  local tags_ok, tags_message = store.set_card_fields(first, {
    { field = "tags", value = "new-tag" },
  }, { cards = stored_valid })
  assert_true(tags_ok, tags_message)
  local tags_text = table.concat(vim.fn.readfile(store_path), "\n")
  assert_contains(tags_text, "  tags: answer content", "field lookup skips field-like block content")
  assert_contains(tags_text, "tags: new-tag", "field lookup updates the real dedented field")

  local replacement = "new first line\n  nested value indentation\nfield: answer content\n@end\n"
  local replace_ok, replace_message = store.set_card_fields(first, {
    { field = "answer", value = replacement },
  }, { cards = stored_valid })
  assert_true(replace_ok, replace_message)
  local replaced_text = table.concat(vim.fn.readfile(store_path), "\n")
  assert_true(not replaced_text:find("old first line", 1, true), "replacing a block removes every old content line")
  assert_contains(
    replaced_text,
    "answer: |\n  new first line\n    nested value indentation\n  field: answer content\n  @end\n  \ntags: new-tag",
    "store replacement writes one complete canonical block"
  )
  assert_equal(second.start_line, second_start + 2, "later cached card ranges follow a larger replacement")
  assert_equal(first.values.answer, replacement, "the updated card cache retains the full multiline value")
  assert_true(first.multiline_fields.answer, "the updated card cache records its block field")

  local reparsed = parser.parse_file(store_path)
  assert_equal(reparsed[1].values.answer, replacement, "the persisted replacement parses back exactly")
  assert_equal(reparsed[2].values.term, "second card", "a multiline replacement does not consume the next card")

  local scalar_ok, scalar_message = store.set_card_fields(first, {
    { field = "answer", value = "short replacement" },
  }, { cards = stored_valid })
  assert_true(scalar_ok, scalar_message)
  local scalar_text = table.concat(vim.fn.readfile(store_path), "\n")
  assert_contains(scalar_text, "answer: short replacement", "a block can be replaced by a scalar value")
  assert_true(
    not scalar_text:find("nested value indentation", 1, true),
    "block-to-scalar replacement removes continuations"
  )
  assert_true(not first.multiline_fields.answer, "the card cache clears block state after scalar replacement")
  assert_equal(second.start_line, second_start - 3, "later cached ranges follow a block-to-scalar replacement")

  local add_notes_ok, add_notes_message = store.restore_card_fields(first, {
    notes = "one\ntwo",
  }, { "notes" }, { cards = stored_valid })
  assert_true(add_notes_ok, add_notes_message)
  assert_contains(
    table.concat(vim.fn.readfile(store_path), "\n"),
    "notes: |\n  one\n  two",
    "structured restore can insert a multiline field"
  )
  local remove_notes_ok, remove_notes_message = store.restore_card_fields(
    first,
    {},
    { "notes" },
    { cards = stored_valid }
  )
  assert_true(remove_notes_ok, remove_notes_message)
  local removed_text = table.concat(vim.fn.readfile(store_path), "\n")
  assert_true(not removed_text:find("notes: |", 1, true), "removing a field deletes its block header")
  assert_true(not removed_text:find("  one", 1, true), "removing a field deletes every block content line")
end
