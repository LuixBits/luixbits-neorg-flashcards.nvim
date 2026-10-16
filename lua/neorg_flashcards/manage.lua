local dialog = require("neorg_flashcards.dialog")
local chapters = require("neorg_flashcards.chapters")
local metadata = require("neorg_flashcards.metadata")
local store = require("neorg_flashcards.store")
local util = require("neorg_flashcards.util")
local M = {}

function M.change_tag(config, cards, old, replacement)
  local _, metadata_error = metadata.load(config)
  if metadata_error then
    return false, metadata_error
  end
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
  local initial = metadata.load(config)
  local collection = initial.label or config.label or config.id
  local category, menu, tags, settings, run
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
  local function input(prompt, default, callback, opts)
    opts = opts or {}
    opts.prompt, opts.default = prompt, default
    opts.description = opts.description or { collection }
    opts.validate = opts.validate
      or function(value)
        if util.trim(value) == "" then
          return "Enter a value."
        end
      end
    dialog.input(opts, function(value)
      if value ~= nil and live() then
        callback(util.trim(value))
      end
    end)
  end
  local function tag_token(value)
    if value == "" or value:find("[%s,]") then
      return "Use one word; hyphens are allowed."
    end
  end
  local function choose_category(callback)
    if category then
      callback(category)
      return
    end
    local groups = metadata.groups(context.cards, metadata.load(config), config, os.time())
    groups = vim.tbl_filter(function(group)
      return group.name ~= ""
    end, groups)
    dialog.select(groups, {
      prompt = "Choose tag",
      description = { collection },
      format_item = function(group)
        return group.label .. " (" .. group.name .. ")"
      end,
    }, function(group)
      if group and live() then
        callback(group)
      end
    end)
  end
  local function pick(title, description, choices, back)
    if live() then
      dialog.select(choices, { prompt = title, description = { description }, back = back }, run)
    end
  end
  tags = function()
    if not live() then
      return
    end
    category = nil
    local groups = metadata.groups(context.cards, metadata.load(config), config, os.time())
    groups = vim.tbl_filter(function(group)
      return group.name ~= ""
    end, groups)
    table.insert(groups, 1, { create = true })
    dialog.select(groups, {
      prompt = "Tags",
      description = { collection },
      back = menu,
      format_item = function(group)
        if group.create then
          return "+ New tag"
        end
        return string.format("%s (%d %s)", group.label, #group.cards, #group.cards == 1 and "card" or "cards")
      end,
    }, function(group)
      if not group or not live() then
        return
      end
      if group.create then
        run("New tag")
      else
        category = group
        pick("Tag", group.name, {
          "Rename or merge tag",
          "Create chapter from tag",
          "Note appearance",
          "Remove tag",
        }, tags)
      end
    end)
  end
  settings = function()
    local choices = { "Daily goal" }
    if not context.owned then
      vim.list_extend(choices, { "Enable card type", "Default card type" })
    end
    pick("Study settings", collection, choices, menu)
  end
  run = function(choice)
    if not choice or not live() then
      return
    end
    local data = metadata.load(config)
    if choice == "Tags" then
      tags()
    elseif choice == "Study settings" then
      settings()
    elseif choice == "Note appearance" then
      pick("Note appearance", category.label, { "Note label", "Note color", "Note order" }, tags)
    elseif choice == "Add card" then
      context.add_card()
    elseif choice == "Edit card" then
      context.edit_card()
    elseif choice == "Delete card" then
      context.delete_card()
    elseif choice == "New chapter" then
      input("New chapter", "", function(value)
        finish(chapters.create(config, value))
      end)
    elseif choice == "Create chapter from tag" then
      choose_category(function(group)
        input("New chapter", group.label, function(value)
          dialog.select({ "Cancel", "Create chapter" }, {
            prompt = "Create chapter",
            description = {
              value,
              string.format(
                "Move %d %s into this chapter. Existing tags are kept.",
                #group.cards,
                #group.cards == 1 and "card" or "cards"
              ),
            },
          }, function(answer)
            if answer == "Create chapter" and live() then
              finish(chapters.create(config, value, group.cards))
            end
          end)
        end)
      end)
    elseif choice == "Rename chapter" then
      local chapter = data.chapters[context.chapter]
      if chapter then
        input("Rename chapter", chapter.label, function(value)
          finish(chapters.rename(config, context.chapter, value))
        end)
      end
    elseif choice == "Remove chapter" then
      local chapter = data.chapters[context.chapter]
      if chapter then
        local count = 0
        for _, card in ipairs(context.cards) do
          if chapters.id(data, card) == context.chapter then
            count = count + 1
          end
        end
        dialog.select({ "Cancel", "Remove chapter" }, {
          prompt = "Remove chapter",
          description = {
            chapter.label,
            string.format("%d %s move to Unfiled.", count, count == 1 and "card will" or "cards will"),
            "Cards and review history are kept.",
          },
          danger = "Remove chapter",
        }, function(answer)
          if answer == "Remove chapter" and live() then
            finish(chapters.delete(config, context.chapter))
          end
        end)
      end
    elseif choice == "Move card to chapter" then
      dialog.select(chapters.groups(context.cards, data, config), {
        prompt = "Move card to chapter",
        description = { collection },
        format_item = function(group)
          return group.label
        end,
        back = menu,
      }, function(group)
        if group and live() then
          finish(chapters.move(config, { context.card }, group.name))
        end
      end)
    elseif choice == "Rename collection" then
      input("Rename collection", data.label or config.label, function(value)
        finish(metadata.update(config, function(next_data)
          next_data.label = value
        end))
      end)
    elseif choice == "Daily goal" then
      input("Daily goal", tostring(data.goal), function(value)
        finish(metadata.update(config, function(next_data)
          next_data.goal = tonumber(value)
        end))
      end, {
        description = { "Unique cards per day. Use 0 to turn it off.", "Today's saved goal stays the same." },
        validate = function(value)
          local n = tonumber(value)
          if not n or n < 0 or n > 10000 or n ~= math.floor(n) then
            return "Use a whole number from 0 to 10000."
          end
        end,
      })
    elseif choice == "New tag" then
      input("New tag", "", function(value)
        finish(metadata.update(config, function(next_data)
          next_data.categories[value:lower()] = next_data.categories[value:lower()] or {}
        end))
      end, { description = { "One word, such as travel or household." }, validate = tag_token })
    elseif choice == "Note label" or choice == "Note color" or choice == "Note order" then
      choose_category(function(group)
        local function update(key, value)
          finish(metadata.update(config, function(next_data)
            next_data.categories[group.name] = next_data.categories[group.name] or {}
            next_data.categories[group.name][key] = value
          end))
        end
        if choice == "Note color" then
          dialog.select({ "note", "accent", "good", "hard", "again" }, {
            prompt = "Note color",
            description = { "Uses colors from your theme." },
          }, function(value)
            if value and live() then
              update("accent", value)
            end
          end)
        elseif choice == "Note order" then
          input("Note order", tostring(group.order), function(value)
            update("order", tonumber(value))
          end, {
            description = { "Lower numbers appear first on the desk." },
            validate = function(value)
              local n = tonumber(value)
              if not n or n ~= n or math.abs(n) == math.huge then
                return "Enter a number."
              end
            end,
          })
        else
          input("Note label", group.label, function(value)
            update("label", value)
          end)
        end
      end)
    elseif choice == "Rename or merge tag" or choice == "Remove tag" then
      choose_category(function(group)
        local function confirm(replacement)
          local action = replacement and "Change tag" or "Remove tag"
          dialog.select({ "Cancel", action }, {
            prompt = action,
            description = {
              replacement and (group.name .. " -> " .. replacement) or group.name,
              string.format(
                "Changes tags on %d %s. Cards and history are kept.",
                #group.cards,
                #group.cards == 1 and "card" or "cards"
              ),
            },
            danger = not replacement and action or nil,
          }, function(answer)
            if answer == action and live() then
              finish(M.change_tag(config, context.cards, group.name, replacement))
            end
          end)
        end
        if choice == "Remove tag" then
          confirm(nil)
        else
          input("Rename or merge tag", group.name, function(value)
            if value ~= group.name then
              confirm(value)
            end
          end, { description = { "Using an existing tag merges the two groups." }, validate = tag_token })
        end
      end)
    elseif choice == "New collection" then
      if context.can_create == false then
        dialog.select({ "Close" }, {
          prompt = "Collections are configured",
          description = { "Your setup disables creating collections here. Add one in your Lua or Nix configuration." },
        }, function() end)
        return
      end
      input("Collection ID", "", function(id)
        input("Collection name", id, function(label)
          input("Collection directory", "", function(path)
            local kinds = {
              "japanese",
              "japanese_production",
              "japanese_kanji",
              "japanese_sentence",
              "question_answer",
              "term_definition",
              "code_output",
              "chinese",
            }
            dialog.select(kinds, {
              prompt = "Card type",
              description = { label },
              format_item = function(kind)
                return require("neorg_flashcards.presets")[kind].label or kind
              end,
            }, function(kind)
              if kind and live() then
                finish(context.create_deck(id, { label = label, path = path, types = { kind } }))
              end
            end)
          end)
        end)
      end, {
        description = { "A short ID, such as japanese or computer-science." },
        validate = function(value)
          if not value:match("^[a-z][a-z0-9_-]*$") then
            return "Start with a lowercase letter; use letters, numbers, - or _."
          end
        end,
      })
    elseif choice == "Enable card type" then
      context.deck_type()
    elseif choice == "Default card type" then
      context.deck_default()
    elseif choice == "Detach collection" then
      if context.owned then
        dialog.select({ "Close" }, {
          prompt = "Collection from configuration",
          description = {
            collection,
            "Remove its entry in your Lua or Nix configuration to detach it. Its files are kept.",
          },
        }, function() end)
        return
      end
      dialog.select({ "Cancel", "Detach collection" }, {
        prompt = "Detach collection",
        description = {
          collection,
          "Removes this collection from the workspace.",
          "Card files and review history are kept.",
        },
        danger = "Detach collection",
      }, function(answer)
        if answer == "Detach collection" and live() then
          finish(context.detach_deck())
        end
      end)
    end
  end
  menu = function()
    local title, name, choices
    if context.card then
      title, name = "Card", context.card_label or collection
      choices = { "Edit card", "Move card to chapter", "Delete card" }
    elseif context.kind == "chapter" or context.kind == "chapters" or context.kind == "cards" then
      local chapter = initial.chapters[context.chapter]
      title, name = "Chapter", chapter and chapter.label or (context.chapter == "" and "Unfiled" or "All cards")
      choices = { "Add card", "New chapter" }
      if chapter then
        table.insert(choices, "Rename chapter")
        table.insert(choices, "Remove chapter")
      end
    else
      title, name = "Collection", collection
      choices = { "Rename collection", "New chapter", "Tags", context.owned and "Daily goal" or "Study settings" }
      if context.can_create ~= false then
        table.insert(choices, "New collection")
      end
      if not context.owned then
        table.insert(choices, "Detach collection")
      end
    end
    pick(title, name, choices)
  end
  if context.action then
    run(context.action)
  else
    menu()
  end
end

return M
