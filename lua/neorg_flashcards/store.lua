local identity = require("neorg_flashcards.identity")
local util = require("neorg_flashcards.util")

local M = {}

local function field_line(lines, start_line, end_line, field)
  for index = start_line + 1, math.min(end_line - 1, #lines) do
    local key = lines[index]:match("^%s*([%w_-]+)%s*:")
    if key and key:lower():gsub("-", "_") == field then
      return index
    end
  end
  return nil
end

local function source_lines(path)
  if util.isempty(path) then
    return nil, nil, "Cannot save rating for an unsaved buffer"
  end

  local bufnr = util.loaded_buffer(path)
  if bufnr then
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), bufnr, nil
  end

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, nil, string.format("%s: could not read file", path)
  end

  return lines, nil, nil
end

local function write_source_lines(path, bufnr, lines)
  if bufnr then
    local was_modified = vim.bo[bufnr].modified
    local was_modifiable = vim.bo[bufnr].modifiable

    if vim.bo[bufnr].readonly then
      return false, "Open flashcard buffer is read-only", false
    end
    if not was_modifiable then
      return false, "Open flashcard buffer is not modifiable", false
    end

    local original_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    if was_modified then
      return true, "Flashcard changes updated in open modified buffer; write the file to persist them.", false
    end

    local ok, err = pcall(vim.api.nvim_buf_call, bufnr, function()
      vim.cmd("silent write")
    end)
    if not ok then
      local read_ok, disk_lines = pcall(vim.fn.readfile, path)
      if read_ok and vim.deep_equal(disk_lines, lines) then
        return true, "Flashcard changes were saved, but a post-write hook failed: " .. tostring(err), true
      end

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
        return false,
          string.format("%s (also could not restore the buffer: %s)", tostring(err), tostring(restore_err)),
          false
      end
      return false, err, false
    end
    return true, nil, true
  end

  local ok, err = pcall(vim.fn.writefile, lines, path)
  if not ok or err == -1 then
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
  local lines, bufnr, err = source_lines(card.path)
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

  local ok, message, persisted = write_source_lines(card.path, bufnr, lines)
  if not ok then
    return false, "Could not save flashcard metadata: " .. tostring(message), false
  end

  local delta = #lines - before
  for _, update in ipairs(updates) do
    card.values[update.field] = update.value
    if update.field == "id" or update.field == "card_id" then
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

  local lines, bufnr, err = source_lines(card.path)
  if not lines then
    return false, err, false
  end

  if card.source_version and card.source_version ~= util.lines_fingerprint(lines) then
    return false, "Source changed since this review started; restart the review before undoing this rating.", false
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

  local ok, message, persisted = write_source_lines(card.path, bufnr, lines)
  if not ok then
    return false, "Could not restore rating: " .. tostring(message), false
  end

  local delta = #lines - before
  for field in pairs(restored) do
    card.values[field] = prior[field]
    if field == "id" or field == "card_id" then
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
function M.delete_card(card)
  if type(card) ~= "table" or util.isempty(card.path) then
    return false, "Cannot delete a flashcard without a saved source file", false
  end

  local lines, bufnr, err = source_lines(card.path)
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
    if end_line ~= #lines or lines[end_line]:match("^%s*@end%s*$") then
      return false, "Unclosed flashcard range changed; refresh before deleting it.", false
    end
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

  local ok, message, persisted = write_source_lines(card.path, bufnr, candidate)
  if not ok then
    return false, "Could not delete flashcard: " .. tostring(message), false
  end
  return true, message, persisted
end

-- Buffer-aware file access shared with the add-card flow: reads go through a
-- loaded buffer when one exists, writes persist unless that buffer has unsaved
-- edits.
function M.read_lines(path)
  return source_lines(path)
end

function M.write_lines(path, bufnr, lines)
  return write_source_lines(path, bufnr, lines)
end

local function migration_result(cards)
  return {
    total = #cards,
    assigned = 0,
    existing = 0,
    files = 0,
    pending_buffers = 0,
    persisted = true,
    dry_run = false,
    planned = 0,
    assignments = {},
    messages = {},
    errors = {},
  }
end

local function migration_error(result, message)
  table.insert(result.errors, message)
end

local function source_key(path)
  local canonical = util.canonical_path(path)
  return canonical ~= "" and canonical or path
end

local function generated_id(used, opts)
  local factory = opts and opts.id_factory or identity.generate
  for _ = 1, 1000 do
    local id = util.trim(factory(used))
    if identity.is_valid(id) and not used[id] then
      return id
    end
  end
  return nil
end

-- Batch-migrate legacy cards without silently overwriting stale sources.
-- Every source is read and fingerprint-checked before the first write. Loaded,
-- modified buffers are updated in memory but deliberately left unpersisted,
-- matching set_card_fields' safety contract.
function M.migrate_card_ids(cards, opts)
  cards = cards or {}
  opts = opts or {}
  local result = migration_result(cards)
  result.dry_run = opts.dry_run == true

  local used = {}
  local missing = {}
  for _, card in ipairs(cards) do
    local id = identity.card_id(card)
    if id then
      result.existing = result.existing + 1
      if not identity.is_valid(id) then
        migration_error(
          result,
          string.format("Invalid flashcard id %s at %s:%d", id, card.path or "[No Name]", card.start_line or 0)
        )
      elseif used[id] and used[id] ~= card then
        migration_error(
          result,
          string.format(
            "Duplicate flashcard id %s at %s:%d and %s:%d",
            id,
            used[id].path or "[No Name]",
            used[id].start_line or 0,
            card.path or "[No Name]",
            card.start_line or 0
          )
        )
      else
        used[id] = card
      end
    else
      table.insert(missing, card)
    end
  end

  if #result.errors > 0 then
    return false, result
  end

  local groups = {}
  for _, card in ipairs(missing) do
    if util.isempty(card.path) then
      migration_error(result, string.format("Cannot assign an id to an unsaved card at line %d", card.start_line or 0))
    else
      local id = generated_id(used, opts)
      if not id then
        migration_error(result, "Could not generate a unique flashcard id")
        break
      end
      used[id] = card

      local assignment = {
        card = card,
        id = id,
        path = card.path,
        start_line = card.start_line,
        end_line = card.end_line,
      }
      table.insert(result.assignments, assignment)

      local key = source_key(card.path)
      groups[key] = groups[key] or {
        path = card.path,
        assignments = {},
        cards = {},
      }
      table.insert(groups[key].assignments, assignment)
    end
  end

  for _, card in ipairs(cards) do
    if not util.isempty(card.path) then
      local group = groups[source_key(card.path)]
      if group then
        table.insert(group.cards, card)
      end
    end
  end

  if #result.errors > 0 then
    return false, result
  end

  result.planned = #result.assignments

  if result.dry_run or #result.assignments == 0 then
    result.persisted = not result.dry_run
    return true, result
  end

  -- Preflight and construct every updated source before writing any of them.
  local prepared = {}
  for _, group in pairs(groups) do
    local lines, bufnr, err = source_lines(group.path)
    if not lines then
      migration_error(result, err)
    else
      local group_ok = true
      local fingerprint = util.lines_fingerprint(lines)
      for _, assignment in ipairs(group.assignments) do
        local card = assignment.card
        if card.source_version and card.source_version ~= fingerprint then
          migration_error(
            result,
            string.format(
              "%s:%d changed since collection; collect the cards again before migrating ids",
              card.path,
              card.start_line
            )
          )
          group_ok = false
          break
        end

        local end_line = end_line_for_card(lines, card)
        if not end_line then
          migration_error(result, string.format("Could not find @end for %s:%d", card.path, card.start_line))
          group_ok = false
          break
        end
        assignment.insertion_line = end_line
      end

      if group_ok then
        table.sort(group.assignments, function(left, right)
          return left.insertion_line > right.insertion_line
        end)
        for _, assignment in ipairs(group.assignments) do
          table.insert(lines, assignment.insertion_line, "id: " .. assignment.id)
        end

        group.lines = lines
        group.bufnr = bufnr
        table.insert(prepared, group)
      end
    end
  end

  if #result.errors > 0 then
    return false, result
  end

  table.sort(prepared, function(left, right)
    return source_key(left.path) < source_key(right.path)
  end)

  for _, group in ipairs(prepared) do
    local ok, message, persisted = write_source_lines(group.path, group.bufnr, group.lines)
    if not ok then
      migration_error(result, string.format("Could not migrate ids in %s: %s", group.path, tostring(message)))
      if result.files > 0 then
        migration_error(
          result,
          string.format(
            "%d earlier file(s) were already updated; migration is additive, so fix the error and run it again",
            result.files
          )
        )
      end
      result.persisted = false
      return false, result
    end

    result.files = result.files + 1
    if message then
      table.insert(result.messages, message)
    end
    if not persisted then
      result.pending_buffers = result.pending_buffers + 1
      result.persisted = false
    end

    for _, card in ipairs(group.cards) do
      local start_delta = 0
      local end_delta = 0
      for _, assignment in ipairs(group.assignments) do
        if assignment.insertion_line < card.start_line then
          start_delta = start_delta + 1
        end
        if assignment.insertion_line <= card.end_line then
          end_delta = end_delta + 1
        end
      end
      card.start_line = card.start_line + start_delta
      card.end_line = card.end_line + end_delta
    end

    for _, assignment in ipairs(group.assignments) do
      assignment.card.values.id = assignment.id
      assignment.card.id = assignment.id
      result.assigned = result.assigned + 1
    end
    update_source_versions(group.cards, group.assignments[1].card, group.lines)
  end

  return true, result
end

return M
