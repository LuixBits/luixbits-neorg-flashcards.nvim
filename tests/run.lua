local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)

local parser = require("neorg_flashcards.parser")
local presets = require("neorg_flashcards.presets")
local schema = require("neorg_flashcards.schema")
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
  "NeorgFlashcardOpen",
  "NeorgFlashcardAdd",
  "NeorgFlashcardHelp",
  "NeorgFlashcardReview",
  "NeorgFlashcardReviewFile",
  "NeorgFlashcardReviewTag",
  "NeorgFlashcardReviewScore",
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

local util = require("neorg_flashcards.util")
assert_equal(
  util.path_label(chapter_two_path, collection_dir),
  "course/chapter-02.norg",
  "collection paths have concise labels"
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

local original_input = vim.ui.input
local answers = {
  "机",
  "つくえ",
  "desk",
  "noun",
  "jlpt furniture",
}
local answer_index = 0

vim.ui.input = function(_, callback)
  answer_index = answer_index + 1
  callback(answers[answer_index])
end

flashcards.add_kind("")
vim.ui.input = original_input

assert_equal(answer_index, #answers, "prompt flow requested each configured field")

local prompted = table.concat(vim.fn.readfile(prompted_path), "\n")
assert_contains(prompted, "@flashcard japanese", "prompt flow inserted a Japanese card")
assert_contains(prompted, "japanese: 机", "prompt flow saved front field")
assert_contains(prompted, "english: desk", "prompt flow saved required answer field")
assert_contains(prompted, "tags: jlpt furniture", "prompt flow saved optional tags")
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

vim.g.neorg_flashcards_tests_passed = true
print("neorg_flashcards tests passed")
