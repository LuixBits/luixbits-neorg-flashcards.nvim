-- Serializable definitions for decks created in Overview. Configured decks
-- retain ownership of their settings; the registry never rewrites Lua/Nix.
local store = require("neorg_flashcards.store")
local presets = require("neorg_flashcards.presets")
local M = {}

function M.path(opts)
  if opts.deck_registry == false then
    return nil
  end
  return vim.fn.expand(opts.deck_registry or (vim.fn.stdpath("data") .. "/neorg-flashcards/decks.json"))
end

function M.read(path)
  if not path then
    return { version = 1, decks = {} }
  end
  local lines, buf, err = store.read_lines(path, { create = true, reject_symlink = true })
  if not lines then
    return nil, err
  end
  local data = { version = 1, decks = {} }
  if #lines > 0 then
    local ok, value = pcall(vim.json.decode, table.concat(lines, "\n"))
    if not ok then
      return nil, "could not decode deck registry"
    end
    data = value
  end
  if type(data) ~= "table" or data.version ~= 1 or type(data.decks) ~= "table" then
    return nil, "unsupported deck registry format"
  end
  return data, nil, lines, buf
end

function M.merge(opts, data)
  local result = vim.deepcopy(opts)
  result.collections = result.collections or {}
  local err
  if not data then
    data, err = M.read(M.path(opts))
  end
  if not data then
    return nil, err
  end
  for id, deck in pairs(data.decks) do
    if result.collections[id] then
      return nil, "deck registry conflicts with configured collection: " .. tostring(id)
    end
    if type(deck) ~= "table" or type(deck.types) ~= "table" or #deck.types == 0 then
      return nil, "registered deck requires bundled card types: " .. tostring(id)
    end
    local ok, schemas = pcall(presets.only, unpack(deck.types))
    if not ok then
      return nil, tostring(schemas)
    end
    result.collections[id] = {
      label = deck.label,
      path = deck.path,
      default_file = deck.default_file or "cards.norg",
      default_card_type = deck.default_card_type or deck.types[1],
      schemas = schemas,
      scheduling = deck.scheduling,
      history_file = deck.history_file,
    }
  end
  return result
end

function M.update(opts, change)
  local path = M.path(opts)
  if not path then
    return false, "UI-created decks are disabled by deck_registry = false"
  end
  local data, err, lines, buf = M.read(path)
  if not data then
    return false, err
  end
  local ok, message = pcall(change, data.decks)
  if not ok then
    return false, tostring(message)
  end
  local merged, merge_err = M.merge(opts, data)
  if not merged then
    return false, merge_err
  end
  -- Preparation validates IDs, schemas, pinned roots, and history isolation.
  local workspace, errors = require("neorg_flashcards.collections").prepare(merged)
  if not workspace then
    return false, table.concat(errors, "; ")
  end
  local parent = vim.fn.fnamemodify(path, ":h")
  local made, mkdir_err = pcall(vim.fn.mkdir, parent, "p")
  if not made then
    return false, tostring(mkdir_err)
  end
  for index = #lines, 1, -1 do
    lines[index] = nil
  end
  lines[1] = vim.json.encode(data)
  return store.write_lines(path, buf, lines, { reject_symlink = true })
end

return M
