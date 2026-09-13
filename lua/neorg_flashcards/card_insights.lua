-- Pure per-card review history and attention signals. The hub can render these
-- values without teaching this module about windows, highlights, or keymaps.

local history = require("neorg_flashcards.history")
local schedule = require("neorg_flashcards.schedule")
local util = require("neorg_flashcards.util")

local M = {}

local RECENT_REVIEWS = 3

---Return review events after applying append-only undo compensation.
---@param entries table[]
---@return table[]
function M.effective_entries(entries)
  return history.effective_entries(entries)
end

local function card_id(card)
  return util.trim(card and card.values and card.values.id)
end

local function is_rating(entry)
  local rating = tonumber(entry and entry.rating)
  return entry and entry.event == "rated" and (rating == 1 or rating == 2 or rating == 3)
end

local function grouped_reviews(entries)
  local grouped = {}
  for order, entry in ipairs(M.effective_entries(entries)) do
    local id = util.trim(entry.card_id)
    if id ~= "" and is_rating(entry) then
      grouped[id] = grouped[id] or {}
      table.insert(grouped[id], { entry = entry, order = order })
    end
  end
  for id, wrapped in pairs(grouped) do
    table.sort(wrapped, function(left, right)
      local left_epoch = tonumber(left.entry.epoch) or 0
      local right_epoch = tonumber(right.entry.epoch) or 0
      return left_epoch == right_epoch and left.order < right.order or left_epoch < right_epoch
    end)
    local reviews = {}
    for _, item in ipairs(wrapped) do
      table.insert(reviews, item.entry)
    end
    grouped[id] = reviews
  end
  return grouped
end

local function recent_reviews(reviews)
  local result = {}
  for index = math.max(1, #reviews - RECENT_REVIEWS + 1), #reviews do
    table.insert(result, reviews[index])
  end
  return result
end

local function hint_used(entry)
  return entry.hint_used == true or (tonumber(entry.hints_used) or 0) > 0
end

local function add_reason(reasons, code, message, priority, details)
  local reason = details or {}
  reason.code = code
  reason.message = message
  reason.priority = priority
  table.insert(reasons, reason)
end

local function reasons_for(config, card, reviews)
  local reasons = {}
  local threshold = tonumber(config.leech_threshold) or 8
  local lapses = math.max(0, math.floor(tonumber(card.values.lapses) or 0))
  if lapses >= threshold then
    add_reason(reasons, "leech", string.format("%d lapses", lapses), 30, {
      lapses = lapses,
      threshold = threshold,
    })
  end

  local recent = recent_reviews(reviews)
  local again_count, hint_count = 0, 0
  for _, entry in ipairs(recent) do
    if tonumber(entry.rating) == 1 then
      again_count = again_count + 1
    end
    if hint_used(entry) then
      hint_count = hint_count + 1
    end
  end

  local latest_rating = #reviews > 0 and tonumber(reviews[#reviews].rating) or tonumber(card.values.score)
  if again_count >= 2 then
    add_reason(
      reasons,
      "repeated_again",
      string.format("%d of the last %d reviews were Again", again_count, #recent),
      20,
      { count = again_count, sample_size = #recent }
    )
  elseif latest_rating == 1 then
    add_reason(reasons, "last_again", "Last review was Again", 10)
  end

  if hint_count >= 2 then
    add_reason(
      reasons,
      "frequent_hints",
      string.format("%d of the last %d reviews used hints", hint_count, #recent),
      10,
      { count = hint_count, sample_size = #recent }
    )
  end
  return reasons, recent
end

local function latest_epoch(reviews)
  return #reviews > 0 and (tonumber(reviews[#reviews].epoch) or 0) or 0
end

---Build collection-wide per-card insights. by_card uses the original card
---tables as keys, while by_id is convenient for integrations with history.
---@param config table
---@param cards table[]
---@param entries table[]
---@param now? number
---@return table
function M.build(config, cards, entries, now)
  config = config or {}
  now = now or os.time()
  local reviews_by_id = grouped_reviews(entries)
  local result = { by_card = {}, by_id = {}, attention = {} }

  for _, card in ipairs(cards or {}) do
    local id = card_id(card)
    local reviews = reviews_by_id[id] or {}
    local reasons, recent = reasons_for(config, card, reviews)
    local status = schedule.card_state(card, now, config.scheduling)
    local priority = 0
    for _, reason in ipairs(reasons) do
      priority = math.max(priority, reason.priority)
    end
    local insight = {
      card = card,
      card_id = id ~= "" and id or nil,
      reviews = reviews,
      recent_reviews = recent,
      reasons = reasons,
      priority = priority,
      latest_epoch = latest_epoch(reviews),
      needs_attention = #reasons > 0 and status.availability == "active",
    }
    result.by_card[card] = insight
    if id ~= "" and result.by_id[id] == nil then
      result.by_id[id] = insight
    end
    if insight.needs_attention then
      table.insert(result.attention, insight)
    end
  end

  table.sort(result.attention, function(left, right)
    if left.priority ~= right.priority then
      return left.priority > right.priority
    elseif left.latest_epoch ~= right.latest_epoch then
      return left.latest_epoch > right.latest_epoch
    end
    return tostring(left.card_id or "") < tostring(right.card_id or "")
  end)
  return result
end

local function interval_seconds(entry, scheduling)
  local epoch, due = tonumber(entry.epoch), tonumber(entry.due)
  if epoch and due and due >= epoch then
    return due - epoch
  end

  local interval = entry.after and tonumber(entry.after.interval)
  if interval == nil then
    return nil
  elseif interval == 0 then
    local again_minutes = tonumber(scheduling and scheduling.again_minutes) or schedule.DEFAULTS.again_minutes
    return again_minutes * 60
  end
  return interval * 86400
end

---Return the newest review steps in chronological order for a compact trail.
---@param insight table
---@param limit? integer
---@param scheduling? table
---@return table[]
function M.recall_trail(insight, limit, scheduling)
  local reviews = insight and insight.reviews or {}
  limit = math.max(1, math.floor(tonumber(limit) or 5))
  local result = {}
  for index = math.max(1, #reviews - limit + 1), #reviews do
    local entry = reviews[index]
    table.insert(result, {
      rating = tonumber(entry.rating),
      epoch = tonumber(entry.epoch),
      interval_seconds = interval_seconds(entry, scheduling),
      hint_used = hint_used(entry),
      event = entry,
    })
  end
  return result
end

return M
