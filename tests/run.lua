local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)

local form = require("neorg_flashcards.form")
local overview = require("neorg_flashcards.overview")
local parser = require("neorg_flashcards.parser")
local presets = require("neorg_flashcards.presets")
local schedule = require("neorg_flashcards.schedule")
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
vim.api.nvim_buf_set_lines(form_buf, 0, -1, false, {
  "Japanese: 机",
  "Reading: つくえ",
  "English: desk",
  "Notes: noun",
  "Tags: jlpt furniture",
})
form.save()
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
assert_true(schedule.is_due({ values = { due = "2020-01-01 00:00" } }, fixed_now), "past card is due")
assert_true(not schedule.is_due({ values = { due = "2999-01-01 00:00" } }, fixed_now), "future card is not due")
assert_true(schedule.is_due({ values = {} }, fixed_now), "new card is due")
assert_equal(schedule.due_key({ values = { due = "2026-08-20 12:00" } }), fixed_now, "due key uses the due epoch")
assert_equal(schedule.due_key({ values = {} }), 0, "new cards sort first by due key")

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

vim.cmd("NeorgFlashcardOverview")
local overview_popup, overview_text = current_popup()
assert_contains(overview_text, "╭", "overview draws group boxes")
assert_contains(overview_text, "nature", "overview lists the shared tag group")
assert_contains(overview_text, "hiking", "overview lists the second tag group")
assert_contains(overview_text, "untagged", "overview groups cards without tags")
assert_contains(overview_text, "▸", "overview shows the selected card preview")
assert_contains(overview_text, "● due", "overview shows the color legend")
assert_buffer_maps(overview_popup, { "q", "h", "l", "j", "k", "<CR>", "r", "p", "e", "R", "a", "s" })
assert_true(#vim.api.nvim_buf_get_extmarks(overview_popup, -1, 0, -1, {}) > 0, "overview paints highlight extmarks")

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
assert_contains(canvas_text, "▸", "closing the group review returns to the overview canvas")
overview.close()

vim.fn.writefile({ os.date("%Y-%m-%d %H:%M") .. "\t3" }, collection_dir .. "/reviews.log")
vim.cmd("NeorgFlashcardStats")
local stats_popup, stats_text = current_popup()
assert_contains(stats_text, "1 reviews total", "stats totals the review log")
assert_contains(stats_text, "1 today", "stats counts today's reviews")
assert_contains(stats_text, "Mon", "stats heatmap has weekday rows")
assert_contains(stats_text, "Due forecast", "stats shows the due forecast")
assert_contains(stats_text, "╭", "stats view keeps the canvas above the analytics")
assert_buffer_maps(stats_popup, { "q", "<CR>", "r", "p", "e", "R", "a", "s" })
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
flashcards.rate_current(3)
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

vim.g.neorg_flashcards_tests_passed = true
print("neorg_flashcards tests passed")
