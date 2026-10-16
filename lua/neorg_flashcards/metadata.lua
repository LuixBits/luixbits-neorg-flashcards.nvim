local store = require("neorg_flashcards.store")
local util = require("neorg_flashcards.util")
local M = {}

local function options(config)
  return { allowed_root = config._root or config.path, reject_symlink = true, create = true }
end

function M.path(config)
  return config.path .. "/.flashcards-workspace.json"
end

function M.defaults()
  return { version = 1, categories = {}, chapters = {}, chapter_cards = {}, goals = {}, goal = 20 }
end

local function normalize(data)
  data.chapters = data.chapters or {}
  data.chapter_cards = data.chapter_cards or {}
  return data
end

function M.validate(data)
  if type(data) ~= "table" or data.version ~= 1 then
    return false, "unsupported workspace metadata version"
  end
  if type(data.categories) ~= "table" or type(data.goals) ~= "table" then
    return false, "workspace categories and goals must be objects"
  end
  if
    (data.chapters ~= nil and type(data.chapters) ~= "table")
    or (data.chapter_cards ~= nil and type(data.chapter_cards) ~= "table")
  then
    return false, "workspace chapters and chapter_cards must be objects"
  end
  for id, chapter in pairs(data.chapters or {}) do
    if
      type(id) ~= "string"
      or id == ""
      or id:find("[%c]")
      or type(chapter) ~= "table"
      or type(chapter.label) ~= "string"
      or util.trim(chapter.label) == ""
      or chapter.label:find("[%c]")
    then
      return false, "chapters need stable IDs and non-empty single-line names"
    end
  end
  for id, chapter in pairs(data.chapter_cards or {}) do
    if type(id) ~= "string" or id == "" or type(chapter) ~= "string" or not (data.chapters or {})[chapter] then
      return false, "chapter membership must reference an existing chapter"
    end
  end
  local function valid_goal(value)
    return type(value) == "number" and value >= 0 and value <= 10000 and value == math.floor(value)
  end
  if not valid_goal(data.goal) then
    return false, "daily goal must be an integer from 0 to 10000"
  end
  if data.label ~= nil and (type(data.label) ~= "string" or data.label:find("[%c]")) then
    return false, "deck label must be a single line"
  end
  for tag, category in pairs(data.categories) do
    if type(tag) ~= "string" or tag == "" or tag:find("[%s,]") or type(category) ~= "table" then
      return false, "category keys must be non-empty tag tokens"
    end
    if category.label ~= nil and (type(category.label) ~= "string" or category.label:find("[%c]")) then
      return false, "category labels must be single lines"
    end
    if
      category.order ~= nil
      and (
        type(category.order) ~= "number"
        or category.order ~= category.order
        or math.abs(category.order) == math.huge
      )
    then
      return false, "category order must be a number"
    end
    if
      category.accent ~= nil and not vim.tbl_contains({ "note", "accent", "good", "hard", "again" }, category.accent)
    then
      return false, "unknown category accent"
    end
  end
  for day, goal in pairs(data.goals) do
    if type(day) ~= "string" or not day:match("^%d%d%d%d%-%d%d%-%d%d$") or not valid_goal(goal) then
      return false, "invalid daily goal snapshot"
    end
  end
  return true
end

function M.load(config)
  local lines, _, err = store.read_lines(M.path(config), options(config))
  if not lines then
    return M.defaults(), err
  end
  if #lines == 0 then
    return M.defaults()
  end
  local ok, data = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok then
    return M.defaults(), "could not decode workspace metadata: " .. tostring(data)
  end
  local valid, message = M.validate(data)
  if not valid then
    return M.defaults(), message
  end
  return normalize(data)
end

function M.update(config, change)
  local opts = options(config)
  local path = M.path(config)
  local lines, buf, err = store.read_lines(path, opts)
  if not lines then
    return false, err
  end
  local data = M.defaults()
  if #lines > 0 then
    local ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
    if not ok then
      return false, "repair the workspace metadata before editing it"
    end
    data = decoded
  end
  local valid, message = M.validate(data)
  if not valid then
    return false, message
  end
  normalize(data)
  local ok, result = pcall(change, data)
  if not ok then
    return false, tostring(result)
  end
  valid, message = M.validate(data)
  if not valid then
    return false, message
  end
  for index = #lines, 1, -1 do
    lines[index] = nil
  end
  lines[1] = vim.json.encode(data)
  return store.write_lines(path, buf, lines, opts)
end

function M.begin_day(config, now)
  local day = os.date("%Y-%m-%d", now or os.time())
  local data, err = M.load(config)
  if err then
    return false, err
  end
  if data.goals[day] ~= nil then
    return true
  end
  return M.update(config, function(current)
    current.goals[day] = current.goals[day] or current.goal
  end)
end

function M.tags(card)
  local result, seen = {}, {}
  for raw_tag in util.trim(card.values.tags):gsub(",", " "):gmatch("%S+") do
    local tag = raw_tag:lower()
    if not seen[tag] then
      seen[tag] = true
      table.insert(result, tag)
    end
  end
  return result
end

function M.groups(cards, data, config, now)
  local schedule = require("neorg_flashcards.schedule")
  local groups = {}
  for tag in pairs(data.categories) do
    groups[tag] = { name = tag, cards = {}, due = 0 }
  end
  for _, card in ipairs(cards) do
    local tags = M.tags(card)
    if #tags == 0 then
      tags = { "" }
    end
    for _, tag in ipairs(tags) do
      groups[tag] = groups[tag] or { name = tag, cards = {}, due = 0 }
      table.insert(groups[tag].cards, card)
      if schedule.is_due(card, now, config.scheduling) then
        groups[tag].due = groups[tag].due + 1
      end
    end
  end
  local result = {}
  for tag, group in pairs(groups) do
    local settings = data.categories[tag] or {}
    group.label = settings.label or (tag == "" and "Untagged" or tag)
    group.accent = settings.accent or "note"
    group.order = settings.order or 0
    table.insert(result, group)
  end
  table.sort(result, function(a, b)
    if a.name == "" or b.name == "" then
      return b.name == "" and a.name ~= ""
    end
    if a.order ~= b.order then
      return a.order < b.order
    end
    return a.name < b.name
  end)
  return result
end

return M
