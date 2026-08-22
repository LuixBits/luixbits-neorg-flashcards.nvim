-- Versioned, append-only review history. Corrupt lines are reported and
-- skipped independently, so one interrupted append never hides good history.

local identity = require("neorg_flashcards.identity")
local schedule = require("neorg_flashcards.schedule")
local util = require("neorg_flashcards.util")

local M = {}

M.VERSION = 1
M.FILENAME = "reviews.jsonl"

local config = {}
local LOCK_WAIT_MS = 2000
local captured_destinations = {}

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

local function ensure_parent(path, label)
  local directory = vim.fn.fnamemodify(path, ":h")
  local ok_mkdir, mkdir_result = pcall(vim.fn.mkdir, directory, "p")
  if not ok_mkdir or mkdir_result == 0 and vim.fn.isdirectory(directory) ~= 1 then
    return false, string.format("could not create %s directory: %s", label, tostring(mkdir_result))
  end
  return true
end

local function canonical_path(path)
  path = vim.fn.expand(path)
  -- `:p` is available on every supported Neovim and is a no-op for an
  -- already-absolute path. `vim.fs.is_absolute` is newer than our 0.10 floor.
  path = vim.fn.fnamemodify(path, ":p")
  return util.canonical_path(path)
end

-- History destinations are captured as physical paths before they enter the
-- retry queue. Keep the final component unresolved so replacing it with a
-- symlink is detectable, and reject a parent that no longer resolves to the
-- physical directory captured earlier.
local function resolve_captured_path(path)
  local lexical = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(path), ":p"))
  local path_stat = (vim.uv or vim.loop).fs_lstat(lexical)
  if path_stat and path_stat.type == "link" then
    return nil, "review history destination became a symbolic link"
  elseif path_stat and path_stat.type ~= "file" then
    return nil, "review history destination is not a regular file"
  end

  local parent = vim.fs.normalize(vim.fn.fnamemodify(lexical, ":h"))
  local resolved_parent = canonical_path(parent)
  if resolved_parent ~= parent then
    return nil, "review history parent changed since it was captured; run setup again"
  end
  return vim.fs.normalize(resolved_parent .. "/" .. vim.fn.fnamemodify(lexical, ":t"))
end

local function remember_captured_destination(path, root, replace)
  local destination = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(path), ":p"))
  if captured_destinations[destination] and not replace then
    return destination
  end
  local parent = canonical_path(vim.fn.fnamemodify(destination, ":h"))
  local stat = (vim.uv or vim.loop).fs_stat(parent)
  captured_destinations[destination] = {
    parent = parent,
    dev = stat and stat.dev or nil,
    ino = stat and stat.ino or nil,
    root = type(root) == "table" and vim.deepcopy(root) or nil,
  }
  return destination
end

local function validate_captured_identity(path, captured_identity)
  local destination = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(path), ":p"))
  local identity = captured_identity or captured_destinations[destination]
  if not identity then
    return true
  end

  if identity.root then
    local _, root_err = util.resolve_pinned_directory(identity.root)
    if root_err then
      return false, root_err
    end
  end

  local parent = canonical_path(vim.fn.fnamemodify(destination, ":h"))
  if parent ~= identity.parent then
    return false, "review history parent changed since it was captured; run setup again"
  end
  local stat = (vim.uv or vim.loop).fs_stat(parent)
  if stat and stat.type ~= "directory" then
    return false, "review history parent is no longer a directory"
  elseif identity.dev ~= nil and identity.ino ~= nil then
    if not stat or stat.dev ~= identity.dev or stat.ino ~= identity.ino then
      return false, "review history parent was replaced since it was captured; run setup again"
    end
  elseif stat then
    identity.dev = stat.dev
    identity.ino = stat.ino
  end
  return true
end

local function validate_captured_path(path, captured_identity)
  local identity_ok, identity_err = validate_captured_identity(path, captured_identity)
  if not identity_ok then
    return false, identity_err
  end
  local resolved, err = resolve_captured_path(path)
  local expected = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(path), ":p"))
  if not resolved then
    return false, err
  elseif resolved ~= expected then
    return false, "review history destination changed since it was captured; run setup again"
  end
  return true
end

local function is_destination(value)
  return type(value) == "table" and value._neorg_flashcards_history_destination == true
end

local function new_destination(path, root)
  local destination = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(path), ":p"))
  local parent = canonical_path(vim.fn.fnamemodify(destination, ":h"))
  local stat = (vim.uv or vim.loop).fs_stat(parent)
  local captured = {
    _neorg_flashcards_history_destination = true,
    path = destination,
    parent = parent,
    dev = stat and stat.dev or nil,
    ino = stat and stat.ino or nil,
    root = type(root) == "table" and vim.deepcopy(root) or nil,
  }
  local root_key = captured.root
      and table.concat({ captured.root.canonical or "", captured.root.dev or "", captured.root.ino or "" }, ":")
    or ""
  captured.key =
    vim.fn.sha256(table.concat({ destination, root_key, parent, captured.dev or "", captured.ino or "" }, "\0"))
  return captured
end

local function lock_token(path)
  local ok_read, lines = pcall(vim.fn.readfile, path)
  if not ok_read or #lines ~= 1 then
    return nil
  end
  return lines[1]
end

local function release_lock(lock)
  local uv = vim.uv or vim.loop
  if lock.fd then
    pcall(uv.fs_close, lock.fd)
  end
  if lock_token(lock.path) == lock.token then
    pcall(uv.fs_unlink, lock.path)
  end
end

local function create_lock(path)
  local uv = vim.uv or vim.loop
  local fd, open_err, open_code = uv.fs_open(path, "wx", 384)
  if not fd then
    return nil, open_err, open_code
  end
  local token = string.format("%s:%s", vim.fn.getpid(), uv.hrtime())
  local written, write_err = uv.fs_write(fd, token, 0)
  if not written then
    pcall(uv.fs_close, fd)
    pcall(uv.fs_unlink, path)
    return nil, write_err
  end
  pcall(uv.fs_fsync, fd)
  return { fd = fd, path = path, token = token }
end

local function remove_dead_owner_lock(path)
  local uv = vim.uv or vim.loop
  local token = lock_token(path)
  local owner = token and tonumber(token:match("^(%d+):")) or nil
  if not owner then
    return false
  end
  local _, _, kill_code = uv.kill(owner, 0)
  if kill_code ~= "ESRCH" or lock_token(path) ~= token then
    return false
  end
  local removed = uv.fs_unlink(path)
  return removed ~= nil or lock_token(path) == nil
end

-- Only one process may reap a dead owner's lock. The reaper keeps the original
-- pathname in place until it has confirmed the same dead-owner token twice;
-- no successor can acquire the original lock during that check.
local function recover_dead_lock(lock_path)
  local reaper_path = lock_path .. ".reap"
  local reaper, _, reaper_code = create_lock(reaper_path)
  if not reaper and reaper_code == "EEXIST" and remove_dead_owner_lock(reaper_path) then
    reaper = create_lock(reaper_path)
  end
  if not reaper then
    return false
  end

  local recovered = remove_dead_owner_lock(lock_path)
  release_lock(reaper)
  return recovered
end

-- JSONL updates use a small cross-process lock file. All plugin instances
-- resolve the destination before deriving this path, so symlink aliases share
-- the same lock. Each holder writes a unique token and only removes that exact
-- token on release; an old holder can never unlink a successor's lock.
local function acquire_lock(path, label)
  local parent_ok, parent_err = ensure_parent(path, label)
  if not parent_ok then
    return nil, parent_err
  end

  local uv = vim.uv or vim.loop
  local lock_path = path .. ".lock"
  local deadline = uv.hrtime() + LOCK_WAIT_MS * 1000000
  while true do
    local lock, open_err, open_code = create_lock(lock_path)
    if lock then
      return lock
    end
    if open_code ~= "EEXIST" then
      return nil, string.format("could not lock %s: %s", label, tostring(open_err))
    end
    if recover_dead_lock(lock_path) then
      -- Retry acquisition immediately after removing the confirmed dead owner.
    elseif uv.hrtime() >= deadline then
      return nil,
        string.format(
          "timed out waiting for %s lock; remove %s only if no Neovim instance is using it",
          label,
          lock_path
        )
    else
      uv.sleep(2)
    end
  end
end

local function with_lock(path, label, callback, destination)
  local path_ok, path_err = validate_captured_path(path, destination)
  if not path_ok then
    return false, path_err
  end
  local lock, lock_err = acquire_lock(path, label)
  if not lock then
    return false, lock_err
  end
  path_ok, path_err = validate_captured_path(path, destination)
  if not path_ok then
    release_lock(lock)
    return false, path_err
  end
  local ok, result, detail = pcall(callback)
  release_lock(lock)
  if not ok then
    return false, string.format("could not update %s: %s", label, tostring(result))
  end
  return result, detail
end

local read_lines

local function atomic_write(path, lines, opts)
  opts = opts or {}
  local uv = vim.uv or vim.loop
  local label = opts.label or "JSONL file"
  local path_ok, path_err = validate_captured_path(path, opts.destination)
  if not path_ok then
    return false, path_err
  end
  local parent_ok, parent_err = ensure_parent(path, label)
  if not parent_ok then
    return false, parent_err
  end
  path_ok, path_err = validate_captured_path(path, opts.destination)
  if not path_ok then
    return false, path_err
  end

  local initial_stat = uv.fs_lstat(path)
  if initial_stat and initial_stat.type == "link" then
    return false, "refusing to replace a symbolic-link " .. label
  elseif initial_stat and initial_stat.type ~= "file" then
    return false, label .. " destination is not a regular file"
  end

  local directory = vim.fn.fnamemodify(path, ":h")
  local basename = vim.fn.fnamemodify(path, ":t")
  local temporary =
    string.format("%s/.%s.neorg-flashcards-%s-%s.tmp", directory, basename, vim.fn.getpid(), uv.hrtime())
  local ok_write, write_result = pcall(vim.fn.writefile, lines, temporary)
  if not ok_write or write_result == -1 then
    pcall(vim.fn.delete, temporary)
    return false, "could not write " .. label .. ": " .. tostring(write_result)
  end

  local permissions = initial_stat and vim.fn.getfperm(path) or ""
  if permissions ~= "" then
    local ok_permissions, permission_result = pcall(vim.fn.setfperm, temporary, permissions)
    if not ok_permissions or permission_result == 0 then
      pcall(vim.fn.delete, temporary)
      return false, "could not preserve " .. label .. " permissions"
    end
  end

  if opts.expected_lines then
    local current, current_err = read_lines(path)
    if not current then
      pcall(vim.fn.delete, temporary)
      return false, "could not recheck " .. label .. ": " .. tostring(current_err)
    elseif not vim.deep_equal(current, opts.expected_lines) then
      pcall(vim.fn.delete, temporary)
      return false, label .. " changed while it was being updated; retry"
    end
  end

  local final_stat = uv.fs_lstat(path)
  if final_stat and final_stat.type == "link" then
    pcall(vim.fn.delete, temporary)
    return false, "refusing to replace a symbolic-link " .. label
  elseif final_stat and final_stat.type ~= "file" then
    pcall(vim.fn.delete, temporary)
    return false, label .. " destination is not a regular file"
  end

  path_ok, path_err = validate_captured_path(path, opts.destination)
  if not path_ok then
    pcall(vim.fn.delete, temporary)
    return false, path_err
  end

  local renamed, rename_err = uv.fs_rename(temporary, path)
  if not renamed then
    pcall(vim.fn.delete, temporary)
    return false, "could not replace " .. label .. ": " .. tostring(rename_err)
  end
  return true
end

local function source_config(source)
  if type(source) == "table" then
    return source
  end
  return config
end

function M.path(source)
  if is_destination(source) then
    local path_ok, path_err = validate_captured_path(source.path, source)
    if not path_ok then
      return nil, path_err
    elseif not source.path:match("%.jsonl$") then
      return nil, "review history destination must be a .jsonl file separate from card sources"
    end
    return source.path
  elseif type(source) == "string" then
    local path_ok, path_err = validate_captured_path(source)
    if not path_ok then
      return nil, path_err
    end
    local resolved, resolve_err = resolve_captured_path(source)
    if not resolved then
      return nil, resolve_err
    end
    if not resolved:match("%.jsonl$") then
      return nil, "review history destination must be a .jsonl file separate from card sources"
    end
    return resolved
  end

  local opts = source_config(source)
  if util.isempty(opts.flashcards_dir) then
    return nil, "flashcards_dir is not configured"
  end
  local root_spec = opts._collection_root or opts.flashcards_dir
  local root, root_err = util.resolve_pinned_directory(root_spec)
  if not root then
    return nil, root_err
  end
  local requested = not util.isempty(opts.history_file) and opts.history_file or (root .. "/" .. M.FILENAME)
  local destination = canonical_path(requested)
  if not destination:match("%.jsonl$") then
    return nil, "review history destination must be a .jsonl file separate from card sources"
  elseif not util.resolved_path_is_within(destination, root) then
    return nil, "review history destination must be inside flashcards_dir"
  end
  if type(root_spec) ~= "table" and not captured_destinations[destination] then
    root_spec = util.pin_directory(opts.flashcards_dir)
  end
  remember_captured_destination(destination, root_spec, false)
  return destination
end

function M.capture(source)
  if is_destination(source) then
    local path, path_err = M.path(source)
    if not path then
      return nil, path_err
    end
    return source
  end

  local path, path_err = M.path(source)
  if not path then
    return nil, path_err
  end
  if type(source) == "string" then
    local identity = captured_destinations[path]
    local destination = new_destination(path, identity and identity.root or nil)
    if identity then
      destination.parent = identity.parent
      destination.dev = identity.dev
      destination.ino = identity.ino
    end
    return destination
  end

  local opts = source_config(source)
  local root_spec = opts._collection_root
  if type(root_spec) ~= "table" then
    root_spec = util.pin_directory(opts.flashcards_dir)
  end
  return new_destination(path, root_spec)
end

function M.destination_key(source)
  if is_destination(source) then
    return source.key
  end
  local destination, destination_err = M.capture(source)
  if not destination then
    return nil, destination_err
  end
  return destination.key
end

function M.outbox_path(source)
  local history_destination, destination_err
  if is_destination(source) then
    history_destination = source
  else
    history_destination, destination_err = M.capture(source)
  end
  if not history_destination then
    return nil, destination_err
  end
  local state_root = canonical_path(vim.fn.stdpath("state"))
  local digest = history_destination.key:sub(1, 24)
  local destination = vim.fs.normalize(state_root .. "/neorg-flashcards/outbox/" .. digest .. ".jsonl")
  return remember_captured_destination(destination, nil, false)
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

local function finite_number(value)
  value = tonumber(value)
  if not value or value ~= value or value == math.huge or value == -math.huge then
    return nil
  end
  return value
end

local function normalize_epoch(epoch, timestamp)
  local value
  if epoch ~= nil then
    value = finite_number(epoch)
    if not value then
      return nil, "review event epoch must be a finite number"
    end
  elseif timestamp ~= nil then
    value = finite_number(timestamp) or epoch_from_timestamp(timestamp)
    if not value then
      return nil, "review event timestamp is invalid"
    end
  else
    return nil, "review event requires an epoch or timestamp"
  end

  value = math.floor(value)
  local ok_date, formatted = pcall(os.date, "!%Y-%m-%dT%H:%M:%SZ", value)
  if not ok_date or type(formatted) ~= "string" or formatted == "" then
    return nil, "review event epoch is outside the representable date range"
  end
  return value, formatted
end

local function normalize_event(event)
  if type(event) ~= "table" then
    return nil, "review event must be a table"
  end

  for removed, replacement in pairs({
    action = "event",
    score = "rating",
    id = "card_id",
    old_state = "before",
    new_state = "after",
  }) do
    if event[removed] ~= nil then
      return nil, string.format("review event field %s was removed; use %s", removed, replacement)
    end
  end

  local normalized = copy(event)
  if type(normalized.version) ~= "number" then
    return nil, "review event requires a numeric version"
  end
  if normalized.version ~= M.VERSION then
    return nil, "unsupported review event version: " .. tostring(normalized.version)
  end

  normalized.type = util.trim(normalized.type):lower()
  if normalized.type ~= "review" and normalized.type ~= "card_state" then
    return nil, "review event type must be review or card_state"
  end
  normalized.event = util.trim(normalized.event):lower()
  if normalized.event == "" or not normalized.event:match("^[%w_-]+$") then
    return nil, "review event action is invalid"
  end

  local raw_rating = normalized.rating
  normalized.rating = rating(raw_rating)
  if normalized.event == "rated" and not normalized.rating then
    return nil, "review event rating must be 1, 2, or 3"
  end
  if raw_rating ~= nil and not normalized.rating then
    return nil, "review event rating must be 1, 2, or 3"
  end
  normalized.card_id = util.trim(normalized.card_id)
  if normalized.card_id == "" then
    return nil, "review event requires a stable card_id"
  end
  if normalized.card_id ~= "" and not identity.is_valid(normalized.card_id) then
    return nil, "review event has an invalid card_id"
  end
  local epoch, timestamp_or_err = normalize_epoch(normalized.epoch, normalized.timestamp)
  if not epoch then
    return nil, timestamp_or_err
  end
  normalized.epoch = epoch
  normalized.timestamp = timestamp_or_err

  if normalized.event_id ~= nil then
    normalized.event_id = util.trim(normalized.event_id)
    if normalized.event_id == "" then
      normalized.event_id = nil
    end
  end

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
  details.rating = score or details.rating
  if now then
    details.epoch = now
  elseif details.epoch == nil and details.timestamp == nil then
    details.epoch = os.time()
  end
  details.version = M.VERSION
  details.type = "review"
  details.event = details.event or "rated"

  return normalize_event(details)
end

read_lines = function(path)
  if util.isempty(path) then
    return {}, nil
  end
  local path_stat = (vim.uv or vim.loop).fs_lstat(path)
  if not path_stat then
    return {}, nil
  elseif path_stat.type == "link" then
    return nil, "refusing to read a symbolic-link JSONL destination"
  elseif path_stat.type ~= "file" then
    return nil, "JSONL destination is not a regular file"
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, tostring(lines)
  end
  return lines, nil
end

local function decode_event_line(line)
  local ok_decode, raw = pcall(decode, line)
  if not ok_decode or type(raw) ~= "table" then
    return nil, "invalid JSON event"
  end
  return normalize_event(raw)
end

local function stable_value(value, active)
  local value_type = type(value)
  if value_type == "nil" then
    return "nil"
  elseif value_type == "boolean" or value_type == "number" then
    return value_type .. ":" .. tostring(value)
  elseif value_type == "string" then
    return "string:" .. string.format("%q", value)
  elseif value_type ~= "table" then
    return value_type .. ":" .. tostring(value)
  end

  active = active or {}
  if active[value] then
    error("cyclic review event")
  end
  active[value] = true
  local keys = {}
  for key in pairs(value) do
    table.insert(keys, key)
  end
  table.sort(keys, function(left, right)
    local left_key = type(left) .. ":" .. tostring(left)
    local right_key = type(right) .. ":" .. tostring(right)
    return left_key < right_key
  end)
  local parts = {}
  for _, key in ipairs(keys) do
    table.insert(parts, stable_value(key, active) .. "=" .. stable_value(value[key], active))
  end
  active[value] = nil
  return "table:{" .. table.concat(parts, ",") .. "}"
end

local function event_key(event)
  local event_id = util.trim(event and event.event_id)
  if event_id ~= "" then
    return "id:" .. event_id
  end
  local ok, serialized = pcall(stable_value, event)
  if not ok then
    return nil, serialized
  end
  return "event:" .. vim.fn.sha256(serialized)
end

function M.append(event, source)
  local normalized, normalize_err = normalize_event(event)
  if not normalized then
    return false, normalize_err
  end

  local destination, destination_err = M.capture(source)
  if not destination then
    return false, destination_err or "review history path is not configured"
  end
  local path, path_err = M.path(destination)
  if util.isempty(path) then
    return false, path_err or "review history path is not configured"
  end

  local ok_encode, line = pcall(encode, normalized)
  if not ok_encode then
    return false, "could not encode review history: " .. tostring(line)
  end

  return with_lock(path, "review history", function()
    local lines, read_err = read_lines(path)
    if not lines then
      return false, "could not inspect review history: " .. tostring(read_err)
    end
    if normalized.event_id then
      for _, existing_line in ipairs(lines) do
        if not util.isempty(existing_line) then
          local existing = decode_event_line(existing_line)
          if existing and existing.event_id == normalized.event_id then
            return true, normalized
          end
        end
      end
    end

    local previous = vim.deepcopy(lines)
    table.insert(lines, line)
    local ok_write, write_err = atomic_write(path, lines, {
      destination = destination,
      expected_lines = previous,
      label = "review history",
    })
    if not ok_write then
      return false, "could not append review history: " .. tostring(write_err)
    end
    return true, normalized
  end, destination)
end

function M.read_outbox(source)
  local path, path_err = M.outbox_path(source)
  if not path then
    return {}, { path_err or "review history outbox path is not configured" }, false
  end
  local lines, read_err = read_lines(path)
  if not lines then
    return {}, { path .. ": " .. tostring(read_err) }, false
  end
  local events, errors = {}, {}
  for index, line in ipairs(lines) do
    if not util.isempty(line) then
      local event, event_err = decode_event_line(line)
      if event then
        table.insert(events, event)
      else
        table.insert(errors, string.format("%s:%d: %s", path, index, event_err or "invalid JSON event"))
      end
    end
  end
  return events, errors, true
end

function M.write_outbox(source, events)
  local path, path_err = M.outbox_path(source)
  if not path then
    return false, path_err or "review history outbox path is not configured"
  end

  local additions = {}
  for _, event in ipairs(events) do
    local normalized, normalize_err = normalize_event(event)
    if not normalized then
      return false, normalize_err
    end
    local ok_encode, line = pcall(encode, normalized)
    if not ok_encode then
      return false, "could not encode review history outbox: " .. tostring(line)
    end
    local key, key_err = event_key(normalized)
    if not key then
      return false, "could not identify review history outbox event: " .. tostring(key_err)
    end
    table.insert(additions, { key = key, line = line })
  end

  if #additions == 0 then
    return true
  end

  return with_lock(path, "review history outbox", function()
    local lines, read_err = read_lines(path)
    if not lines then
      return false, "could not read review history outbox: " .. tostring(read_err)
    end

    local previous = vim.deepcopy(lines)
    local seen = {}
    for _, line in ipairs(lines) do
      if not util.isempty(line) then
        local existing = decode_event_line(line)
        if existing then
          local key = event_key(existing)
          if key then
            seen[key] = true
          end
        end
      end
    end
    local changed = false
    for _, addition in ipairs(additions) do
      if not seen[addition.key] then
        table.insert(lines, addition.line)
        seen[addition.key] = true
        changed = true
      end
    end
    if not changed then
      return true
    end
    return atomic_write(path, lines, {
      expected_lines = previous,
      label = "review history outbox",
    })
  end)
end

-- Remove only the successfully delivered events. Unrelated events written by
-- another Neovim instance and malformed raw lines are retained byte-for-byte.
function M.remove_outbox(source, events)
  local path, path_err = M.outbox_path(source)
  if not path then
    return false, path_err or "review history outbox path is not configured"
  end

  local remove = {}
  for _, event in ipairs(events or {}) do
    local normalized, normalize_err = normalize_event(event)
    if not normalized then
      return false, normalize_err
    end
    local key, key_err = event_key(normalized)
    if not key then
      return false, "could not identify review history outbox event: " .. tostring(key_err)
    end
    remove[key] = true
  end
  if vim.tbl_isempty(remove) then
    return true
  end

  return with_lock(path, "review history outbox", function()
    local lines, read_err = read_lines(path)
    if not lines then
      return false, "could not read review history outbox: " .. tostring(read_err)
    end
    local previous = vim.deepcopy(lines)
    local kept, changed = {}, false
    for _, line in ipairs(lines) do
      local discard = false
      if not util.isempty(line) then
        local existing = decode_event_line(line)
        if existing then
          local key = event_key(existing)
          discard = key ~= nil and remove[key] == true
        end
      end
      if discard then
        changed = true
      else
        table.insert(kept, line)
      end
    end
    if not changed then
      return true
    elseif #kept > 0 then
      return atomic_write(path, kept, {
        expected_lines = previous,
        label = "review history outbox",
      })
    end

    local ok_delete, delete_result = pcall(vim.fn.delete, path)
    if not ok_delete or delete_result ~= 0 and vim.fn.filereadable(path) == 1 then
      return false, "could not clear delivered review history outbox"
    end
    return true
  end)
end

function M.append_review(card, score, now, details, source)
  local event, err = M.new_event(card, score, now, details)
  if not event then
    return false, err
  end
  return M.append(event, source)
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
        local event, event_err = normalize_event(raw)
        if event then
          event._history_order = #entries + 1
          table.insert(entries, event)
        else
          table.insert(errors, string.format("%s:%d: %s", path, index, event_err))
        end
      end
    end
  end
end

function M.read(source)
  local entries = {}
  local errors = {}
  local destination, destination_err = M.capture(source)
  if destination then
    local path, path_err = M.path(destination)
    if path then
      read_jsonl(path, entries, errors)
    elseif path_err then
      table.insert(errors, path_err)
    end
  elseif destination_err then
    table.insert(errors, destination_err)
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
