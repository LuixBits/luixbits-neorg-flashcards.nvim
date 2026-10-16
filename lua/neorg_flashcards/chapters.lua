local metadata = require("neorg_flashcards.metadata")
local schema = require("neorg_flashcards.schema")
local schedule = require("neorg_flashcards.schedule")
local util = require("neorg_flashcards.util")
local M = {}

function M.id(data, card)
  return (data.chapter_cards or {})[schema.card_id(card)] or ""
end

function M.groups(cards, data, config, now)
  local by_id = { [""] = { name = "", label = "Unfiled", cards = {}, due = 0, chapter = true } }
  for id, chapter in pairs(data.chapters or {}) do
    by_id[id] = { name = id, label = chapter.label, cards = {}, due = 0, chapter = true }
  end
  for _, card in ipairs(cards) do
    local group = by_id[M.id(data, card)] or by_id[""]
    table.insert(group.cards, card)
    if schedule.is_due(card, now, config.scheduling) then
      group.due = group.due + 1
    end
  end
  local result = vim.tbl_values(by_id)
  table.sort(result, function(a, b)
    if a.name == "" or b.name == "" then
      return b.name == "" and a.name ~= ""
    end
    if a.label:lower() == b.label:lower() then
      return a.name < b.name
    end
    return a.label:lower() < b.label:lower()
  end)
  return result
end

local function assign(data, cards, id)
  if id ~= "" and not data.chapters[id] then
    error("Chapter no longer exists")
  end
  for _, card in ipairs(cards) do
    local card_id = schema.card_id(card)
    if not card_id then
      error("Cards need valid IDs before they can be moved")
    end
    data.chapter_cards[card_id] = id ~= "" and id or nil
  end
end

function M.create(config, label, cards)
  label = util.trim(label)
  local id
  local ok, err = metadata.update(config, function(data)
    for _, existing in pairs(data.chapters) do
      if existing.label:lower() == label:lower() then
        error("A chapter with that name already exists")
      end
    end
    local stem = label:lower():gsub("[^a-z0-9]+", "-"):gsub("^%-", ""):gsub("%-$", "")
    if stem == "" then
      stem = "chapter"
    end
    id = stem
    local suffix = 1
    while data.chapters[id] do
      suffix = suffix + 1
      id = stem .. "-" .. suffix
    end
    data.chapters[id] = { label = label }
    assign(data, cards or {}, id)
  end)
  return ok, err, ok and id or nil
end

function M.rename(config, id, label)
  return metadata.update(config, function(data)
    if not data.chapters[id] then
      error("Chapter no longer exists")
    end
    label = util.trim(label)
    for other_id, chapter in pairs(data.chapters) do
      if other_id ~= id and chapter.label:lower() == label:lower() then
        error("A chapter with that name already exists")
      end
    end
    data.chapters[id].label = label
  end)
end

function M.move(config, cards, id)
  return metadata.update(config, function(data)
    assign(data, cards, id)
  end)
end

function M.delete(config, id)
  return metadata.update(config, function(data)
    if not data.chapters[id] then
      error("Chapter no longer exists")
    end
    data.chapters[id] = nil
    for card_id, chapter in pairs(data.chapter_cards) do
      if chapter == id then
        data.chapter_cards[card_id] = nil
      end
    end
  end)
end

return M
