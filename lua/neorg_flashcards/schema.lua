local identity = require("neorg_flashcards.identity")
local schedule = require("neorg_flashcards.schedule")
local util = require("neorg_flashcards.util")

local M = {}

M.defaults = {}

local function default_front(card_schema)
  if card_schema.front and card_schema.front ~= "" then
    return card_schema.front
  end

  for _, field in ipairs(card_schema.fields or {}) do
    if field.required then
      return field.key
    end
  end

  return card_schema.fields and card_schema.fields[1] and card_schema.fields[1].key or "front"
end

function M.for_kind(config, kind)
  return (config.schemas or {})[kind]
end

function M.field_value(card, field)
  local value = tostring(card.values[field] or "")
  return util.isempty(value) and "" or value
end

local SYSTEM_FIELDS = {
  id = true,
  score = true,
  reviewed = true,
  due = true,
  interval = true,
  ease = true,
  reps = true,
  lapses = true,
  lifecycle = true,
  availability = true,
  available_at = true,
}

local REMOVED_FIELDS = {
  card_id = "id",
  state = "lifecycle and availability",
  suspended = "availability",
  buried = "availability",
  buried_until = "available_at",
}

local SCHEDULING_OPTIONS = {
  again_minutes = true,
  hard_hours = true,
  good_days = true,
  starting_ease = true,
  min_ease = true,
  max_ease = true,
  max_interval_days = true,
  mid_hours = true,
}

local SCHEMA_OPTIONS = { label = true, front = true, fields = true, aliases = true }
local FIELD_OPTIONS = {
  key = true,
  label = true,
  title = true,
  default = true,
  placeholder = true,
  help = true,
  required = true,
  reveal = true,
  multiline = true,
  typed_answer = true,
  prompt = true,
  input = true,
}
local UI_OPTIONS = { show_shortcuts = true, rating_highlights = true, heatmap_highlights = true }
local RATING_OPTIONS = { again = true, hard = true, good = true }
local HEATMAP_OPTIONS = {}
for level = 0, 4 do
  HEATMAP_OPTIONS[level] = true
  HEATMAP_OPTIONS[tostring(level)] = true
end

local function reject_unknown_keys(errors, value, allowed, context)
  if type(value) ~= "table" then
    return
  end
  local keys = vim.tbl_keys(value)
  table.sort(keys, function(left, right)
    return tostring(left) < tostring(right)
  end)
  for _, key in ipairs(keys) do
    if not allowed[key] then
      table.insert(errors, string.format("unknown %s option: %s", context, tostring(key)))
    end
  end
end

local function finite_number(value)
  local number = tonumber(value)
  if not number or number ~= number or number == math.huge or number == -math.huge then
    return nil
  end
  return number
end

local function same_existing_file(left, right)
  local uv = vim.uv or vim.loop
  local left_stat = not util.isempty(left) and uv.fs_stat(left) or nil
  local right_stat = not util.isempty(right) and uv.fs_stat(right) or nil
  return left_stat
    and right_stat
    and left_stat.dev ~= nil
    and left_stat.ino ~= nil
    and left_stat.dev == right_stat.dev
    and left_stat.ino == right_stat.ino
end

local function add_number_error(errors, card, field, opts)
  local raw = util.trim(card.values[field])
  if raw == "" then
    return
  end
  local number = finite_number(raw)
  if
    not number
    or opts and opts.nonnegative and number < 0
    or opts and opts.positive and number <= 0
    or opts and opts.integer and number % 1 ~= 0
    or opts and opts.minimum and number < opts.minimum
    or opts and opts.maximum and number > opts.maximum
  then
    table.insert(errors, "invalid " .. field)
  end
end

---Validate one normalized collection before it becomes active.
---@param config table
---@return string[] errors
function M.validate_collection(config)
  local errors = {}
  if type(config.scheduling) == "table" and config.scheduling.mid_hours ~= nil then
    table.insert(errors, "scheduling.mid_hours was removed; use hard_hours")
  end
  local root = util.canonical_path(config.path)
  local default_file = util.canonical_path(config.default_file)

  if root == "" then
    table.insert(errors, "path is required")
  end
  if default_file == "" then
    table.insert(errors, "default_file is required")
  elseif not default_file:match("%.norg$") then
    table.insert(errors, "default_file must be a .norg file")
  elseif root ~= "" and not util.path_is_within(default_file, root) then
    table.insert(errors, "default_file must be inside the collection path")
  end
  local requested_history = config.history_file
  if util.isempty(requested_history) and root ~= "" then
    requested_history = root .. "/reviews.jsonl"
  end
  local history_file = util.isempty(requested_history) and "" or util.canonical_path(requested_history)
  if history_file ~= "" then
    if not history_file:match("%.jsonl$") then
      table.insert(errors, "review history destination must be a .jsonl file separate from card sources")
    elseif root ~= "" and not util.path_is_within(history_file, root) then
      table.insert(errors, "review history destination must be inside the collection path")
    elseif default_file ~= "" and (history_file == default_file or same_existing_file(history_file, default_file)) then
      table.insert(errors, "review history destination must be separate from default_file")
    end
  end

  local schemas = config.schemas
  if type(schemas) ~= "table" or vim.tbl_isempty(schemas) then
    table.insert(errors, "at least one card schema is required")
    schemas = {}
  end

  local default_card_type = util.trim(config.default_card_type)
  if default_card_type == "" then
    table.insert(errors, "default_card_type is required")
  elseif not schemas[default_card_type] then
    table.insert(errors, "default_card_type does not name a configured schema: " .. default_card_type)
  end

  local kinds = vim.tbl_keys(schemas)
  table.sort(kinds)
  for _, kind in ipairs(kinds) do
    local card_schema = schemas[kind]
    if not tostring(kind):match("^[a-z][a-z0-9_-]*$") then
      table.insert(errors, "schema kind must use lowercase letters, numbers, _ or -: " .. tostring(kind))
    end
    if type(card_schema) ~= "table" then
      table.insert(errors, "card schema must be a table: " .. tostring(kind))
    else
      reject_unknown_keys(errors, card_schema, SCHEMA_OPTIONS, kind .. " schema")
      if card_schema.label ~= nil and type(card_schema.label) ~= "string" then
        table.insert(errors, "card schema label must be a string: " .. tostring(kind))
      end
      if card_schema.aliases ~= nil then
        table.insert(errors, "schema aliases are not supported; update stored cards instead: " .. tostring(kind))
      end
      if type(card_schema.fields) ~= "table" or #card_schema.fields == 0 then
        table.insert(errors, "card schema has no fields: " .. tostring(kind))
      else
        local seen = {}
        for index, field in ipairs(card_schema.fields) do
          local key = type(field) == "table" and util.trim(field.key) or ""
          if not key:match("^[a-z][a-z0-9_]*$") then
            table.insert(errors, string.format("%s field %d has an invalid key: %s", kind, index, key))
          elseif SYSTEM_FIELDS[key] then
            table.insert(errors, string.format("%s field is reserved by the scheduler: %s", kind, key))
          elseif seen[key] then
            table.insert(errors, string.format("%s schema repeats field: %s", kind, key))
          else
            seen[key] = true
          end
          if type(field) == "table" then
            reject_unknown_keys(errors, field, FIELD_OPTIONS, string.format("%s field %s", kind, key))
            for _, property in ipairs({ "label", "title", "default", "placeholder", "help" }) do
              if field[property] ~= nil and type(field[property]) ~= "string" then
                table.insert(errors, string.format("%s field %s.%s must be a string", kind, key, property))
              end
            end
            for _, property in ipairs({ "required", "reveal", "multiline", "typed_answer" }) do
              if field[property] ~= nil and type(field[property]) ~= "boolean" then
                table.insert(errors, string.format("%s field %s.%s must be a boolean", kind, key, property))
              end
            end
            if field.typed_answer == true and field.reveal ~= true then
              table.insert(errors, string.format("%s field %s.typed_answer requires reveal = true", kind, key))
            end
            if field.prompt ~= nil or field.input ~= nil then
              table.insert(errors, string.format("%s field %s contains a removed composer option", kind, key))
            end
          end
        end
        local front = util.trim(card_schema.front)
        if front == "" then
          table.insert(errors, "card schema requires an explicit front field: " .. tostring(kind))
        elseif not seen[front] then
          table.insert(errors, string.format("%s front field is not declared: %s", kind, front))
        end
      end
    end
  end

  local scheduling = config.scheduling or {}
  if type(scheduling) ~= "table" then
    table.insert(errors, "scheduling must be a table")
    scheduling = {}
  else
    reject_unknown_keys(errors, scheduling, SCHEDULING_OPTIONS, "scheduling")
  end
  local numeric_options = {
    again_minutes = { positive = true },
    hard_hours = { positive = true },
    good_days = { positive = true },
    starting_ease = { positive = true },
    min_ease = { positive = true },
    max_ease = { positive = true },
    max_interval_days = { positive = true },
  }
  local parsed = {}
  for key, constraints in pairs(numeric_options) do
    parsed[key] = finite_number(scheduling[key])
    if not parsed[key] or constraints.positive and parsed[key] <= 0 then
      table.insert(errors, "scheduling." .. key .. " must be a positive finite number")
    end
  end
  if parsed.min_ease and parsed.starting_ease and parsed.min_ease > parsed.starting_ease then
    table.insert(errors, "scheduling.min_ease must not exceed starting_ease")
  end
  if parsed.starting_ease and parsed.max_ease and parsed.starting_ease > parsed.max_ease then
    table.insert(errors, "scheduling.starting_ease must not exceed max_ease")
  end
  if parsed.good_days and parsed.max_interval_days and parsed.good_days > parsed.max_interval_days then
    table.insert(errors, "scheduling.good_days must not exceed max_interval_days")
  end
  local leech_threshold = finite_number(config.leech_threshold)
  if not leech_threshold or leech_threshold <= 0 or leech_threshold % 1 ~= 0 then
    table.insert(errors, "leech_threshold must be a positive integer")
  end

  if type(config.ui) ~= "table" then
    table.insert(errors, "ui must be a table")
  else
    reject_unknown_keys(errors, config.ui, UI_OPTIONS, "ui")
    if type(config.ui.show_shortcuts) ~= "boolean" then
      table.insert(errors, "ui.show_shortcuts must be a boolean")
    end

    if type(config.ui.rating_highlights) ~= "table" then
      table.insert(errors, "ui.rating_highlights must be a table")
    else
      reject_unknown_keys(errors, config.ui.rating_highlights, RATING_OPTIONS, "ui.rating_highlights")
      for _, rating in ipairs({ "again", "hard", "good" }) do
        if type(config.ui.rating_highlights[rating]) ~= "table" then
          table.insert(errors, "ui.rating_highlights." .. rating .. " must be a highlight table")
        end
      end
    end

    if type(config.ui.heatmap_highlights) ~= "table" then
      table.insert(errors, "ui.heatmap_highlights must be a table")
    else
      reject_unknown_keys(errors, config.ui.heatmap_highlights, HEATMAP_OPTIONS, "ui.heatmap_highlights")
      for level = 0, 4 do
        local value = config.ui.heatmap_highlights[level]
        if value == nil then
          value = config.ui.heatmap_highlights[tostring(level)]
        end
        if type(value) ~= "table" then
          table.insert(errors, string.format("ui.heatmap_highlights[%d] must be a highlight table", level))
        end
      end
    end
  end

  if config.on_review ~= nil and type(config.on_review) ~= "function" then
    table.insert(errors, "on_review must be a function")
  end

  return errors
end

function M.front(config, card)
  local card_schema = M.for_kind(config, card.kind)
  if not card_schema then
    return "Front", ""
  end

  local front = default_front(card_schema)
  local title = card_schema.label or front
  for _, field in ipairs(card_schema.fields or {}) do
    if field.key == front then
      title = field.title or card_schema.label or front
      break
    end
  end

  return title, M.field_value(card, front)
end

function M.reveal_fields(config, card)
  local card_schema = M.for_kind(config, card.kind)
  local fields = {}
  if not card_schema then
    return fields
  end

  for _, field in ipairs(card_schema.fields or {}) do
    if field.reveal then
      local value = M.field_value(card, field.key)
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

function M.typed_answer_fields(config, card)
  local card_schema = M.for_kind(config, card.kind)
  local fields = {}
  if not card_schema then
    return fields
  end
  for _, field in ipairs(card_schema.fields or {}) do
    if field.typed_answer then
      local value = M.field_value(card, field.key)
      if not util.isempty(value) then
        table.insert(fields, {
          key = field.key,
          title = field.title or field.key,
          value = value,
        })
      end
    end
  end
  return fields
end

function M.composer_fields(config, kind)
  local card_schema = M.for_kind(config, kind)
  local fields = {}

  for _, field in ipairs((card_schema and card_schema.fields) or {}) do
    local label = field.label or (field.key .. ": ")
    local title = field.title
    if util.isempty(title) then
      title = util.trim(tostring(label):gsub(":%s*$", ""))
    end
    table.insert(fields, {
      key = field.key,
      label = label,
      title = title,
      default = field.default or "",
      required = field.required or false,
      multiline = field.multiline or false,
      typed_answer = field.typed_answer or false,
      placeholder = field.placeholder or "",
      help = field.help or "",
    })
  end

  return fields
end

function M.validate_card(config, card)
  local errors = {}
  local card_schema = M.for_kind(config, card.kind)

  if not card_schema then
    table.insert(errors, "unsupported flashcard kind: " .. card.kind)
    return errors
  end

  if not card.closed then
    table.insert(errors, "missing @end")
  end

  for _, syntax_error in ipairs(card.syntax_errors or {}) do
    table.insert(errors, syntax_error)
  end

  local id = identity.card_id(card)
  if not id then
    table.insert(errors, "missing id")
  elseif not identity.is_valid(id) then
    table.insert(errors, "invalid id (use letters, numbers, _, ., :, or -)")
  end

  local duplicate_fields = vim.tbl_keys(card.duplicate_fields or {})
  table.sort(duplicate_fields)
  for _, field in ipairs(duplicate_fields) do
    table.insert(errors, "duplicate field: " .. field)
  end
  for field, replacement in pairs(REMOVED_FIELDS) do
    if card.values[field] ~= nil then
      table.insert(errors, string.format("removed field %s (replace with %s)", field, replacement))
    end
  end

  local allowed_fields = vim.deepcopy(SYSTEM_FIELDS)
  local declared_fields = {}
  for _, field in ipairs(card_schema.fields or {}) do
    allowed_fields[field.key] = true
    declared_fields[field.key] = field
  end
  local present_fields = vim.tbl_keys(card.values or {})
  table.sort(present_fields)
  for _, field in ipairs(present_fields) do
    if not allowed_fields[field] and not REMOVED_FIELDS[field] then
      table.insert(errors, "unknown field: " .. field)
    end
  end

  local multiline_fields = vim.tbl_keys(card.multiline_fields or {})
  table.sort(multiline_fields)
  for _, field in ipairs(multiline_fields) do
    local declaration = declared_fields[field]
    if SYSTEM_FIELDS[field] or declaration and declaration.multiline ~= true then
      table.insert(errors, "field does not allow multiline values: " .. field)
    end
  end

  local score = util.trim(card.values.score)
  if score ~= "" and score ~= "1" and score ~= "2" and score ~= "3" then
    table.insert(errors, "invalid score")
  end
  local due = util.trim(card.values.due)
  if due ~= "" and not schedule.parse_due(due) then
    table.insert(errors, "invalid due")
  end
  local reviewed = util.trim(card.values.reviewed)
  if reviewed ~= "" and not schedule.parse_due(reviewed) then
    table.insert(errors, "invalid reviewed")
  end
  local available_at = util.trim(card.values.available_at)
  if available_at ~= "" and not schedule.parse_due(available_at) then
    table.insert(errors, "invalid available_at")
  end
  local scheduling = config.scheduling or schedule.DEFAULTS
  add_number_error(errors, card, "interval", {
    nonnegative = true,
    maximum = tonumber(scheduling.max_interval_days) or schedule.DEFAULTS.max_interval_days,
  })
  add_number_error(errors, card, "ease", {
    minimum = tonumber(scheduling.min_ease) or schedule.DEFAULTS.min_ease,
    maximum = tonumber(scheduling.max_ease) or schedule.DEFAULTS.max_ease,
  })
  add_number_error(errors, card, "reps", { nonnegative = true, integer = true })
  add_number_error(errors, card, "lapses", { nonnegative = true, integer = true })

  local lifecycle = util.trim(card.values.lifecycle):lower()
  if
    lifecycle ~= ""
    and lifecycle ~= "new"
    and lifecycle ~= "learning"
    and lifecycle ~= "review"
    and lifecycle ~= "relearning"
  then
    table.insert(errors, "invalid lifecycle")
  end
  local availability = util.trim(card.values.availability):lower()
  if availability ~= "" and availability ~= "active" and availability ~= "suspended" and availability ~= "buried" then
    table.insert(errors, "invalid availability")
  elseif availability == "buried" and available_at == "" then
    table.insert(errors, "buried cards require available_at")
  end

  for _, field in ipairs(card_schema.fields or {}) do
    if field.required and util.isempty(M.field_value(card, field.key)) then
      table.insert(errors, "missing " .. field.key)
    end
  end

  return errors
end

---Render one card field. A multiline value uses an explicit block whose
---container indentation is exactly two spaces beyond the card directive. Any
---additional indentation is part of the value and survives a round trip.
---@param field string
---@param value any
---@param opts? { force_multiline?: boolean, indent?: string }
---@return string[]
function M.field_lines(field, value, opts)
  opts = opts or {}
  local indent = tostring(opts.indent or "")
  value = tostring(value or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  if value:find("\n", 1, true) or opts.force_multiline == true then
    local lines = { indent .. field .. ": |" }
    for _, line in ipairs(util.value_lines(value)) do
      table.insert(lines, indent .. "  " .. line)
    end
    return lines
  end
  return { indent .. field .. ": " .. util.trim(value) }
end

function M.card_lines(config, kind, values)
  values = values or {}
  local card_schema = M.for_kind(config, kind)
  local lines = {
    "",
    "@flashcard " .. kind,
    "id: " .. (identity.card_id({ values = values }) or identity.generate()),
  }

  for _, field in ipairs((card_schema and card_schema.fields) or {}) do
    local value = tostring(values[field.key] or "")
    if field.required or not util.isempty(value) then
      local preserve_edge_space = field.multiline == true and (value:match("^%s") or value:match("%s$")) ~= nil
      vim.list_extend(lines, M.field_lines(field.key, value, { force_multiline = preserve_edge_space }))
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

local score_values = {
  ["1"] = 1,
  again = 1,
  ["2"] = 2,
  hard = 2,
  ["3"] = 3,
  good = 3,
}

function M.score_filter(value)
  value = util.trim(value):lower()
  if value == "new" then
    return {
      label = "new",
      matches = function(card)
        return M.card_score(card) == nil
      end,
    }
  end

  local score = score_values[value]
  if not score then
    return nil
  end

  local labels = {
    [1] = "again",
    [2] = "hard",
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
    again = 0,
    hard = 0,
    good = 0,
  }

  for _, card in ipairs(cards) do
    local score = M.card_score(card)
    if score == 1 then
      stats.again = stats.again + 1
    elseif score == 2 then
      stats.hard = stats.hard + 1
    elseif score == 3 then
      stats.good = stats.good + 1
    else
      stats.new = stats.new + 1
    end
  end

  return stats
end

return M
