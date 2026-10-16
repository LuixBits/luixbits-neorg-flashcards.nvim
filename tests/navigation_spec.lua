return function(T)
  local flashcards = require("neorg_flashcards")
  local overview = require("neorg_flashcards.overview")
  local review = require("neorg_flashcards.review")
  local form = require("neorg_flashcards.form")
  local equal, truth, contains = T.assert_equal, T.assert_true, T.assert_contains
  local columns, lines = vim.o.columns, vim.o.lines
  local root = vim.fn.tempname()
  overview.close()
  truth(flashcards.setup({
    default_collection = "demo",
    deck_registry = false,
    ui = { motion = false },
    collections = {
      demo = {
        path = root,
        default_card_type = "japanese",
        schemas = require("neorg_flashcards.presets").only("japanese"),
      },
    },
  }))
  local source = root .. "/cards.norg"
  local fixture = {
    "@flashcard japanese",
    "id: fc_navigation_water",
    "japanese: 水",
    "english: water",
    "@end",
    "@flashcard japanese",
    "id: fc_navigation_tea",
    "japanese: 茶",
    "english: tea",
    "@end",
  }
  vim.fn.writefile(fixture, source)
  local function key(lhs)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(lhs, true, false, true), "xt", false)
  end
  local function pane_text(win)
    return table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), "\n")
  end

  for _, size in ipairs({ { 140, 40 }, { 80, 24 } }) do
    vim.o.columns, vim.o.lines = size[1], size[2]
    for _, page in ipairs({ "overview", "stats" }) do
      truth(flashcards.overview({ view = page, browser_level = "collections", reset_browser = true }))
      local main = vim.api.nvim_get_current_win()
      overview.focus_side()
      local side = vim.api.nvim_get_current_win()
      overview.focus_main()
      local main_text, side_text = pane_text(main), pane_text(side)
      local stacked = size[1] < 105
      local forward, backward = stacked and "j" or "l", stacked and "k" or "h"
      local main_position, side_position = vim.api.nvim_win_get_position(main), vim.api.nvim_win_get_position(side)
      truth(
        stacked and side_position[1] > main_position[1] or not stacked and side_position[2] > main_position[2],
        page .. " details occupy the expected direction"
      )
      for _, prefix in ipairs({ "<C-", "<C-w>" }) do
        local function direction(letter)
          key(prefix .. letter .. (prefix == "<C-" and ">" or ""))
        end
        direction(backward)
        equal(vim.api.nvim_get_current_win(), main, "moving past a pane edge stays put")
        direction(forward)
        equal(vim.api.nvim_get_current_win(), side, "directional navigation reaches details")
        direction(forward)
        equal(vim.api.nvim_get_current_win(), side, "moving beyond details does not toggle focus")
        for _, perpendicular in ipairs(stacked and { "h", "l" } or { "j", "k" }) do
          direction(perpendicular)
          equal(vim.api.nvim_get_current_win(), side, "an empty direction does not switch panes")
        end
        direction(backward)
        equal(vim.api.nvim_get_current_win(), main, "opposite direction returns to the main pane")
      end
      key("<C-w>w")
      equal(vim.api.nvim_get_current_win(), side, "Ctrl-W w still cycles panes")
      key("<C-w>w")
      equal(vim.api.nvim_get_current_win(), main, "Ctrl-W w returns to the main pane")
      equal(pane_text(main), main_text, "pane navigation preserves the calendar and library selection")
      equal(pane_text(side), side_text, "pane navigation preserves the selected item's details")
      equal(overview.current_view(), page, "Ctrl-J does not activate the Enter action")
      truth(not review.is_active(), "pane navigation cannot start a review")
      overview.close()
    end
  end

  vim.o.columns, vim.o.lines = 140, 40
  truth(flashcards.overview({ view = "overview", browser_level = "collections", reset_browser = true }))
  key("l")
  contains(T.current_tab_text(), "CHAPTER", "l opens a collection")
  key("<Right>")
  contains(T.current_tab_text(), "2 shown", "Right opens its All cards chapter")
  key("h")
  contains(T.current_tab_text(), "CHAPTER", "h returns to chapters")
  key("<Left>")
  contains(T.current_tab_text(), "COLLECTION", "Left returns to collections")
  key("<Right>")
  key("l")
  key("<Right>")
  truth(review.is_active(), "Right opens the selected card for review")
  key("h")
  truth(not review.is_active(), "h closes review")
  equal(overview.current_view(), "desk", "review returns to the Desk")

  truth(flashcards.review_due())
  equal(flashcards.get_review_state().index, 1)
  for _, pair in ipairs({ { "j", "k" }, { "<Down>", "<Up>" } }) do
    key(pair[1])
    equal(flashcards.get_review_state().index, 2, "down browses the next pending card")
    key(pair[2])
    equal(flashcards.get_review_state().index, 1, "up browses the previous pending card")
  end
  key("H")
  equal(flashcards.get_review_state().hints, 1, "uppercase H gives a hint")
  truth(not flashcards.get_review_state().showing_answer, "a hint leaves the answer hidden")
  for _, reveal in ipairs({ "l", "<Right>", "<CR>", "<Space>" }) do
    key(reveal)
    truth(flashcards.get_review_state().showing_answer, "explicit reveal works with " .. reveal)
    key(reveal)
    equal(flashcards.get_review_state().reviewed, 0, "holding a reveal key cannot rate a card")
    key("<Down>")
    truth(not flashcards.get_review_state().showing_answer, "browsing shows the next question")
  end
  key("<Left>")
  truth(not review.is_active(), "Left closes review without rating")
  equal(table.concat(vim.fn.readfile(source), "\n"), table.concat(fixture, "\n"), "navigation preserves source cards")

  truth(form.open(flashcards.active_collection(), "japanese"))
  vim.cmd("stopinsert")
  for _, pair in ipairs({ { "j", "k" }, { "<Down>", "<Up>" } }) do
    key(pair[1])
    equal(vim.api.nvim_win_get_cursor(0)[1], 2, "down selects the next form field")
    key(pair[2])
    equal(vim.api.nvim_win_get_cursor(0)[1], 1, "up selects the previous form field")
  end
  -- Insert Ctrl-H must remain backspace rather than moving to the workspace.
  key("iwater<Esc>")
  key("a<C-h><Esc>")
  truth(form.is_open(), "Insert Ctrl-H stays in the form")
  equal(vim.api.nvim_get_current_line(), "wate", "Insert Ctrl-H still deletes inside the field")
  form.close({ force = true })
  overview.close()
  vim.o.columns, vim.o.lines = columns, lines
  vim.fn.delete(root, "rf")
end
