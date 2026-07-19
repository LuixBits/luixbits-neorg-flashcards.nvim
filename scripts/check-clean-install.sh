#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/neorg-flashcards-clean.XXXXXX")"
NVIM_BIN="${NVIM:-nvim}"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/config" "$TMP/state" "$TMP/cache" "$TMP/data"

cat > "$TMP/config/init.lua" <<EOF
vim.opt.runtimepath:prepend("$ROOT")

local presets = require("neorg_flashcards.presets")

require("neorg_flashcards").setup({
  flashcards_dir = "$TMP/notes/flashcards",
  default_file = "$TMP/notes/flashcards/cards.norg",
  default_kind = "japanese",
  languages = presets.only("japanese"),
})

vim.cmd("NeorgFlashcardOpen")

local current_file = vim.api.nvim_buf_get_name(0)
local expected_file = vim.fs.normalize(vim.fn.resolve("$TMP/notes/flashcards/cards.norg"))
if vim.fs.normalize(vim.fn.resolve(current_file)) ~= expected_file then
  error("unexpected flashcard file: " .. current_file)
end

if vim.fn.filereadable("$TMP/notes/flashcards/cards.norg") ~= 1 then
  error("default flashcard file was not created")
end

local has_neorg = pcall(require, "neorg")
if has_neorg then
  error("clean install unexpectedly found Neorg")
end

vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  "@flashcard japanese",
  "japanese: 素",
  "english: plain",
  "@end",
})
vim.cmd.write()
vim.cmd("NeorgFlashcardReviewFile")

local popup = vim.api.nvim_get_current_buf()
if vim.bo[popup].buftype ~= "nofile" or vim.bo[popup].filetype ~= "norg" then
  error("plain-Neovim review popup was not created")
end

local popup_text = table.concat(vim.api.nvim_buf_get_lines(popup, 0, -1, false), "\n")
if not popup_text:find("素", 1, true) then
  error("plain-Neovim review did not render the card")
end

require("neorg_flashcards").close_review()

vim.g.neorg_flashcards_clean_install_passed = true
print("clean install check passed without Neorg")
EOF

XDG_CONFIG_HOME="$TMP/config" \
XDG_STATE_HOME="$TMP/state" \
XDG_CACHE_HOME="$TMP/cache" \
XDG_DATA_HOME="$TMP/data" \
NVIM_LOG_FILE="${NVIM_LOG_FILE:-/dev/null}" \
"$NVIM_BIN" --headless -u "$TMP/config/init.lua" -i NONE -n \
  --cmd "set shadafile=NONE" \
  -c "if !get(g:, 'neorg_flashcards_clean_install_passed', v:false) || v:errmsg !=# '' | cquit 1 | endif" \
  -c "qa!"
