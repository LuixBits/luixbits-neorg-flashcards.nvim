local highlights = require("neorg_flashcards.highlights")
local schedule = require("neorg_flashcards.schedule")
local schema = require("neorg_flashcards.schema")
local util = require("neorg_flashcards.util")

local M = {}

local TOP_LEVEL_OPTIONS = {
  collections = true,
  default_collection = true,
  on_review = true,
  ui = true,
}

local COLLECTION_OPTIONS = {
  default_card_type = true,
  default_file = true,
  history_file = true,
  label = true,
  leech_threshold = true,
  path = true,
  scheduling = true,
  schemas = true,
}

local UI_DEFAULTS = {
  show_shortcuts = true,
  rating_highlights = vim.deepcopy(highlights.defaults.rating_highlights),
  heatmap_highlights = vim.deepcopy(highlights.defaults.heatmap_highlights),
}

local function sorted_keys(value)
  local keys = vim.tbl_keys(value or {})
  table.sort(keys, function(left, right)
    return tostring(left) < tostring(right)
  end)
  return keys
end

local function reject_unknown(value, allowed, context)
  local errors = {}
  if type(value) ~= "table" then
    return errors
  end
  for _, key in ipairs(sorted_keys(value)) do
    if not allowed[key] then
      table.insert(errors, string.format("unknown %s option: %s", context, tostring(key)))
    end
  end
  return errors
end

local function append_errors(target, source, prefix)
  for _, message in ipairs(source or {}) do
    table.insert(target, prefix and (prefix .. message) or message)
  end
end

local function absolute_path(value)
  return vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(value), ":p"))
end

local function resolve_inside(root, value, fallback)
  value = util.isempty(value) and fallback or vim.fn.expand(value)
  if not value:match("^/") then
    value = root .. "/" .. value
  end
  return absolute_path(value)
end

local function same_existing_file(left, right)
  if left == right then
    return true
  end
  local uv = vim.uv or vim.loop
  local left_stat = uv.fs_stat(left)
  local right_stat = uv.fs_stat(right)
  return left_stat
    and right_stat
    and left_stat.dev ~= nil
    and left_stat.ino ~= nil
    and left_stat.dev == right_stat.dev
    and left_stat.ino == right_stat.ino
end

local function merge_ui(opts)
  local ui = vim.tbl_deep_extend("force", vim.deepcopy(UI_DEFAULTS), opts or {})
  local rating_overrides = type(opts) == "table" and opts.rating_highlights or nil
  if type(rating_overrides) == "table" then
    for _, rating in ipairs({ "again", "hard", "good" }) do
      if rating_overrides[rating] ~= nil then
        ui.rating_highlights[rating] = vim.deepcopy(rating_overrides[rating])
      end
    end
  end
  local heatmap_overrides = type(opts) == "table" and opts.heatmap_highlights or nil
  if type(heatmap_overrides) == "table" then
    for level = 0, 4 do
      local override = heatmap_overrides[level]
      if override == nil then
        override = heatmap_overrides[tostring(level)]
      end
      if override ~= nil then
        ui.heatmap_highlights[level] = vim.deepcopy(override)
      end
      ui.heatmap_highlights[tostring(level)] = nil
    end
  end
  return ui
end

local function normalize_collection(id, value, shared)
  local errors = {}
  if type(value) ~= "table" then
    return nil, { string.format("collection %s must be a table", id) }
  end
  append_errors(errors, reject_unknown(value, COLLECTION_OPTIONS, "collection " .. id))

  if type(value.path) ~= "string" or util.trim(value.path) == "" then
    table.insert(errors, "collection " .. id .. ".path is required")
  end
  if value.label ~= nil and type(value.label) ~= "string" then
    table.insert(errors, "collection " .. id .. ".label must be a string")
  end
  if value.default_file ~= nil and type(value.default_file) ~= "string" then
    table.insert(errors, "collection " .. id .. ".default_file must be a string")
  end
  if value.history_file ~= nil and type(value.history_file) ~= "string" then
    table.insert(errors, "collection " .. id .. ".history_file must be a string")
  end
  if type(value.default_card_type) ~= "string" or util.trim(value.default_card_type) == "" then
    table.insert(errors, "collection " .. id .. ".default_card_type is required")
  end
  if value.scheduling ~= nil and type(value.scheduling) ~= "table" then
    table.insert(errors, "collection " .. id .. ".scheduling must be a table")
  end
  if #errors > 0 then
    return nil, errors
  end

  local root = absolute_path(value.path)
  local context = {
    id = id,
    label = util.isempty(value.label) and id or util.trim(value.label),
    path = root,
    default_file = resolve_inside(root, value.default_file, "cards.norg"),
    history_file = resolve_inside(root, value.history_file, "reviews.jsonl"),
    default_card_type = value.default_card_type,
    schemas = vim.deepcopy(value.schemas),
    scheduling = vim.tbl_deep_extend("force", vim.deepcopy(schedule.DEFAULTS), value.scheduling or {}),
    leech_threshold = value.leech_threshold == nil and 8 or value.leech_threshold,
    ui = vim.deepcopy(shared.ui),
    on_review = shared.on_review,
  }

  append_errors(errors, schema.validate_collection(context), "collection " .. id .. ": ")
  if #errors > 0 then
    return nil, errors
  end

  return context, errors
end

local function roots_overlap(left, right)
  return util.path_is_within(left.path, right.path) or util.path_is_within(right.path, left.path)
end

---Validate and normalize the public workspace configuration.
---@param opts table
---@return table|nil workspace
---@return string[] errors
function M.prepare(opts)
  local errors = {}
  if type(opts) ~= "table" then
    return nil, { "options must be a table" }
  end
  append_errors(errors, reject_unknown(opts, TOP_LEVEL_OPTIONS, "setup"))
  if type(opts.collections) ~= "table" or vim.tbl_isempty(opts.collections) then
    table.insert(errors, "at least one collection is required")
  end
  if type(opts.default_collection) ~= "string" or util.trim(opts.default_collection) == "" then
    table.insert(errors, "default_collection is required")
  end
  if opts.on_review ~= nil and type(opts.on_review) ~= "function" then
    table.insert(errors, "on_review must be a function")
  end
  if opts.ui ~= nil and type(opts.ui) ~= "table" then
    table.insert(errors, "ui must be a table")
  end
  if #errors > 0 then
    return nil, errors
  end

  local shared = { ui = merge_ui(opts.ui), on_review = opts.on_review }
  local contexts = {}
  for _, id in ipairs(sorted_keys(opts.collections)) do
    if type(id) ~= "string" or not id:match("^[a-z][a-z0-9_-]*$") then
      table.insert(errors, "collection id must use lowercase letters, numbers, _ or -: " .. tostring(id))
    else
      local context, context_errors = normalize_collection(id, opts.collections[id], shared)
      append_errors(errors, context_errors)
      if context then
        contexts[id] = context
      end
    end
  end

  local default_id = util.trim(opts.default_collection)
  if not contexts[default_id] then
    table.insert(errors, "default_collection does not name a configured collection: " .. default_id)
  end

  local ids = sorted_keys(contexts)
  for left_index = 1, #ids do
    for right_index = left_index + 1, #ids do
      local left = contexts[ids[left_index]]
      local right = contexts[ids[right_index]]
      if roots_overlap(left, right) then
        table.insert(errors, string.format("collection paths must not overlap: %s and %s", left.id, right.id))
      elseif same_existing_file(left.history_file, right.history_file) then
        table.insert(errors, string.format("collections must not share review history: %s and %s", left.id, right.id))
      end
    end
  end
  if #errors > 0 then
    return nil, errors
  end

  for _, id in ipairs(ids) do
    local context = contexts[id]
    local ok_mkdir, mkdir_result = pcall(vim.fn.mkdir, context.path, "p")
    if not ok_mkdir or (mkdir_result == 0 and vim.fn.isdirectory(context.path) ~= 1) then
      return nil, { string.format("could not create collection %s: %s", id, tostring(mkdir_result)) }
    end
    local root, root_error = util.pin_directory(context.path)
    if not root then
      return nil, { string.format("collection %s: %s", id, tostring(root_error)) }
    end
    context._root = root
  end

  return {
    active_id = default_id,
    default_id = default_id,
    collections = contexts,
    ids = ids,
    ui = shared.ui,
    on_review = shared.on_review,
  }, {}
end

function M.active(workspace)
  return workspace and workspace.collections[workspace.active_id] or nil
end

function M.get(workspace, id)
  return workspace and workspace.collections[id] or nil
end

function M.ids(workspace)
  return vim.deepcopy(workspace and workspace.ids or {})
end

function M.select(workspace, id)
  local context = M.get(workspace, id)
  if not context then
    return nil, "Unknown flashcard collection: " .. tostring(id)
  end
  workspace.active_id = id
  return context
end

function M.public(context)
  if not context then
    return nil
  end
  local result = vim.deepcopy(context)
  result._root = nil
  result.on_review = nil
  return result
end

return M
