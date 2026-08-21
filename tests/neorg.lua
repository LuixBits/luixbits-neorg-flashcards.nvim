local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)

local neorg_ok, neorg = pcall(require, "neorg")
assert(neorg_ok, neorg)
if vim.fn.exists(":Neorg") ~= 2 then
  neorg.setup()
end

local presets = require("neorg_flashcards.presets")
local flashcards = require("neorg_flashcards")
local cards = root .. "/docs/demo/flashcards/cards.norg"

flashcards.setup({
  flashcards_dir = vim.fn.fnamemodify(cards, ":h"),
  default_file = cards,
  default_kind = "japanese",
  languages = presets.only("japanese"),
})

assert(vim.fn.exists(":Flashcards") == 2, "unified :Flashcards command was not registered")
vim.cmd("Flashcards cards")
local overview = require("neorg_flashcards.overview")
assert(overview.current_view() == "cards", "unified command did not open the Cards page")
assert(#vim.api.nvim_tabpage_list_wins(0) == 2, "hub did not create its two native Neovim panes")
local hub_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(hub_text:find(" Cards", 1, true), "Cards page was not rendered with Neorg installed")
assert(vim.bo.filetype == "norg", "hub scratch buffer does not use the norg filetype")
overview.close()

vim.cmd.edit(vim.fn.fnameescape(cards))
assert(vim.bo.filetype == "norg", "Neorg did not detect the norg filetype")
local parser_ok, parser_or_error = pcall(vim.treesitter.get_parser, 0, "norg")
assert(parser_ok, parser_or_error)

vim.cmd("Flashcards review file")
local popup = vim.api.nvim_get_current_buf()
assert(vim.bo[popup].buftype == "nofile", "review popup was not created")
local text = table.concat(vim.api.nvim_buf_get_lines(popup, 0, -1, false), "\n")
assert(text:find("Source: cards.norg", 1, true), "review popup omitted the source")
assert(text:find("Japanese", 1, true), "review popup omitted the card front")
flashcards.close_review()

vim.g.neorg_flashcards_neorg_tests_passed = true
print("neorg_flashcards Neorg integration tests passed")
