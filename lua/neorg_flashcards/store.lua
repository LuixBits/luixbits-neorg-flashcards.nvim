local util = require("neorg_flashcards.util")

local M = {}
local SOURCE_GUARD = {}
local LOCK_WAIT_MS = 2000

local function absolute_path(path)
  return vim.fn.fnamemodify(vim.fn.expand(path), ":p")
end

local function resolve_destination(path, opts)
  opts = opts or {}
  local uv = vim.uv or vim.loop
  path = absolute_path(path)
  local path_stat = uv.fs_lstat(path)
  if opts.reject_symlink and path_stat and path_stat.type == "link" then
    return nil, "refusing to replace a symbolic-link destination"
  end

  if path_stat and path_stat.type ~= "file" and path_stat.type ~= "link" then
    return nil, "source destination is not a regular file"
  end

  local destination = path
  if opts.follow_symlink ~= false then
    local resolved = uv.fs_realpath(path)
    if path_stat and path_stat.type == "link" then
      if not resolved then
        return nil, "could not resolve source-file symbolic link"
      end
      local target_stat = uv.fs_stat(resolved)
      if not target_stat or target_stat.type ~= "file" then
        return nil, "source-file symbolic link does not target a regular file"
      end
    end
    destination = resolved or util.canonical_path(path)
  else
    -- Canonicalize the directory for shared locking, but deliberately leave
    -- the final component unresolved. Derived files such as deletion backups
    -- replace this directory entry and must never be redirected through a
    -- symlink that occupies it.
    local directory = vim.fn.fnamemodify(path, ":h")
    local canonical_directory = uv.fs_realpath(directory) or util.canonical_path(directory)
    destination = vim.fs.normalize(canonical_directory .. "/" .. vim.fn.fnamemodify(path, ":t"))
  end

  if opts.allowed_root ~= nil then
    local allowed_root, root_err = util.resolve_pinned_directory(opts.allowed_root)
    if not allowed_root then
      return nil, root_err
    end
    if not util.resolved_path_is_within(destination, allowed_root) then
      return nil, "source destination must stay inside the configured flashcards_dir"
    end
  end
  return destination
end

local function ensure_destination_parent(path, opts)
  opts = opts or {}
  local destination, destination_err = resolve_destination(path, opts)
  if not destination then
    return nil, destination_err
  end

  local parent = vim.fs.normalize(vim.fn.fnamemodify(destination, ":h"))
  local root, root_err = util.resolve_pinned_directory(opts.allowed_root)
  if not root then
    return nil, root_err
  elseif not util.resolved_path_is_within(parent, root) then
    return nil, "source directory must stay inside the configured flashcards_dir"
  end

  local uv = vim.uv or vim.loop
  local current = root
  local prefix = root:sub(-1) == "/" and root or (root .. "/")
  local relative = parent == root and "" or parent:sub(#prefix + 1)
  for component in relative:gmatch("[^/]+") do
    current = vim.fs.normalize(current .. "/" .. component)
    local stat = uv.fs_lstat(current)
    if not stat then
      local created, create_err, create_code = uv.fs_mkdir(current, 493)
      if not created and create_code ~= "EEXIST" then
        return nil, "could not create flashcard directory: " .. tostring(create_err)
      end
      stat = uv.fs_lstat(current)
    end
    if not stat or stat.type ~= "directory" then
      return nil, "flashcard target directory is not a regular directory"
    end
  end

  local checked, checked_err = resolve_destination(path, opts)
  if not checked then
    return nil, checked_err
  elseif checked ~= destination then
    return nil, "source destination changed while its directory was being prepared"
  end
  return checked
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

local function acquire_destination_lock(destination)
  local uv = vim.uv or vim.loop
  local directory = vim.fn.fnamemodify(destination, ":h")
  local basename = vim.fn.fnamemodify(destination, ":t")
  local lock_path = string.format("%s/.%s.neorg-flashcards.lock", directory, basename)
  local deadline = uv.hrtime() + LOCK_WAIT_MS * 1000000
  while true do
    local lock, open_err, open_code = create_lock(lock_path)
    if lock then
      return lock
    end
    if open_code ~= "EEXIST" then
      return nil, "could not lock source destination: " .. tostring(open_err)
    end
    if recover_dead_lock(lock_path) then
      -- Retry immediately after removing a lock whose owner no longer exists.
    elseif uv.hrtime() >= deadline then
      return nil,
        string.format("timed out waiting for source lock; remove %s only if no Neovim instance is using it", lock_path)
    else
      uv.sleep(2)
    end
  end
end

local function source_guard(lines)
  local metatable = getmetatable(lines)
  return metatable and metatable[SOURCE_GUARD] or nil
end

local function guard_source_lines(lines, destination, opts)
  local metatable = getmetatable(lines) or {}
  metatable[SOURCE_GUARD] = {
    destination = destination,
    fingerprint = util.lines_fingerprint(lines),
    allowed_root = opts and opts.allowed_root or nil,
    missing = (vim.uv or vim.loop).fs_lstat(destination) == nil,
  }
  setmetatable(lines, metatable)
  return true
end

local function field_line(lines, start_line, end_line, field)
  for index = start_line + 1, math.min(end_line - 1, #lines) do
    local key = lines[index]:match("^%s*([%w_-]+)%s*:")
    if key and key:lower():gsub("-", "_") == field then
      return index
    end
  end
  return nil
end

local function source_lines(path, opts)
  if util.isempty(path) then
    return nil, nil, "Cannot save rating for an unsaved buffer"
  end

  local destination, destination_err = resolve_destination(path, opts)
  if not destination then
    return nil, nil, string.format("%s: %s", path, destination_err)
  end

  local bufnr = util.loaded_buffer(destination)
  if bufnr then
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    guard_source_lines(lines, destination, opts)
    return lines, bufnr, nil
  end

  local ok, lines = pcall(vim.fn.readfile, destination)
  if not ok then
    return nil, nil, string.format("%s: could not read file", path)
  end

  local guarded, guard_err = guard_source_lines(lines, destination, opts)
  if not guarded then
    return nil, nil, string.format("%s: %s", path, guard_err)
  end
  return lines, nil, nil
end

-- Source paths may deliberately be symlinks into a collection. Resolve an
-- existing source symlink once, require a regular-file target, and replace that
-- target so the user's link remains intact. Derived paths such as deletion
-- backups opt out: replacing their directory entry must never redirect a write
-- through a pre-existing symlink.
local function atomic_write(path, lines, opts)
  opts = opts or {}
  local uv = vim.uv or vim.loop
  local destination, destination_err = resolve_destination(path, opts)
  if not destination then
    return false, destination_err
  end

  local lock, lock_err = acquire_destination_lock(destination)
  if not lock then
    return false, lock_err
  end

  local directory = vim.fn.fnamemodify(destination, ":h")
  local basename = vim.fn.fnamemodify(destination, ":t")
  local temporary = string.format(
    "%s/.%s.neorg-flashcards-%s-%s.tmp",
    directory,
    basename,
    tostring(vim.fn.getpid()),
    tostring(uv.hrtime())
  )
  local function fail(message)
    pcall(vim.fn.delete, temporary)
    release_lock(lock)
    return false, message
  end

  local permissions = opts.permissions
  if permissions == nil then
    permissions = vim.fn.getfperm(destination)
  end

  local ok_write, write_result = pcall(vim.fn.writefile, lines, temporary)
  if not ok_write or write_result == -1 then
    return fail(tostring(write_result))
  end
  if permissions ~= "" then
    local ok_permissions, permission_result = pcall(vim.fn.setfperm, temporary, permissions)
    if not ok_permissions or permission_result == 0 then
      return fail("could not preserve source-file permissions")
    end
  end

  -- The source may have changed after it was read and validated but while the
  -- replacement file was being prepared. Re-resolve the user's path and
  -- compare its current contents immediately before rename. The adjacent lock
  -- serializes every unloaded write made by this plugin; this final check also
  -- rejects a known-stale snapshot after a non-cooperating writer intervenes.
  local expected = opts.expected
  if expected then
    local current_destination, current_err = resolve_destination(path, opts)
    if not current_destination then
      return fail("source changed while preparing this update: " .. tostring(current_err))
    end
    if current_destination ~= expected.destination then
      return fail("source changed while preparing this update; retry against the latest file")
    end

    if expected.missing then
      if uv.fs_lstat(absolute_path(path)) then
        return fail("source changed while preparing this update; retry against the latest file")
      end
    else
      local ok_current, current_lines = pcall(vim.fn.readfile, current_destination)
      if not ok_current or util.lines_fingerprint(current_lines) ~= expected.fingerprint then
        return fail("source changed while preparing this update; retry against the latest file")
      end
    end
  elseif opts.reject_symlink then
    -- Backups do not replace a source snapshot, but their safety rule must
    -- still hold if a symlink appears while the temporary file is written.
    local current_destination, current_err = resolve_destination(path, opts)
    if not current_destination or current_destination ~= destination then
      return fail(tostring(current_err or "destination changed while preparing this update"))
    end
  end

  local renamed, rename_err = uv.fs_rename(temporary, destination)
  if not renamed then
    return fail(tostring(rename_err))
  end
  release_lock(lock)
  return true
end

local function has_matching_custom_writer(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  local tail = vim.fn.fnamemodify(name, ":t")
  local canonical = util.canonical_path(name)
  for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ event = "BufWriteCmd" })) do
    if autocmd.buf == bufnr then
      return true
    end
    local pattern = autocmd.pattern
    if type(pattern) == "string" and pattern ~= "" then
      local ok_regex, regex = pcall(vim.fn.glob2regpat, pattern)
      if ok_regex then
        local candidates = pattern:find("[/\\]") and { name, canonical } or { tail }
        for _, candidate in ipairs(candidates) do
          if candidate ~= "" and vim.fn.match(candidate, regex) >= 0 then
            return true
          end
        end
      end
    end
  end
  return false
end

local function execute_write_hooks(event, bufnr)
  local previous_error = vim.v.errmsg
  vim.v.errmsg = ""
  local ok, err = pcall(vim.api.nvim_exec_autocmds, event, {
    buffer = bufnr,
    modeline = false,
  })
  local reported_error = vim.v.errmsg
  vim.v.errmsg = previous_error
  if not ok then
    return false, err
  elseif reported_error ~= "" then
    return false, reported_error
  end
  return true
end

local function write_source_lines(path, bufnr, lines, opts)
  opts = opts or {}
  local expected = source_guard(lines)
  local destination_opts = vim.tbl_extend("force", {}, opts)
  if expected and expected.allowed_root then
    destination_opts.allowed_root = expected.allowed_root
  end
  local current_destination, destination_err = resolve_destination(path, destination_opts)
  if not current_destination then
    return false, destination_err, false
  end

  if bufnr then
    if
      not vim.api.nvim_buf_is_valid(bufnr)
      or util.canonical_path(vim.api.nvim_buf_get_name(bufnr)) ~= current_destination
    then
      return false, "Source buffer no longer matches the configured collection destination", false
    end
    local was_modified = vim.bo[bufnr].modified
    local was_modifiable = vim.bo[bufnr].modifiable

    if vim.bo[bufnr].readonly then
      return false, "Open flashcard buffer is read-only", false
    end
    if not was_modifiable then
      return false, "Open flashcard buffer is not modifiable", false
    end

    local original_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local function restore_buffer()
      local restored, restore_err = pcall(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then
          error("buffer was deleted while writing")
        end
        vim.bo[bufnr].modifiable = true
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, original_lines)
        vim.bo[bufnr].modified = was_modified
        vim.bo[bufnr].modifiable = was_modifiable
      end)
      if not restored then
        return false, restore_err
      end
      return true
    end

    local function restore_failure(reason)
      local restored, restore_err = restore_buffer()
      if not restored then
        reason = string.format("%s (also could not restore the buffer: %s)", tostring(reason), tostring(restore_err))
      end
      return false, reason, false
    end

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    local prepared_destination, prepared_err = resolve_destination(path, destination_opts)
    if
      not prepared_destination
      or prepared_destination ~= current_destination
      or not vim.api.nvim_buf_is_valid(bufnr)
      or util.canonical_path(vim.api.nvim_buf_get_name(bufnr)) ~= current_destination
    then
      return restore_failure(
        prepared_err or "source changed while preparing this update; retry against the latest file"
      )
    end

    if was_modified then
      return true, "Flashcard changes updated in open modified buffer; write the file to persist them.", false
    end

    -- A custom writer owns the semantics of its buffer. Do not bypass or
    -- compose with it: retain the candidate as a normal modified buffer and
    -- let that writer persist it when the user next saves.
    if has_matching_custom_writer(bufnr) then
      return true, "Flashcard changes updated in a custom-write buffer; write the file to persist them.", false
    end

    local pre_ok, pre_err = execute_write_hooks("BufWritePre", bufnr)
    if not pre_ok then
      return restore_failure(pre_err)
    end

    if not vim.api.nvim_buf_is_valid(bufnr) then
      return false, "source buffer was deleted by a pre-write hook", false
    end
    prepared_destination, prepared_err = resolve_destination(path, destination_opts)
    if
      not prepared_destination
      or prepared_destination ~= current_destination
      or util.canonical_path(vim.api.nvim_buf_get_name(bufnr)) ~= current_destination
    then
      return restore_failure(
        prepared_err or "source changed while preparing this update; retry against the latest file"
      )
    end

    local persisted = false
    local post_error
    local write_error
    local writing = false
    local write_autocmd
    write_autocmd = vim.api.nvim_create_autocmd("BufWriteCmd", {
      buffer = bufnr,
      once = true,
      callback = function()
        if writing then
          error("recursive flashcard source write")
        end
        writing = true

        if not vim.api.nvim_buf_is_valid(bufnr) then
          write_error = "source buffer was deleted while writing"
          writing = false
          return
        end
        local checked_destination, checked_err = resolve_destination(path, destination_opts)
        if
          not checked_destination
          or checked_destination ~= current_destination
          or util.canonical_path(vim.api.nvim_buf_get_name(bufnr)) ~= current_destination
        then
          write_error = checked_err or "source changed while preparing this update; retry against the latest file"
          writing = false
          return
        end

        local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local atomic_ok, atomic_err = atomic_write(path, buffer_lines, {
          expected = expected,
          allowed_root = destination_opts.allowed_root,
        })
        if not atomic_ok then
          write_error = atomic_err
          writing = false
          return
        end

        for index = #lines, 1, -1 do
          lines[index] = nil
        end
        for index, line in ipairs(buffer_lines) do
          lines[index] = line
        end
        persisted = true
        vim.bo[bufnr].modified = false
        local post_ok, post_err = execute_write_hooks("BufWritePost", bufnr)
        if not post_ok then
          post_error = post_err
        end
        writing = false
      end,
    })

    local ok, err = pcall(vim.api.nvim_buf_call, bufnr, function()
      vim.cmd("silent write")
    end)
    pcall(vim.api.nvim_del_autocmd, write_autocmd)
    if not persisted then
      return restore_failure(write_error or err or "source write did not persist")
    end
    if post_error or not ok then
      return true, "Flashcard changes were saved, but a post-write hook failed: " .. tostring(post_error or err), true
    end
    return true, nil, true
  end

  if not expected then
    local destination
    destination, destination_err = resolve_destination(path, destination_opts)
    if not destination then
      return false, destination_err, false
    end
    if (vim.uv or vim.loop).fs_lstat(absolute_path(path)) then
      return false, "Source changed before this update; retry against the latest file", false
    end
    expected = {
      destination = destination,
      missing = true,
    }
  end

  local allowed_root = expected.allowed_root or destination_opts.allowed_root
  local ok, err = atomic_write(path, lines, {
    expected = expected,
    allowed_root = allowed_root,
  })
  if not ok then
    return false, err, false
  end
  return true, nil, true
end

local function end_line_for_card(lines, card)
  if lines[card.end_line] and lines[card.end_line]:match("^%s*@end%s*$") then
    return card.end_line
  end

  for index = card.start_line, #lines do
    if lines[index]:match("^%s*@end%s*$") then
      return index
    end
  end

  return nil
end

local function upsert_field(lines, start_line, end_line, field, value)
  local line = field_line(lines, start_line, end_line, field)
  local rendered = field .. ": " .. value

  if line then
    lines[line] = rendered
    return 0
  end

  table.insert(lines, end_line, rendered)
  return 1
end

local function adjust_cached_lines(cards, updated_card, original_end_line, delta)
  if delta == 0 then
    return
  end

  for _, card in ipairs(cards or {}) do
    if card.path == updated_card.path and card ~= updated_card and card.start_line > original_end_line then
      card.start_line = card.start_line + delta
      card.end_line = card.end_line + delta
    end
  end
end

local function update_source_versions(cards, updated_card, lines)
  local source_version = util.lines_fingerprint(lines)
  updated_card.source_version = source_version

  for _, card in ipairs(cards or {}) do
    if card ~= updated_card and card.path == updated_card.path then
      card.source_version = source_version
    end
  end
end

function M.set_card_fields(card, updates, opts)
  opts = opts or {}
  local lines, bufnr, err = source_lines(card.path, opts)
  if not lines then
    return false, err, false
  end

  if card.source_version and card.source_version ~= util.lines_fingerprint(lines) then
    return false, "Source changed since this review started; restart the review before rating this card.", false
  end

  local original_end_line = card.end_line
  local end_line = end_line_for_card(lines, card)
  if not end_line then
    return false, "Could not find @end for " .. card.path .. ":" .. card.start_line, false
  end

  local before = #lines
  for _, update in ipairs(updates) do
    local inserted = upsert_field(lines, card.start_line, end_line, update.field, update.value)
    end_line = end_line + inserted
  end

  local ok, message, persisted = write_source_lines(card.path, bufnr, lines, opts)
  if not ok then
    return false, "Could not save flashcard metadata: " .. tostring(message), false
  end

  local delta = #lines - before
  for _, update in ipairs(updates) do
    card.values[update.field] = update.value
    if update.field == "id" then
      card.id = update.value
    end
  end
  card.end_line = card.end_line + delta
  adjust_cached_lines(opts and opts.cards, card, original_end_line, delta)
  local final_lines = bufnr and vim.api.nvim_buf_get_lines(bufnr, 0, -1, false) or lines
  update_source_versions(opts and opts.cards, card, final_lines)

  return true, message, persisted
end

-- Restore a set of fields exactly as they were before an operation. A field
-- absent from `prior` is deleted instead of being retained as `field: `.
-- This is intentionally one source write, so undo cannot expose a half-
-- restored scheduling state.
function M.restore_card_fields(card, prior, fields, opts)
  prior = prior or {}
  fields = fields or {}
  opts = opts or {}

  local lines, bufnr, err = source_lines(card.path, opts)
  if not lines then
    return false, err, false
  end

  if card.source_version and card.source_version ~= util.lines_fingerprint(lines) then
    return false, "Source changed since this card was loaded; refresh before changing it.", false
  end

  local original_end_line = card.end_line
  local end_line = end_line_for_card(lines, card)
  if not end_line then
    return false, "Could not find @end for " .. card.path .. ":" .. card.start_line, false
  end

  local before = #lines
  local restored = {}
  for _, item in ipairs(fields) do
    local field = type(item) == "table" and item.field or item
    field = util.trim(field):lower():gsub("-", "_")
    if field ~= "" and not restored[field] then
      restored[field] = true
      local value = prior[field]
      if value == nil then
        local line = field_line(lines, card.start_line, end_line, field)
        if line then
          table.remove(lines, line)
          end_line = end_line - 1
        end
      else
        local inserted = upsert_field(lines, card.start_line, end_line, field, tostring(value))
        end_line = end_line + inserted
      end
    end
  end

  local ok, message, persisted = write_source_lines(card.path, bufnr, lines, opts)
  if not ok then
    return false, "Could not update flashcard fields: " .. tostring(message), false
  end

  local delta = #lines - before
  for field in pairs(restored) do
    card.values[field] = prior[field]
    if field == "id" then
      card.id = prior[field]
    end
  end
  card.end_line = card.end_line + delta
  adjust_cached_lines(opts and opts.cards, card, original_end_line, delta)
  local final_lines = bufnr and vim.api.nvim_buf_get_lines(bufnr, 0, -1, false) or lines
  update_source_versions(opts and opts.cards, card, final_lines)

  return true, message, persisted
end

function M.unset_card_fields(card, fields, opts)
  return M.restore_card_fields(card, {}, fields, opts)
end

-- Delete one physical flashcard block. Card IDs are deliberately not used as
-- the target: duplicate IDs make a card invalid, but users must still be able
-- to remove either duplicate safely. The source fingerprint and exact cached
-- range protect the asynchronous confirmation flow from deleting a block
-- after its file changed underneath the hub.
function M.delete_card(card, opts)
  opts = opts or {}
  if type(card) ~= "table" or util.isempty(card.path) then
    return false, "Cannot delete a flashcard without a saved source file", false
  end

  local lines, bufnr, err = source_lines(card.path, opts)
  if not lines then
    return false, err, false
  end

  if card.source_version and card.source_version ~= util.lines_fingerprint(lines) then
    return false, "Source changed since this card was selected; refresh before deleting it.", false
  end

  local start_line = tonumber(card.start_line)
  local end_line = tonumber(card.end_line)
  if
    not start_line
    or not end_line
    or start_line ~= math.floor(start_line)
    or end_line ~= math.floor(end_line)
    or start_line < 1
    or end_line < start_line
    or end_line > #lines
  then
    return false, "Flashcard source range is invalid; refresh before deleting it.", false
  end

  local source_kind = lines[start_line] and lines[start_line]:match("^%s*@flashcard%s+([%w_-]+)%s*$")
  if not source_kind or (not util.isempty(card.kind) and source_kind ~= card.kind) then
    return false, "Flashcard no longer starts at the selected source line; refresh before deleting it.", false
  end

  if card.closed == false then
    return false, "Cannot safely delete an unclosed flashcard; add its missing @end first.", false
  elseif not lines[end_line]:match("^%s*@end%s*$") then
    return false, "Flashcard no longer ends at the selected source line; refresh before deleting it.", false
  end

  local candidate = vim.deepcopy(lines)
  for _ = start_line, end_line do
    table.remove(candidate, start_line)
  end

  -- A normally formatted block has a blank line on either side. Removing the
  -- block would leave two adjacent separators, so collapse only that join and
  -- leave all unrelated prose and file headings untouched.
  if
    start_line > 1
    and candidate[start_line - 1]
    and candidate[start_line]
    and util.trim(candidate[start_line - 1]) == ""
    and util.trim(candidate[start_line]) == ""
  then
    table.remove(candidate, start_line)
  end

  local backup_path
  if not bufnr then
    backup_path = card.path .. ".flashcards-backup"
    local uv = vim.uv or vim.loop
    local source_path = uv.fs_realpath(card.path) or card.path
    local source_permissions = vim.fn.getfperm(source_path)
    if source_permissions == "" then
      return false, "Could not create deletion backup: could not read source-file permissions", false
    end
    local backup_ok, backup_err = atomic_write(backup_path, lines, {
      allowed_root = opts.allowed_root,
      follow_symlink = false,
      reject_symlink = true,
      permissions = source_permissions,
    })
    if not backup_ok then
      return false, "Could not create deletion backup: " .. tostring(backup_err), false
    end
  end

  local ok, message, persisted = write_source_lines(card.path, bufnr, candidate, opts)
  if not ok then
    return false, "Could not delete flashcard: " .. tostring(message), false
  end
  if backup_path then
    message = "Flashcard deleted; previous source saved to " .. backup_path
  end
  return true, message, persisted
end

-- Buffer-aware file access shared with the add-card flow: reads go through a
-- loaded buffer when one exists, writes persist unless that buffer has unsaved
-- edits.
function M.read_lines(path, opts)
  return source_lines(path, opts)
end

function M.write_lines(path, bufnr, lines, opts)
  return write_source_lines(path, bufnr, lines, opts)
end

function M.resolve_path(path, opts)
  return resolve_destination(path, opts)
end

function M.ensure_parent(path, opts)
  return ensure_destination_parent(path, opts)
end

return M
