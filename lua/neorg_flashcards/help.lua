local popup = require("neorg_flashcards.popup")

local M = {}

local state = {
  buf = nil,
  win = nil,
}

local config = {}

local function configured_kinds()
  local kinds = vim.tbl_keys(config.schemas or {})
  table.sort(kinds)

  if #kinds == 0 then
    return "none"
  end

  return table.concat(kinds, ", ")
end

local function default_card_type()
  if config.default_card_type and config.default_card_type ~= "" then
    return config.default_card_type
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
  local opened = popup.open(state, {
    title = " Flashcards Quick Guide ",
    footer = " / find · n/N matches · q/Esc close ",
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

  if not opened then
    return false
  end

  local rendered = popup.set_lines(state, {
    "* Flashcards",
    "",
    "Collection: " .. (config.label or config.id or ""),
    "Folder: " .. (config.path or ""),
    "Files: .norg (Neorg itself is optional)",
    "Default card type: " .. default_card_type(),
    "Kinds: " .. configured_kinds(),
    "",
    "Hub: 1 Overview · 2 Cards · 3 Stats · Tab pages · ? keys",
    "  <C-w>w pane · j/k line · Ctrl-D/U half-page · gg/G ends",
    "Overview: Enter/r review · d/A queues · a add · e edit",
    "Cards: Enter/r review · a add · / search · f filter · o sort",
    "  x suspend · b bury · D delete · p preview · e edit",
    "Stats: d due · A all · R refresh",
    "",
    "Collection: C switch · c open problems · H quick guide · R refresh",
    "Card form: Enter next/save · Ctrl-S save · Ctrl-N save+new",
    "  Tab fields · Esc then ? keys · q cancel",
    "",
    "Review: Enter/Space reveal · h hint · t type answer",
    "  1 Again · 2 Hard · 3 Good · j/k browse · u undo",
    "  b bury · x suspend · e edit · ? keys · q close",
    "",
    "Command routes: :Flashcards overview|cards|stats|review|add",
    "                open|check|help|collection",
    "",
    "Inside this guide: / find · n/N next/previous match",
    "Full manual: :help neorg-flashcards",
  })
  return rendered == true
end

return M
