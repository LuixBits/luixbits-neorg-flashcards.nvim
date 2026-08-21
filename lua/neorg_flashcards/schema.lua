local identity = require("neorg_flashcards.identity")
local util = require("neorg_flashcards.util")

local M = {}

M.default_languages = {}

local function default_front(language)
  if language.front and language.front ~= "" then
    return language.front
  end

  for _, field in ipairs(language.fields or {}) do
    if field.required then
      return field.key
    end
  end

  return language.fields and language.fields[1] and language.fields[1].key or "front"
end

function M.for_kind(config, kind)
  return (config.languages or {})[kind]
end

function M.field_value(card, language, field)
  local value = util.trim(card.values[field])
  if not util.isempty(value) then
    return value
  end

  for _, alias in ipairs((language.aliases and language.aliases[field]) or {}) do
    value = util.trim(card.values[alias])
    if not util.isempty(value) then
      return value
    end
  end

  return ""
end

function M.front(config, card)
  local language = M.for_kind(config, card.kind)
  if not language then
    return "Front", ""
  end

  local front = default_front(language)
  local title = language.label or front
  for _, field in ipairs(language.fields or {}) do
    if field.key == front then
      title = field.title or language.label or front
      break
    end
  end

  return title, M.field_value(card, language, front)
end

function M.reveal_fields(config, card)
  local language = M.for_kind(config, card.kind)
  local fields = {}
  if not language then
    return fields
  end

  for _, field in ipairs(language.fields or {}) do
    if field.reveal then
      local value = M.field_value(card, language, field.key)
      if not util.isempty(value) then
        table.insert(fields, {
          title = field.title or field.key,
          value = value,
        })
      end
    end
  end

  return fields
end

function M.prompt_fields(config, kind)
  local language = M.for_kind(config, kind)
  local prompts = {}

  for _, field in ipairs((language and language.fields) or {}) do
    if field.prompt ~= false then
      table.insert(prompts, {
        key = field.key,
        label = field.label or (field.key .. ": "),
        default = field.default or "",
        required = field.required or false,
      })
    end
  end

  return prompts
end

function M.validate_card(config, card)
  local errors = {}
  local language = M.for_kind(config, card.kind)

  if not language then
    table.insert(errors, "unsupported flashcard kind: " .. card.kind)
    return errors
  end

  if not card.closed then
    table.insert(errors, "missing @end")
  end

  local id = identity.card_id(card)
  if id and not identity.is_valid(id) then
    table.insert(errors, "invalid id (use letters, numbers, _, ., :, or -)")
  end

  for _, field in ipairs(language.fields or {}) do
    if field.required and util.isempty(M.field_value(card, language, field.key)) then
      table.insert(errors, "missing " .. field.key)
    end
  end

  return errors
end

function M.card_lines(config, kind, values)
  values = values or {}
  local language = M.for_kind(config, kind)
  local lines = {
    "",
    "@flashcard " .. kind,
    "id: " .. (identity.card_id({ values = values }) or identity.generate()),
  }

  for _, field in ipairs((language and language.fields) or {}) do
    local value = util.trim(values[field.key])
    if field.required or not util.isempty(value) then
      table.insert(lines, field.key .. ": " .. value)
    end
  end

  table.insert(lines, "@end")
  table.insert(lines, "")
  return lines
end

function M.card_id(card)
  return identity.card_id(card)
end

function M.new_card_id(used)
  return identity.generate(used)
end

function M.card_score(card)
  local score = tonumber(util.trim(card.values.score))
  if score == 1 or score == 2 or score == 3 then
    return score
  end
  return nil
end

local score_aliases = {
  ["1"] = 1,
  bad = 1,
  weak = 1,
  hard = 1,
  ["2"] = 2,
  mid = 2,
  medium = 2,
  ok = 2,
  ["3"] = 3,
  good = 3,
  easy = 3,
}

function M.score_filter(value)
  value = util.trim(value):lower()
  if value == "new" or value == "unrated" then
    return {
      label = "new",
      matches = function(card)
        return M.card_score(card) == nil
      end,
    }
  end

  local score = score_aliases[value]
  if not score then
    return nil
  end

  local labels = {
    [1] = "bad",
    [2] = "mid",
    [3] = "good",
  }

  return {
    label = labels[score],
    matches = function(card)
      return M.card_score(card) == score
    end,
  }
end

function M.card_has_tag(card, tag)
  tag = util.trim(tag):lower()
  if tag == "" then
    return true
  end

  local tags = util.trim(card.values.tags):gsub(",", " ")
  for item in tags:gmatch("%S+") do
    if item:lower() == tag then
      return true
    end
  end

  return false
end

function M.review_stats(cards)
  local stats = {
    new = 0,
    bad = 0,
    medium = 0,
    good = 0,
  }

  for _, card in ipairs(cards) do
    local score = M.card_score(card)
    if score == 1 then
      stats.bad = stats.bad + 1
    elseif score == 2 then
      stats.medium = stats.medium + 1
    elseif score == 3 then
      stats.good = stats.good + 1
    else
      stats.new = stats.new + 1
    end
  end

  return stats
end

return M
