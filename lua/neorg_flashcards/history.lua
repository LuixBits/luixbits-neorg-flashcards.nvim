-- Versioned, append-only review history. Corrupt lines are reported and
-- skipped independently, so one interrupted append never hides good history.

local identity = require("neorg_flashcards.identity")
local schedule = require("neorg_flashcards.schedule")
local util = require("neorg_flashcards.util")

local M = {}

M.VERSION = 1
M.FILENAME = "reviews.jsonl"
M.LEGACY_FILENAME = "reviews.log"

local config = {}

local function copy(value)
  if vim and vim.deepcopy then
    return vim.deepcopy(value)
  end
  local result = {}
  for key, item in pairs(value or {}) do
    result[key] = item
  end
  return result
end

local function encode(value)
  if vim.json and vim.json.encode then
    return vim.json.encode(value)
  end
  return vim.fn.json_encode(value)
end

local function decode(value)
  if vim.json and vim.json.decode then
    return vim.json.decode(value)
  end
  return vim.fn.json_decode(value)
end

local function source_config(source)
  if type(source) == "table" then
    return source
  end
  return config
end

function M.path(source)
  if type(source) == "string" then
    return vim.fs.normalize(vim.fn.expand(source))
  end

  local opts = source_config(source)
  if not util.isempty(opts.history_file) then
    return vim.fs.normalize(vim.fn.expand(opts.history_file))
  end
  if util.isempty(opts.flashcards_dir) then
    return nil
  end
  return vim.fs.normalize(vim.fn.expand(opts.flashcards_dir .. "/" .. M.FILENAME))
end

function M.legacy_path(source)
  if type(source) == "string" then
    return vim.fs.normalize(vim.fn.fnamemodify(source, ":h") .. "/" .. M.LEGACY_FILENAME)
  end

  local opts = source_config(source)
  if not util.isempty(opts.legacy_history_file) then
    return vim.fs.normalize(vim.fn.expand(opts.legacy_history_file))
  end
  if util.isempty(opts.flashcards_dir) then
    return nil
  end
  return vim.fs.normalize(vim.fn.expand(opts.flashcards_dir .. "/" .. M.LEGACY_FILENAME))
end

function M.setup(opts)
  config = opts or {}
end

local function rating(value)
  value = tonumber(value)
  if value == 1 or value == 2 or value == 3 then
    return value
  end
  return nil
end

local function epoch_from_timestamp(value)
  if type(value) ~= "string" then
    return nil
  end

  local plain = value:match("^(%d%d%d%d%-%d%d?%-%d%d?[ T]%d%d?:%d%d)")
  if not plain then
    return nil
  end
  return schedule.parse_due(plain:gsub("T", " "))
end

local function normalize_event(event, opts)
  if type(event) ~= "table" then
    return nil, "review event must be a table"
  end

  local normalized = copy(event)
  normalized.version = tonumber(normalized.version) or M.VERSION
  if normalized.version ~= M.VERSION then
    return nil, "unsupported review event version: " .. tostring(normalized.version)
  end

  normalized.type = normalized.type or "review"
  normalized.event = util.trim(normalized.event or normalized.action or "rated"):lower()
  normalized.action = nil
  if normalized.event == "review" then
    normalized.event = "rated"
  end
  if normalized.event == "" or not normalized.event:match("^[%w_-]+$") then
    return nil, "review event action is invalid"
  end

  local raw_rating = normalized.rating or normalized.score
  normalized.rating = rating(raw_rating)
  if normalized.event == "rated" and not normalized.rating then
    return nil, "review event rating must be 1, 2, or 3"
  end
  if raw_rating ~= nil and not normalized.rating then
    return nil, "review event rating must be 1, 2, or 3"
  end
  normalized.score = normalized.rating -- compatibility with the old stats API

  normalized.card_id = util.trim(normalized.card_id or normalized.id)
  if normalized.card_id == "" and not (opts and opts.allow_missing_card_id) then
    return nil, "review event requires a stable card_id"
  end
  if normalized.card_id ~= "" and not identity.is_valid(normalized.card_id) then
    return nil, "review event has an invalid card_id"
  end
  if normalized.card_id == "" then
    normalized.card_id = nil
  end
  normalized.id = nil

  normalized.epoch = tonumber(normalized.epoch)
    or tonumber(normalized.timestamp)
    or epoch_from_timestamp(normalized.timestamp)
    or os.time()
  normalized.epoch = math.floor(normalized.epoch)
  normalized.timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ", normalized.epoch)

  if normalized.duration_ms ~= nil then
    normalized.duration_ms = math.max(0, math.floor(tonumber(normalized.duration_ms) or 0))
  end
  if normalized.hint_used ~= nil then
    normalized.hint_used = normalized.hint_used == true
  end

  return normalized
end

function M.new_event(card, score, now, details)
  details = copy(details or {})
  details.card_id = details.card_id or identity.card_id(card)
  details.rating = score or details.rating or details.score
  if now then
    details.epoch = now
  elseif details.epoch == nil and details.timestamp == nil then
    details.epoch = os.time()
  end
  details.version = M.VERSION
  details.type = "review"
  details.event = details.event or details.action or "rated"

  if details.old_state and not details.before then
    details.before = details.old_state
  end
  if details.new_state and not details.after then
    details.after = details.new_state
  end
  details.old_state = nil
  details.new_state = nil

  return normalize_event(details)
end

local function append_arguments(first, second, third)
  if
    type(first) == "table"
    and (first.rating ~= nil or first.score ~= nil or first.card_id ~= nil or first.event ~= nil)
  then
    return first, second, third
  end
  return second, first, third
end

-- Both append(event, config) and append(config, event) are accepted. Calling
-- setup(config) once and then append(event) is the simplest integration.
function M.append(first, second, third)
  local event, source, opts = append_arguments(first, second, third)
  local normalized, normalize_err = normalize_event(event, opts)
  if not normalized then
    return false, normalize_err
  end

  local path = M.path(source)
  if util.isempty(path) then
    return false, "review history path is not configured"
  end

  local ok_encode, line = pcall(encode, normalized)
  if not ok_encode then
    return false, "could not encode review history: " .. tostring(line)
  end

  local directory = vim.fn.fnamemodify(path, ":h")
  local ok_mkdir, mkdir_result = pcall(vim.fn.mkdir, directory, "p")
  if not ok_mkdir or mkdir_result == 0 and vim.fn.isdirectory(directory) ~= 1 then
    return false, "could not create review history directory: " .. tostring(mkdir_result)
  end

  local ok_write, write_result = pcall(vim.fn.writefile, { line }, path, "a")
  if not ok_write or write_result == -1 then
    return false, "could not append review history: " .. tostring(write_result)
  end

  return true, normalized
end

function M.append_review(card, score, now, details, source)
  local event, err = M.new_event(card, score, now, details)
  if not event then
    return false, err
  end
  return M.append(event, source)
end

local function read_lines(path)
  if util.isempty(path) or vim.fn.filereadable(path) ~= 1 then
    return {}, nil
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, tostring(lines)
  end
  return lines, nil
end

local function read_jsonl(path, entries, errors)
  local lines, read_err = read_lines(path)
  if not lines then
    table.insert(errors, string.format("%s: %s", path, read_err))
    return
  end

  for index, line in ipairs(lines) do
    if not util.isempty(line) then
      local ok_decode, raw = pcall(decode, line)
      if not ok_decode or type(raw) ~= "table" then
        table.insert(errors, string.format("%s:%d: invalid JSON review event", path, index))
      else
        local event, event_err = normalize_event(raw, { allow_missing_card_id = true })
        if event then
          if not event.card_id then
            event.unidentified = true
          end
          event._history_order = #entries + 1
          table.insert(entries, event)
        else
          table.insert(errors, string.format("%s:%d: %s", path, index, event_err))
        end
      end
    end
  end
end

local function read_legacy(path, entries, errors)
  local lines, read_err = read_lines(path)
  if not lines then
    table.insert(errors, string.format("%s: %s", path, read_err))
    return
  end

  for index, line in ipairs(lines) do
    if not util.isempty(line) then
      local stamp, score = line:match("^(%d%d%d%d%-%d%d?%-%d%d? +%d%d?:%d%d)%s*\t?(%d)%s*$")
      local epoch = stamp and schedule.parse_due(stamp)
      score = rating(score)
      if epoch and score then
        table.insert(entries, {
          version = 0,
          type = "review",
          event = "rated",
          timestamp = stamp,
          epoch = epoch,
          rating = score,
          score = score,
          legacy = true,
          unidentified = true,
          _history_order = #entries + 1,
        })
      else
        table.insert(errors, string.format("%s:%d: invalid legacy review entry", path, index))
      end
    end
  end
end

-- Returns entries, errors. Legacy reviews.log entries are included by default;
-- pass { include_legacy = false } to read only the v1 JSONL ledger.
function M.read(source, opts)
  if type(source) == "table" and source.include_legacy ~= nil and opts == nil and source.flashcards_dir == nil then
    opts = source
    source = nil
  end
  opts = opts or {}

  local entries = {}
  local errors = {}
  local path = M.path(source)
  if path then
    read_jsonl(path, entries, errors)
  end

  local legacy_path = M.legacy_path(source)
  if opts.include_legacy ~= false and legacy_path and legacy_path ~= path then
    read_legacy(legacy_path, entries, errors)
  end

  table.sort(entries, function(left, right)
    if left.epoch == right.epoch then
      return left._history_order < right._history_order
    end
    return left.epoch < right.epoch
  end)
  for _, entry in ipairs(entries) do
    entry._history_order = nil
  end
  return entries, errors
end

return M
