return function(T)
  local flashcards = require("neorg_flashcards")
  local overview = require("neorg_flashcards.overview")
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  vim.fn.writefile({
    "@flashcard japanese",
    "id: fc_display_options",
    "japanese: 猫",
    "english: cat",
    "tags: lesson-1",
    "@end",
  }, root .. "/cards.norg")
  overview.close()
  local note_win = vim.api.nvim_get_current_win()
  local saved = { list = vim.wo.list, listchars = vim.wo.listchars, conceallevel = vim.wo.conceallevel }
  vim.wo.list, vim.wo.listchars, vim.wo.conceallevel = true, "trail:°,tab:→ ", 2
  flashcards.setup({
    deck_registry = false,
    default_collection = "test",
    ui = { motion = false },
    collections = {
      test = {
        path = root,
        default_card_type = "japanese",
        schemas = require("neorg_flashcards.presets").only("japanese"),
      },
    },
  })
  local function clean_windows()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      T.assert_equal(vim.wo[win].list, false, "app windows suppress visible whitespace")
      T.assert_equal(vim.wo[win].conceallevel, 0, "app borders and key labels remain literal")
      T.assert_equal(
        vim.bo[vim.api.nvim_win_get_buf(win)].filetype,
        "neorg_flashcards",
        "app buffers do not trigger Neorg source hooks"
      )
    end
  end
  for _, page in ipairs({ "desk", "stats", "overview", "desk" }) do
    T.assert_true(flashcards[page]())
    clean_windows()
  end
  T.assert_true(flashcards.review_due())
  clean_windows()
  flashcards.close_review()
  overview.close()
  T.assert_equal(vim.api.nvim_get_current_win(), note_win, "closing the workspace restores the note window")
  T.assert_equal(vim.wo.list, true, "normal note whitespace preferences are preserved")
  T.assert_equal(vim.wo.conceallevel, 2, "normal note concealment is preserved")
  for key, value in pairs(saved) do
    vim.wo[key] = value
  end
  T.setup(T.config)
  vim.fn.delete(root, "rf")
end
