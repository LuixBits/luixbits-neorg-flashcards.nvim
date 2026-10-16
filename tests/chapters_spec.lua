return function(T)
  local metadata = require("neorg_flashcards.metadata")
  local chapters = require("neorg_flashcards.chapters")
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  local config = { path = root }
  local equal, truth = T.assert_equal, T.assert_true
  local cards = {
    { values = { id = "fc_chapter_one", tags = "travel lesson1" } },
    { values = { id = "fc_chapter_two", tags = "household" } },
  }
  -- Old workspaces are readable without rewriting their cards or sidecars.
  local legacy = '{"version":1,"categories":{},"goals":{},"goal":20}'
  vim.fn.writefile({ legacy }, metadata.path(config))
  local data, err = metadata.load(config)
  equal(err, nil)
  equal(vim.tbl_count(data.chapters), 0, "old metadata gains an empty chapter view")
  equal(vim.fn.readfile(metadata.path(config))[1], legacy, "loading is read-only")
  equal(#chapters.groups(cards, data, config)[1].cards, 2, "existing cards stay accessible in Unfiled")

  local ok, message, lesson = chapters.create(config, "Lesson 1", { cards[1] })
  truth(ok, message)
  truth(chapters.create(config, "Verbs"))
  data = metadata.load(config)
  equal(chapters.id(data, cards[1]), lesson, "chapter membership uses stable card IDs")
  equal(chapters.id(data, cards[2]), "", "unassigned cards stay unfiled")
  equal(cards[1].values.tags, "travel lesson1", "chapter creation never consumes tags")
  local groups = chapters.groups(cards, data, config)
  equal(#groups, 3, "empty chapters are visible alongside Unfiled")
  truth(chapters.rename(config, lesson, "基本"), "Unicode chapter names are supported")
  data = metadata.load(config)
  equal(chapters.id(data, cards[1]), lesson, "renaming preserves membership")
  equal(data.chapters[lesson].label, "基本")
  truth(chapters.move(config, { cards[2] }, lesson))
  truth(chapters.move(config, { cards[1] }, ""))
  data = metadata.load(config)
  equal(chapters.id(data, cards[1]), "", "moving to Unfiled clears the assignment")
  equal(chapters.id(data, cards[2]), lesson, "moving affects only selected cards")
  truth(not chapters.move(config, cards, "missing"), "stale chapter destinations are rejected")
  truth(not chapters.create(config, "verbs"), "duplicate chapter names are rejected")
  truth(not chapters.rename(config, lesson, "\n"), "empty and multiline names cannot be saved")
  truth(chapters.delete(config, lesson))
  equal(chapters.id(metadata.load(config), cards[2]), "", "deleting a chapter preserves its cards in Unfiled")

  vim.fn.writefile(
    { '{"version":1,"categories":{},"goals":{},"goal":20,"chapter_cards":{"x":"missing"}}' },
    metadata.path(config)
  )
  local before = vim.fn.readfile(metadata.path(config))[1]
  truth(not chapters.create(config, "Lesson 2"), "corrupt membership is never silently overwritten")
  equal(vim.fn.readfile(metadata.path(config))[1], before)
  vim.fn.delete(root, "rf")
end
