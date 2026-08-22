return function(T)
  local parser = require("neorg_flashcards.parser")
  local presets = require("neorg_flashcards.presets")
  local schema = require("neorg_flashcards.schema")
  local store = require("neorg_flashcards.store")
  local flashcards = require("neorg_flashcards")

  local assert_true = T.assert_true
  local assert_equal = T.assert_equal
  local assert_contains = T.assert_contains
  local canonical_path = T.canonical_path
  local current_popup = T.current_popup
  local assert_buffer_maps = T.assert_buffer_maps
  local test_root = T.test_root
  local config = T.config

  local collection_dir = config.flashcards_dir
  local nested_dir = collection_dir .. "/course"
  vim.fn.mkdir(nested_dir, "p")

  local chapter_one_path = collection_dir .. "/chapter-01.norg"
  local chapter_two_path = nested_dir .. "/chapter-02.norg"
  vim.fn.writefile({
    "@flashcard japanese",
    "id: fc_chapter_one",
    "japanese: 一",
    "english: one",
    "tags: numbers chapter-01",
    "@end",
  }, chapter_one_path)
  vim.fn.writefile({
    "@flashcard japanese",
    "id: fc_chapter_two",
    "japanese: 二",
    "english: two",
    "tags: numbers chapter-02",
    "@end",
  }, chapter_two_path)

  local collection_config = {
    flashcards_dir = collection_dir,
    schemas = presets.only("japanese"),
  }
  local collected_cards, collection_errors = parser.collect_flashcards(collection_config)
  assert_equal(#collection_errors, 0, "recursive collection has no errors")
  assert_equal(#collected_cards, 2, "collection includes cards from nested chapter files")
  assert_equal(collected_cards[1].values.japanese, "一", "root chapter is collected first")
  assert_equal(collected_cards[2].values.japanese, "二", "nested chapter is collected")
  assert_true(schema.card_has_tag(collected_cards[2], "chapter-02"), "chapter tags work across the collection")

  do
    local duplicate_cards = parser.parse_lines({
      "@flashcard japanese",
      "id: fc_duplicate",
      "japanese: A",
      "english: a",
      "@end",
      "@flashcard japanese",
      "id: fc_duplicate",
      "japanese: B",
      "english: b",
      "@end",
    }, chapter_one_path)
    local duplicate_safe, duplicate_errors, duplicate_invalid = parser.valid_cards(collection_config, duplicate_cards)
    assert_equal(#duplicate_safe, 0, "both cards in a duplicate-ID set are quarantined")
    assert_equal(#duplicate_errors, 2, "duplicate-ID validation reports every ambiguous block")
    assert_equal(#duplicate_invalid, 2, "duplicate-ID validation exposes both repair descriptors")
    assert_contains(duplicate_invalid[1].messages[1], "duplicate id", "invalid descriptor explains the ID collision")

    local duplicate_path = collection_dir .. "/duplicates.norg"
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_collected_duplicate",
      "japanese: C",
      "english: c",
      "@end",
      "@flashcard japanese",
      "id: fc_collected_duplicate",
      "japanese: D",
      "english: d",
      "@end",
    }, duplicate_path)
    local collected_safe, collected_errors, collected_invalid = parser.collect_flashcards(collection_config)
    assert_equal(#collected_safe, 2, "collection review keeps only uniquely identified cards")
    assert_equal(#collected_errors, 2, "collection validation reports both duplicate-ID blocks")
    assert_equal(#collected_invalid, 2, "collection exposes duplicate blocks to the Cards repair view")
    vim.fn.delete(duplicate_path)
  end
  do
    local cross_file_a = collection_dir .. "/cross-file-a.norg"
    local cross_file_b = collection_dir .. "/cross-file-b.norg"
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_cross_file_duplicate",
      "japanese: 左",
      "english: left",
      "@end",
    }, cross_file_a)
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_cross_file_duplicate",
      "japanese: 右",
      "english: right",
      "@end",
    }, cross_file_b)
    vim.cmd.edit(vim.fn.fnameescape(cross_file_a))

    local messages = {}
    local notify_original = vim.notify
    vim.notify = function(message)
      table.insert(messages, tostring(message))
    end
    vim.cmd("Flashcards review file")
    vim.notify = notify_original

    assert_true(not flashcards.get_review_state().active, "file review excludes an ID duplicated in another file")
    assert_contains(table.concat(messages, "\n"), "duplicate id", "file review explains the cross-file ID collision")
    vim.cmd("silent! bwipeout!")
    vim.fn.delete(cross_file_a)
    vim.fn.delete(cross_file_b)

    local readable_path = collection_dir .. "/readable-current.norg"
    local unreadable_path = collection_dir .. "/unreadable-sentinel.norg"
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_readable_current",
      "japanese: 読",
      "english: read",
      "@end",
    }, readable_path)
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_unreadable_unknown",
      "japanese: 不明",
      "english: unknown",
      "@end",
    }, unreadable_path)
    vim.cmd.edit(vim.fn.fnameescape(readable_path))

    local parse_file_original = parser.parse_file
    parser.parse_file = function(path)
      if canonical_path(path) == canonical_path(unreadable_path) then
        return {}, { path .. ": could not read file" }
      end
      return parse_file_original(path)
    end
    messages = {}
    vim.notify = function(message)
      table.insert(messages, tostring(message))
    end
    vim.cmd("Flashcards review file")
    vim.notify = notify_original
    parser.parse_file = parse_file_original

    assert_true(not flashcards.get_review_state().active, "file review stops when a collection source is unreadable")
    assert_contains(
      table.concat(messages, "\n"),
      "could not read file",
      "identity-safety refusal names the unreadable source"
    )
    vim.cmd("silent! bwipeout!")
    vim.fn.delete(readable_path)
    vim.fn.delete(unreadable_path)
  end

  local util = require("neorg_flashcards.util")
  assert_equal(
    util.path_label(chapter_two_path, collection_dir),
    "course/chapter-02.norg",
    "collection paths have concise labels"
  )
  local linked_collection = test_root .. "/flashcards-link"
  local linked, link_error = vim.uv.fs_symlink(collection_dir, linked_collection, { dir = true })
  assert_true(linked, "test setup creates a collection symlink: " .. tostring(link_error))
  assert_equal(
    util.path_label(chapter_two_path, linked_collection),
    "course/chapter-02.norg",
    "collection labels resolve symlinked roots"
  )

  local external_card = test_root .. "/outside-collection.norg"
  local external_link = collection_dir .. "/outside-link.norg"
  vim.fn.writefile({
    "@flashcard japanese",
    "id: fc_outside_symlink",
    "japanese: 外",
    "english: outside",
    "@end",
  }, external_card)
  local linked_file, linked_file_error = vim.uv.fs_symlink(external_card, external_link)
  assert_true(linked_file, "test setup creates an external card symlink: " .. tostring(linked_file_error))
  local bounded_cards, bounded_errors = parser.collect_flashcards(collection_config)
  assert_equal(#bounded_errors, 0, "an external symlink does not add collection errors")
  assert_equal(#bounded_cards, 2, "collection scans do not follow card symlinks outside the configured root")
  vim.fn.delete(external_link)
  vim.fn.delete(external_card)

  vim.cmd("Flashcards review tag chapter-02")
  local tag_popup, tag_text = current_popup()
  assert_contains(tag_text, "tag:chapter-02 | 1/1", "tag command scopes the review")
  assert_contains(tag_text, "Source: course/chapter-02.norg", "tag review shows its chapter source")
  assert_contains(tag_text, "二", "tag review renders the matching card")
  assert_buffer_maps(tag_popup, { "q", "?", "e", "j", "k", "1", "2", "3" })
  flashcards.close_review()
  assert_true(not vim.api.nvim_buf_is_valid(tag_popup), "closing review wipes its scratch buffer")

  vim.cmd("Flashcards review score new")
  local _, score_text = current_popup()
  assert_contains(score_text, "score:new | 1/2", "score command reviews both unrated chapter cards")
  flashcards.close_review()

  vim.cmd("Flashcards review all")
  local _, all_text = current_popup()
  assert_contains(all_text, "all | 1/2", "all command combines chapter files")
  flashcards.close_review()

  vim.cmd.edit(vim.fn.fnameescape(chapter_one_path))
  local linked_cards, linked_errors = parser.collect_flashcards({
    flashcards_dir = linked_collection,
    schemas = collection_config.schemas,
  })
  assert_equal(#linked_errors, 0, "symlinked collection has no errors")
  assert_equal(#linked_cards, 2, "symlinked collection deduplicates loaded chapter paths")

  vim.cmd("Flashcards review file")
  local _, file_text = current_popup()
  assert_contains(file_text, "file | 1/1", "file command reviews only the current chapter")
  assert_contains(file_text, "Source: chapter-01.norg", "file review shows its chapter source")
  flashcards.close_review()

  vim.api.nvim_buf_set_lines(0, 0, 0, false, {
    "@flashcard japanese",
    "id: fc_live_zero",
    "japanese: zero",
    "english: zero",
    "tags: numbers chapter-01",
    "@end",
    "",
  })

  local live_cards, live_errors = parser.collect_flashcards(collection_config)
  assert_equal(#live_errors, 0, "collection accepts unsaved cards in a loaded chapter")
  assert_equal(#live_cards, 3, "collection reads the loaded chapter buffer")

  local original_card
  for _, card in ipairs(live_cards) do
    if card.values.japanese == "一" then
      original_card = card
      break
    end
  end
  assert_true(original_card ~= nil, "original chapter card remains in the live collection")

  local live_ok, live_message, live_persisted = store.set_card_fields(original_card, {
    { field = "score", value = "3" },
    { field = "reviewed", value = "2026-07-19" },
  }, { cards = live_cards })
  assert_true(live_ok, live_message)
  assert_equal(live_persisted, false, "rating an unsaved chapter remains in its loaded buffer")

  local live_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local zero_line
  local original_line
  local score_line
  for index, line in ipairs(live_lines) do
    if line == "japanese: zero" then
      zero_line = index
    elseif line == "japanese: 一" then
      original_line = index
    elseif line == "score: 3" then
      score_line = index
    end
  end
  assert_true(zero_line < original_line, "unsaved card remains before the original card")
  assert_true(score_line > original_line, "rating is written to the reviewed card, not the inserted card")
  assert_true(
    not table.concat(vim.fn.readfile(chapter_one_path), "\n"):find("score: 3", 1, true),
    "rating is not persisted while the chapter buffer has unsaved edits"
  )

  local zero_card
  for _, card in ipairs(live_cards) do
    if card.values.japanese == "zero" then
      zero_card = card
      break
    end
  end
  assert_true(zero_card ~= nil, "unsaved chapter card is present in the live collection")
  vim.api.nvim_buf_set_lines(0, 0, 0, false, { "* changed after collection" })
  local stale_ok, stale_message = store.set_card_fields(zero_card, {
    { field = "score", value = "1" },
  }, { cards = live_cards })
  assert_true(not stale_ok, "rating refuses a source changed after collection")
  assert_contains(stale_message, "restart the review", "stale-source error explains the recovery")
  vim.cmd("silent! bwipeout!")

  T.collection_dir = collection_dir
  T.collection_config = collection_config
  T.chapter_one_path = chapter_one_path
  T.chapter_two_path = chapter_two_path
end
