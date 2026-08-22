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
  languages = vim.deepcopy(schema.default_languages),
  scheduling = vim.deepcopy(schedule.DEFAULTS),
  leech_threshold = 8,
  ui = {
    show_shortcuts = true,
  },
}

local config = vim.deepcopy(defaults)
local pending_history = {}
local add_anchor_ns = vim.api.nvim_create_namespace("neorg_flashcards_add_anchor")
local active_add_anchor = nil
-- Failed persisted events are kept in independent FIFO queues per history
-- destination. A stale or read-only path must not block reviews after setup()
-- switches the plugin to another collection.
local failed_history = {}

local command_routes = {
  "overview",
  "cards",
  "stats",
  "review",
  "add",
  "open",
  "check",
  "migrate",
  "help",
}

local function ensure_flashcards_dir()
  vim.fn.mkdir(config.flashcards_dir, "p")
end

local function ensure_default_file_dir()
  vim.fn.mkdir(vim.fn.fnamemodify(config.default_file, ":h"), "p")
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

local function ensure_editable_flashcard_buffer()
  if current_buffer_is_norg() then
    return false
  end

  M.open_flashcards()
  return true
end

---Build and commit a card insertion through the buffer-aware store.
---@param kind string
---@param values table<string, string>
---@param target table
---@param card_config table
---@return table result
local function insert_card(kind, values, target, card_config)
  if target.create_with_heading then
    vim.fn.mkdir(vim.fn.fnamemodify(target.path, ":h"), "p")
  end

  local lines, bufnr, err = store.read_lines(target.path)
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

  local ok, write_err, persisted = store.write_lines(target.path, bufnr, candidate)
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

  if form.is_open() then
    util.notify("Finish or discard the open flashcard first", vim.log.levels.WARN)
    return
  end

  local append = ensure_editable_flashcard_buffer()
  local target_buf = vim.api.nvim_get_current_buf()
  local target_path = vim.api.nvim_buf_get_name(target_buf)
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
  ensure_flashcards_dir()
  ensure_default_file_dir()
  local existed = vim.fn.filereadable(config.default_file) == 1
  vim.cmd.edit(util.fname(config.default_file))

  if not existed and vim.api.nvim_buf_line_count(0) == 1 and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "" then
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      "* Flashcards",
      "",
    })
    vim.cmd.write()
  end

  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(0), 0 })
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

  if form.is_open() then
    util.notify("Finish or discard the open flashcard first", vim.log.levels.WARN)
    return
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
  util.notify(table.concat(messages, "\n"), level)
  return level ~= vim.log.levels.ERROR, cards, issues, errors
end

function M.review_all()
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
  local current_cards = parser.parse_buffer(0)
  local current_set = {}
  for _, card in ipairs(current_cards) do
    current_set[card] = true
  end

  local current_path = util.canonical_path(vim.api.nvim_buf_get_name(0))
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
  score = util.trim(score)

  if score == "" then
    vim.ui.input({ prompt = "Score (bad/mid/good/new): " }, function(input)
      if input == nil then
        util.notify("Score review cancelled", vim.log.levels.WARN)
        return
      end
      M.review_score(input)
    end)
    return
  end

  local filter = schema.score_filter(score)
  if not filter then
    util.notify("Unknown score: " .. score .. " (use bad, mid, good, new, or 1/2/3)", vim.log.levels.ERROR)
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

local function notify_migration_errors(result)
  local errors = (result and result.errors) or { "Unknown card ID migration error" }
  util.notify(table.concat(errors, "\n"), vim.log.levels.ERROR)
end

local function apply_id_migration()
  local ok, result = parser.migrate_ids(config)
  if not ok then
    notify_migration_errors(result)
    return false, result
  end

  local pending = result.pending_buffers or 0
  local suffix = pending > 0 and string.format("; %d modified buffer(s) still need saving", pending) or ""
  util.notify(
    string.format("Assigned stable IDs to %d card(s) across %d file(s)%s", result.assigned, result.files, suffix)
  )
  overview.refresh()
  return true, result
end

---Preview and confirm the one-time stable-ID migration for legacy cards.
---@param opts table|nil `{ dry_run = true }` only previews; `{ apply = true }`
---applies without the interactive confirmation (useful to embedding callers).
function M.migrate_ids(opts)
  opts = opts or {}
  local ok, preview = parser.migrate_ids(config, { dry_run = true })
  if not ok then
    notify_migration_errors(preview)
    return false, preview
  end

  if preview.planned == 0 then
    util.notify(string.format("All %d flashcard(s) already have stable IDs", preview.total))
    return true, preview
  end
  if opts.dry_run then
    return true, preview
  end
  if opts.apply then
    return apply_id_migration()
  end

  vim.ui.select({ "Migrate " .. preview.planned .. " cards", "Cancel" }, {
    prompt = string.format("Add stable IDs to %d legacy card(s) across the collection?", preview.planned),
  }, function(choice)
    if choice and choice:match("^Migrate") then
      apply_id_migration()
    else
      util.notify("Card ID migration cancelled", vim.log.levels.WARN)
    end
  end)
  return true, preview
end

local function update_card(card, updates, success_message, cards)
  if not card then
    return false, "No flashcard selected"
  end
  local ok, message = store.set_card_fields(card, updates, { cards = cards or { card } })
  if not ok then
    util.notify(message, vim.log.levels.ERROR)
    return false, message
  end
  if message then
    util.notify(message, vim.log.levels.WARN)
  elseif success_message then
    util.notify(success_message)
  end
  overview.refresh()
  return true, message
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

function M.toggle_suspend(card, context)
  local status = schedule.card_status(card, os.time(), config.scheduling)
  local suspended = status.availability ~= "suspended"
  return update_card(
    card,
    { { field = "availability", value = suspended and "suspended" or "active" } },
    suspended and "Flashcard suspended" or "Flashcard resumed",
    context and context.cards
  )
end

function M.bury_card(card, context)
  return update_card(card, {
    { field = "availability", value = "buried" },
    { field = "available_at", value = schedule.format_due(next_day()) },
  }, "Flashcard buried until tomorrow", context and context.cards)
end

function M.toggle_bury(card, context)
  local status = schedule.card_status(card, os.time(), config.scheduling)
  if status.availability == "buried" then
    return update_card(card, {
      { field = "availability", value = "active" },
      { field = "available_at", value = "" },
    }, "Flashcard unburied", context and context.cards)
  end
  return M.bury_card(card, context)
end

function M.open_card(card)
  if not card or util.isempty(card.path) then
    M.open_flashcards()
    return
  end
  overview.close()
  vim.cmd.edit(util.fname(card.path))
  vim.api.nvim_win_set_cursor(0, { card.start_line, 0 })
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
  elseif route == "migrate" then
    if M.migrate_ids then
      M.migrate_ids()
    else
      util.notify("Card ID migration is not available", vim.log.levels.WARN)
    end
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
    choices = vim.tbl_keys(config.languages or {})
    table.sort(choices)
  end

  return vim.tbl_filter(function(value)
    return value:find("^" .. vim.pesc(arg_lead)) ~= nil
  end, choices)
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  config.flashcards_dir = vim.fs.normalize(vim.fn.expand(config.flashcards_dir))
  config.default_file = vim.fs.normalize(vim.fn.expand(config.default_file))

  local user_on_review = config.on_review
  local user_on_bury = config.on_bury
  local user_on_suspend = config.on_suspend
  local user_on_edit = config.on_edit

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
    copy._source_bufnr = nil
    copy._history_path = nil
    copy._user_on_review = nil
    return copy
  end

  local function history_destination_key(destination)
    return history.path(destination or config) or false
  end

  local function failed_history_queue(destination, create)
    local key = history_destination_key(destination)
    for _, queue in ipairs(failed_history) do
      if queue.destination == key then
        return queue
      end
    end
    if not create then
      return nil
    end
    local queue = { destination = key, events = {} }
    table.insert(failed_history, queue)
    return queue
  end

  local function failed_history_count()
    local count = 0
    for _, queue in ipairs(failed_history) do
      count = count + #queue.events
    end
    return count
  end

  local function drain_failed_history(destination, targeted)
    local target = targeted and history_destination_key(destination) or nil
    local appended = false
    local drained = true
    local index = 1
    while index <= #failed_history do
      local queue = failed_history[index]
      if not targeted or queue.destination == target then
        while #queue.events > 0 do
          local ok, result = history.append(queue.events[1], queue.destination or config)
          if not ok then
            drained = false
            util.notify("Could not retry review history: " .. tostring(result), vim.log.levels.WARN)
            break
          end
          table.remove(queue.events, 1)
          appended = true
        end
        if #queue.events == 0 then
          table.remove(failed_history, index)
        else
          index = index + 1
        end
      else
        index = index + 1
      end
    end
    if appended then
      overview.refresh()
    end
    return drained
  end

  local function append_review_history(event, notify_user, destination, observer)
    local copy = history_event_copy(event)
    local history_path = history.path(destination or config)
    drain_failed_history(history_path, true)
    local queue = failed_history_queue(history_path, false)
    local ok, result = false, "an earlier review history event is still queued"
    if not queue then
      ok, result = history.append(copy, history_path or destination or config)
    end
    if not ok then
      queue = queue or failed_history_queue(history_path, true)
      table.insert(queue.events, copy)
      util.notify("Could not append review history; queued for retry: " .. tostring(result), vim.log.levels.WARN)
    end
    if notify_user ~= false then
      call_user_review(event, observer)
    end
    overview.refresh()
    return ok
  end

  local function queue_pending_history(event)
    if event.type ~= "review" then
      return
    end
    if event.event == "undo" then
      for index = #pending_history, 1, -1 do
        if pending_history[index].event_id == event.undo_of then
          table.remove(pending_history, index)
          overview.refresh()
          return
        end
      end
      return
    end
    if event.event == "rated" then
      event._source_bufnr = util.loaded_buffer(event.path)
      event._history_path = history.path(config)
      event._user_on_review = user_on_review or false
      table.insert(pending_history, event)
      overview.refresh()
    end
  end

  local review_config = vim.tbl_deep_extend("force", {}, config, {
    on_review = append_review_history,
    on_review_pending = queue_pending_history,
    on_bury = function(card, context)
      local ok, message = M.bury_card(card, context)
      if ok and type(user_on_bury) == "function" then
        local hook_ok, accepted, hook_message = pcall(user_on_bury, card, context)
        if not hook_ok then
          util.notify("on_bury callback failed: " .. tostring(accepted), vim.log.levels.WARN)
        elseif accepted == false then
          util.notify(hook_message or "on_bury callback rejected the completed action", vim.log.levels.WARN)
        end
      end
      return ok, message
    end,
    on_suspend = function(card, context)
      local ok, message = M.toggle_suspend(card, context)
      if ok and type(user_on_suspend) == "function" then
        local hook_ok, accepted, hook_message = pcall(user_on_suspend, card, context)
        if not hook_ok then
          util.notify("on_suspend callback failed: " .. tostring(accepted), vim.log.levels.WARN)
        elseif accepted == false then
          util.notify(hook_message or "on_suspend callback rejected the completed action", vim.log.levels.WARN)
        end
      end
      return ok, message
    end,
    on_edit = function(card)
      M.open_card(card)
      if type(user_on_edit) == "function" then
        local hook_ok, hook_err = pcall(user_on_edit, card)
        if not hook_ok then
          util.notify("on_edit callback failed: " .. tostring(hook_err), vim.log.levels.WARN)
        end
      end
    end,
  })

  history.setup(config)
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
      if not drained and args.event == "VimLeavePre" then
        util.notify(
          string.format("%d persisted review history event(s) could not be written before exit", failed_history_count()),
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
    on_migrate = M.migrate_ids,
    on_open_source = M.open_card,
    on_help = M.help,
    on_toggle_suspend = M.toggle_suspend,
    on_bury = M.toggle_bury,
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
