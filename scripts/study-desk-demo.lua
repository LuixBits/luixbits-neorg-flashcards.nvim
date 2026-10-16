local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.o.termguicolors = true
vim.o.laststatus = 2
vim.o.showtabline = 0
vim.o.ruler = false
local base = vim.fn.tempname()
vim.fn.mkdir(base .. "/japanese", "p")
vim.fn.mkdir(base .. "/computer-science", "p")
local samples = {
  { "猫", "ねこ", "cat", "animals" },
  { "犬", "いぬ", "dog", "animals" },
  { "鳥", "とり", "bird", "animals" },
  { "水", "みず", "water", "food" },
  { "食べる", "たべる", "to eat", "food verbs" },
  { "勉強", "べんきょう", "study", "verbs" },
  { "山", "やま", "mountain", "nature" },
  { "川", "かわ", "river", "nature" },
}
local lines = {}
for i, sample in ipairs(samples) do
  vim.list_extend(lines, {
    "@flashcard japanese",
    "id: fc_visual_" .. i,
    "japanese: " .. sample[1],
    "reading: " .. sample[2],
    "english: " .. sample[3],
    "tags: " .. sample[4],
    "@end",
    "",
  })
end
vim.fn.writefile(lines, base .. "/japanese/cards.norg")
local p = require("neorg_flashcards.presets")
require("neorg_flashcards").setup({
  deck_registry = false,
  default_collection = "japanese",
  ui = { motion = vim.env.FLASHCARDS_DEMO_MOTION == "1", ascii = vim.env.FLASHCARDS_DEMO_ASCII == "1" },
  collections = {
    japanese = {
      label = "Japanese",
      path = base .. "/japanese",
      default_card_type = "japanese",
      schemas = p.only("japanese"),
    },
    computer_science = {
      label = "Computer Science",
      path = base .. "/computer-science",
      default_card_type = "question_answer",
      schemas = p.only("question_answer"),
    },
  },
})
local config = require("neorg_flashcards").active_collection()
local cards = require("neorg_flashcards.parser").collect_flashcards(config)
local chapters = require("neorg_flashcards.chapters")
chapters.create(config, "Lesson 1", { cards[1], cards[2], cards[4] })
chapters.create(config, "Lesson 2", { cards[3], cards[7], cards[8] })
chapters.create(config, "Verbs", { cards[5], cards[6] })
if vim.env.FLASHCARDS_DEMO_HISTORY == "1" then
  local history = require("neorg_flashcards.history")
  local calendar = require("neorg_flashcards.calendar")
  for offset = 0, 13 do
    if offset % 4 ~= 3 then
      for index = 1, (offset % 5) + 2 do
        history.append(
          {
            version = 1,
            type = "review",
            event = "rated",
            event_id = "demo-" .. offset .. "-" .. index,
            card_id = "fc_visual_" .. index,
            collection_id = "japanese",
            epoch = calendar.shift(os.time(), -offset),
            rating = index % 3 == 0 and 2 or 3,
            duration_ms = 1200 + index * 800,
            hint_used = index == 3,
          },
          config
        )
      end
    end
  end
end
require("neorg_flashcards").desk()
