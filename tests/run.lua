local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)

local form = require("neorg_flashcards.form")
local health = require("neorg_flashcards.health")
local history = require("neorg_flashcards.history")
local identity = require("neorg_flashcards.identity")
local overview = require("neorg_flashcards.overview")
local parser = require("neorg_flashcards.parser")
local presets = require("neorg_flashcards.presets")
local review_engine = require("neorg_flashcards.review")
local schedule = require("neorg_flashcards.schedule")
local schema = require("neorg_flashcards.schema")
local stats = require("neorg_flashcards.stats")
local store = require("neorg_flashcards.store")
local flashcards = require("neorg_flashcards")

local function assert_true(value, message)
  if not value then
    error(message or "expected truthy value", 2)
  end
end

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error(
      string.format(
        "%s\nexpected: %s\nactual: %s",
        message or "values differ",
        vim.inspect(expected),
        vim.inspect(actual)
      ),
      2
    )
  end
end

local function assert_contains(value, pattern, message)
  if not tostring(value):find(pattern, 1, true) then
    error(string.format("%s\nmissing: %s\nvalue: %s", message or "pattern not found", pattern, tostring(value)), 2)
  end
end

local function canonical_path(path)
  return vim.uv.fs_realpath(path) or vim.fn.fnamemodify(path, ":p")
end

local function current_popup()
  local bufnr = vim.api.nvim_get_current_buf()
  assert_equal(vim.bo[bufnr].buftype, "nofile", "plugin opens a nofile popup")
  assert_equal(vim.bo[bufnr].filetype, "norg", "plugin popup uses the norg filetype")
  return bufnr, table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
end

local function current_tab_text()
  local panes = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local bufnr = vim.api.nvim_win_get_buf(win)
    table.insert(panes, table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n"))
  end
  return table.concat(panes, "\n")
end

local function assert_buffer_maps(bufnr, expected)
  local maps = {}
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
    maps[map.lhs] = true
  end

  for _, lhs in ipairs(expected) do
    assert_true(maps[lhs], "missing popup-local mapping: " .. lhs)
  end
end

local test_root = vim.fn.tempname()
local config = {
  flashcards_dir = test_root .. "/flashcards",
  default_file = test_root .. "/flashcards/inbox/cards.norg",
  default_kind = "japanese",
  languages = presets.only("japanese", "chinese"),
}

flashcards.setup(config)

for _, command in ipairs({
  "Flashcards",
  "NeorgFlashcardOpen",
  "NeorgFlashcardAdd",
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
  assert_equal(vim.fn.exists(":" .. command), 2, command .. " is registered")
end
assert_equal(vim.fn.maparg("<leader>ncr", "n"), "", "setup does not create global keymaps")

vim.cmd("NeorgFlashcardHelp")
local help_popup, help_text = current_popup()
assert_contains(help_text, "Files: .norg (Neorg itself is optional)", "help explains the file and Neorg relationship")
assert_buffer_maps(help_popup, { "q" })
require("neorg_flashcards.help").close()
assert_true(not vim.api.nvim_buf_is_valid(help_popup), "closing help wipes its scratch buffer")

vim.cmd("NeorgFlashcardOpen")
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
  "word: 勉強",
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
assert_equal(front_value, "勉強", "Japanese alias front value")

local chinese_lines = {
  "@flashcard chinese",
  "hanzi: 学习",
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
assert_equal(front_value, "学习", "Chinese alias front value")

local reveal = schema.reveal_fields(config, valid_chinese[1])
assert_equal(reveal[1].title, "Pinyin", "Chinese pinyin is revealed first")
assert_equal(reveal[2].title, "English", "Chinese English is revealed")

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
local valid_unsupported, unsupported_errors = parser.valid_cards({ languages = {} }, unsupported_cards)
assert_equal(#valid_unsupported, 0, "unsupported language is invalid")
assert_contains(unsupported_errors[1], "unsupported flashcard kind", "unsupported error is explicit")

local score_filter = schema.score_filter("bad")
assert_true(score_filter ~= nil, "bad score filter exists")
assert_true(score_filter.matches({ values = { score = "1" } }), "bad score filter matches score 1")
assert_true(not score_filter.matches({ values = { score = "2" } }), "bad score filter rejects score 2")

local collection_dir = config.flashcards_dir
local nested_dir = collection_dir .. "/course"
vim.fn.mkdir(nested_dir, "p")

local chapter_one_path = collection_dir .. "/chapter-01.norg"
local chapter_two_path = nested_dir .. "/chapter-02.norg"
vim.fn.writefile({
  "@flashcard japanese",
  "japanese: 一",
  "english: one",
  "tags: numbers chapter-01",
  "@end",
}, chapter_one_path)
vim.fn.writefile({
  "@flashcard japanese",
  "japanese: 二",
  "english: two",
  "tags: numbers chapter-02",
  "@end",
}, chapter_two_path)

local collection_config = {
  flashcards_dir = collection_dir,
  languages = presets.only("japanese"),
}
local collected_cards, collection_errors = parser.collect_flashcards(collection_config)
assert_equal(#collection_errors, 0, "recursive collection has no errors")
assert_equal(#collected_cards, 2, "collection includes cards from nested chapter files")
assert_equal(collected_cards[1].values.japanese, "一", "root chapter is collected first")
assert_equal(collected_cards[2].values.japanese, "二", "nested chapter is collected")
assert_true(schema.card_has_tag(collected_cards[2], "chapter-02"), "chapter tags work across the collection")

do
  local migration_dir = test_root .. "/migration"
  vim.fn.mkdir(migration_dir, "p")
  local migration_path = migration_dir .. "/legacy.norg"
  vim.fn.writefile({
    "@flashcard japanese",
    "japanese: 古い",
    "english: old",
    "@end",
    "",
    "@flashcard japanese",
    "japanese: 新規",
    "english: fresh",
    "@end",
  }, migration_path)
  local migration_config = {
    flashcards_dir = migration_dir,
    languages = presets.only("japanese"),
  }
  local migration_sequence = 0
  local function migration_id()
    migration_sequence = migration_sequence + 1
    return "fc_migration_" .. migration_sequence
  end
  local preview_ok, preview = parser.migrate_ids(migration_config, {
    dry_run = true,
    id_factory = migration_id,
  })
  assert_true(preview_ok, "legacy ID migration can be previewed")
  assert_equal(preview.planned, 2, "migration preview reports every legacy card")
  assert_true(
    not table.concat(vim.fn.readfile(migration_path), "\n"):find("id:", 1, true),
    "migration dry-run does not modify card files"
  )

  migration_sequence = 0
  local migration_ok, migration = parser.migrate_ids(migration_config, { id_factory = migration_id })
  assert_true(migration_ok, "legacy ID migration applies after a successful preflight")
  assert_equal(migration.assigned, 2, "migration applies every planned ID")
  local migrated_cards = parser.parse_file(migration_path)
  assert_equal(migrated_cards[1].id, "fc_migration_1", "migration writes the first stable ID")
  assert_equal(migrated_cards[2].id, "fc_migration_2", "migration writes the second stable ID")

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
  }, migration_path)
  local duplicate_ok, duplicate_result = store.migrate_card_ids(duplicate_cards, { dry_run = true })
  assert_true(not duplicate_ok, "ID migration rejects a collection with duplicate IDs")
  assert_contains(duplicate_result.errors[1], "Duplicate flashcard id", "duplicate-ID failure identifies the cause")

  local duplicate_safe, duplicate_errors, duplicate_invalid = parser.valid_cards(migration_config, duplicate_cards)
  assert_equal(#duplicate_safe, 0, "both cards in a duplicate-ID set are quarantined")
  assert_equal(#duplicate_errors, 2, "duplicate-ID validation reports every ambiguous block")
  assert_equal(#duplicate_invalid, 2, "duplicate-ID validation exposes both repair descriptors")
  assert_contains(duplicate_invalid[1].messages[1], "duplicate id", "invalid descriptor explains the ID collision")

  local duplicate_path = migration_dir .. "/duplicates.norg"
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
  local collected_safe, collected_errors, collected_invalid = parser.collect_flashcards(migration_config)
  assert_equal(#collected_safe, 2, "collection review keeps only the two migrated, uniquely identified cards")
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
  vim.cmd("NeorgFlashcardReviewFile")
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
  vim.cmd("NeorgFlashcardReviewFile")
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
local collection_alias = test_root .. "/flashcards-alias"
local linked, link_error = vim.uv.fs_symlink(collection_dir, collection_alias, { dir = true })
assert_true(linked, "test setup creates a collection symlink: " .. tostring(link_error))
assert_equal(
  util.path_label(chapter_two_path, collection_alias),
  "course/chapter-02.norg",
  "collection labels resolve symlinked roots"
)

vim.cmd("NeorgFlashcardReviewTag chapter-02")
local tag_popup, tag_text = current_popup()
assert_contains(tag_text, "tag:chapter-02 | 1/1", "tag command scopes the review")
assert_contains(tag_text, "Source: course/chapter-02.norg", "tag review shows its chapter source")
assert_contains(tag_text, "二", "tag review renders the matching card")
assert_buffer_maps(tag_popup, { "q", "e", "n", "p", "1", "2", "3" })
flashcards.close_review()
assert_true(not vim.api.nvim_buf_is_valid(tag_popup), "closing review wipes its scratch buffer")

vim.cmd("NeorgFlashcardReviewScore new")
local _, score_text = current_popup()
assert_contains(score_text, "score:new | 1/2", "score command reviews both unrated chapter cards")
flashcards.close_review()

vim.cmd("NeorgFlashcardReview")
local _, all_text = current_popup()
assert_contains(all_text, "all | 1/2", "all command combines chapter files")
flashcards.close_review()

vim.cmd.edit(vim.fn.fnameescape(chapter_one_path))
local alias_cards, alias_errors = parser.collect_flashcards({
  flashcards_dir = collection_alias,
  languages = collection_config.languages,
})
assert_equal(#alias_errors, 0, "symlinked collection has no errors")
assert_equal(#alias_cards, 2, "symlinked collection deduplicates loaded chapter paths")

vim.cmd("NeorgFlashcardReviewFile")
local _, file_text = current_popup()
assert_contains(file_text, "file | 1/1", "file command reviews only the current chapter")
assert_contains(file_text, "Source: chapter-01.norg", "file review shows its chapter source")
flashcards.close_review()

vim.api.nvim_buf_set_lines(0, 0, 0, false, {
  "@flashcard japanese",
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

local card_path = vim.fn.tempname() .. ".norg"
vim.fn.writefile({
  "@flashcard japanese",
  "japanese: 猫",
  "english: cat",
  "@end",
}, card_path)

local stored_cards = parser.parse_file(card_path)
local stored_valid, stored_errors = parser.valid_cards(config, stored_cards)
assert_equal(#stored_errors, 0, "stored card validates")
assert_equal(#stored_valid, 1, "stored card is valid")

local ok, message = store.set_card_fields(stored_valid[1], {
  { field = "score", value = "3" },
  { field = "reviewed", value = "2026-07-01" },
}, { cards = stored_valid })

assert_true(ok, message)

local updated = table.concat(vim.fn.readfile(card_path), "\n")
assert_contains(updated, "score: 3", "score was written")
assert_contains(updated, "reviewed: 2026-07-01", "review date was written")

local prompted_path = vim.fn.tempname() .. ".norg"
vim.cmd.edit(vim.fn.fnameescape(prompted_path))
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  "* Prompt Test",
  "",
})
vim.cmd.write()
vim.api.nvim_win_set_cursor(0, { 2, 0 })

local form_target = vim.api.nvim_get_current_buf()
flashcards.add_kind("")
local form_buf = vim.api.nvim_get_current_buf()
assert_true(form_buf ~= form_target, "add opens the form buffer")
assert_equal(vim.bo[form_buf].buftype, "nofile", "form is a scratch buffer")
assert_equal(vim.api.nvim_win_get_cursor(0)[1], 1, "form starts on the first field")

local form_imaps = {}
for _, map in ipairs(vim.api.nvim_buf_get_keymap(form_buf, "i")) do
  form_imaps[map.lhs:lower()] = true -- lhs casing is canonicalized (<C-S>)
end
for _, lhs in ipairs({ "<c-s>", "<cr>", "<tab>", "<s-tab>" }) do
  assert_true(form_imaps[lhs], "form maps " .. lhs .. " in insert mode")
end
form.next_field()
assert_equal(vim.api.nvim_win_get_cursor(0)[1], 2, "Enter hops to the next field")
form.cycle_field(-1)
assert_equal(vim.api.nvim_win_get_cursor(0)[1], 1, "Shift-Tab hops back")

vim.api.nvim_buf_set_lines(form_buf, 0, -1, false, {
  "Japanese: 机",
  "Reading: つくえ",
  "English: desk",
  "Notes: noun",
  "Tags: jlpt furniture",
})
form.save()
assert_equal(vim.api.nvim_win_get_cursor(0)[1], 1, "saving resets the form to the first field")
form.close()

local prompted = table.concat(vim.fn.readfile(prompted_path), "\n")
assert_contains(prompted, "@flashcard japanese", "form flow inserted a Japanese card")
assert_contains(prompted, "japanese: 机", "form flow saved front field")
assert_contains(prompted, "english: desk", "form flow saved required answer field")
assert_contains(prompted, "tags: jlpt furniture", "form flow saved optional tags")
assert_equal(vim.api.nvim_get_current_buf(), form_target, "closing the form returns to the card file")
vim.cmd("silent! bwipeout!")

local modified_path = vim.fn.tempname() .. ".norg"
vim.fn.writefile({
  "@flashcard japanese",
  "japanese: 犬",
  "english: dog",
  "@end",
}, modified_path)

vim.cmd.edit(vim.fn.fnameescape(modified_path))
vim.api.nvim_buf_set_lines(0, 2, 2, false, {
  "notes: edited in an open buffer",
})

local modified_cards = parser.parse_buffer(0)
local modified_valid, modified_errors = parser.valid_cards(config, modified_cards)
assert_equal(#modified_errors, 0, "modified open-buffer card validates")
assert_equal(#modified_valid, 1, "modified open-buffer card is valid")

local modified_ok, modified_message, modified_persisted = store.set_card_fields(modified_valid[1], {
  { field = "score", value = "1" },
  { field = "reviewed", value = "2026-07-01" },
}, { cards = modified_valid })

assert_true(modified_ok, modified_message)
assert_equal(modified_persisted, false, "modified open buffer is not written automatically")
assert_contains(modified_message, "open modified buffer", "modified buffer warning is explicit")

local modified_buffer_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
local modified_disk_text = table.concat(vim.fn.readfile(modified_path), "\n")
assert_contains(modified_buffer_text, "score: 1", "score is applied to the modified buffer")
assert_true(not modified_disk_text:find("score: 1", 1, true), "score is not written to disk while buffer is modified")
vim.cmd("silent! bwipeout!")

do
  local protected_path = vim.fn.tempname() .. ".norg"
  local protected_lines = {
    "@flashcard japanese",
    "id: fc_write_rollback",
    "japanese: 守",
    "english: protect",
    "@end",
  }
  vim.fn.writefile(protected_lines, protected_path)
  vim.cmd.edit(vim.fn.fnameescape(protected_path))
  local protected_card = parser.parse_buffer(0)[1]

  vim.bo.readonly = true
  local readonly_ok, readonly_message, readonly_persisted = store.set_card_fields(protected_card, {
    { field = "score", value = "3" },
  })
  assert_true(not readonly_ok, "read-only source buffers reject scheduling writes")
  assert_contains(readonly_message, "read-only", "read-only failure is explicit")
  assert_equal(readonly_persisted, false, "rejected read-only writes are not persisted")
  assert_equal(
    table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"),
    table.concat(protected_lines, "\n"),
    "read-only rejection leaves the buffer untouched"
  )
  vim.bo.readonly = false

  vim.bo.modifiable = false
  local unmodifiable_ok = store.set_card_fields(protected_card, { { field = "score", value = "3" } })
  assert_true(not unmodifiable_ok, "unmodifiable source buffers reject scheduling writes")
  assert_equal(
    table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"),
    table.concat(protected_lines, "\n"),
    "unmodifiable rejection leaves the buffer untouched"
  )
  vim.bo.modifiable = true

  vim.api.nvim_create_autocmd("BufWritePre", {
    buffer = 0,
    once = true,
    callback = function()
      vim.api.nvim_buf_set_lines(0, 0, 1, false, { "write hook mutation" })
      vim.bo.modifiable = false
      error("forced write failure")
    end,
  })
  local failed_ok, failed_message, failed_persisted = store.set_card_fields(protected_card, {
    { field = "score", value = "3" },
  })
  assert_true(not failed_ok, "a failing write hook rejects the scheduling update")
  assert_contains(failed_message, "forced write failure", "write failure keeps the original error")
  assert_equal(failed_persisted, false, "a rolled-back write is not reported as persisted")
  assert_equal(
    table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"),
    table.concat(protected_lines, "\n"),
    "failed writes restore the exact original buffer lines"
  )
  assert_true(not vim.bo.modified, "failed writes restore the clean modified flag")
  assert_true(vim.bo.modifiable, "failed writes restore the original modifiable flag")
  assert_equal(
    table.concat(vim.fn.readfile(protected_path), "\n"),
    table.concat(protected_lines, "\n"),
    "failed writes leave the source file unchanged"
  )

  vim.api.nvim_create_autocmd("BufWritePost", {
    buffer = 0,
    once = true,
    callback = function()
      error("forced post-write failure")
    end,
  })
  local post_ok, post_message, post_persisted = store.set_card_fields(protected_card, {
    { field = "score", value = "3" },
  })
  assert_true(post_ok, "a post-write hook error does not reject metadata already saved to disk")
  assert_true(post_persisted, "post-write hook errors still report matching disk content as persisted")
  assert_contains(post_message, "post-write hook failed", "post-write errors return an explicit warning")
  assert_contains(
    table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"),
    "score: 3",
    "post-write errors keep the persisted update in the buffer"
  )
  assert_contains(
    table.concat(vim.fn.readfile(protected_path), "\n"),
    "score: 3",
    "post-write errors keep the persisted update on disk"
  )
  vim.cmd("silent! bwipeout!")
end

do
  local pending_path = vim.fn.tempname() .. ".norg"
  vim.fn.writefile({
    "@flashcard japanese",
    "id: fc_pending_first",
    "japanese: 東",
    "english: east",
    "@end",
    "",
    "@flashcard japanese",
    "id: fc_pending_second",
    "japanese: 西",
    "english: west",
    "@end",
  }, pending_path)
  vim.cmd.edit(vim.fn.fnameescape(pending_path))
  vim.api.nvim_buf_set_lines(0, 2, 2, false, { "notes: unsaved user edit" })
  assert_true(vim.bo.modified, "pending-history fixture begins with a modified source buffer")

  local before_entries, before_errors = history.read(config, { include_legacy = false })
  assert_equal(#before_errors, 0, "pending-history baseline is readable")
  vim.cmd("NeorgFlashcardReviewFile")
  assert_true(review_engine.rate_current(3), "first rating is accepted in a modified source buffer")
  assert_true(review_engine.rate_current(2), "second rating is accepted in the same modified source buffer")
  assert_true(flashcards.get_review_state().completed, "modified-buffer review reaches finite completion")
  flashcards.close_review()

  local queued_entries, queued_errors = history.read(config, { include_legacy = false })
  assert_equal(#queued_errors, 0, "queued history remains readable")
  assert_equal(
    #queued_entries,
    #before_entries,
    "ratings in an unsaved modified buffer do not enter durable history early"
  )

  vim.cmd("write")
  local flushed_entries, flushed_errors = history.read(config, { include_legacy = false })
  assert_equal(#flushed_errors, 0, "history remains readable after pending ratings flush")
  assert_equal(#flushed_entries, #before_entries + 2, "BufWritePost flushes every pending rating exactly once")
  assert_equal(flushed_entries[#flushed_entries - 1].rating, 3, "pending ratings preserve their original order")
  assert_equal(flushed_entries[#flushed_entries].rating, 2, "later pending ratings remain later in history")
  assert_true(flushed_entries[#flushed_entries - 1].persisted, "flushed events are marked persisted")
  assert_true(flushed_entries[#flushed_entries].persisted, "every flushed event is marked persisted")
  vim.cmd("silent! bwipeout!")
end

do
  local undo_path = vim.fn.tempname() .. ".norg"
  vim.fn.writefile({
    "@flashcard japanese",
    "id: fc_pending_undo",
    "japanese: 北",
    "english: north",
    "@end",
  }, undo_path)
  vim.cmd.edit(vim.fn.fnameescape(undo_path))
  vim.api.nvim_buf_set_lines(0, 2, 2, false, { "notes: another unsaved edit" })

  local before_entries, before_errors = history.read(config, { include_legacy = false })
  assert_equal(#before_errors, 0, "undo-cancellation history baseline is readable")
  vim.cmd("NeorgFlashcardReviewFile")
  assert_true(review_engine.rate_current(3), "modified-buffer rating can be queued before undo")
  assert_true(flashcards.undo_last_rating(), "queued rating can be undone before the source is saved")
  flashcards.close_review()

  vim.cmd("write")
  local after_entries, after_errors = history.read(config, { include_legacy = false })
  assert_equal(#after_errors, 0, "history remains readable after saving an undone rating")
  assert_equal(
    #after_entries,
    #before_entries,
    "undo before save cancels its pending rating instead of writing a rated/undo pair"
  )
  vim.cmd("silent! bwipeout!")
end

do
  local discarded_path = vim.fn.tempname() .. ".norg"
  vim.fn.writefile({
    "@flashcard japanese",
    "id: fc_pending_discarded",
    "japanese: 南",
    "english: south",
    "@end",
  }, discarded_path)
  vim.cmd.edit(vim.fn.fnameescape(discarded_path))
  vim.api.nvim_buf_set_lines(0, 2, 2, false, { "notes: edit that will be discarded" })

  local before_entries, before_errors = history.read(config, { include_legacy = false })
  assert_equal(#before_errors, 0, "discarded-buffer history baseline is readable")
  vim.cmd("NeorgFlashcardReviewFile")
  assert_true(review_engine.rate_current(3), "modified-buffer rating is queued before buffer deletion")
  flashcards.close_review()

  vim.cmd("bdelete!")
  vim.cmd.edit(vim.fn.fnameescape(discarded_path))
  vim.api.nvim_buf_set_lines(0, 2, 2, false, { "notes: unrelated saved edit" })
  vim.cmd("write")

  local after_entries, after_errors = history.read(config, { include_legacy = false })
  assert_equal(#after_errors, 0, "history remains readable after a dirty buffer is discarded")
  assert_equal(
    #after_entries,
    #before_entries,
    "deleting a dirty source buffer discards its queued rating before a later write to the same path"
  )
  vim.cmd("silent! bwipeout!")
end

do
  local original_path = vim.fn.tempname() .. ".norg"
  local renamed_path = vim.fn.tempname() .. ".norg"
  vim.fn.writefile({
    "@flashcard japanese",
    "id: fc_pending_saveas",
    "japanese: 上",
    "english: up",
    "@end",
  }, original_path)
  vim.cmd.edit(vim.fn.fnameescape(original_path))
  vim.api.nvim_buf_set_lines(0, 2, 2, false, { "notes: save under a new name" })

  local before_entries, before_errors = history.read(config, { include_legacy = false })
  assert_equal(#before_errors, 0, "saveas history baseline is readable")
  vim.cmd("NeorgFlashcardReviewFile")
  assert_true(review_engine.rate_current(2), "modified-buffer rating is queued before saveas")
  flashcards.close_review()
  vim.cmd("saveas! " .. vim.fn.fnameescape(renamed_path))

  local after_entries, after_errors = history.read(config, { include_legacy = false })
  assert_equal(#after_errors, 0, "history remains readable after saveas")
  assert_equal(#after_entries, #before_entries + 1, "saveas flushes the queued rating exactly once")
  assert_equal(
    after_entries[#after_entries].path,
    canonical_path(renamed_path),
    "saveas history follows the buffer to its persisted path"
  )
  assert_equal(after_entries[#after_entries]._source_bufnr, nil, "internal buffer identity is not serialized")
  vim.cmd("silent! bwipeout!")
end

do
  local reentry_path = vim.fn.tempname() .. ".norg"
  vim.fn.writefile({
    "@flashcard japanese",
    "id: fc_pending_setup_reentry",
    "japanese: 中",
    "english: middle",
    "@end",
  }, reentry_path)
  vim.cmd.edit(vim.fn.fnameescape(reentry_path))
  vim.api.nvim_buf_set_lines(0, 2, 2, false, { "notes: pending across setup" })

  local before_entries, before_errors = history.read(config, { include_legacy = false })
  assert_equal(#before_errors, 0, "setup-reentry history baseline is readable")
  vim.cmd("NeorgFlashcardReviewFile")
  assert_true(review_engine.rate_current(3), "modified-buffer rating is queued before setup reentry")
  flashcards.close_review()

  local alternate_dir = vim.fn.tempname()
  local alternate_config = vim.tbl_deep_extend("force", {}, config, {
    flashcards_dir = alternate_dir,
    default_file = alternate_dir .. "/cards.norg",
  })
  flashcards.setup(alternate_config)
  vim.cmd("write")

  local after_entries, after_errors = history.read(config, { include_legacy = false })
  assert_equal(#after_errors, 0, "history remains readable after setup reentry")
  assert_equal(#after_entries, #before_entries + 1, "setup reentry preserves and flushes pending ratings")
  local alternate_entries = history.read(alternate_config, { include_legacy = false })
  assert_equal(#alternate_entries, 0, "pending history keeps its original destination across setup reentry")
  flashcards.setup(config)
  vim.cmd("silent! bwipeout!")
end

local fixed_now = os.time({ year = 2026, month = 8, day = 20, hour = 12, min = 0, sec = 0 })

local function updates_map(updates)
  local map = {}
  for _, update in ipairs(updates) do
    map[update.field] = update.value
  end
  return map
end

local good_updates, good_due = schedule.review_updates({ values = {} }, 3, fixed_now)
local good_map = updates_map(good_updates)
assert_equal(good_map.score, "3", "rating keeps its score field")
assert_equal(good_map.interval, "3", "first good rating uses the three-day interval")
assert_equal(good_map.ease, "2.55", "good rating nudges ease up")
assert_equal(good_map.reviewed, "2026-08-20", "rating stamps the review date")
assert_equal(good_due, fixed_now + 3 * 86400, "good rating is due three days out")
assert_equal(good_map.due, schedule.format_due(fixed_now + 3 * 86400), "due field matches the due epoch")

local grown = updates_map(schedule.review_updates({ values = { interval = "3", ease = "2.5" } }, 3, fixed_now))
assert_equal(grown.interval, "7.5", "good rating multiplies the interval by ease")

local mid_updates, mid_due = schedule.review_updates({ values = {} }, 2, fixed_now)
local mid_map = updates_map(mid_updates)
assert_equal(mid_map.interval, "0.5", "first mid rating uses the twelve-hour interval")
assert_equal(mid_map.ease, "2.5", "mid rating keeps the starting ease")
assert_equal(mid_due, fixed_now + 12 * 3600, "mid rating is due twelve hours out")

local mid_grown = updates_map(schedule.review_updates({ values = { interval = "0.5" } }, 2, fixed_now))
assert_equal(mid_grown.interval, "0.6", "mid rating grows the interval slowly")

local bad_updates, bad_due = schedule.review_updates({ values = {} }, 1, fixed_now)
local bad_map = updates_map(bad_updates)
assert_equal(bad_map.interval, "0", "bad rating resets the interval")
assert_equal(bad_map.ease, "2.3", "bad rating lowers ease")
assert_equal(bad_due, fixed_now + 600, "bad rating is due again within minutes")

local clamped = updates_map(schedule.review_updates({ values = { ease = "1.3" } }, 1, fixed_now))
assert_equal(clamped.ease, "1.3", "ease never drops below the minimum")

assert_equal(schedule.parse_due("2026-08-20 12:00"), fixed_now, "datetime due parses")
assert_equal(
  schedule.parse_due("2026-08-20"),
  os.time({ year = 2026, month = 8, day = 20, hour = 0, min = 0, sec = 0 }),
  "date-only due parses as the start of the day"
)
assert_equal(schedule.parse_due(schedule.format_due(fixed_now)), fixed_now, "due format roundtrips")
assert_equal(schedule.parse_due("garbage"), nil, "garbage due is rejected")
assert_equal(schedule.parse_due("2026-02-30"), nil, "normalized impossible dates are rejected")
assert_equal(schedule.parse_due("2026-08-20 24:00"), nil, "hours outside local clock range are rejected")
assert_equal(schedule.parse_due("2026-08-20 23:60"), nil, "minutes outside local clock range are rejected")
assert_true(schedule.is_due({ values = { due = "2020-01-01 00:00" } }, fixed_now), "past card is due")
assert_true(not schedule.is_due({ values = { due = "2999-01-01 00:00" } }, fixed_now), "future card is not due")
assert_true(schedule.is_due({ values = {} }, fixed_now), "new card is due")
assert_equal(schedule.due_key({ values = { due = "2026-08-20 12:00" } }), fixed_now, "due key uses the due epoch")
assert_equal(schedule.due_key({ values = {} }), 0, "new cards sort first by due key")

do
  local new_state = schedule.card_status({ values = {} }, fixed_now)
  assert_equal(new_state.lifecycle, "new", "cards without review evidence are new")
  assert_equal(new_state.timing, "due", "new cards are ready immediately")
  assert_equal(new_state.availability, "active", "new cards start active")

  local learning_state = schedule.card_status({ values = { reps = "1", interval = "0" } }, fixed_now)
  assert_equal(learning_state.lifecycle, "learning", "short first intervals are learning")
  local relearning_state = schedule.card_status({
    values = { reps = "4", lapses = "1", lifecycle = "relearning", due = "2026-08-20 10:00" },
  }, fixed_now)
  assert_equal(relearning_state.lifecycle, "relearning", "explicit relearning state is preserved")
  assert_equal(relearning_state.timing, "due", "a card due earlier today is due, not overdue")
  local overdue_state = schedule.card_status({
    values = { reps = "4", interval = "5", due = "2026-08-19 23:59" },
  }, fixed_now)
  assert_equal(overdue_state.lifecycle, "review", "mature cards use the review lifecycle")
  assert_equal(overdue_state.timing, "overdue", "a card due before today is overdue")

  local suspended_card = {
    values = { availability = "suspended", due = "2020-01-01 00:00" },
  }
  local buried_card = {
    values = {
      availability = "buried",
      available_at = "2026-08-21 00:00",
      due = "2020-01-01 00:00",
    },
  }
  assert_equal(
    schedule.card_status(suspended_card, fixed_now).availability,
    "suspended",
    "suspension is explicit state"
  )
  assert_equal(schedule.card_status(buried_card, fixed_now).availability, "buried", "burial is explicit state")
  assert_equal(
    schedule.card_status({ values = { availability = "active", suspended = "true", state = "suspended" } }, fixed_now).availability,
    "active",
    "canonical active availability overrides legacy suspension markers"
  )
  assert_true(not schedule.is_due(suspended_card, fixed_now), "suspended cards are excluded from due queues")
  assert_true(not schedule.is_due(buried_card, fixed_now), "buried cards are excluded from due queues")
  assert_equal(
    schedule.next_due({ suspended_card, buried_card }, fixed_now),
    schedule.parse_due("2026-08-21 00:00"),
    "next-due hints use a buried card's availability time and ignore suspended cards"
  )
end

do
  local history_dir = test_root .. "/history-isolated"
  local history_config = { flashcards_dir = history_dir }
  local history_card = { values = { id = "fc_history_card" } }
  local rated_event = assert(history.new_event(history_card, 3, fixed_now - 60, {
    event_id = "review-1",
    duration_ms = 4200,
    hint_used = true,
    before = { lifecycle = "learning" },
    after = { lifecycle = "review" },
  }))
  local append_ok, appended = history.append(rated_event, history_config)
  assert_true(append_ok, appended)
  assert_equal(appended.card_id, "fc_history_card", "history events use the stable card ID")
  assert_equal(appended.rating, 3, "history records the answer rating")

  local second_event = assert(history.new_event(history_card, 1, fixed_now, {
    event_id = "review-2",
    duration_ms = 1800,
  }))
  assert_true(history.append(second_event, history_config), "a second JSONL history event appends")
  local undo_event = assert(history.new_event(history_card, 1, fixed_now + 1, {
    event = "undo",
    event_id = "undo-1",
    undo_of = "review-2",
  }))
  assert_true(history.append(undo_event, history_config), "undo is stored as a compensating history event")

  local history_entries, history_errors = history.read(history_config, { include_legacy = false })
  assert_equal(#history_errors, 0, "valid JSONL history reads without errors")
  assert_equal(#history_entries, 3, "JSONL history preserves rated and compensating events")
  local effective_history = stats.effective_entries(history_entries)
  assert_equal(#effective_history, 1, "analytics removes a rating cancelled by undo")
  assert_equal(effective_history[1].event_id, "review-1", "undo compensation targets the matching event")
  assert_contains(
    table.concat(vim.fn.readfile(history.path(history_config)), "\n"),
    '"card_id":"fc_history_card"',
    "history is stored as structured JSONL"
  )
end

do
  local analytic_entries = {
    { type = "review", event = "rated", event_id = "a", epoch = fixed_now - 86400, rating = 1, duration_ms = 1000 },
    { type = "review", event = "rated", event_id = "b", epoch = fixed_now - 2 * 86400, rating = 2, duration_ms = 3000 },
    {
      type = "review",
      event = "rated",
      event_id = "c",
      epoch = fixed_now - 3 * 86400,
      rating = 3,
      duration_ms = 5000,
      hint_used = true,
    },
    { type = "review", event = "undo", epoch = fixed_now, rating = 1, undo_of = "a" },
  }
  local analytic_cards = {
    { values = { id = "fc_a", japanese = "A" } },
    {
      values = {
        id = "fc_b",
        japanese = "B",
        reps = "3",
        interval = "4",
        due = "2026-08-19 08:00",
      },
    },
    {
      values = {
        id = "fc_c",
        japanese = "C",
        reps = "3",
        interval = "4",
        due = "2026-08-22 12:00",
      },
    },
    {
      values = {
        id = "fc_d",
        japanese = "D",
        reps = "3",
        interval = "4",
        availability = "suspended",
        due = "2020-01-01 00:00",
      },
    },
    {
      values = {
        id = "fc_e",
        japanese = "E",
        reps = "3",
        interval = "4",
        availability = "buried",
        available_at = "2026-08-21 00:00",
        due = "2020-01-01 00:00",
      },
    },
  }
  local metrics = stats.metrics(analytic_cards, analytic_entries, fixed_now)
  assert_equal(metrics.reviews, 2, "analytics excludes an undone answer")
  assert_equal(metrics.retention_7, 100, "retention treats Hard and Good as successful recalls")
  assert_equal(metrics.retention_7_count, 2, "retention reports its sample size")
  assert_equal(metrics.median_duration_ms, 4000, "analytics reports median answer duration")
  assert_equal(metrics.hints, 1, "analytics counts answers that used hints")
  assert_equal(metrics.new, 1, "analytics counts lifecycle states")
  assert_equal(metrics.review, 4, "analytics counts mature review cards")
  assert_equal(metrics.due, 2, "analytics due count excludes buried and suspended cards")
  assert_equal(metrics.overdue, 1, "analytics separates overdue from due-today cards")
  assert_equal(metrics.suspended, 1, "analytics counts suspended cards")
  assert_equal(metrics.buried, 1, "analytics counts buried cards")
  local forecast = stats.forecast_counts(analytic_cards, fixed_now, 7)
  assert_equal(forecast[1], 2, "forecast puts new and overdue active cards in today's bucket")
  assert_equal(vim.tbl_count(forecast), 7, "forecast returns the requested horizon")
end

do
  local health_cards = {
    {
      kind = "japanese",
      path = collection_dir .. "/health.norg",
      start_line = 1,
      values = { id = "fc_health_duplicate", japanese = "same", english = "one" },
    },
    {
      kind = "japanese",
      path = collection_dir .. "/health.norg",
      start_line = 7,
      values = {
        id = "fc_health_duplicate",
        japanese = "same",
        english = "two",
        due = "never",
        interval = "minus",
        lifecycle = "forgotten",
        lapses = "8",
      },
    },
    {
      kind = "japanese",
      path = collection_dir .. "/health.norg",
      start_line = 15,
      values = { japanese = "missing id", english = "three" },
    },
  }
  local health_issues = health.inspect(collection_config, health_cards)
  local issue_codes = {}
  for _, issue in ipairs(health_issues) do
    issue_codes[issue.code] = true
  end
  for _, code in ipairs({
    "duplicate_id",
    "duplicate_front",
    "invalid_due",
    "invalid_interval",
    "invalid_lifecycle",
    "leech",
    "missing_id",
  }) do
    assert_true(issue_codes[code], "collection health reports " .. code)
  end
  local health_counts = health.counts(health_issues)
  assert_true(health_counts.error >= 3, "collection health distinguishes hard errors")
  assert_true(health_counts.warn >= 3, "collection health distinguishes actionable warnings")
end

vim.fn.writefile({
  "@flashcard japanese",
  "japanese: 過去",
  "english: past",
  "due: 2020-01-01 00:00",
  "@end",
  "",
  "@flashcard japanese",
  "japanese: 未来",
  "english: future",
  "due: 2999-01-01 00:00",
  "@end",
}, collection_dir .. "/due-check.norg")

vim.cmd("NeorgFlashcardReviewDue")
local _, due_text = current_popup()
assert_contains(due_text, "due | 1/3", "due review keeps only due and new cards")
assert_true(not due_text:find("未来", 1, true), "due review skips cards scheduled in the future")
flashcards.close_review()

local requeue_path = vim.fn.tempname() .. ".norg"
vim.fn.writefile({
  "@flashcard japanese",
  "japanese: 朝",
  "english: morning",
  "@end",
  "",
  "@flashcard japanese",
  "japanese: 夜",
  "english: night",
  "@end",
}, requeue_path)
vim.cmd.edit(vim.fn.fnameescape(requeue_path))

vim.cmd("NeorgFlashcardReviewFile")
local _, requeue_initial = current_popup()
assert_contains(requeue_initial, "file | 1/2", "requeue fixture starts with two cards")
flashcards.rate_current(1)
local _, requeue_text = current_popup()
assert_contains(requeue_text, "file | 2/3", "bad rating requeues the card within the session")
flashcards.close_review()

local requeue_disk = table.concat(vim.fn.readfile(requeue_path), "\n")
assert_contains(requeue_disk, "score: 1", "bad rating persists the score")
assert_contains(requeue_disk, "due: ", "bad rating persists a due timestamp")
assert_contains(requeue_disk, "interval: 0", "bad rating persists the reset interval")
assert_contains(requeue_disk, "ease: 2.3", "bad rating persists the lowered ease")
vim.cmd("silent! bwipeout!")

vim.fn.writefile({
  "@flashcard japanese",
  "japanese: 山",
  "english: mountain",
  "tags: nature hiking",
  "score: 1",
  "due: 2020-01-01 00:00",
  "@end",
  "",
  "@flashcard japanese",
  "japanese: 川",
  "english: river",
  "tags: nature",
  "@end",
}, collection_dir .. "/overview-check.norg")

local invalid_ui_path = collection_dir .. "/invalid-ui.norg"
vim.fn.writefile({
  "@flashcard japanese",
  "id: fc_ui_duplicate",
  "japanese: 壱",
  "english: one",
  "@end",
  "@flashcard japanese",
  "id: fc_ui_duplicate",
  "japanese: 弐",
  "english: two",
  "@end",
  "@flashcard japanese",
  "id: fc_ui_missing_answer",
  "japanese: 参",
  "@end",
}, invalid_ui_path)

vim.cmd("Flashcards")
local overview_popup, overview_text = current_popup()
assert_equal(overview.current_view(), "overview", "bare :Flashcards opens the Overview page")
assert_equal(#vim.api.nvim_tabpage_list_wins(0), 2, "dashboard opens cards and analytics panes")
assert_contains(overview_text, "nature", "overview lists the shared tag group")
assert_contains(overview_text, "hiking", "overview lists the second tag group")
assert_contains(overview_text, "untagged", "overview groups cards without tags")
assert_contains(overview_text, "nature · 2 cards · 2 due", "overview counts cards and due per group")
assert_contains(overview_text, "▸", "overview shows the selected card marker")
assert_contains(overview_text, "● due", "overview shows the color legend")
assert_contains(overview_text, "山 — mountain", "card lines show front and reveal")
assert_buffer_maps(overview_popup, {
  "q",
  "<Esc>",
  "?",
  "H",
  "1",
  "2",
  "3",
  "<Tab>",
  "j",
  "k",
  "<CR>",
  "r",
  "d",
  "A",
  "a",
  "/",
  "f",
  "o",
  "X",
  "x",
  "b",
  "p",
  "e",
  "c",
  "m",
  "R",
  "s",
})
assert_true(#vim.api.nvim_buf_get_extmarks(overview_popup, -1, 0, -1, {}) > 0, "overview paints highlight extmarks")

local stats_pane_buf
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if win ~= vim.api.nvim_get_current_win() then
    stats_pane_buf = vim.api.nvim_win_get_buf(win)
  end
end
local analytics_text = table.concat(vim.api.nvim_buf_get_lines(stats_pane_buf, 0, -1, false), "\n")
assert_contains(analytics_text, "Analytics", "dashboard shows the analytics pane")
assert_contains(analytics_text, "Due forecast", "analytics pane shows the forecast")

local overview_cursor = vim.api.nvim_win_get_cursor(0)
overview.move(1)
local moved_cursor = vim.api.nvim_win_get_cursor(0)
assert_true(
  moved_cursor[1] ~= overview_cursor[1] or moved_cursor[2] ~= overview_cursor[2],
  "moving the selection repositions the cursor"
)

overview.move(-1) -- back onto the alphabetically first group (chapter-01)
overview.review_group()
local _, group_review_text = current_popup()
assert_contains(group_review_text, "tag:chapter-01 | 1/1", "overview reviews the selected group")
flashcards.close_review()
local _, canvas_text = current_popup()
assert_contains(canvas_text, "▸", "closing the group review returns to the card list")

vim.cmd("Flashcards cards")
assert_equal(overview.current_view(), "cards", ":Flashcards cards routes into the Cards browser")
local cards_popup, cards_text = current_popup()
assert_contains(cards_text, " Cards", "Cards page renders its primary table")
assert_contains(cards_text, "shown of", "Cards page reports the filtered collection size")
assert_contains(current_tab_text(), " Card details", "Cards browser retains its contextual detail pane")
assert_buffer_maps(cards_popup, { "/", "f", "o", "X", "x", "b", "p", "e" })
assert_contains(cards_text, "[INVALID]", "Cards page keeps invalid blocks visible for repair")
assert_contains(cards_text, "3 invalid", "Cards page counts invalid blocks separately from reviewable cards")
assert_contains(current_tab_text(), "duplicate id", "invalid card details explain duplicate identities")
assert_contains(cards_text, "source:", "invalid rows include their source location")

local invalid_disk_before = table.concat(vim.fn.readfile(invalid_ui_path), "\n")
local invalid_messages = {}
local invalid_notify_original = vim.notify
vim.notify = function(message)
  table.insert(invalid_messages, tostring(message))
end
overview.review_selected()
overview.toggle_suspend()
overview.bury()
vim.notify = invalid_notify_original
assert_contains(table.concat(invalid_messages, "\n"), "cannot be reviewed", "invalid rows cannot start review")
assert_contains(table.concat(invalid_messages, "\n"), "Repair this invalid block", "invalid rows reject state actions")
assert_equal(
  table.concat(vim.fn.readfile(invalid_ui_path), "\n"),
  invalid_disk_before,
  "blocked invalid-card actions do not rewrite the source"
)
vim.fn.delete(invalid_ui_path)
overview.refresh()
local _, repaired_cards_text = current_popup()
assert_true(not repaired_cards_text:find("[INVALID]", 1, true), "refresh removes repaired or deleted invalid rows")

local input_original = vim.ui.input
local search_prompt
vim.ui.input = function(opts, callback)
  search_prompt = opts.prompt
  callback("mountain")
end
overview.search()
vim.ui.input = input_original
assert_equal(search_prompt, "Search cards: ", "Cards search uses a concise prompt")
local _, searched_text = current_popup()
assert_contains(searched_text, "search: “mountain”", "Cards search displays the active query")
assert_contains(searched_text, "山", "Cards search matches answer text as well as card fronts")
overview.clear_browser()

local select_original = vim.ui.select
local filter_prompt
vim.ui.select = function(items, opts, callback)
  filter_prompt = opts.prompt
  local selected
  for _, item in ipairs(items) do
    if item.value == "new" then
      selected = item
      break
    end
  end
  callback(selected)
end
overview.choose_filter()
vim.ui.select = select_original
assert_equal(filter_prompt, "Card state filter", "Cards filtering names the state dimension")
local _, filtered_text = current_popup()
assert_contains(filtered_text, "filter: new", "Cards browser renders the active lifecycle filter")
overview.clear_browser()

overview.toggle_suspend()
local _, suspended_text = current_popup()
assert_contains(suspended_text, "[SUSPENDED]", "Cards action can suspend the selected card")
overview.toggle_suspend()
local _, resumed_text = current_popup()
assert_true(not resumed_text:find("[SUSPENDED]", 1, true), "Cards action can resume the selected card")

overview.bury()
local _, buried_text = current_popup()
assert_contains(buried_text, "[BURIED]", "Cards action can bury the selected card")
overview.bury()
local _, unburied_text = current_popup()
assert_true(not unburied_text:find("[BURIED]", 1, true), "Cards action can unbury the selected card")

overview.context_help()
local _, cards_help_text = current_popup()
assert_contains(cards_help_text, "Search cards", "context help is generated from Cards actions")
assert_contains(cards_help_text, "Suspend or unsuspend", "context help includes enabled state actions")
overview.help_close()

overview.peek()
local _, peek_text = current_popup()
assert_contains(peek_text, "State:", "Cards preview includes scheduling state")
assert_contains(peek_text, "Source:", "Cards preview includes its source")
overview.peek_close()

vim.fn.writefile({ os.date("%Y-%m-%d %H:%M") .. "\t3" }, collection_dir .. "/reviews.log")
local expected_stats_entries = stats.read_log()
local expected_stats = stats.metrics({}, expected_stats_entries, os.time())
vim.cmd("Flashcards stats")
assert_equal(overview.current_view(), "stats", ":Flashcards stats routes into the Stats page")
assert_equal(#vim.api.nvim_tabpage_list_wins(0), 2, "stats opens the two-pane dashboard")
local stats_popup, stats_text = current_popup()
assert_contains(stats_text, expected_stats.reviews .. " reviews total", "stats totals JSONL and legacy review history")
assert_contains(stats_text, expected_stats.today .. " today", "stats counts today's effective reviews")
assert_contains(stats_text, "Retention", "stats shows recall retention windows")
assert_contains(stats_text, "Answer buttons", "stats shows rating distribution")
assert_contains(stats_text, "Card states", "stats shows lifecycle and availability counts")
assert_contains(stats_text, "Mon", "stats heatmap has weekday rows")
assert_contains(stats_text, "Due forecast", "stats shows the due forecast")
assert_buffer_maps(stats_popup, { "q", "1", "2", "3", "d", "A", "R", "s" })
overview.close()
assert_true(not overview.is_open(), "closing the stats view closes the dashboard tab")

local cloze_path = vim.fn.tempname() .. ".norg"
vim.fn.writefile({
  "@flashcard japanese",
  "japanese: 東京は{{c1::日本}}の首都です",
  "reading: とうきょう",
  "english: Tokyo is the capital of {{c1::Japan|country}}",
  "@end",
}, cloze_path)
vim.cmd.edit(vim.fn.fnameescape(cloze_path))

vim.cmd("NeorgFlashcardReviewFile")
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

local summary_path = vim.fn.tempname() .. ".norg"
vim.fn.writefile({
  "@flashcard japanese",
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

vim.cmd("NeorgFlashcardReviewFile")
review_engine.hint()
local _, first_hint_text = current_popup()
assert_contains(first_hint_text, "Hint 1", "review shows the first progressive hint without revealing the answer")
local hinted_state = flashcards.get_review_state()
assert_equal(hinted_state.hints, 1, "review state counts progressive hints")

local gated = review_engine.rate_current(3, { require_reveal = true })
assert_true(not gated, "a popup rating cannot bypass answer reveal")
local _, revealed_text = current_popup()
assert_contains(revealed_text, "Choose a rating", "first rating key reveals the answer and interval choices")
assert_contains(revealed_text, "1 Again", "revealed card previews the Again interval")
assert_equal(flashcards.get_review_state().reviewed, 0, "reveal gating does not count an answer")

assert_true(review_engine.rate_current(3, { require_reveal = true }), "rating succeeds after reveal")
local _, completed_text = current_popup()
assert_contains(completed_text, "Session complete", "finite review renders an explicit completion screen")
local completed_state = flashcards.get_review_state()
assert_true(completed_state.completed, "finite review exposes completion state")
assert_equal(completed_state.reviewed, 1, "completion reports the accepted rating")
assert_equal(completed_state.remaining, 0, "completion has no implicit wraparound queue")

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

-- add_to_default goes through the form and appends to the default file; it
-- runs last against the first collection because it writes a card into
-- flashcards_dir/inbox.
flashcards.add_to_default("")
local default_form_buf = vim.api.nvim_get_current_buf()
assert_equal(vim.bo[default_form_buf].buftype, "nofile", "add_to_default opens the form")
vim.api.nvim_buf_set_lines(default_form_buf, 0, -1, false, {
  "Japanese: 猫",
  "Reading: ねこ",
  "English: cat",
  "Notes: ",
  "Tags: animals",
})
form.save()
form.close()

local default_text = table.concat(vim.fn.readfile(config.default_file), "\n")
assert_contains(default_text, "* Flashcards", "default file keeps its heading")
assert_contains(default_text, "@flashcard japanese", "dashboard add writes a card to the default file")
assert_contains(default_text, "japanese: 猫", "dashboard add saved the front field")
assert_contains(default_text, "tags: animals", "dashboard add saved the tags")

local future_dir = vim.fn.tempname()
vim.fn.mkdir(future_dir, "p")
vim.fn.writefile({
  "@flashcard japanese",
  "japanese: 明日",
  "english: tomorrow",
  "due: 2999-01-01 00:00",
  "@end",
}, future_dir .. "/cards.norg")

flashcards.setup({
  flashcards_dir = future_dir,
  default_file = future_dir .. "/cards.norg",
  default_kind = "japanese",
  languages = presets.only("japanese"),
})

local hints = {}
local hint_original = vim.notify
vim.notify = function(message)
  table.insert(hints, tostring(message))
end
vim.cmd("NeorgFlashcardReviewDue")
vim.notify = hint_original

local hint_seen = false
for _, message in ipairs(hints) do
  if message:find("next at 2999-01-01", 1, true) then
    hint_seen = true
  end
end
assert_true(hint_seen, "empty due review hints at the next due time")

do
  local failure_dir = vim.fn.tempname()
  local failure_path = failure_dir .. "/cards.norg"
  vim.fn.mkdir(failure_dir, "p")
  vim.fn.writefile({
    "@flashcard japanese",
    "id: fc_history_append_failure",
    "japanese: 失",
    "english: fail",
    "@end",
  }, failure_path)

  local observed_event = nil
  flashcards.setup({
    flashcards_dir = failure_dir,
    default_file = failure_path,
    default_kind = "japanese",
    languages = presets.only("japanese"),
    on_review = function(event)
      observed_event = event
    end,
  })
  vim.cmd.edit(vim.fn.fnameescape(failure_path))

  local append_original = history.append
  local refresh_original = overview.refresh
  local append_attempts, refreshes = 0, 0
  history.append = function()
    append_attempts = append_attempts + 1
    return false, "forced history append failure"
  end
  overview.refresh = function()
    refreshes = refreshes + 1
  end
  local failure_messages = {}
  local failure_notify_original = vim.notify
  vim.notify = function(message)
    table.insert(failure_messages, tostring(message))
  end

  vim.cmd("NeorgFlashcardReviewFile")
  assert_true(review_engine.rate_current(3), "source rating succeeds when history append fails")
  flashcards.close_review()

  vim.notify = failure_notify_original
  history.append = append_original
  overview.refresh = refresh_original
  vim.cmd("doautocmd FocusGained")
  local recovered_entries, recovered_errors = history.read({
    flashcards_dir = failure_dir,
  }, { include_legacy = false })
  assert_equal(append_attempts, 1, "persisted rating attempts history append once")
  assert_true(
    observed_event ~= nil and observed_event.persisted,
    "user review callback still observes the persisted rating"
  )
  assert_true(refreshes > 0, "history failure still refreshes the hub state")
  assert_contains(table.concat(failure_messages, "\n"), "forced history append failure", "history failure is reported")
  assert_equal(#recovered_errors, 0, "retried review history remains readable")
  assert_equal(#recovered_entries, 1, "a transient history failure is retried instead of losing the persisted rating")
  assert_equal(recovered_entries[1].card_id, "fc_history_append_failure", "history retry preserves card identity")
  assert_contains(
    table.concat(vim.fn.readfile(failure_path), "\n"),
    "score: 3",
    "history failure does not roll back a successfully persisted source rating"
  )
  vim.cmd("silent! bwipeout!")
end

do
  local old_dir = vim.fn.tempname()
  local old_path = old_dir .. "/cards.norg"
  local new_dir = vim.fn.tempname()
  local new_path = new_dir .. "/cards.norg"
  vim.fn.mkdir(old_dir, "p")
  vim.fn.mkdir(new_dir, "p")
  vim.fn.writefile({
    "@flashcard japanese",
    "id: fc_retry_order_one",
    "japanese: 一",
    "english: one",
    "@end",
    "",
    "@flashcard japanese",
    "id: fc_retry_order_two",
    "japanese: 二",
    "english: two",
    "@end",
  }, old_path)
  vim.fn.writefile({
    "@flashcard japanese",
    "id: fc_retry_new_destination",
    "japanese: 新",
    "english: new",
    "@end",
  }, new_path)

  local old_config = {
    flashcards_dir = old_dir,
    default_file = old_path,
    default_kind = "japanese",
    languages = presets.only("japanese"),
  }
  local new_config = {
    flashcards_dir = new_dir,
    default_file = new_path,
    default_kind = "japanese",
    languages = presets.only("japanese"),
  }
  local old_history_path = history.path(old_config)
  local append_original = history.append
  history.append = function(event, destination, opts)
    if history.path(destination) == old_history_path then
      return false, "old history destination remains unavailable"
    end
    return append_original(event, destination, opts)
  end

  flashcards.setup(old_config)
  vim.cmd.edit(vim.fn.fnameescape(old_path))
  vim.cmd("NeorgFlashcardReviewFile")
  assert_true(review_engine.rate_current(3), "first failed-history rating persists its source")
  assert_true(review_engine.rate_current(2), "second failed-history rating persists its source")
  flashcards.close_review()

  flashcards.setup(new_config)
  vim.cmd.edit(vim.fn.fnameescape(new_path))
  vim.cmd("NeorgFlashcardReviewFile")
  assert_true(review_engine.rate_current(3), "a stale history path does not block the new destination")
  flashcards.close_review()

  local new_entries, new_errors = history.read(new_config, { include_legacy = false })
  assert_equal(#new_errors, 0, "the reconfigured destination remains readable")
  assert_equal(#new_entries, 1, "the reconfigured destination receives its review immediately")
  assert_equal(new_entries[1].card_id, "fc_retry_new_destination", "the new destination receives the right event")

  history.append = append_original
  vim.cmd("doautocmd FocusGained")
  local old_entries, old_errors = history.read(old_config, { include_legacy = false })
  assert_equal(#old_errors, 0, "the recovered old destination remains readable")
  assert_equal(#old_entries, 2, "both queued events reach the recovered old destination")
  assert_equal(old_entries[1].card_id, "fc_retry_order_one", "same-destination retry keeps first-in order")
  assert_equal(old_entries[2].card_id, "fc_retry_order_two", "same-destination retry keeps second-in order")

  vim.cmd("doautocmd FocusGained")
  old_entries = history.read(old_config, { include_legacy = false })
  new_entries = history.read(new_config, { include_legacy = false })
  assert_equal(#old_entries, 2, "repeated drains do not duplicate old-destination events")
  assert_equal(#new_entries, 1, "repeated drains do not duplicate new-destination events")
  vim.cmd("silent! bwipeout!")
end

do
  local alias_dir = vim.fn.tempname()
  local alias_path = alias_dir .. "/cards.norg"
  vim.fn.mkdir(alias_dir, "p")
  vim.fn.writefile({
    "@flashcard japanese",
    "card_id: fc_card_id_alias_event",
    "japanese: 別",
    "english: separate",
    "@end",
  }, alias_path)

  local state_events = {}
  flashcards.setup({
    flashcards_dir = alias_dir,
    default_file = alias_path,
    default_kind = "japanese",
    languages = presets.only("japanese"),
    on_review_event = function(event)
      table.insert(state_events, event)
    end,
  })
  vim.cmd.edit(vim.fn.fnameescape(alias_path))
  vim.cmd("NeorgFlashcardReviewFile")
  assert_true(flashcards.suspend_current(), "review can suspend a card using the card_id alias")

  local suspended_event = state_events[#state_events]
  assert_equal(suspended_event.event, "suspended", "suspend emits a card-state event")
  assert_equal(
    suspended_event.card_id,
    "fc_card_id_alias_event",
    "card-state events resolve the supported card_id alias"
  )
  flashcards.close_review()
  vim.cmd("silent! bwipeout!")
end

vim.g.neorg_flashcards_tests_passed = true
print("neorg_flashcards tests passed")
