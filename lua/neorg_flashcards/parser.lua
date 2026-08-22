local schema = require("neorg_flashcards.schema")
local util = require("neorg_flashcards.util")

local M = {}

local function source_label(card)
  local path = card.path ~= "" and card.path or "[No Name]"
  return string.format("%s:%d", path, card.start_line)
end

function M.parse_lines(lines, path)
  local cards = {}
  local index = 1
  local source_version = util.lines_fingerprint(lines)

  while index <= #lines do
    local kind = lines[index]:match("^%s*@flashcard%s+([%w_-]+)%s*$")
    if kind then
      local card = {
        kind = kind,
        values = {},
        duplicate_fields = {},
        multiline_fields = {},
        path = path or "",
        start_line = index,
        end_line = index,
        closed = false,
        source_version = source_version,
      }
      local last_key = nil
      index = index + 1

      while index <= #lines do
        local line = lines[index]
        if line:match("^%s*@end%s*$") then
          card.end_line = index
          card.closed = true
          break
        end

        local key, value = line:match("^%s*([%w_-]+)%s*:%s*(.-)%s*$")
        if key then
          last_key = key:lower():gsub("-", "_")
          if card.values[last_key] ~= nil then
            card.duplicate_fields[last_key] = true
          end
          card.values[last_key] = util.trim(value)
        elseif last_key and not util.isempty(line) then
          card.multiline_fields[last_key] = true
          card.values[last_key] = card.values[last_key] .. "\n" .. util.trim(line)
        end

        index = index + 1
      end

      if not card.closed then
        card.end_line = #lines
      end
      card.id = schema.card_id(card)
      table.insert(cards, card)
    end
    index = index + 1
  end

  return cards
end

function M.parse_buffer(bufnr)
  bufnr = bufnr or 0
  local path = vim.api.nvim_buf_get_name(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return M.parse_lines(lines, path)
end

function M.parse_file(path)
  local bufnr = util.loaded_buffer(path)
  if bufnr then
    return M.parse_buffer(bufnr), {}
  end

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return {}, { string.format("%s: could not read file", path) }
  end

  return M.parse_lines(lines, path), {}
end

function M.valid_cards(config, cards)
  local valid = {}
  local errors = {}
  local invalid = {}
  local messages_by_card = {}
  local cards_by_id = {}

  for _, card in ipairs(cards) do
    local card_errors = schema.validate_card(config, card)
    messages_by_card[card] = card_errors

    local id = schema.card_id(card)
    if id then
      cards_by_id[id] = cards_by_id[id] or {}
      table.insert(cards_by_id[id], card)
    end
  end

  -- A stable ID is the scheduling identity of a card. If it is ambiguous,
  -- neither copy is safe to review: updating one could otherwise attach
  -- history or scheduling state to the wrong block.
  for id, duplicate_cards in pairs(cards_by_id) do
    if #duplicate_cards > 1 then
      for _, card in ipairs(duplicate_cards) do
        local other_sources = {}
        for _, other in ipairs(duplicate_cards) do
          if other ~= card then
            table.insert(other_sources, source_label(other))
          end
        end
        table.insert(
          messages_by_card[card],
          string.format("duplicate id %s (also used by %s)", id, table.concat(other_sources, ", "))
        )
      end
    end
  end

  for _, card in ipairs(cards) do
    local card_errors = messages_by_card[card]
    if #card_errors == 0 then
      table.insert(valid, card)
    else
      table.insert(invalid, {
        card = card,
        messages = card_errors,
        source = source_label(card),
      })
      table.insert(errors, string.format("%s: %s", source_label(card), table.concat(card_errors, ", ")))
    end
  end

  return valid, errors, invalid
end

function M.flashcard_files(config)
  local root_spec = config._collection_root or config.flashcards_dir
  if type(root_spec) == "string" then
    vim.fn.mkdir(config.flashcards_dir, "p")
  end
  local root, root_err = util.resolve_pinned_directory(root_spec)
  if not root then
    return {}, root_err
  end

  local discovered = vim.fn.globpath(root, "**/*.norg", false, true)
  local files = {}
  local seen = {}

  for _, path in ipairs(discovered) do
    local canonical = util.canonical_path(path)
    if util.resolved_path_is_within(canonical, root) and not seen[canonical] then
      table.insert(files, path)
      seen[canonical] = true
    end
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local path = vim.api.nvim_buf_get_name(bufnr)
    local canonical = util.canonical_path(path)
    if
      vim.api.nvim_buf_is_loaded(bufnr)
      and path:match("%.norg$")
      and util.resolved_path_is_within(canonical, root)
      and not seen[canonical]
    then
      table.insert(files, path)
      seen[canonical] = true
    end
  end

  table.sort(files)
  return files, nil
end

function M.collect_flashcards(config)
  local cards = {}
  local errors = {}

  local files, discovery_err = M.flashcard_files(config)
  if discovery_err then
    table.insert(errors, discovery_err)
  end
  for _, file in ipairs(files) do
    local file_cards, file_errors = M.parse_file(file)
    for _, card in ipairs(file_cards) do
      table.insert(cards, card)
    end
    for _, err in ipairs(file_errors) do
      table.insert(errors, err)
    end
  end

  local valid, validation_errors, invalid = M.valid_cards(config, cards)
  for _, err in ipairs(validation_errors) do
    table.insert(errors, err)
  end

  return valid, errors, invalid
end

return M
