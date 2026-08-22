local schedule = require("neorg_flashcards.schedule")
local schema = require("neorg_flashcards.schema")
local history = require("neorg_flashcards.history")
local util = require("neorg_flashcards.util")

local M = {}
local config = {}

local function issue(severity, code, message, card)
  return {
    severity = severity,
    code = code,
    message = message,
    card = card,
  }
end

local function label(card, root)
  return string.format("%s:%d", util.path_label(card.path, root), card.start_line)
end

local function number_issue(issues, card, field, opts)
  local value = util.trim(card.values[field])
  if value == "" then
    return
  end

  local number = tonumber(value)
  if not number or (opts and opts.nonnegative and number < 0) or (opts and opts.integer and number % 1 ~= 0) then
    table.insert(issues, issue("error", "invalid_" .. field, field .. " is not a valid number", card))
  end
end

---Inspect valid cards for collection-level and scheduling health problems.
---Parser/schema errors remain the caller's responsibility.
---@param config table
---@param cards table[]
---@return table[] issues
function M.inspect(config, cards)
  local issues = {}
  local ids = {}
  local fronts = {}

  for _, card in ipairs(cards or {}) do
    local id = schema.card_id(card)
    if not id then
      table.insert(issues, issue("warn", "missing_id", "card has no stable id", card))
    elseif ids[id] then
      table.insert(issues, issue("error", "duplicate_id", "duplicate card id: " .. id, card))
    else
      ids[id] = card
    end

    local _, front = schema.front(config, card)
    local front_key = card.kind .. "\0" .. util.trim(front):lower():gsub("%s+", " ")
    if front_key ~= card.kind .. "\0" then
      if fronts[front_key] then
        table.insert(issues, issue("warn", "duplicate_front", "duplicate front: " .. util.trim(front), card))
      else
        fronts[front_key] = card
      end
    end

    local due = util.trim(card.values.due)
    if due ~= "" and not schedule.parse_due(due) then
      table.insert(issues, issue("error", "invalid_due", "due is not a valid local date/time", card))
    end
    local available_at = util.trim(card.values.available_at)
    if available_at ~= "" and not schedule.parse_due(available_at) then
      table.insert(issues, issue("error", "invalid_available_at", "available_at is not a valid local date/time", card))
    end

    number_issue(issues, card, "interval", { nonnegative = true })
    number_issue(issues, card, "ease", { nonnegative = true })
    number_issue(issues, card, "reps", { nonnegative = true, integer = true })
    number_issue(issues, card, "lapses", { nonnegative = true, integer = true })

    local lifecycle = util.trim(card.values.lifecycle):lower()
    if
      lifecycle ~= ""
      and lifecycle ~= "new"
      and lifecycle ~= "learning"
      and lifecycle ~= "review"
      and lifecycle ~= "relearning"
    then
      table.insert(issues, issue("error", "invalid_lifecycle", "unknown lifecycle: " .. lifecycle, card))
    end

    local availability = util.trim(card.values.availability):lower()
    if availability ~= "" and availability ~= "active" and availability ~= "suspended" and availability ~= "buried" then
      table.insert(issues, issue("error", "invalid_availability", "unknown availability: " .. availability, card))
    end

    local leech_threshold = tonumber(config.leech_threshold) or 8
    if (tonumber(card.values.lapses) or 0) >= leech_threshold then
      table.insert(
        issues,
        issue("warn", "leech", string.format("card has lapsed at least %d times", leech_threshold), card)
      )
    end
  end

  table.sort(issues, function(left, right)
    if left.severity ~= right.severity then
      return left.severity == "error"
    end
    if left.card.path ~= right.card.path then
      return left.card.path < right.card.path
    end
    return left.card.start_line < right.card.start_line
  end)

  return issues
end

function M.format(config, item)
  return string.format("%s: [%s] %s", label(item.card, config.flashcards_dir), item.severity, item.message)
end

function M.counts(issues)
  local counts = { error = 0, warn = 0 }
  for _, item in ipairs(issues or {}) do
    counts[item.severity] = (counts[item.severity] or 0) + 1
  end
  return counts
end

function M.setup(opts)
  config = opts or {}
end

-- Neovim discovers this as `:checkhealth neorg_flashcards`. The same
-- collection inspection powers the hub's `c` action and :Flashcards check.
function M.check()
  local report = vim.health
  report.start("neorg-flashcards")

  if util.isempty(config.flashcards_dir) then
    report.error("flashcards_dir is not configured")
    return
  end

  local _, root_err = util.resolve_pinned_directory(config._collection_root or config.flashcards_dir)
  if root_err then
    report.error(root_err)
    return
  end
  report.ok("Collection directory: " .. config.flashcards_dir)

  local schema_count = vim.tbl_count(config.schemas or {})
  if schema_count == 0 then
    report.error("No flashcard schemas are configured")
  else
    report.ok(string.format("%d card schema(s) configured", schema_count))
  end

  local cards, parser_errors = require("neorg_flashcards.parser").collect_flashcards(config)
  for _, message in ipairs(parser_errors) do
    report.error(message)
  end

  local review_entries, history_errors = history.read(config)
  if #history_errors == 0 then
    report.ok(string.format("Review history readable: %d event(s)", #review_entries))
  else
    for _, message in ipairs(history_errors) do
      report.warn(message)
    end
  end

  local pending_entries, outbox_errors = history.read_outbox(config)
  if #pending_entries > 0 then
    report.warn(string.format("%d review history event(s) are waiting in the durable retry queue", #pending_entries))
  end
  for _, message in ipairs(outbox_errors) do
    report.error(message)
  end

  local issues = M.inspect(config, cards)
  local counts = M.counts(issues)
  if #parser_errors == 0 and counts.error == 0 and counts.warn == 0 then
    report.ok(string.format("Collection healthy: %d card(s)", #cards))
    return
  end

  if counts.error == 0 then
    report.ok(string.format("%d valid card(s)", #cards))
  end
  if counts.warn > 0 then
    report.warn(string.format("%d collection warning(s)", counts.warn))
  end
  for index, item in ipairs(issues) do
    if index > 10 then
      report.info(string.format("… and %d more issue(s); use :Flashcards check for the full list", #issues - 10))
      break
    end
    local message = M.format(config, item)
    if item.severity == "error" then
      report.error(message)
    else
      report.warn(message)
    end
  end
end

return M
