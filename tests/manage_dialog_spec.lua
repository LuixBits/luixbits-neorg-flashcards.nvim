return function(T)
  local flashcards = require("neorg_flashcards")
  local overview = require("neorg_flashcards.overview")
  local metadata = require("neorg_flashcards.metadata")
  local chapters = require("neorg_flashcards.chapters")
  local parser = require("neorg_flashcards.parser")
  local form = require("neorg_flashcards.form")
  local truth, equal, contains = T.assert_true, T.assert_equal, T.assert_contains
  local root = vim.fn.tempname()
  overview.close()
  truth(flashcards.setup({
    default_collection = "japanese",
    deck_registry = false,
    collections = {
      japanese = {
        path = root,
        label = "Japanese",
        default_card_type = "japanese",
        schemas = require("neorg_flashcards.presets").only("japanese"),
      },
    },
  }))
  local config = flashcards.active_collection()
  local source = root .. "/cards.norg"
  vim.fn.writefile(
    { "@flashcard japanese", "id: fc_dialog", "japanese: 水", "english: water", "tags: household", "@end" },
    source
  )
  truth(chapters.create(config, "Lesson 1", parser.collect_flashcards(config)))
  local function keys(value)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(value, true, false, true), "xt", false)
  end
  local function content()
    return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  end
  local function choose(label)
    equal(vim.bo.filetype, "neorg_flashcards_dialog", "a management action stays inside workspace dialogs")
    keys("gg")
    for _ = 1, 25 do
      local line = vim.api.nvim_get_current_line():gsub("^%s*>%s*", "")
      if line == label then
        keys("<CR>")
        return
      end
      keys("j")
    end
    error("Missing menu item: " .. label .. "\n" .. content())
  end
  local function enter(value)
    equal(vim.bo.filetype, "neorg_flashcards_dialog")
    vim.cmd.stopinsert()
    keys("0C" .. value .. "<CR>")
  end
  truth(flashcards.overview({ view = "overview", browser_level = "collections", reset_browser = true }))
  keys("m")
  contains(content(), "Rename collection")
  truth(not content():find("Edit card", 1, true), "collection menu excludes card operations")
  truth(not content():find("Detach collection", 1, true), "configured collections hide unavailable detachment")
  truth(not content():find("New collection", 1, true), "a disabled registry hides creation")
  choose("Daily goal")
  enter("-1")
  contains(T.decoration_text(0), "Use a whole number", "invalid input stays visible with its explanation")
  enter("15")
  equal(metadata.load(config).goal, 15, "a corrected goal persists")

  keys("m")
  choose("Tags")
  choose("household (1 card)")
  choose("Rename or merge tag")
  enter("travel")
  contains(content(), "Changes tags on 1 card.")
  choose("Cancel")
  equal(parser.collect_flashcards(config)[1].values.tags, "household", "cancel preserves the tag")
  keys("m")
  choose("Tags")
  choose("household (1 card)")
  choose("Rename or merge tag")
  enter("travel")
  choose("Change tag")
  equal(parser.collect_flashcards(config)[1].values.tags, "travel", "confirmed rename preserves complete tag tokens")
  truth(vim.fn.filereadable(source .. ".flashcards-tags-backup") == 1, "tag changes retain their backup")

  keys("<CR>j")
  keys("m")
  contains(content(), "Rename chapter")
  truth(not content():find("Daily goal", 1, true), "chapter menu excludes collection settings")
  choose("Rename chapter")
  enter("Lesson One")
  equal(metadata.load(config).chapters["lesson-1"].label, "Lesson One")
  keys("<CR>m")
  contains(content(), "水", "card actions identify the card")
  choose("Edit card")
  truth(form.is_open(), "card menu opens the existing composer")
  vim.api.nvim_buf_set_lines(0, 0, 1, false, { "未保存" })
  form.close()
  equal(vim.bo.filetype, "neorg_flashcards_dialog", "dirty drafts use the same confirmation")
  overview.focus_side()
  local other_pane = vim.api.nvim_get_current_win()
  vim.wait(30, function()
    return false
  end)
  equal(vim.api.nvim_get_current_win(), other_pane, "cancelling on focus loss does not pull focus back")
  truth(form.is_open(), "leaving the discard prompt keeps the draft")
  form.close({ force = true })
  overview.focus_main()
  keys("m")
  choose("Move card to chapter")
  choose("Unfiled")
  equal(chapters.id(metadata.load(config), parser.collect_flashcards(config)[1]), "")
  keys("hjm")
  choose("Remove chapter")
  contains(content(), "0 cards will move to Unfiled.")
  choose("Remove chapter")
  truth(not metadata.load(config).chapters["lesson-1"])
  equal(#parser.collect_flashcards(config), 1, "removing a chapter keeps its card")

  keys("<CR>m") -- All cards after the chapter is removed.
  choose("Delete card")
  contains(content(), "cards.norg:1", "confirmation retains the exact source")
  contains(content(), "Review history is kept.")
  keys("<CR>")
  equal(#parser.collect_flashcards(config), 1, "Enter defaults to Cancel")
  keys("D")
  choose("Delete card")
  equal(#parser.collect_flashcards(config), 0)
  truth(vim.fn.filereadable(source .. ".flashcards-backup") == 1, "deletion still creates the recovery copy")

  vim.fn.writefile({ "@flashcard japanese", "japanese: 未完成" }, source)
  overview.refresh()
  keys("m")
  contains(content(), "Repair source", "invalid cards offer repair in their menu")
  truth(not content():find("Move card", 1, true), "invalid IDs cannot be moved through the menu")
  truth(not content():find("Delete card", 1, true), "unclosed blocks do not offer deletion")
  keys("q")

  overview.close()
  flashcards.overview({ view = "overview", browser_level = "collections", reset_browser = true })
  keys("e")
  vim.cmd.stopinsert()
  local stale = vim.api.nvim_get_current_win()
  overview.close()
  vim.wait(30, function()
    return false
  end)
  truth(not vim.api.nvim_win_is_valid(stale), "closing the hub removes its pending rename")
  equal(metadata.load(config).label, nil)
  vim.fn.delete(root, "rf")

  -- Exercise the real chained input flow and settings on a UI-created collection.
  local registry_root = vim.fn.tempname()
  truth(flashcards.setup({
    default_collection = "japanese",
    deck_registry = registry_root .. "/decks.json",
    collections = {
      japanese = {
        path = registry_root .. "/japanese",
        label = "Japanese",
        default_card_type = "japanese",
        schemas = require("neorg_flashcards.presets").only("japanese"),
      },
    },
  }))
  flashcards.overview({ view = "overview", browser_level = "collections", reset_browser = true })
  keys("m")
  choose("New collection")
  enter("science")
  enter("Science")
  enter(registry_root .. "/science")
  choose("Question and answer")
  equal(flashcards.active_collection().id, "science")
  keys("m")
  choose("Study settings")
  contains(content(), "Enable card type")
  contains(content(), "Default card type")
  keys("h")
  choose("Detach collection")
  choose("Cancel")
  equal(flashcards.active_collection().id, "science", "cancel keeps the UI-created collection")
  local kept = registry_root .. "/science/kept.norg"
  vim.fn.writefile({ "* Keep this note" }, kept)
  keys("m")
  choose("Detach collection")
  choose("Detach collection")
  equal(vim.fn.readfile(kept)[1], "* Keep this note", "detachment keeps source files")
  equal(flashcards.active_collection().id, "japanese")
  overview.close()
  vim.fn.delete(registry_root, "rf")
end
