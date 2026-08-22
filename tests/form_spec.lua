return function(T)
  local form = require("neorg_flashcards.form")
  local actions = require("neorg_flashcards.ui.actions")
  local flashcards = require("neorg_flashcards")

  local assert_true = T.assert_true
  local assert_equal = T.assert_equal
  local assert_contains = T.assert_contains
  local current_popup = T.current_popup
  local assert_buffer_maps = T.assert_buffer_maps
  local window_footer = T.window_footer
  local decoration_text = T.decoration_text
  local config = T.config

  do
    local outside_path = vim.fn.tempname() .. ".norg"
    vim.fn.writefile({ "* Outside collection", "" }, outside_path)
    vim.cmd.edit(vim.fn.fnameescape(outside_path))
    local outside_messages = {}
    local outside_notify_original = vim.notify
    vim.notify = function(message)
      table.insert(outside_messages, tostring(message))
    end
    flashcards.add_kind("")
    vim.notify = outside_notify_original
    assert_true(not form.is_open(), "add refuses a target outside the configured collection")
    assert_contains(
      table.concat(outside_messages, "\n"),
      "only be added inside the configured collection",
      "outside-root add explains the collection boundary"
    )
    assert_equal(
      table.concat(vim.fn.readfile(outside_path), "\n"),
      "* Outside collection\n",
      "outside-root add leaves the file untouched"
    )
    vim.cmd("silent! bwipeout!")

    local missing_chapter_path = config.flashcards_dir .. "/clean-new-chapter.norg"
    assert_equal(vim.fn.filereadable(missing_chapter_path), 0, "new-chapter fixture starts without a disk file")
    vim.cmd.edit(vim.fn.fnameescape(missing_chapter_path))
    local missing_chapter_buffer = vim.api.nvim_get_current_buf()
    assert_true(not vim.bo[missing_chapter_buffer].modified, "named new-chapter buffer starts clean")

    flashcards.add_kind("")
    local missing_chapter_form = vim.api.nvim_get_current_buf()
    assert_true(form.is_open(), "add opens the composer for a clean named new chapter")
    vim.api.nvim_buf_set_lines(missing_chapter_form, 0, -1, false, {
      "新章",
      "しんしょう",
      "new chapter",
      "created from a named empty buffer",
      "fixture",
    })
    assert_true(form.save(), "a card can be saved into a clean named new chapter")
    assert_true(not form.is_open(), "successful new-chapter save closes the composer")
    assert_equal(
      vim.api.nvim_get_current_buf(),
      missing_chapter_buffer,
      "new-chapter save returns to its named source buffer"
    )
    assert_equal(vim.fn.filereadable(missing_chapter_path), 1, "new-chapter save creates the named source file")
    assert_true(not vim.bo[missing_chapter_buffer].modified, "persisted new-chapter source is clean")
    local missing_chapter_text = table.concat(vim.fn.readfile(missing_chapter_path), "\n")
    assert_contains(missing_chapter_text, "@flashcard japanese", "new chapter stores a flashcard block")
    assert_contains(missing_chapter_text, "japanese: 新章", "new chapter stores the front field")
    assert_contains(missing_chapter_text, "english: new chapter", "new chapter stores the answer field")
    vim.cmd("silent! bwipeout!")
    assert_equal(vim.fn.delete(missing_chapter_path), 0, "new-chapter fixture is removed after verification")

    local prompted_path = config.flashcards_dir .. "/prompted-form.norg"
    vim.cmd.edit(vim.fn.fnameescape(prompted_path))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      "* Prompt Test",
      "",
    })
    vim.cmd.write()
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    local form_target = vim.api.nvim_get_current_buf()
    flashcards.add_kind("")
    local form_buf = vim.api.nvim_get_current_buf()
    assert_true(form_buf ~= form_target, "add opens the form buffer")
    assert_equal(vim.bo[form_buf].buftype, "nofile", "form is a scratch buffer")
    assert_equal(vim.bo[form_buf].filetype, "neorg_flashcards_form", "composer has a dedicated filetype")
    assert_equal(vim.api.nvim_win_get_cursor(0)[1], 1, "form starts on the first field")
    assert_equal(vim.api.nvim_win_get_cursor(0)[2], 0, "virtual labels do not offset the value cursor")
    assert_buffer_maps(form_buf, { "q", "?", "<CR>", "i", "j", "k", "<C-S>", "<C-N>" })
    assert_contains(window_footer(), "Ctrl-S save", "form promotes save and return")
    assert_contains(window_footer(), "Ctrl-N new", "form exposes repeated entry without another global key")

    local initial_form_lines = vim.api.nvim_buf_get_lines(form_buf, 0, -1, false)
    assert_equal(#initial_form_lines, 5, "composer keeps exactly one raw line per field")
    for index, line in ipairs(initial_form_lines) do
      assert_equal(line, "", "composer field " .. index .. " starts with value-only text")
    end

    local inline_labels = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(form_buf, -1, 0, -1, { details = true })) do
      local details = mark[4] or {}
      if details.virt_text_pos == "inline" then
        table.insert(inline_labels, mark)
      end
    end
    table.sort(inline_labels, function(left, right)
      return left[2] < right[2]
    end)
    assert_equal(#inline_labels, 5, "every composer field has one virtual label")
    for index, mark in ipairs(inline_labels) do
      assert_equal(mark[2], index - 1, "virtual label follows its field row")
      assert_equal(mark[3], 0, "virtual label is anchored at value column zero")
      assert_equal(mark[4].right_gravity, false, "typing cannot move the virtual label")
    end

    local initial_decorations = decoration_text(form_buf)
    assert_contains(initial_decorations, "Target", "composer identifies its immutable destination")
    assert_contains(initial_decorations, vim.fn.fnamemodify(prompted_path, ":t"), "composer shows the destination file")
    assert_contains(initial_decorations, "Japanese", "composer renders field labels outside the buffer")
    assert_contains(initial_decorations, "e.g. 猫", "composer renders schema placeholders")
    assert_contains(initial_decorations, "Word or expression", "composer renders help for the active field")

    local form_action_ids = {}
    for _, binding in ipairs(actions.available_bindings("form", { save_new = true })) do
      form_action_ids[binding.mode .. ":" .. binding.key] = binding.action
    end
    assert_equal(form_action_ids["n:<C-s>"], "save_close", "normal Ctrl-S saves and closes")
    assert_equal(form_action_ids["i:<C-s>"], "save_close", "insert Ctrl-S saves and closes")
    assert_equal(form_action_ids["n:<C-n>"], "save_new", "normal Ctrl-N saves and starts another")
    assert_equal(form_action_ids["i:<C-n>"], "save_new", "insert Ctrl-N saves and starts another")
    assert_equal(form_action_ids["i:<CR>"], "next_or_save", "insert Enter advances or saves")
    assert_equal(form_action_ids["n:<CR>"], "edit_field", "normal Enter edits the selected value")

    form.context_help()
    do
      local _, form_help_text = current_popup()
      assert_contains(form_help_text, "Card form keys", "form has contextual key help")
      assert_contains(form_help_text, "Normal or Insert mode", "form help distinguishes editing modes")
      assert_contains(form_help_text, "Save the card and return", "form help explains save and close")
      assert_contains(form_help_text, "Save and start another", "form help explains repeated entry")
    end
    form.help_close()
    assert_equal(vim.api.nvim_get_current_buf(), form_buf, "closing form help returns to the form")

    local form_imaps = {}
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(form_buf, "i")) do
      form_imaps[map.lhs:lower()] = true -- lhs casing is canonicalized (<C-S>)
    end
    for _, lhs in ipairs({
      "<c-s>",
      "<c-n>",
      "<cr>",
      "<tab>",
      "<s-tab>",
      "<esc>",
      "<bs>",
      "<c-h>",
      "<del>",
      "<c-w>",
    }) do
      assert_true(form_imaps[lhs], "form maps " .. lhs .. " in insert mode")
    end
    form.goto_field(1)
    assert_equal(form.masked_backspace(), "", "Backspace stops at the start of a masked value")
    assert_equal(form.masked_word_backspace(), "", "word deletion stops at the start of a masked value")
    assert_equal(form.masked_delete(), "", "Delete stops at the end of an empty masked value")
    assert_equal(vim.api.nvim_buf_line_count(form_buf), 5, "masked deletion cannot join field rows")

    vim.cmd("stopinsert")
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("i<BS><Esc>", true, false, true), "xt", false)
    assert_equal(vim.api.nvim_buf_line_count(form_buf), 5, "actual Backspace input cannot join masked field rows")
    assert_contains(decoration_text(form_buf), "Japanese", "actual Backspace input cannot remove a virtual label")

    vim.api.nvim_buf_set_lines(form_buf, 0, 1, false, { "ab" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    assert_equal(form.masked_delete(), "<Del>", "Delete remains available inside a masked value")
    vim.api.nvim_win_set_cursor(0, { 1, 1 })
    assert_equal(form.masked_backspace(), "<BS>", "Backspace remains available inside a masked value")
    vim.api.nvim_buf_set_lines(form_buf, 0, 1, false, { "" })
    form.next_field()
    assert_equal(vim.api.nvim_win_get_cursor(0)[1], 2, "Enter hops to the next field")
    form.cycle_field(-1)
    assert_equal(vim.api.nvim_win_get_cursor(0)[1], 1, "Shift-Tab hops back")

    assert_true(not form.save(), "required-field validation prevents an empty save")
    assert_true(form.is_open(), "validation keeps the composer open")
    assert_equal(vim.api.nvim_win_get_cursor(0)[1], 1, "validation focuses the first invalid field")
    local validation_text = decoration_text(form_buf)
    assert_contains(validation_text, "Japanese is required", "validation is shown beside the front field")
    assert_contains(validation_text, "English is required", "all missing required fields are marked together")

    vim.api.nvim_buf_set_lines(form_buf, 0, 1, false, { "机" })
    vim.wait(30, function()
      return false
    end, 5)
    assert_equal(vim.api.nvim_buf_get_lines(form_buf, 0, 1, false)[1], "机", "raw field contains only its value")

    vim.api.nvim_buf_set_lines(form_buf, 1, 1, false, { "unexpected extra row" })
    assert_true(
      vim.wait(200, function()
        return vim.api.nvim_buf_line_count(form_buf) == 5
      end),
      "composer repairs structural line insertion"
    )
    assert_equal(
      vim.api.nvim_buf_get_lines(form_buf, 0, 1, false)[1],
      "机",
      "structural repair restores the last valid draft"
    )
    assert_contains(decoration_text(form_buf), "single-line", "structural repair explains the field constraint")

    vim.api.nvim_buf_set_lines(form_buf, 0, -1, false, {
      "机",
      "つくえ",
      "desk",
      "noun",
      "jlpt furniture",
    })
    assert_true(form.save(), "save and return accepts a valid card")
    assert_true(not form.is_open(), "normal save closes the composer")

    local prompted = table.concat(vim.fn.readfile(prompted_path), "\n")
    assert_contains(prompted, "@flashcard japanese", "form flow inserted a Japanese card")
    assert_contains(prompted, "japanese: 机", "form flow saved front field")
    assert_contains(prompted, "english: desk", "form flow saved required answer field")
    assert_contains(prompted, "tags: jlpt furniture", "form flow saved optional tags")
    assert_true(not prompted:find("japanese: Japanese:", 1, true), "virtual labels never leak into card storage")
    assert_equal(vim.api.nvim_get_current_buf(), form_target, "closing the form returns to the card file")

    flashcards.add_kind("")
    local dirty_form_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(dirty_form_buf, 0, 1, false, { "草" })
    vim.cmd("Flashcards open")
    assert_true(form.is_open(), "open cannot strand an active composer")
    assert_equal(vim.api.nvim_get_current_buf(), dirty_form_buf, "open does not replace the composer buffer")
    local select_original = vim.ui.select
    local close_choices, close_callback
    vim.ui.select = function(items, _, callback)
      close_choices = items
      close_callback = callback
    end
    assert_true(not form.close(), "dirty close waits for confirmation")
    assert_true(form.is_open(), "dirty composer remains open while confirmation is pending")
    assert_equal(close_choices[1], "Keep editing", "dirty close offers the safe choice first")
    assert_equal(close_choices[2], "Discard draft", "dirty close offers explicit discard")
    close_callback("Keep editing", 1)
    assert_true(form.is_open(), "keeping a draft returns to the composer")
    form.close()
    close_callback("Discard draft", 2)
    vim.ui.select = select_original
    assert_true(not form.is_open(), "discarding a draft closes the composer")
    assert_equal(vim.api.nvim_get_current_buf(), form_target, "discard returns to the original target")

    flashcards.add_kind("")
    local stale_prompt_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(stale_prompt_buf, 0, 1, false, { "古い" })
    local stale_select_original = vim.ui.select
    local stale_close_callback
    vim.ui.select = function(_, _, callback)
      stale_close_callback = callback
    end
    assert_true(not form.close(), "stale-confirmation fixture opens a discard prompt")
    form.close({ force = true })
    flashcards.add_kind("")
    local replacement_form_buf = vim.api.nvim_get_current_buf()
    stale_close_callback("Discard draft", 2)
    vim.ui.select = stale_select_original
    assert_true(form.is_open(), "a stale discard callback cannot close a later form generation")
    assert_equal(
      vim.api.nvim_get_current_buf(),
      replacement_form_buf,
      "stale confirmation does not steal focus from the replacement form"
    )
    form.close({ force = true })

    local add_anchor_namespace = vim.api.nvim_create_namespace("neorg_flashcards_add_anchor")
    flashcards.add_kind("")
    local native_dirty_form = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(native_dirty_form, 0, 1, false, { "native close draft" })
    local native_select_original = vim.ui.select
    local native_close_choices, native_close_callback
    vim.ui.select = function(items, _, callback)
      native_close_choices = items
      native_close_callback = callback
    end
    vim.cmd("q")
    assert_true(
      vim.wait(200, function()
        return native_close_callback ~= nil
      end),
      "native close routes a dirty draft through confirmation"
    )
    assert_true(form.is_open(), "native close reopens the dirty composer")
    assert_equal(
      vim.api.nvim_buf_get_lines(native_dirty_form, 0, 1, false)[1],
      "native close draft",
      "native close preserves the draft values"
    )
    assert_equal(native_close_choices[1], "Keep editing", "native close keeps the safe choice first")
    native_close_callback("Keep editing", 1)
    assert_true(form.is_open(), "keeping a native-close draft returns to the composer")

    native_close_choices, native_close_callback = nil, nil
    vim.cmd("q")
    assert_true(
      vim.wait(200, function()
        return native_close_callback ~= nil
      end),
      "a repeated native close asks before discarding again"
    )
    native_close_callback("Discard draft", 2)
    vim.ui.select = native_select_original
    assert_true(not form.is_open(), "discarding the recovered draft closes the composer")
    assert_equal(
      #vim.api.nvim_buf_get_extmarks(form_target, add_anchor_namespace, 0, -1, {}),
      0,
      "discarding the recovered draft releases the insertion anchor"
    )

    flashcards.add_kind("")
    assert_equal(
      #vim.api.nvim_buf_get_extmarks(form_target, add_anchor_namespace, 0, -1, {}),
      1,
      "an open composer owns one insertion anchor"
    )
    vim.cmd("q")
    assert_true(not form.is_open(), "native close finalizes a clean composer")
    assert_equal(
      #vim.api.nvim_buf_get_extmarks(form_target, add_anchor_namespace, 0, -1, {}),
      0,
      "native window close releases the insertion anchor"
    )

    local failed_context
    assert_true(
      form.open(config, "japanese", {
        target_path = prompted_path,
        target_label = "prompted-card-test",
        on_save = function(_, context)
          failed_context = context
          return { ok = false, persisted = false, message = "forced composer failure" }
        end,
      }),
      "composer opens with a structured save callback"
    )
    local failed_form_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(failed_form_buf, 0, -1, false, { "雨", "あめ", "rain", "", "weather" })
    assert_true(not form.save(), "structured save failure is rejected")
    assert_true(form.is_open(), "failed save retains the composer draft")
    assert_equal(failed_context.kind, "japanese", "save callback receives immutable kind context")
    assert_equal(failed_context.mode, "close", "save callback receives the requested mode")
    assert_equal(failed_context.target.path, prompted_path, "save callback receives the captured target")
    assert_contains(decoration_text(failed_form_buf), "forced composer failure", "save failure is visible in the form")
    vim.wait(30, function()
      return false
    end, 5)
    assert_contains(
      decoration_text(failed_form_buf),
      "forced composer failure",
      "a pending change refresh cannot erase a newer save error"
    )
    assert_equal(
      vim.api.nvim_buf_get_lines(failed_form_buf, 0, 1, false)[1],
      "雨",
      "failed save preserves field values"
    )
    form.close({ force = true })

    local teardown_closes = 0
    assert_true(
      form.open(config, "japanese", {
        target_path = prompted_path,
        on_save = function()
          return { ok = true, persisted = true, path = prompted_path }
        end,
        on_close = function()
          teardown_closes = teardown_closes + 1
          error("forced form on_close failure")
        end,
      }),
      "composer opens for teardown regression"
    )
    local teardown_form_buf = vim.api.nvim_get_current_buf()
    local teardown_form_win = vim.api.nvim_get_current_win()
    vim.api.nvim_buf_set_lines(teardown_form_buf, 0, -1, false, { "風", "かぜ", "wind", "", "weather" })
    local teardown_group = vim.api.nvim_create_augroup("NeorgFlashcardsTeardownRegression", { clear = true })
    vim.api.nvim_create_autocmd("WinClosed", {
      group = teardown_group,
      pattern = tostring(teardown_form_win),
      once = true,
      callback = function()
        error("forced form close hook failure")
      end,
    })
    local set_current_win_original = vim.api.nvim_set_current_win
    vim.api.nvim_set_current_win = function()
      error("forced form focus hook failure")
    end
    local teardown_notifications = {}
    local teardown_notify_original = vim.notify
    vim.notify = function(message)
      table.insert(teardown_notifications, tostring(message))
    end
    local teardown_ok, teardown_saved = pcall(form.save)
    vim.notify = teardown_notify_original
    vim.api.nvim_set_current_win = set_current_win_original
    pcall(vim.api.nvim_del_augroup_by_id, teardown_group)
    assert_true(teardown_ok, teardown_saved)
    assert_true(teardown_saved, "successful save survives close and focus hook failures")
    assert_true(not form.is_open(), "teardown hook failures cannot retain a retryable composer")
    assert_equal(teardown_closes, 1, "teardown hook failures still run on_close exactly once")
    assert_contains(
      table.concat(teardown_notifications, "\n"),
      "UI cleanup hook failed",
      "best-effort teardown reports its warning"
    )
    form.close({ force = true })
    assert_equal(teardown_closes, 1, "later close calls do not repeat on_close")

    local original_columns, original_lines = vim.o.columns, vim.o.lines
    vim.o.columns = 40
    vim.o.lines = 10
    local narrow_ok, narrow_error = pcall(function()
      assert_true(
        form.open(config, "japanese", {
          target_path = prompted_path,
          target_label = "a/very/long/target/path/cards.norg",
        }),
        "composer opens in a narrow editor"
      )
      local narrow_window = vim.api.nvim_get_current_win()
      local narrow_config = vim.api.nvim_win_get_config(narrow_window)
      assert_true(narrow_config.width <= vim.o.columns - 4, "narrow composer width stays inside the editor")
      assert_true(narrow_config.height <= vim.o.lines - 4, "narrow composer height stays inside the editor")
      assert_true(narrow_config.row >= 0, "narrow composer row is non-negative")
      assert_true(narrow_config.col >= 0, "narrow composer column is non-negative")
      assert_true(
        vim.fn.strdisplaywidth(window_footer(narrow_window)) <= narrow_config.width,
        "narrow composer footer fits its window"
      )
      form.goto_field(5)
      assert_equal(vim.api.nvim_win_get_cursor(narrow_window)[1], 5, "every field remains reachable in a short window")
      form.close({ force = true })
    end)
    if form.is_open() then
      form.close({ force = true })
    end
    vim.o.columns = original_columns
    vim.o.lines = original_lines
    assert_true(narrow_ok, narrow_error)
    vim.cmd("silent! bwipeout!")

    local dirty_add_path = config.flashcards_dir .. "/dirty-add.norg"
    vim.fn.writefile({ "* Dirty add target", "" }, dirty_add_path)
    vim.cmd.edit(vim.fn.fnameescape(dirty_add_path))
    vim.api.nvim_buf_set_lines(0, 1, 1, false, { "unsaved source text" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    local dirty_add_target = vim.api.nvim_get_current_buf()
    flashcards.add_kind("")
    local dirty_add_form = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(dirty_add_form, 0, -1, false, { "犬", "いぬ", "dog", "", "animals" })
    assert_true(form.save(), "composer accepts a card into a modified target buffer")
    assert_equal(vim.api.nvim_get_current_buf(), dirty_add_target, "modified-target save returns to its source buffer")
    assert_true(vim.bo[dirty_add_target].modified, "adding does not clear unrelated unsaved target edits")
    local dirty_add_buffer_text = table.concat(vim.api.nvim_buf_get_lines(dirty_add_target, 0, -1, false), "\n")
    local dirty_add_disk_text = table.concat(vim.fn.readfile(dirty_add_path), "\n")
    assert_contains(dirty_add_buffer_text, "unsaved source text", "candidate insertion preserves unsaved source text")
    assert_contains(dirty_add_buffer_text, "japanese: 犬", "candidate insertion updates the loaded target")
    assert_true(
      not dirty_add_disk_text:find("unsaved source text", 1, true),
      "dirty target is not written automatically"
    )
    assert_true(
      not dirty_add_disk_text:find("japanese: 犬", 1, true),
      "new card waits for the dirty target to be saved"
    )
    vim.cmd.write()
    vim.cmd("silent! bwipeout!")

    local post_add_path = config.flashcards_dir .. "/post-add.norg"
    vim.fn.writefile({ "* Post-write add target", "" }, post_add_path)
    vim.cmd.edit(vim.fn.fnameescape(post_add_path))
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.api.nvim_create_autocmd("BufWritePost", {
      buffer = 0,
      once = true,
      callback = function()
        error("forced add post-write failure")
      end,
    })
    flashcards.add_kind("")
    local post_add_form = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(post_add_form, 0, -1, false, { "鳥", "とり", "bird", "", "animals" })
    assert_true(form.save(), "post-write hook failure still accepts a committed card")
    assert_true(not form.is_open(), "committed post-write failure cannot leave a retryable draft")
    local post_add_text = table.concat(vim.fn.readfile(post_add_path), "\n")
    local _, post_add_count = post_add_text:gsub("@flashcard japanese", "")
    assert_equal(post_add_count, 1, "post-write hook failure commits exactly one card")
    vim.cmd("silent! bwipeout!")
    vim.fn.delete(prompted_path)
    vim.fn.delete(dirty_add_path)
    vim.fn.delete(post_add_path)
  end
end
