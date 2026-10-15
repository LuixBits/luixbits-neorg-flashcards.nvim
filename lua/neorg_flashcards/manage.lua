local metadata = require("neorg_flashcards.metadata")
local store = require("neorg_flashcards.store")
local util = require("neorg_flashcards.util")
local M = {}

function M.change_tag(config, cards, old, replacement)
  if old == "" or old:find("[%s,]") or (replacement and (replacement == "" or replacement:find("[%s,]"))) then
    return false, "categories must use one tag token"
  end
  old = old:lower()
  replacement = replacement and replacement:lower() or nil
  if replacement == old then
    return true, "Category tag is unchanged"
  end
  local changes, files = {}, {}
  for _, card in ipairs(cards) do
    local tags, next_tags, found = metadata.tags(card), {}, false
    for _, tag in ipairs(tags) do
      if tag == old then
        found = true
      else
        table.insert(next_tags, tag)
      end
    end
    if found then
      if replacement and not vim.tbl_contains(next_tags, replacement) then
        table.insert(next_tags, replacement)
      end
      table.insert(changes, { card = card, tags = table.concat(next_tags, " ") })
      files[card.path] = true
    end
  end
  local opts = { allowed_root = config._root or config.path, cards = cards }
  -- Preflight every source before touching any card, and preserve recoverable
  -- snapshots. The source writer still checks each card immediately at commit.
  for path in pairs(files) do
    local lines, buf, err = store.read_lines(path, opts)
    if not lines then
      return false, err
    end
    if buf and (vim.bo[buf].readonly or not vim.bo[buf].modifiable) then
      return false, "source buffer is read-only: " .. path
    end
    local backup = path .. ".flashcards-tags-backup"
    local previous, backup_buf, backup_err =
      store.read_lines(backup, { allowed_root = opts.allowed_root, create = true, reject_symlink = true })
    if not previous then
      return false, backup_err
    end
    for i = #previous, 1, -1 do
      previous[i] = nil
    end
    for i, line in ipairs(lines) do
      previous[i] = line
    end
    local ok, write_err =
      store.write_lines(backup, backup_buf, previous, { allowed_root = opts.allowed_root, reject_symlink = true })
    if not ok then
      return false, write_err
    end
  end
  local changed, pending, paths = 0, 0, {}
  for _, change in ipairs(changes) do
    local ok, err, persisted = store.set_card_fields(change.card, { { field = "tags", value = change.tags } }, opts)
    if not ok then
      return false,
        string.format(
          "Stopped after %d cards. Changed: %s. Failed: %s (%s). Backups use .flashcards-tags-backup.",
          changed,
          table.concat(vim.tbl_keys(paths), ", "),
          change.card.path,
          tostring(err)
        )
    end
    changed = changed + 1
    paths[change.card.path] = true
    if not persisted then
      pending = pending + 1
    end
  end
  local ok, err = metadata.update(config, function(data)
    if replacement then
      data.categories[replacement] = data.categories[replacement] or data.categories[old] or {}
    end
    data.categories[old] = nil
  end)
  if not ok then
    return false, string.format("Updated %d cards; category metadata still needs repair: %s", changed, tostring(err))
  end
  return true,
    string.format(
      "Updated %d cards%s",
      changed,
      pending > 0 and string.format(" (%d in modified buffers; write to persist)", pending) or ""
    )
end

function M.open(context)
  local config = context.config
  local function live()
    if context.valid() then
      return true
    end
    util.notify("This management prompt has expired; open it again", vim.log.levels.WARN)
    return false
  end
  local function finish(ok, message)
    if message then
      util.notify(message, ok and vim.log.levels.INFO or vim.log.levels.ERROR)
    end
    if context.valid() then
      context.refresh()
    end
  end
  local function input(prompt, default, callback)
    vim.ui.input({ prompt = prompt, default = default }, function(value)
      if value ~= nil and live() then
        callback(util.trim(value))
      end
    end)
  end
  local function choose_category(callback)
    local data = metadata.load(config)
    local groups = metadata.groups(context.cards, data, config, os.time())
    groups = vim.tbl_filter(function(group)
      return group.name ~= ""
    end, groups)
    vim.ui.select(groups, {
      prompt = "Category",
      format_item = function(group)
        return group.label .. " (" .. group.name .. ")"
      end,
    }, function(group)
      if group and live() then
        callback(group)
      end
    end)
  end
  local choices = {
    "Deck label",
    "Daily goal",
    "Create category",
    "Category label",
    "Category accent",
    "Category order",
    "Rename or merge category",
    "Remove category tag",
    "New deck",
    "Deck default card type",
    "Detach UI-created deck",
  }
  vim.ui.select(choices, { prompt = "Manage " .. (config.label or config.id) }, function(choice)
    if not choice or not live() then
      return
    end
    local data = metadata.load(config)
    if choice == "Deck label" then
      input("Deck label: ", data.label or config.label, function(value)
        if value == "" then
          return
        end
        finish(metadata.update(config, function(next_data)
          next_data.label = value
        end))
      end)
    elseif choice == "Daily goal" then
      input("Unique cards per day (0 disables; today's saved goal stays): ", tostring(data.goal), function(value)
        finish(metadata.update(config, function(next_data)
          next_data.goal = tonumber(value)
        end))
      end)
    elseif choice == "Create category" then
      input("Category tag (one word, hyphens allowed): ", "", function(value)
        finish(metadata.update(config, function(next_data)
          next_data.categories[value:lower()] = next_data.categories[value:lower()] or {}
        end))
      end)
    elseif choice == "Category label" or choice == "Category accent" or choice == "Category order" then
      choose_category(function(group)
        local function update(key, value)
          finish(metadata.update(config, function(next_data)
            next_data.categories[group.name] = next_data.categories[group.name] or {}
            next_data.categories[group.name][key] = value
          end))
        end
        if choice == "Category accent" then
          vim.ui.select({ "note", "accent", "good", "hard", "again" }, { prompt = "Theme accent" }, function(value)
            if value and live() then
              update("accent", value)
            end
          end)
        elseif choice == "Category order" then
          input("Shelf order (lower appears first): ", tostring(group.order), function(value)
            if not tonumber(value) then
              finish(false, "Enter a number")
              return
            end
            update("order", tonumber(value))
          end)
        else
          input("Category label: ", group.label, function(value)
            update("label", value)
          end)
        end
      end)
    elseif choice == "Rename or merge category" or choice == "Remove category tag" then
      choose_category(function(group)
        local function confirm(replacement)
          vim.ui.select({ "Cancel", "Apply" }, {
            prompt = string.format(
              "%s: change tags on %d cards%s?",
              group.name,
              #group.cards,
              replacement and (" to " .. replacement) or " (cards are kept)"
            ),
          }, function(answer)
            if answer == "Apply" and live() then
              finish(M.change_tag(config, context.cards, group.name, replacement))
            end
          end)
        end
        if choice == "Remove category tag" then
          confirm(nil)
        else
          input("Destination tag (existing tags merge): ", group.name, function(value)
            if value == group.name then
              return
            end
            confirm(value)
          end)
        end
      end)
    elseif choice == "New deck" then
      input("Deck ID (lowercase, letters/numbers/hyphens): ", "", function(id)
        input("Deck name: ", id, function(label)
          input("Deck directory: ", "", function(path)
            if path == "" then
              finish(false, "A deck directory is required")
              return
            end
            vim.ui.select({
              "japanese",
              "japanese_production",
              "japanese_kanji",
              "japanese_sentence",
              "question_answer",
              "term_definition",
              "code_output",
              "chinese",
            }, { prompt = "Card type (more can be configured later)" }, function(kind)
              if kind and live() then
                finish(context.create_deck(id, { label = label, path = path, types = { kind } }))
              end
            end)
          end)
        end)
      end)
    elseif choice == "Deck default card type" then
      context.deck_default()
    elseif choice == "Detach UI-created deck" then
      vim.ui.select(
        { "Cancel", "Detach" },
        { prompt = "Detach this deck? Its cards and history are kept." },
        function(answer)
          if answer == "Detach" and live() then
            finish(context.detach_deck())
          end
        end
      )
    end
  end)
end

return M
