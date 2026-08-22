local form = require("neorg_flashcards.form")
local help = require("neorg_flashcards.help")
local health = require("neorg_flashcards.health")
local history = require("neorg_flashcards.history")
local overview = require("neorg_flashcards.overview")
local parser = require("neorg_flashcards.parser")
local presets = require("neorg_flashcards.presets")
local review = require("neorg_flashcards.review")
local schedule = require("neorg_flashcards.schedule")
local schema = require("neorg_flashcards.schema")
local stats = require("neorg_flashcards.stats")
local store = require("neorg_flashcards.store")
local util = require("neorg_flashcards.util")

local M = {}
M.presets = presets

local defaults = {
  flashcards_dir = vim.fn.expand("~/notes/flashcards"),
  default_file = vim.fn.expand("~/notes/flashcards/cards.norg"),
  default_kind = nil,
  schemas = vim.deepcopy(schema.defaults),
  scheduling = vim.deepcopy(schedule.DEFAULTS),
  leech_threshold = 8,
  ui = {
    show_shortcuts = true,
    rating_highlights = {
      again = { link = "DiagnosticError" },
      hard = { link = "DiagnosticWarn" },
      good = { link = "DiagnosticOk" },
    },
  },
}

local config = vim.deepcopy(defaults)
local pending_history = {}
local add_anchor_ns = vim.api.nvim_create_namespace("neorg_flashcards_add_anchor")
local active_add_anchor = nil
-- Keep destination identities, not snapshots of their queues. The outbox on
-- disk is the source of truth so concurrent Neovim instances can merge and
-- drain events without replacing one another's stale in-memory copies.
local failed_history_destinations = {}
local reported_outbox_errors = {}
local failed_history_memory = {}
local generated_history_event_sequence = 0
local record_card_state = function() end

local command_routes = {
  "overview",
  "cards",
  "stats",
  "review",
  "add",
  "open",
  "check",
  "help",
}

local function collection_root(card_config)
  card_config = card_config or config
  return card_config._collection_root or card_config.flashcards_dir
end

local function preflight_target(path, card_config)
  return store.resolve_path(path, { allowed_root = collection_root(card_config) })
end

local function clear_add_anchor(expected)
  local anchor = active_add_anchor
  if expected and anchor ~= expected then
    return
  end
  active_add_anchor = nil
  if not anchor or not anchor.bufnr or not anchor.mark_id or not vim.api.nvim_buf_is_valid(anchor.bufnr) then
    return
  end
  pcall(vim.api.nvim_buf_del_extmark, anchor.bufnr, add_anchor_ns, anchor.mark_id)
end

local function capture_add_target(path, opts)
  opts = opts or {}
  clear_add_anchor()

  path = vim.fs.normalize(vim.fn.expand(path))
  local anchor = {
    mode = opts.append and "end" or "row",
    row = opts.row,
    bufnr = opts.bufnr,
  }

  if anchor.mode == "row" and anchor.bufnr and vim.api.nvim_buf_is_valid(anchor.bufnr) then
    local ok, mark_id = pcall(vim.api.nvim_buf_set_extmark, anchor.bufnr, add_anchor_ns, anchor.row, 0, {
      right_gravity = true,
    })
    if ok then
      anchor.mark_id = mark_id
    end
  end

  active_add_anchor = anchor
  return {
    path = path,
    label = util.path_label(path, config.flashcards_dir),
    create_with_heading = opts.create_with_heading == true,
    anchor = anchor,
  }
end

local function resolve_add_row(target, lines, bufnr)
  local anchor = target.anchor
  if anchor.mode == "end" then
    return #lines
  end

  local row = anchor.row or #lines
  if
    anchor.mark_id
    and anchor.bufnr == bufnr
    and vim.api.nvim_buf_is_valid(anchor.bufnr)
    and vim.api.nvim_buf_is_loaded(anchor.bufnr)
  then
    local ok, position = pcall(vim.api.nvim_buf_get_extmark_by_id, anchor.bufnr, add_anchor_ns, anchor.mark_id, {})
    if ok and position and #position > 0 then
      row = position[1]
    end
  end

  return math.max(0, math.min(row, #lines))
end

local function advance_add_anchor(target, row, count, bufnr)
  local anchor = target.anchor
  if anchor.mode == "end" then
    return
  end

  anchor.row = row + count
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end

  local ok, mark_id = pcall(vim.api.nvim_buf_set_extmark, bufnr, add_anchor_ns, anchor.row, 0, {
    id = anchor.bufnr == bufnr and anchor.mark_id or nil,
    right_gravity = true,
  })
  if ok then
    anchor.bufnr = bufnr
    anchor.mark_id = mark_id
  end
end

local function add_result(target, ok, persisted, message)
  return {
    ok = ok == true,
    persisted = persisted == true,
    path = target.path,
    message = message,
  }
end

local function notify_add_result(result)
  local level = vim.log.levels.ERROR
  if result.ok then
    level = result.persisted and vim.log.levels.INFO or vim.log.levels.WARN
  end
  pcall(util.notify, result.message, level)
end

local function refresh_after_add()
  local ok, err = pcall(overview.refresh)
  if not ok then
    pcall(util.notify, "Flashcard saved, but the overview could not refresh: " .. tostring(err), vim.log.levels.WARN)
  end
end

local function current_buffer_is_norg()
  local path = vim.api.nvim_buf_get_name(0)
  return path ~= "" and path:match("%.norg$")
end

local function form_blocks(action)
  if not form.is_open() then
    return false
  end
  util.notify("Finish or discard the open flashcard before " .. action, vim.log.levels.WARN)
  return true
end

local function review_blocks(action)
  if not review.is_active() then
    return false
  end
  util.notify("Finish or close the active review before " .. action, vim.log.levels.WARN)
  return true
end

local function ensure_editable_flashcard_buffer()
  if current_buffer_is_norg() then
    return false, true
  end

  local opened = M.open_flashcards()
  return true, opened == true
end

---Build and commit a card insertion through the buffer-aware store.
---@param kind string
---@param values table<string, string>
---@param target table
---@param card_config table
---@return table result
local function insert_card(kind, values, target, card_config)
  local store_opts = { allowed_root = collection_root(card_config) }
  local _, target_err = store.resolve_path(target.path, store_opts)
  if target_err then
    local result = add_result(target, false, false, "Could not save flashcard: " .. tostring(target_err))
    notify_add_result(result)
    return result
  end

  if target.create_with_heading then
    local _, parent_err = store.ensure_parent(target.path, store_opts)
    if parent_err then
      local result = add_result(target, false, false, "Could not save flashcard: " .. tostring(parent_err))
      notify_add_result(result)
      return result
    end
    local _, recheck_err = store.resolve_path(target.path, store_opts)
    if recheck_err then
      local result = add_result(target, false, false, "Could not save flashcard: " .. tostring(recheck_err))
      notify_add_result(result)
      return result
    end
  end

  local lines, bufnr, err = store.read_lines(target.path, store_opts)
  if
    not lines
    and target.create_with_heading
    and vim.fn.filereadable(target.path) == 0
    and not util.loaded_buffer(target.path)
  then
    lines = { "* Flashcards", "" }
    bufnr = nil
    err = nil
  end
  if not lines then
    local result = add_result(target, false, false, "Could not save flashcard: " .. tostring(err))
    notify_add_result(result)
    return result
  end

  local candidate = vim.deepcopy(lines)
  local card_lines = schema.card_lines(card_config, kind, values)
  local row = resolve_add_row(target, candidate, bufnr)
  if row == #candidate and #candidate > 0 and candidate[#candidate] == "" and card_lines[1] == "" then
    table.remove(card_lines, 1)
  end
  for index, line in ipairs(card_lines) do
    table.insert(candidate, row + index, line)
  end

  local ok, write_err, persisted = store.write_lines(target.path, bufnr, candidate, store_opts)
  if not ok then
    local result = add_result(target, false, false, "Could not save flashcard: " .. tostring(write_err))
    notify_add_result(result)
    return result
  end

  advance_add_anchor(target, row, #card_lines, bufnr)
  local message = write_err or ("Flashcard saved to " .. target.label)
  local result = add_result(target, true, persisted, message)

  -- Persistence is already committed at this point. UI hooks are deliberately
  -- best effort so an error cannot leave a filled form that duplicates the
  -- card when the user retries.
  notify_add_result(result)
  refresh_after_add()
  return result
end

local function add_card(kind)
  if not schema.for_kind(config, kind) then
    util.notify("Unsupported flashcard kind: " .. kind, vim.log.levels.ERROR)
    return
  end

  if form_blocks("adding another card") or review_blocks("adding a card") then
    return
  end

  local append, ready = ensure_editable_flashcard_buffer()
  if not ready then
    return
  end
  local target_buf = vim.api.nvim_get_current_buf()
  local target_path = vim.api.nvim_buf_get_name(target_buf)
  local _, target_err = preflight_target(target_path)
  if target_err then
    util.notify(
      "Flashcards can only be added inside the configured collection: " .. tostring(target_err),
      vim.log.levels.ERROR
    )
    return
  end
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local target = capture_add_target(target_path, {
    append = append,
    bufnr = target_buf,
    row = row,
    create_with_heading = append and target_path == config.default_file,
  })
  local card_config = config

  local opened = form.open(card_config, kind, {
    target_label = target.label,
    target_path = target.path,
    on_close = function()
      clear_add_anchor(target.anchor)
    end,
    on_save = function(values)
      return insert_card(kind, values, target, card_config)
    end,
  })
  if not opened then
    clear_add_anchor()
  end
end

function M.open_flashcards()
  if form_blocks("opening the collection") or review_blocks("opening the collection") then
    return false
  end

  local _, target_err = preflight_target(config.default_file)
  if target_err then
    util.notify("Could not open flashcards: " .. tostring(target_err), vim.log.levels.ERROR)
    return false
  end

  local _, parent_err = store.ensure_parent(config.default_file, { allowed_root = collection_root() })
  if parent_err then
    util.notify("Could not create flashcard directory: " .. tostring(parent_err), vim.log.levels.ERROR)
    return false
  end
  local _, recheck_err = preflight_target(config.default_file)
  if recheck_err then
    util.notify("Could not open flashcards: " .. tostring(recheck_err), vim.log.levels.ERROR)
    return false
  end

  local existed = vim.fn.filereadable(config.default_file) == 1
  if not existed then
    local wrote, write_err, persisted = store.write_lines(config.default_file, nil, {
      "* Flashcards",
      "",
    }, { allowed_root = collection_root() })
    if not wrote or not persisted then
      util.notify("Could not create flashcard file: " .. tostring(write_err), vim.log.levels.ERROR)
      return false
    end
  end

  local _, final_err = preflight_target(config.default_file)
  if final_err then
    util.notify("Could not open flashcards: " .. tostring(final_err), vim.log.levels.ERROR)
    return false
  end
  overview.close()
  local opened, open_err = pcall(vim.cmd.edit, util.fname(config.default_file))
  if not opened then
    util.notify("Could not open flashcards: " .. tostring(open_err), vim.log.levels.ERROR)
    return false
  end

  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(0), 0 })
  return true
end

function M.add_kind(kind)
  kind = util.trim(kind)
  if kind == "" then
    kind = util.trim(config.default_kind)
  end

  if kind == "" then
    util.notify("No flashcard kind given and default_kind is not configured", vim.log.levels.ERROR)
    return
  end

  if overview.is_focused() then
    return M.add_to_default(kind)
  end
  add_card(kind)
end

---Add a card straight to the default file, no matter which buffer is current.
---Used by the overview's `a` key. Falls back to default_kind.
---@param kind string|nil
function M.add_to_default(kind)
  kind = util.trim(kind or "")
  if kind == "" then
    kind = util.trim(config.default_kind or "")
  end

  if kind == "" then
    util.notify("No flashcard kind given and default_kind is not configured", vim.log.levels.ERROR)
    return
  end

  if not schema.for_kind(config, kind) then
    util.notify("Unsupported flashcard kind: " .. kind, vim.log.levels.ERROR)
    return
  end

  if form_blocks("adding another card") or review_blocks("adding a card") then
    return
  end

  local _, target_err = preflight_target(config.default_file)
  if target_err then
    util.notify("Could not add flashcard: " .. tostring(target_err), vim.log.levels.ERROR)
    return false
  end

  local target = capture_add_target(config.default_file, {
    append = true,
    create_with_heading = true,
  })
  local card_config = config
  local opened = form.open(card_config, kind, {
    target_label = target.label,
    target_path = target.path,
    on_close = function()
      clear_add_anchor(target.anchor)
    end,
    on_save = function(values)
      return insert_card(kind, values, target, card_config)
    end,
  })
  if not opened then
    clear_add_anchor()
  end
end

function M.validate_file()
  local cards = parser.parse_buffer(0)
  if #cards == 0 then
    util.notify("No @flashcard blocks found", vim.log.levels.WARN)
    return
  end

  local _, errors = parser.valid_cards(config, cards)
  if #errors == 0 then
    util.notify(string.format("%d flashcard block(s) valid", #cards))
  else
    util.notify(table.concat(errors, "\n"), vim.log.levels.ERROR)
  end
end

function M.validate_collection()
  if form_blocks("checking the collection") or review_blocks("checking the collection") then
    return false
  end
  local cards, errors = parser.collect_flashcards(config)
  local issues = health.inspect(config, cards)
  local counts = health.counts(issues)
  local messages = vim.deepcopy(errors)
  local _, history_errors = history.read(config)
  vim.list_extend(messages, history_errors)
  for _, item in ipairs(issues) do
    table.insert(messages, health.format(config, item))
  end

  if #messages == 0 then
    util.notify(string.format("Collection healthy: %d valid flashcard(s)", #cards))
    return true, cards, issues
  end

  local level = (#errors > 0 or counts.error > 0) and vim.log.levels.ERROR or vim.log.levels.WARN
  local items = {}
  for _, message in ipairs(errors) do
    table.insert(items, { text = message, type = "E" })
  end
  for _, message in ipairs(history_errors) do
    table.insert(items, { text = message, type = "W" })
  end
  for _, item in ipairs(issues) do
    table.insert(items, {
      filename = item.card.path,
      lnum = item.card.start_line,
      text = item.message,
      type = item.severity == "error" and "E" or "W",
    })
  end
  vim.fn.setqflist({}, " ", { title = "Flashcards collection health", items = items })
  vim.cmd("copen")
  util.notify(string.format("Flashcard health: %d issue(s) opened in the quickfix list", #items), level)
  return level ~= vim.log.levels.ERROR, cards, issues, errors
end

function M.review_all()
  if form_blocks("starting a review") then
    return false
  end
  local cards, errors = parser.collect_flashcards(config)
  local active = {}
  local now = os.time()
  for _, card in ipairs(cards) do
    if schedule.is_available(card, now) then
      table.insert(active, card)
    end
  end
  review.start(active, errors, "all", "No active flashcards")
end

function M.review_due()
  if form_blocks("starting a review") then
    return false
  end
  local cards, errors = parser.collect_flashcards(config)
  local now = os.time()
  local due = {}
  for _, card in ipairs(cards) do
    if schedule.is_due(card, now) then
      table.insert(due, card)
    end
  end

  local empty_message = "No due flashcards"
  local next_due = schedule.next_due(cards, now)
  if next_due then
    empty_message = empty_message .. " — next at " .. schedule.format_due(next_due)
  end

  review.start(due, errors, "due", empty_message, { sort = "due" })
end

function M.overview(opts)
  if form_blocks("opening the hub") or review_blocks("opening the hub") then
    return false
  end
  overview.open(function()
    return parser.collect_flashcards(config)
  end, opts)
end

function M.stats()
  M.overview({ view = "stats" })
end

function M.cards()
  M.overview({ view = "cards" })
end

-- Validate the current file against every card identity in the collection.
-- Without the wider scope, an ID duplicated in another file could still enter
-- review history through `review file` even though collection review correctly
-- quarantines both copies.
local function current_file_review_cards()
  local current_path = util.canonical_path(vim.api.nvim_buf_get_name(0))
  local root, root_err = util.resolve_pinned_directory(collection_root())
  if not root then
    return {}, { tostring(root_err) }
  end
  if current_path == "" or not util.resolved_path_is_within(current_path, root) then
    return {}, { "Current review file must be saved inside flashcards_dir" }
  end
  local current_cards = parser.parse_buffer(0)
  local current_set = {}
  for _, card in ipairs(current_cards) do
    current_set[card] = true
  end

  local collection_cards, collection_errors, collection_invalid = parser.collect_flashcards(config)
  local unreadable_sources = {}
  for _, message in ipairs(collection_errors or {}) do
    if tostring(message):find("could not read file", 1, true) then
      table.insert(unreadable_sources, message)
    end
  end
  if #unreadable_sources > 0 then
    return {}, unreadable_sources
  end
  local identity_scope = {}
  local function add_other_file(card)
    if not card then
      return
    end
    local card_path = util.canonical_path(card.path)
    if current_path == "" or card_path ~= current_path then
      table.insert(identity_scope, card)
    end
  end
  for _, card in ipairs(collection_cards or {}) do
    add_other_file(card)
  end
  for _, descriptor in ipairs(collection_invalid or {}) do
    add_other_file(descriptor.card)
  end
  vim.list_extend(identity_scope, current_cards)

  local safe, _, invalid = parser.valid_cards(config, identity_scope)
  local selected, errors = {}, {}
  for _, card in ipairs(safe) do
    if current_set[card] then
      table.insert(selected, card)
    end
  end
  for _, descriptor in ipairs(invalid) do
    if current_set[descriptor.card] then
      table.insert(errors, string.format("%s: %s", descriptor.source, table.concat(descriptor.messages, ", ")))
    end
  end
  return selected, errors
end

function M.review_file()
  if form_blocks("starting a review") then
    return false
  end
  local cards, errors = current_file_review_cards()
  local active = {}
  local now = os.time()
  for _, card in ipairs(cards) do
    if schedule.is_available(card, now) then
      table.insert(active, card)
    end
  end
  review.start(active, errors, "file", "No active flashcards in this file")
end

function M.review_tag(tag)
  if form_blocks("starting a review") then
    return false
  end
  tag = util.trim(tag)

  if tag == "" then
    vim.ui.input({ prompt = "Tag: " }, function(input)
      if input == nil then
        util.notify("Tag review cancelled", vim.log.levels.WARN)
        return
      end
      M.review_tag(input)
    end)
    return
  end

  local cards, errors = parser.collect_flashcards(config)
  local filtered = {}
  local now = os.time()
  for _, card in ipairs(cards) do
    if schedule.is_available(card, now) and schema.card_has_tag(card, tag) then
      table.insert(filtered, card)
    end
  end

  review.start(filtered, errors, "tag:" .. tag, "No flashcards found with tag: " .. tag)
end

function M.review_score(score)
  if form_blocks("starting a review") then
    return false
  end
  score = util.trim(score)

  if score == "" then
    vim.ui.input({ prompt = "Rating (again/hard/good/new): " }, function(input)
      if input == nil then
        util.notify("Rating review cancelled", vim.log.levels.WARN)
        return
      end
      M.review_score(input)
    end)
    return
  end

  local filter = schema.score_filter(score)
  if not filter then
    util.notify("Unknown rating: " .. score .. " (use again, hard, good, new, or 1/2/3)", vim.log.levels.ERROR)
    return
  end

  local cards, errors = parser.collect_flashcards(config)
  local filtered = {}
  local now = os.time()
  for _, card in ipairs(cards) do
    if schedule.is_available(card, now) and filter.matches(card) then
      table.insert(filtered, card)
    end
  end

  review.start(filtered, errors, "score:" .. filter.label, "No flashcards found with score: " .. filter.label)
end

function M.close_review()
  review.close()
end

function M.flip_or_next()
  review.flip_or_next()
end

function M.next_card()
  review.next()
end

function M.previous_card()
  review.previous()
end

function M.rate_current(score)
  review.rate_current(score)
end

function M.edit_current_card()
  review.edit_current()
end

function M.type_answer()
  review.type_answer()
end

function M.hint_current()
  review.hint()
end

function M.undo_last_rating()
  return review.undo_last()
end

function M.bury_current()
  return review.bury_current()
end

function M.suspend_current()
  return review.suspend_current()
end

function M.get_review_state()
  return review.get_session_state()
end

function M.help()
  help.open()
end

local function update_card(card, updates, success_message, cards)
  if not card then
    return false, "No flashcard selected"
  end
  local ok, message, persisted = store.set_card_fields(card, updates, {
    allowed_root = collection_root(),
    cards = cards or { card },
  })
  if not ok then
    util.notify(message, vim.log.levels.ERROR)
    return false, message
  end
  if message then
    util.notify(message, persisted and vim.log.levels.INFO or vim.log.levels.WARN)
  elseif success_message then
    util.notify(success_message)
  end
  overview.refresh()
  return true, message, persisted
end

local function next_day(now)
  local date = os.date("*t", now or os.time())
  return os.time({
    year = date.year,
    month = date.month,
    day = date.day + 1,
    hour = 0,
    min = 0,
    sec = 0,
  })
end

local function emit_card_state(card, event, persisted)
  local now = os.time()
  record_card_state({
    event = event,
    type = "card_state",
    persisted = persisted == true,
    card_ref = {
      id = schema.card_id(card),
      path = card.path,
      start_line = card.start_line,
      kind = card.kind,
    },
    card_id = schema.card_id(card),
    path = card.path,
    start_line = card.start_line,
    timestamp = now,
    epoch = now,
  })
end

function M.toggle_suspend(card, context)
  local status = schedule.card_state(card, os.time(), config.scheduling)
  local suspended = status.availability ~= "suspended"
  local ok, message, persisted = update_card(
    card,
    { { field = "availability", value = suspended and "suspended" or "active" } },
    suspended and "Flashcard suspended" or "Flashcard resumed",
    context and context.cards
  )
  if ok and not (context and context._review_emits_state_event) then
    emit_card_state(card, suspended and "suspended" or "resumed", persisted)
  end
  return ok, message, persisted
end

function M.bury_card(card, context)
  local ok, message, persisted = update_card(card, {
    { field = "availability", value = "buried" },
    { field = "available_at", value = schedule.format_due(next_day()) },
  }, "Flashcard buried until tomorrow", context and context.cards)
  if ok and not (context and context._review_emits_state_event) then
    emit_card_state(card, "buried", persisted)
  end
  return ok, message, persisted
end

function M.toggle_bury(card, context)
  local status = schedule.card_state(card, os.time(), config.scheduling)
  if status.availability == "buried" then
    local ok, message, persisted = update_card(card, {
      { field = "availability", value = "active" },
      { field = "available_at", value = "" },
    }, "Flashcard unburied", context and context.cards)
    if ok and not (context and context._review_emits_state_event) then
      emit_card_state(card, "unburied", persisted)
    end
    return ok, message, persisted
  end
  return M.bury_card(card, context)
end

---Delete the exact source block represented by a collected card.
---Review history is intentionally retained as an append-only record.
function M.delete_card(card)
  local ok, message, persisted = store.delete_card(card, { allowed_root = collection_root() })
  if not ok then
    util.notify(message or "Could not delete flashcard", vim.log.levels.ERROR)
    return false, message, false
  end
  if message then
    util.notify(message, persisted and vim.log.levels.INFO or vim.log.levels.WARN)
  elseif persisted then
    util.notify("Flashcard deleted")
  end
  return true, message, persisted
end

---Edit schema-owned card content in the same protected composer used for add.
---Malformed blocks still open as source because structural repair requires the
---literal Neorg text and metadata to remain visible.
function M.edit_card(card, context)
  if not card then
    return false
  end
  if context and context.invalid then
    util.notify("This block needs source-level repair before structured editing", vim.log.levels.WARN)
    M.open_card(card)
    return true
  end
  if form_blocks("editing another card") or review_blocks("editing a card") then
    return false
  end
  local _, target_err = preflight_target(card.path)
  if target_err then
    util.notify("Could not edit flashcard: " .. tostring(target_err), vim.log.levels.ERROR)
    return false
  end

  local fields = schema.composer_fields(config, card.kind)
  local field_names = {}
  for _, field in ipairs(fields) do
    table.insert(field_names, field.key)
  end
  local card_config = config
  local opened = form.open(card_config, card.kind, {
    edit = true,
    allow_save_new = false,
    title = " Edit " .. ((schema.for_kind(card_config, card.kind) or {}).label or card.kind) .. " card ",
    target_label = util.path_label(card.path, card_config.flashcards_dir),
    target_path = card.path,
    initial_values = card.values,
    on_save = function(values)
      local replacements = {}
      for _, field in ipairs(field_names) do
        local value = util.trim(values[field])
        if value ~= "" then
          replacements[field] = value
        end
      end
      local ok, message, persisted = store.restore_card_fields(card, replacements, field_names, {
        allowed_root = collection_root(card_config),
        cards = context and context.cards or { card },
      })
      if not ok then
        return { ok = false, persisted = false, path = card.path, message = message }
      end
      if message then
        util.notify(message, persisted and vim.log.levels.INFO or vim.log.levels.WARN)
      else
        util.notify("Flashcard updated")
      end
      refresh_after_add()
      return { ok = true, persisted = persisted, path = card.path, message = message }
    end,
  })
  return opened == true
end

function M.open_card(card)
  if form_blocks("opening a card source") or review_blocks("opening a card source") then
    return false
  end
  if not card or util.isempty(card.path) then
    return M.open_flashcards()
  end
  local _, target_err = preflight_target(card.path)
  if target_err then
    util.notify("Could not open flashcard source: " .. tostring(target_err), vim.log.levels.ERROR)
    return false
  end
  overview.close()
  local opened, open_err = pcall(vim.cmd.edit, util.fname(card.path))
  if not opened then
    util.notify("Could not open flashcard source: " .. tostring(open_err), vim.log.levels.ERROR)
    return false
  end
  vim.api.nvim_win_set_cursor(0, { card.start_line, 0 })
  return true
end

local function command_words(args)
  return vim.split(util.trim(args or ""), "%s+", { trimempty = true })
end

---Single discoverable command surface.
---@param args string|nil
function M.command(args)
  local words = command_words(args)
  local route = table.remove(words, 1) or "overview"

  if route == "overview" then
    M.overview()
  elseif route == "cards" then
    M.cards()
  elseif route == "stats" then
    M.stats()
  elseif route == "review" then
    local scope = table.remove(words, 1) or "due"
    if scope == "due" then
      M.review_due()
    elseif scope == "all" then
      M.review_all()
    elseif scope == "file" then
      M.review_file()
    elseif scope == "tag" then
      M.review_tag(table.concat(words, " "))
    elseif scope == "score" then
      M.review_score(table.concat(words, " "))
    else
      util.notify("Unknown review scope: " .. scope .. " (use due, all, file, tag, or score)", vim.log.levels.ERROR)
    end
  elseif route == "add" then
    M.add_kind(table.concat(words, " "))
  elseif route == "open" then
    M.open_flashcards()
  elseif route == "check" then
    M.validate_collection()
  elseif route == "help" then
    M.help()
  else
    util.notify("Unknown Flashcards action: " .. route .. " (try :Flashcards help)", vim.log.levels.ERROR)
  end
end

local function complete_command(arg_lead, cmd_line)
  local words = vim.split(cmd_line, "%s+", { trimempty = true })
  local choices = command_routes

  if words[2] == "review" and #words >= 2 then
    choices = { "due", "all", "file", "tag", "score" }
  elseif words[2] == "add" and #words >= 2 then
    choices = vim.tbl_keys(config.schemas or {})
    table.sort(choices)
  end

  return vim.tbl_filter(function(value)
    return value:find("^" .. vim.pesc(arg_lead)) ~= nil
  end, choices)
end

function M.setup(opts)
  if opts ~= nil and type(opts) ~= "table" then
    error("neorg_flashcards.setup: options must be a table", 2)
  end
  local next_config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  local rating_overrides = type(opts) == "table" and type(opts.ui) == "table" and opts.ui.rating_highlights or nil
  if type(rating_overrides) == "table" then
    for _, rating in ipairs({ "again", "hard", "good" }) do
      if rating_overrides[rating] ~= nil then
        next_config.ui.rating_highlights[rating] = vim.deepcopy(rating_overrides[rating])
      end
    end
  end
  for _, path_option in ipairs({ "flashcards_dir", "default_file" }) do
    if type(next_config[path_option]) ~= "string" then
      error("neorg_flashcards.setup: " .. path_option .. " must be a string", 2)
    end
  end
  if next_config.history_file ~= nil and type(next_config.history_file) ~= "string" then
    error("neorg_flashcards.setup: history_file must be a string", 2)
  end
  next_config.flashcards_dir = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(next_config.flashcards_dir), ":p"))
  next_config.default_file = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(next_config.default_file), ":p"))
  if not util.isempty(next_config.history_file) then
    next_config.history_file = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(next_config.history_file), ":p"))
  end
  local config_errors = schema.validate_config(next_config)
  if #config_errors > 0 then
    error("neorg_flashcards.setup: invalid configuration:\n- " .. table.concat(config_errors, "\n- "), 2)
  end
  local ok_mkdir, mkdir_result = pcall(vim.fn.mkdir, next_config.flashcards_dir, "p")
  if not ok_mkdir or (mkdir_result == 0 and vim.fn.isdirectory(next_config.flashcards_dir) ~= 1) then
    error("neorg_flashcards.setup: could not create flashcards_dir: " .. tostring(mkdir_result), 2)
  end
  local root_identity, root_error = util.pin_directory(next_config.flashcards_dir)
  if not root_identity then
    error("neorg_flashcards.setup: " .. tostring(root_error), 2)
  end
  next_config._collection_root = root_identity
  config = next_config

  local user_on_review = config.on_review

  local function call_user_review(event, callback)
    if callback == nil then
      callback = user_on_review
    end
    if type(callback) ~= "function" then
      return
    end
    local hook_ok, hook_err = pcall(callback, event)
    if not hook_ok then
      util.notify("on_review callback failed: " .. tostring(hook_err), vim.log.levels.WARN)
    end
  end

  local function history_event_copy(event)
    local copy = vim.deepcopy(event)
    copy.version = history.VERSION
    copy._source_bufnr = nil
    copy._history_path = nil
    copy._user_on_review = nil
    if util.isempty(copy.event_id) then
      generated_history_event_sequence = generated_history_event_sequence + 1
      local uv = vim.uv or vim.loop
      copy.event_id =
        string.format("nfc:%s:%s:%d", vim.fn.getpid(), tostring(uv.hrtime()), generated_history_event_sequence)
    end
    return copy
  end

  local function history_destination(destination)
    return history.capture(destination or config)
  end

  local function remember_failed_history_destination(destination)
    local captured = history_destination(destination)
    local key = captured and history.destination_key(captured) or nil
    if captured and key then
      failed_history_destinations[key] = captured
    end
    return captured
  end

  local function report_outbox_errors(errors)
    for _, message in ipairs(errors or {}) do
      if not reported_outbox_errors[message] then
        reported_outbox_errors[message] = true
        util.notify("Could not read review history retry queue: " .. message, vim.log.levels.ERROR)
      end
    end
  end

  local function remember_failed_history_event(destination, event)
    local key = history.destination_key(destination)
    if not key then
      return
    end
    local queue = failed_history_memory[key]
    if not queue then
      queue = {}
      failed_history_memory[key] = queue
    end
    for _, queued in ipairs(queue) do
      if queued.event_id == event.event_id then
        return
      end
    end
    table.insert(queue, vim.deepcopy(event))
  end

  local function flush_failed_history_memory(destination)
    local key = history.destination_key(destination)
    if not key then
      return false, "review history destination is not configured"
    end
    local queue = failed_history_memory[key]
    if not queue or #queue == 0 then
      return true
    end
    local ok, err = history.write_outbox(destination, queue)
    if not ok then
      return false, err
    end
    failed_history_memory[key] = nil
    return true
  end

  local function failed_history_count()
    local count = 0
    for key, destination in pairs(failed_history_destinations) do
      local events = history.read_outbox(destination)
      count = count + #events
      count = count + #(failed_history_memory[key] or {})
    end
    return count
  end

  local function load_failed_history(destination)
    local captured = remember_failed_history_destination(destination)
    if not captured then
      return
    end
    local _, errors = history.read_outbox(captured)
    report_outbox_errors(errors)
  end

  local function drain_failed_history(destination, targeted)
    local target = targeted and history_destination(destination) or nil
    if target then
      local key = history.destination_key(target)
      if key then
        failed_history_destinations[key] = target
      end
    else
      remember_failed_history_destination(config)
    end

    local destinations = {}
    if targeted then
      if target then
        table.insert(destinations, target)
      end
    else
      for _, captured in pairs(failed_history_destinations) do
        table.insert(destinations, captured)
      end
      table.sort(destinations, function(left, right)
        return (history.destination_key(left) or "") < (history.destination_key(right) or "")
      end)
    end

    local appended = false
    local drained = true
    for _, queue_destination in ipairs(destinations) do
      local memory_ok, memory_err = flush_failed_history_memory(queue_destination)
      if not memory_ok then
        drained = false
        util.notify("Could not persist review history retry queue: " .. tostring(memory_err), vim.log.levels.ERROR)
      else
        local events, errors, read_ok = history.read_outbox(queue_destination)
        report_outbox_errors(errors)
        if read_ok == false then
          drained = false
        else
          for _, event in ipairs(events) do
            local ok, result = history.append(event, queue_destination)
            if not ok then
              drained = false
              util.notify("Could not retry review history: " .. tostring(result), vim.log.levels.WARN)
              break
            end
            local removed, remove_err = history.remove_outbox(queue_destination, { event })
            if not removed then
              drained = false
              util.notify("Could not update review history retry queue: " .. tostring(remove_err), vim.log.levels.ERROR)
              break
            end
            appended = true
          end
        end
      end
    end
    if appended then
      overview.refresh()
    end
    return drained
  end

  local function append_review_history(event, notify_user, destination, observer)
    local copy = history_event_copy(event)
    local history_destination_token = remember_failed_history_destination(destination or config)
    drain_failed_history(history_destination_token, true)

    local destination_key = history_destination_token and history.destination_key(history_destination_token) or nil
    local queued = history_destination_token and history.read_outbox(history_destination_token) or {}
    local queued_in_memory = destination_key and failed_history_memory[destination_key] or nil
    local ok, result = false, "an earlier review history event is still queued"
    if #queued == 0 and not queued_in_memory then
      ok, result = history.append(copy, history_destination_token or destination or config)
    end
    if not ok then
      if history_destination_token then
        remember_failed_history_event(history_destination_token, copy)
      end
      local queued_ok, queue_err
      if history_destination_token then
        queued_ok, queue_err = flush_failed_history_memory(history_destination_token)
      else
        queued_ok, queue_err = false, "review history path is not configured"
      end
      if queued_ok then
        util.notify("Could not append review history; queued for retry: " .. tostring(result), vim.log.levels.WARN)
      else
        util.notify(
          string.format(
            "Could not append or durably queue review history; retained in memory for retry: %s; %s",
            tostring(result),
            tostring(queue_err)
          ),
          vim.log.levels.ERROR
        )
      end
    end
    if notify_user ~= false then
      call_user_review(event, observer)
    end
    overview.refresh()
    return ok
  end

  local function queue_pending_history(event)
    if event.type ~= "review" and event.type ~= "card_state" then
      return
    end
    if event.type == "review" and event.event == "undo" then
      for index = #pending_history, 1, -1 do
        if pending_history[index].event_id == event.undo_of then
          table.remove(pending_history, index)
          overview.refresh()
          return
        end
      end
    end
    if event.type == "card_state" or event.event == "rated" or event.event == "undo" then
      event._source_bufnr = util.loaded_buffer(event.path)
      event._history_path = history.capture(config)
      event._user_on_review = user_on_review or false
      table.insert(pending_history, event)
      overview.refresh()
    end
  end

  record_card_state = function(event)
    if event.persisted then
      append_review_history(event)
    else
      queue_pending_history(event)
    end
  end

  local review_config = vim.tbl_deep_extend("force", {}, config, {
    on_review = append_review_history,
    on_review_pending = queue_pending_history,
    on_bury = M.bury_card,
    on_suspend = M.toggle_suspend,
    on_edit = M.edit_card,
  })

  history.setup(config)
  load_failed_history(config)
  drain_failed_history()
  local history_group = vim.api.nvim_create_augroup("neorg_flashcards_history", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = history_group,
    callback = function(args)
      drain_failed_history()
      local written = util.canonical_path(args.file)
      local index = 1
      while index <= #pending_history do
        local event = pending_history[index]
        if event._source_bufnr == args.buf or util.canonical_path(event.path) == written then
          local persisted_event = vim.deepcopy(event)
          persisted_event._source_bufnr = nil
          persisted_event._history_path = nil
          persisted_event._user_on_review = nil
          persisted_event.path = written
          if type(persisted_event.card_ref) == "table" then
            persisted_event.card_ref.path = written
          end
          persisted_event.persisted = true
          append_review_history(persisted_event, true, event._history_path, event._user_on_review)
          table.remove(pending_history, index)
        else
          index = index + 1
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "FocusGained", "VimLeavePre" }, {
    group = history_group,
    callback = function(args)
      local drained = drain_failed_history()
      local remaining = failed_history_count()
      if not drained and args.event == "VimLeavePre" and remaining > 0 then
        util.notify(
          string.format("%d persisted review history event(s) could not be written before exit", remaining),
          vim.log.levels.ERROR
        )
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufUnload", "BufDelete", "BufWipeout" }, {
    group = history_group,
    callback = function(args)
      local discarded = 0
      local path = util.canonical_path(args.file)
      for index = #pending_history, 1, -1 do
        if
          pending_history[index]._source_bufnr == args.buf or util.canonical_path(pending_history[index].path) == path
        then
          table.remove(pending_history, index)
          discarded = discarded + 1
        end
      end
      if discarded > 0 then
        util.notify(
          string.format("Discarded %d unsaved review history event(s) with the buffer", discarded),
          vim.log.levels.WARN
        )
      end
    end,
  })
  health.setup(config)
  stats.setup(config)
  help.setup(config)
  overview.setup(config, {
    on_add = function()
      M.add_to_default("")
    end,
    on_review_due = M.review_due,
    on_review_all = M.review_all,
    on_check = M.validate_collection,
    on_edit = M.edit_card,
    on_help = M.help,
    on_toggle_suspend = M.toggle_suspend,
    on_bury = M.toggle_bury,
    on_delete_card = M.delete_card,
  })
  review.setup(review_config)

  vim.api.nvim_create_user_command("Flashcards", function(opts_)
    M.command(opts_.args)
  end, {
    nargs = "*",
    complete = complete_command,
    desc = "Open the flashcard hub or run a flashcard action",
  })
end

return M
