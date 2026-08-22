local popup = require("neorg_flashcards.popup")

local M = {}

local state = {
  buf = nil,
  win = nil,
}

local config = {}

local function configured_kinds()
  local kinds = vim.tbl_keys(config.languages or {})
  table.sort(kinds)

  if #kinds == 0 then
    return "none"
  end

  return table.concat(kinds, ", ")
end

local function default_kind()
  if config.default_kind and config.default_kind ~= "" then
    return config.default_kind
  end

  return "not set"
end

function M.setup(opts)
  config = opts or {}
end

function M.close()
  popup.close(state)
end

function M.open()
  popup.open(state, {
    title = " Flashcards Help ",
    footer = " q close ",
    min_width = 62,
    max_width = 78,
    min_height = 20,
    max_height = 28,
    height_ratio = 0.58,
    maps = {
      { "q", M.close, "Close help" },
      { "<Esc>", M.close, "Close help" },
    },
  })

  popup.set_lines(state, {
    "* Flashcards",
    "",
    "Folder: " .. (config.flashcards_dir or ""),
    "Files: .norg (Neorg itself is optional)",
    "Default kind: " .. default_kind(),
    "Kinds: " .. configured_kinds(),
    "",
    "Open the hub: :Flashcards",
    "  1 Overview · 2 Cards · 3 Stats · Tab next page · ? keys",
    "  Enter/r review · d due · A all · a add · e source",
    "",
    "Cards: / search · f filter · o sort · x suspend · b bury",
    "Collection: c check · m migrate legacy IDs · R refresh",
    "Form: Enter next · Ctrl-S save · Ctrl-N save+new",
    "  Tab fields · Esc then ? keys · q cancel",
    "",
    "Review: Enter/Space reveal · h hint · t type answer",
    "  1 Again · 2 Hard · 3 Good · j/k browse · u undo",
    "  b bury · x suspend · e source · ? keys · q close",
    "",
    "Command routes: :Flashcards overview|cards|stats|review|add",
    "                open|check|migrate|help",
  })
end

return M
