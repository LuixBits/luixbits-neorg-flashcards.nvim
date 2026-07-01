local root = os.getenv("NEORG_FLASHCARDS_DEMO_ROOT") or vim.fn.getcwd()
local flashcards_dir = os.getenv("NEORG_FLASHCARDS_DEMO_DIR") or (root .. "/docs/demo/flashcards")
vim.opt.runtimepath:prepend(root)

vim.o.termguicolors = true
vim.o.laststatus = 0
vim.o.showmode = false
vim.o.ruler = false
vim.o.cmdheight = 1
vim.o.number = false
vim.o.relativenumber = false
vim.o.signcolumn = "no"
vim.o.wrap = true

vim.cmd.colorscheme("default")

local presets = require("neorg_flashcards.presets")

require("neorg_flashcards").setup({
  flashcards_dir = flashcards_dir,
  default_file = flashcards_dir .. "/cards.norg",
  default_kind = "japanese",
  languages = presets.only("japanese"),
})

vim.cmd("NeorgFlashcardOpen")
