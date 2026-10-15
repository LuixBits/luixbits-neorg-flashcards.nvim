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
  { "猫", "ねこ", "cat", "animals chapter-01" },
  { "犬", "いぬ", "dog", "animals chapter-01" },
  { "鳥", "とり", "bird", "animals chapter-02" },
  { "水", "みず", "water", "food chapter-01" },
  { "食べる", "たべる", "to eat", "food verbs" },
  { "勉強", "べんきょう", "study", "verbs chapter-02" },
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
require("neorg_flashcards").desk()
