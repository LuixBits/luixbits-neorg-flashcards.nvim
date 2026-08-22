return function(T)
  local overview = require("neorg_flashcards.overview")
  local form = require("neorg_flashcards.form")
  local stats = require("neorg_flashcards.stats")
  local flashcards = require("neorg_flashcards")

  local assert_true = T.assert_true
  local assert_equal = T.assert_equal
  local assert_contains = T.assert_contains
  local current_popup = T.current_popup
  local current_tab_text = T.current_tab_text
  local assert_buffer_maps = T.assert_buffer_maps
  local collection_dir = T.collection_dir

  local invalid_ui_path = collection_dir .. "/invalid-ui.norg"
  vim.fn.writefile({
    "@flashcard japanese",
    "id: fc_ui_duplicate",
    "japanese: 壱",
    "english: one",
    "@end",
    "@flashcard japanese",
    "id: fc_ui_duplicate",
    "japanese: 弐",
    "english: two",
    "@end",
    "@flashcard japanese",
    "id: fc_ui_missing_answer",
    "japanese: 参",
    "@end",
  }, invalid_ui_path)

  vim.cmd("Flashcards")
  local overview_popup, overview_text = current_popup()
  _G.__flashcards_hub_test = { main_win = vim.api.nvim_get_current_win() }
  assert_equal(overview.current_view(), "overview", "bare :Flashcards opens the Overview page")
  assert_equal(#vim.api.nvim_tabpage_list_wins(0), 2, "dashboard opens cards and analytics panes")
  assert_contains(overview_text, "nature", "overview lists the shared tag group")
  assert_contains(overview_text, "hiking", "overview lists the second tag group")
  assert_contains(overview_text, "untagged", "overview groups cards without tags")
  assert_contains(overview_text, "nature · 2 cards · 2 due", "overview counts cards and due per group")
  assert_contains(overview_text, "▸", "overview shows the selected card marker")
  assert_contains(overview_text, "● due", "overview shows the color legend")
  assert_contains(overview_text, "山 — mountain", "card lines show front and reveal")
  assert_buffer_maps(overview_popup, {
    "q",
    "<Esc>",
    "?",
    "H",
    "1",
    "2",
    "3",
    "<Tab>",
    "j",
    "k",
    "<Down>",
    "<Up>",
    "<C-D>",
    "<C-U>",
    "<PageDown>",
    "<PageUp>",
    "<C-W>w",
    "gg",
    "G",
    "<CR>",
    "r",
    "d",
    "A",
    "a",
    "/",
    "f",
    "o",
    "X",
    "x",
    "b",
    "D",
    "p",
    "e",
    "c",
    "R",
  })
  assert_true(#vim.api.nvim_buf_get_extmarks(overview_popup, -1, 0, -1, {}) > 0, "overview paints highlight extmarks")

  vim.cmd("Flashcards add")
  assert_true(form.is_open(), "the hub routes command-line add into the protected composer")
  form.close({ force = true })
  assert_true(overview.is_open(), "closing a hub composer returns to the intact hub")
  assert_true(vim.api.nvim_buf_is_valid(overview_popup), "hub add does not wipe the main scratch buffer")

  local stats_pane_buf
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= vim.api.nvim_get_current_win() then
      _G.__flashcards_hub_test.side_win = win
      stats_pane_buf = vim.api.nvim_win_get_buf(win)
    end
  end
  local analytics_text = table.concat(vim.api.nvim_buf_get_lines(stats_pane_buf, 0, -1, false), "\n")
  assert_contains(analytics_text, "Analytics", "dashboard shows the analytics pane")
  assert_contains(analytics_text, "Due forecast", "analytics pane shows the forecast")
  assert_contains(
    vim.wo[_G.__flashcards_hub_test.main_win].winbar,
    "Flashcards",
    "primary winbar keeps page navigation visible"
  )
  assert_contains(
    vim.wo[_G.__flashcards_hub_test.side_win].winbar,
    "? keys",
    "secondary winbar keeps shortcut help visible"
  )
  assert_contains(
    vim.wo[_G.__flashcards_hub_test.side_win].winbar,
    "j/k navigate",
    "Overview shortcut ribbon truthfully describes focused-pane movement"
  )

  _G.__flashcards_hub_test.main_cursor = vim.api.nvim_win_get_cursor(_G.__flashcards_hub_test.main_win)
  overview.focus_side()
  assert_equal(vim.api.nvim_get_current_win(), _G.__flashcards_hub_test.side_win, "focus_side selects the side pane")
  vim.api.nvim_win_set_cursor(_G.__flashcards_hub_test.side_win, { 1, 0 })
  overview.move(1)
  assert_equal(
    vim.api.nvim_win_get_cursor(_G.__flashcards_hub_test.side_win)[1],
    2,
    "j/k movement scrolls a focused secondary pane"
  )
  assert_equal(
    vim.api.nvim_win_get_cursor(_G.__flashcards_hub_test.main_win)[1],
    _G.__flashcards_hub_test.main_cursor[1],
    "scrolling the secondary pane does not change the primary selection"
  )
  overview.focus_main()
  assert_equal(vim.api.nvim_get_current_win(), _G.__flashcards_hub_test.main_win, "focus_main selects the main pane")

  local overview_cursor = vim.api.nvim_win_get_cursor(0)
  overview.move(1)
  local moved_cursor = vim.api.nvim_win_get_cursor(0)
  assert_true(
    moved_cursor[1] ~= overview_cursor[1] or moved_cursor[2] ~= overview_cursor[2],
    "moving the selection repositions the cursor"
  )

  overview.move(-1) -- back onto the alphabetically first group (chapter-01)
  overview.review_group()
  local _, group_review_text = current_popup()
  assert_contains(group_review_text, "tag:chapter-01 | 1/1", "overview reviews the selected group")
  flashcards.close_review()
  local _, canvas_text = current_popup()
  assert_contains(canvas_text, "▸", "closing the group review returns to the card list")

  vim.cmd("Flashcards cards")
  assert_equal(overview.current_view(), "cards", ":Flashcards cards routes into the Cards browser")
  local cards_popup, cards_text = current_popup()
  assert_contains(cards_text, " Cards", "Cards page renders its primary table")
  assert_contains(cards_text, "shown of", "Cards page reports the filtered collection size")
  assert_contains(current_tab_text(), " Card details", "Cards browser retains its contextual detail pane")
  assert_buffer_maps(cards_popup, { "/", "f", "o", "X", "x", "b", "p", "e" })
  assert_contains(cards_text, "[INVALID]", "Cards page keeps invalid blocks visible for repair")
  assert_contains(cards_text, "3 invalid", "Cards page counts invalid blocks separately from reviewable cards")
  assert_contains(current_tab_text(), "duplicate id", "invalid card details explain duplicate identities")
  assert_contains(cards_text, "source:", "invalid rows include their source location")
  assert_contains(
    current_tab_text(),
    "Press D to delete this exact invalid block",
    "invalid details expose safe deletion"
  )
  assert_contains(vim.wo[_G.__flashcards_hub_test.side_win].winbar, "D delete", "Cards ribbon exposes deletion")

  overview.context_help()
  local _, invalid_help_text = current_popup()
  assert_true(
    not invalid_help_text:find("Review the selected card", 1, true),
    "invalid-card help does not advertise a blocked review action"
  )
  assert_contains(invalid_help_text, "Edit the selected card", "invalid-card help retains its repair action")
  overview.help_close()

  local invalid_disk_before = table.concat(vim.fn.readfile(invalid_ui_path), "\n")
  local invalid_messages = {}
  local invalid_notify_original = vim.notify
  vim.notify = function(message)
    table.insert(invalid_messages, tostring(message))
  end
  overview.review_selected()
  overview.toggle_suspend()
  overview.bury()
  vim.notify = invalid_notify_original
  assert_contains(table.concat(invalid_messages, "\n"), "cannot be reviewed", "invalid rows cannot start review")
  assert_contains(
    table.concat(invalid_messages, "\n"),
    "Repair this invalid block",
    "invalid rows reject state actions"
  )
  assert_equal(
    table.concat(vim.fn.readfile(invalid_ui_path), "\n"),
    invalid_disk_before,
    "blocked invalid-card actions do not rewrite the source"
  )

  _G.__flashcards_hub_test.select_original = vim.ui.select
  vim.ui.select = function(items, opts, callback)
    _G.__flashcards_hub_test.delete_choices = items
    _G.__flashcards_hub_test.delete_prompt = opts.prompt
    _G.__flashcards_hub_test.delete_callback = callback
  end
  assert_true(overview.delete_selected(), "Cards opens deletion confirmation for an invalid block")
  assert_equal(_G.__flashcards_hub_test.delete_choices[1], "Cancel", "destructive confirmation defaults to Cancel")
  assert_equal(
    _G.__flashcards_hub_test.delete_choices[2],
    "Delete card",
    "destructive confirmation requires an exact Delete card choice"
  )
  assert_contains(_G.__flashcards_hub_test.delete_prompt, "壱", "deletion confirmation names the captured card")
  assert_contains(
    _G.__flashcards_hub_test.delete_prompt,
    "invalid-ui.norg:1",
    "deletion confirmation names the exact invalid source block"
  )
  _G.__flashcards_hub_test.delete_callback("Cancel")
  assert_equal(
    table.concat(vim.fn.readfile(invalid_ui_path), "\n"),
    invalid_disk_before,
    "cancelling deletion leaves the source untouched"
  )

  assert_true(overview.delete_selected(), "Cards can request deletion again after cancellation")
  local stale_delete_callback = _G.__flashcards_hub_test.delete_callback
  overview.close()
  vim.cmd("Flashcards cards")
  stale_delete_callback("Delete card")
  assert_equal(
    table.concat(vim.fn.readfile(invalid_ui_path), "\n"),
    invalid_disk_before,
    "a confirmation from a closed hub cannot delete from a newly opened hub"
  )

  assert_true(overview.delete_selected(), "the reopened Cards page can request a fresh deletion")
  overview.move(1)
  _G.__flashcards_hub_test.delete_callback("Delete card")
  vim.ui.select = _G.__flashcards_hub_test.select_original
  _G.__flashcards_hub_test.invalid_after_delete = table.concat(vim.fn.readfile(invalid_ui_path), "\n")
  assert_true(
    not _G.__flashcards_hub_test.invalid_after_delete:find("japanese: 壱", 1, true),
    "confirmation deletes the originally captured invalid block"
  )
  assert_contains(
    _G.__flashcards_hub_test.invalid_after_delete,
    "japanese: 弐",
    "moving selection while confirmation is open does not delete the newly selected block"
  )
  assert_true(not current_tab_text():find("壱", 1, true), "successful deletion refreshes the Cards browser")

  vim.fn.delete(invalid_ui_path)
  overview.refresh()
  local _, repaired_cards_text = current_popup()
  assert_true(not repaired_cards_text:find("[INVALID]", 1, true), "refresh removes repaired or deleted invalid rows")

  local input_original = vim.ui.input
  local search_prompt
  vim.ui.input = function(opts, callback)
    search_prompt = opts.prompt
    callback("mountain")
  end
  overview.search()
  vim.ui.input = input_original
  assert_equal(search_prompt, "Search cards: ", "Cards search uses a concise prompt")
  local _, searched_text = current_popup()
  assert_contains(searched_text, "search: “mountain”", "Cards search displays the active query")
  assert_contains(searched_text, "山", "Cards search matches answer text as well as card fronts")
  overview.clear_browser()

  local select_original = vim.ui.select
  local filter_prompt
  vim.ui.select = function(items, opts, callback)
    filter_prompt = opts.prompt
    local selected
    for _, item in ipairs(items) do
      if item.value == "new" then
        selected = item
        break
      end
    end
    callback(selected)
  end
  overview.choose_filter()
  vim.ui.select = select_original
  assert_equal(filter_prompt, "Card state filter", "Cards filtering names the state dimension")
  local _, filtered_text = current_popup()
  assert_contains(filtered_text, "filter: new", "Cards browser renders the active lifecycle filter")
  overview.clear_browser()

  overview.toggle_suspend()
  local _, suspended_text = current_popup()
  assert_contains(suspended_text, "[SUSPENDED]", "Cards action can suspend the selected card")
  overview.toggle_suspend()
  local _, resumed_text = current_popup()
  assert_true(not resumed_text:find("[SUSPENDED]", 1, true), "Cards action can resume the selected card")

  overview.bury()
  local _, buried_text = current_popup()
  assert_contains(buried_text, "[BURIED]", "Cards action can bury the selected card")
  overview.bury()
  local _, unburied_text = current_popup()
  assert_true(not unburied_text:find("[BURIED]", 1, true), "Cards action can unbury the selected card")

  overview.context_help()
  local _, cards_help_text = current_popup()
  assert_contains(cards_help_text, "Search cards", "context help is generated from Cards actions")
  assert_contains(cards_help_text, "Suspend the selected card", "context help reflects the selected card state")
  assert_contains(cards_help_text, "Delete the selected card after confirmation", "context help exposes safe deletion")
  overview.help_close()

  overview.peek()
  local _, peek_text = current_popup()
  assert_contains(peek_text, "State:", "Cards preview includes scheduling state")
  assert_contains(peek_text, "Source:", "Cards preview includes its source")
  overview.peek_close()

  local expected_stats_entries, expected_stats_errors = stats.read_history()
  assert_equal(#expected_stats_errors, 0, "Stats reads the versioned review history")
  local expected_stats = stats.metrics({}, expected_stats_entries, os.time())
  vim.cmd("Flashcards stats")
  assert_equal(overview.current_view(), "stats", ":Flashcards stats routes into the Stats page")
  assert_equal(#vim.api.nvim_tabpage_list_wins(0), 2, "stats opens the two-pane dashboard")
  local stats_popup, stats_text = current_popup()
  assert_contains(stats_text, expected_stats.reviews .. " reviews total", "stats totals versioned review history")
  assert_contains(stats_text, expected_stats.today .. " today", "stats counts today's effective reviews")
  assert_contains(stats_text, "Retention", "stats shows recall retention windows")
  assert_contains(stats_text, "Answer buttons", "stats shows rating distribution")
  assert_contains(stats_text, "Card states", "stats shows lifecycle and availability counts")
  assert_contains(stats_text, "Mon", "stats heatmap has weekday rows")
  assert_contains(stats_text, "Due forecast", "stats shows the due forecast")
  assert_buffer_maps(stats_popup, {
    "q",
    "?",
    "1",
    "2",
    "3",
    "j",
    "k",
    "<Down>",
    "<Up>",
    "<C-D>",
    "<C-U>",
    "<PageDown>",
    "<PageUp>",
    "gg",
    "G",
    "d",
    "A",
    "R",
  })
  assert_contains(vim.wo[0].winbar, "? keys", "Stats keeps current shortcuts in its winbar")
  assert_contains(vim.wo[0].winbar, "j/k scroll", "Stats winbar makes line scrolling discoverable")

  local stats_help = table.concat(require("neorg_flashcards.ui.actions").help_lines("stats", {}), "\n")
  assert_contains(stats_help, "Ctrl-W W", "Stats help exposes explicit pane focus")
  assert_contains(stats_help, "Focus the other hub pane", "pane focus help explains its action")

  local hidden_source = collection_dir .. "/overview-check.norg"
  local hidden_source_before = table.concat(vim.fn.readfile(hidden_source), "\n")
  local hidden_input_called = false
  local hidden_select_called = false
  local hidden_input_original = vim.ui.input
  local hidden_select_original = vim.ui.select
  vim.ui.input = function()
    hidden_input_called = true
  end
  vim.ui.select = function()
    hidden_select_called = true
  end
  for _, key in ipairs({ "/", "x", "b", "D" }) do
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), "xt", false)
  end
  vim.ui.input = hidden_input_original
  vim.ui.select = hidden_select_original
  assert_true(not hidden_input_called, "Cards-only search does not dispatch from Stats")
  assert_true(not hidden_select_called, "Cards-only deletion does not dispatch from Stats")
  assert_equal(
    table.concat(vim.fn.readfile(hidden_source), "\n"),
    hidden_source_before,
    "hidden card-state actions do not mutate collection data"
  )

  _G.__flashcards_hub_test.laststatus = vim.o.laststatus
  vim.o.laststatus = 3
  vim.wo[0].statusline = "%#lualine_transparent#"
  assert_contains(vim.wo[0].winbar, "j/k scroll", "global statuslines do not replace the shortcut ribbon")
  vim.o.laststatus = _G.__flashcards_hub_test.laststatus

  overview.context_help()
  _G.__flashcards_hub_test.help_buf, _G.__flashcards_hub_test.help_text = current_popup()
  assert_contains(
    _G.__flashcards_hub_test.help_text,
    "Scroll the focused pane down",
    "Stats help explains j/Down scrolling"
  )
  assert_contains(
    _G.__flashcards_hub_test.help_text,
    "Scroll the focused pane down half a page",
    "Stats help explains half pages"
  )
  assert_contains(_G.__flashcards_hub_test.help_text, "top of the focused pane", "Stats help explains gg")
  assert_contains(_G.__flashcards_hub_test.help_text, "bottom of the focused pane", "Stats help explains G")
  overview.help_close()

  _G.__flashcards_hub_test.stats_line_count = vim.api.nvim_buf_line_count(stats_popup)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  overview.move(1)
  assert_equal(vim.api.nvim_win_get_cursor(0)[1], 2, "Stats j/k movement advances one line")
  _G.__flashcards_hub_test.view_before = vim.fn.winsaveview()
  overview.scroll_page(1)
  _G.__flashcards_hub_test.view_after = vim.fn.winsaveview()
  assert_true(
    _G.__flashcards_hub_test.view_after.lnum > _G.__flashcards_hub_test.view_before.lnum,
    "Stats half-page navigation advances the cursor"
  )
  assert_true(
    _G.__flashcards_hub_test.view_after.topline > _G.__flashcards_hub_test.view_before.topline,
    "Stats half-page navigation scrolls the viewport"
  )
  overview.scroll_edge("bottom")
  assert_equal(
    vim.api.nvim_win_get_cursor(0)[1],
    _G.__flashcards_hub_test.stats_line_count,
    "Stats G navigation reaches the bottom"
  )
  overview.scroll_edge("top")
  assert_equal(vim.api.nvim_win_get_cursor(0)[1], 1, "Stats gg navigation reaches the top")
  overview.close()
  _G.__flashcards_hub_test = nil
  assert_true(not overview.is_open(), "closing the stats view closes the dashboard tab")

  vim.cmd("Flashcards")
  vim.cmd("Flashcards open")
  assert_true(not overview.is_open(), "opening the collection closes the hub cleanly")
  assert_equal(
    vim.fs.normalize(vim.api.nvim_buf_get_name(0)),
    vim.fs.normalize(T.config.default_file),
    "opening the collection lands in the configured card source"
  )

  local background_target = T.collection_dir .. "/background-add.norg"
  vim.fn.writefile({ "* Background add", "" }, background_target)
  vim.cmd.edit(vim.fn.fnameescape(background_target))
  vim.cmd("Flashcards")
  vim.cmd("tabprevious")
  vim.cmd("Flashcards add")
  assert_true(form.is_open(), "add still opens from a normal file while the hub exists in another tab")
  assert_contains(
    T.decoration_text(vim.api.nvim_get_current_buf()),
    "background-add.norg",
    "a background hub does not redirect add away from the current collection file"
  )
  form.close({ force = true })
  overview.close()
  vim.fn.delete(background_target)

  for _, pane_index in ipairs({ 1, 2 }) do
    vim.cmd("Flashcards")
    local hub_wins = vim.api.nvim_tabpage_list_wins(0)
    local hub_bufs = {}
    for _, win in ipairs(hub_wins) do
      table.insert(hub_bufs, vim.api.nvim_win_get_buf(win))
    end
    vim.api.nvim_win_close(hub_wins[pane_index], true)
    assert_true(
      vim.wait(200, function()
        if overview.is_open() then
          return false
        end
        for _, bufnr in ipairs(hub_bufs) do
          if vim.api.nvim_buf_is_valid(bufnr) then
            return false
          end
        end
        return true
      end),
      "native close of hub pane " .. pane_index .. " closes the whole hub"
    )
    for _, bufnr in ipairs(hub_bufs) do
      assert_true(not vim.api.nvim_buf_is_valid(bufnr), "native hub close wipes every scratch buffer")
    end
  end
end
