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
    min_width = 56,
    max_width = 72,
    min_height = 16,
    max_height = 20,
    height_ratio = 0.36,
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
    "Dashboard: :NeorgFlashcardOverview (canvas + stats)",
    "  keys: a add · <CR>/r review · p peek · e edit · s stats",
    "Add card: :NeorgFlashcardAdd [kind] (form, <C-s> saves)",
    "Review: :NeorgFlashcardReview[Due|File|Tag|Score]",
    "Stats: :NeorgFlashcardStats (jumps to analytics)",
    "",
    "Keys: Space reveal/next, n next, p back, t type answer",
    "Score: 1 bad (requeues), 2 mid, 3 good",
    "Edit: e source, q close",
  })
end

return M
