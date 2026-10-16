return function(T)
  local dialog = require("neorg_flashcards.dialog")
  local flashcards = require("neorg_flashcards")
  local overview = require("neorg_flashcards.overview")
  local metadata = require("neorg_flashcards.metadata")
  local chapters = require("neorg_flashcards.chapters")
  local parser = require("neorg_flashcards.parser")
  local form = require("neorg_flashcards.form")
  local root = vim.fn.tempname()
  local equal, truth, contains = T.assert_equal, T.assert_true, T.assert_contains
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
    { "@flashcard japanese", "id: fc_library", "japanese: 水", "english: water", "tags: household", "@end" },
    source
  )
  local original = table.concat(vim.fn.readfile(source), "\n")
  local function key(lhs)
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
      if map.lhs == lhs then
        map.callback()
        return
      end
    end
    error("missing key " .. lhs)
  end
  local input, select = dialog.input, dialog.select
  local answer, choice = "Lesson 1", nil
  dialog.input = function(_, cb)
    cb(answer)
  end
  dialog.select = function(items, _, cb)
    if type(choice) == "function" then
      cb(choice(items))
    else
      cb(choice)
    end
  end
  truth(flashcards.overview({ view = "overview", browser_level = "collections", reset_browser = true }))
  contains(T.current_tab_text(), "COLLECTION", "Overview starts at collections")
  key("<CR>")
  contains(T.current_tab_text(), "CHAPTER", "Enter opens the collection's chapters")
  key("n")
  local data = metadata.load(config)
  truth(data.chapters["lesson-1"], "n creates a chapter")
  key("j") -- Lesson 1, after All cards.
  answer = "Lesson One"
  key("e")
  equal(metadata.load(config).chapters["lesson-1"].label, answer, "e renames the selected chapter")
  key("a")
  truth(form.is_open(), "a opens the composer inside a chapter")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "猫", "ねこ", "cat", "", "travel" })
  truth(form.save(), "a card can be saved directly into a chapter")
  local saved_source = table.concat(vim.fn.readfile(source), "\n")
  equal(saved_source:sub(1, #original), original, "adding preserves the existing card and its tags")
  local cards = parser.collect_flashcards(config)
  equal(#cards, 2)
  local added = cards[1].values.id == "fc_library" and cards[2] or cards[1]
  equal(chapters.id(metadata.load(config), added), "lesson-1", "the composer assigns the new stable ID")
  equal(added.values.tags, "travel", "chapter membership is separate from composer tags")
  overview.focus_main()
  key("<CR>")
  contains(T.current_tab_text(), "1 shown", "opening a chapter limits its card list")
  choice = function(items)
    for _, item in ipairs(items) do
      if item.name == "" then
        return item
      end
    end
  end
  key("M")
  equal(chapters.id(metadata.load(config), added), "", "M moves a card to Unfiled")
  contains(T.current_tab_text(), "No cards match", "the old chapter no longer shows the moved card")
  key("h")
  key("j") -- Lesson One.
  choice = "Cancel"
  key("D")
  truth(metadata.load(config).chapters["lesson-1"], "cancel preserves the chapter")
  choice = "Remove chapter"
  key("D")
  truth(not metadata.load(config).chapters["lesson-1"], "D removes the chapter after confirmation")
  equal(#parser.collect_flashcards(config), 2, "removing a chapter preserves every card")
  equal(table.concat(vim.fn.readfile(source), "\n"), saved_source, "organization leaves existing source text unchanged")
  key("h")
  contains(T.current_tab_text(), "COLLECTION", "h returns to collections")
  local stale
  dialog.input = function(_, cb)
    stale = cb
  end
  key("e")
  overview.close()
  stale("Expired rename")
  equal(metadata.load(config).label, nil, "a prompt cannot mutate a closed collection")
  dialog.input, dialog.select = input, select
  vim.fn.delete(root, "rf")
end
