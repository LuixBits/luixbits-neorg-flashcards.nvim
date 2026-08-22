return function(T)
  local form = require("neorg_flashcards.form")
  local actions = require("neorg_flashcards.ui.actions")
  local flashcards = require("neorg_flashcards")
  local parser = require("neorg_flashcards.parser")
  local presets = require("neorg_flashcards.presets")

  local assert_true = T.assert_true
  local assert_equal = T.assert_equal
  local assert_contains = T.assert_contains
  local current_popup = T.current_popup
  local assert_buffer_maps = T.assert_buffer_maps
  local assert_buffer_maps_absent = T.assert_buffer_maps_absent
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
    flashcards.add_kind("japanese")
    vim.notify = outside_notify_original
    assert_true(not form.is_open(), "add refuses a target outside the configured collection")
    assert_contains(
      table.concat(outside_messages, "\n"),
      "stay inside the configured collection path",
      "outside-root add explains the collection boundary"
    )
    assert_equal(
      table.concat(vim.fn.readfile(outside_path), "\n"),
      "* Outside collection\n",
      "outside-root add leaves the file untouched"
    )
    vim.cmd("silent! bwipeout!")

    local missing_chapter_path = config.path .. "/clean-new-chapter.norg"
    assert_equal(vim.fn.filereadable(missing_chapter_path), 0, "new-chapter fixture starts without a disk file")
    vim.cmd.edit(vim.fn.fnameescape(missing_chapter_path))
    local missing_chapter_buffer = vim.api.nvim_get_current_buf()
    assert_true(not vim.bo[missing_chapter_buffer].modified, "named new-chapter buffer starts clean")

    flashcards.add_kind("japanese")
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

    local prompted_path = config.path .. "/prompted-form.norg"
    vim.cmd.edit(vim.fn.fnameescape(prompted_path))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      "* Prompt Test",
      "",
    })
    vim.cmd.write()
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    local form_target = vim.api.nvim_get_current_buf()
    flashcards.add_kind("japanese")
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
      local form_help_buf, form_help_text = current_popup()
      assert_contains(form_help_text, "Card form keys", "form has contextual key help")
      assert_contains(form_help_text, "Normal or Insert mode", "form help distinguishes editing modes")
      assert_contains(form_help_text, "Save the card and return", "form help explains save and close")
      assert_contains(form_help_text, "Save and start another", "form help explains repeated entry")
      assert_contains(window_footer(), "/ find", "form help advertises native search")
      assert_buffer_maps_absent(form_help_buf, { "/", "n", "N" })
      assert_true(vim.fn.search("Save and start another") > 0, "native search finds a form action")
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

    flashcards.add_kind("japanese")
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

    flashcards.add_kind("japanese")
    local stale_prompt_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(stale_prompt_buf, 0, 1, false, { "古い" })
    local stale_select_original = vim.ui.select
    local stale_close_callback
    vim.ui.select = function(_, _, callback)
      stale_close_callback = callback
    end
    assert_true(not form.close(), "stale-confirmation fixture opens a discard prompt")
    form.close({ force = true })
    flashcards.add_kind("japanese")
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
    flashcards.add_kind("japanese")
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

    native_close_callback = nil
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

    flashcards.add_kind("japanese")
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

    local dirty_add_path = config.path .. "/dirty-add.norg"
    vim.fn.writefile({ "* Dirty add target", "" }, dirty_add_path)
    vim.cmd.edit(vim.fn.fnameescape(dirty_add_path))
    vim.api.nvim_buf_set_lines(0, 1, 1, false, { "unsaved source text" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    local dirty_add_target = vim.api.nvim_get_current_buf()
    flashcards.add_kind("japanese")
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

    local post_add_path = config.path .. "/post-add.norg"
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
    flashcards.add_kind("japanese")
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

    do
      local multiline_path = config.path .. "/multiline-form.norg"
      local multiline_config = vim.deepcopy(config)
      multiline_config.default_file = multiline_path
      multiline_config.default_card_type = "question_answer"
      multiline_config.schemas = presets.only("question_answer")
      multiline_config.schemas.question_answer.fields[1].help = ""
      T.setup(multiline_config)

      vim.fn.writefile({ "* Multiline form", "" }, multiline_path)
      vim.cmd.edit(vim.fn.fnameescape(multiline_path))
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      local multiline_target = vim.api.nvim_get_current_buf()
      local multiline_target_before_save =
        table.concat(vim.api.nvim_buf_get_lines(multiline_target, 0, -1, false), "\n")

      assert_true(flashcards.add_kind("question_answer"), "a generic card opens the protected composer")
      local multiline_form = vim.api.nvim_get_current_buf()
      local multiline_form_win = vim.fn.bufwinid(multiline_form)
      assert_equal(vim.bo[multiline_form].filetype, "neorg_flashcards_form", "generic add uses the shared form")
      assert_true(
        vim.deep_equal(vim.api.nvim_buf_get_lines(multiline_form, 0, -1, false), { "", "", "", "" }),
        "long fields still occupy one protected preview row"
      )
      assert_contains(
        decoration_text(multiline_form),
        "Enter to open the long-field editor",
        "an empty long field explains how to edit it"
      )

      assert_true(form.open_long_field(1), "the question field opens its focused editor")
      local question_editor = vim.api.nvim_get_current_buf()
      assert_equal(
        vim.bo[question_editor].filetype,
        "neorg_flashcards_field",
        "long-field editor has a dedicated filetype"
      )
      assert_contains(window_footer(), "Ctrl-S apply", "long-field footer explains how to apply text")
      assert_contains(window_footer(), "Esc cancel", "long-field footer explains how to cancel")
      local question_maps = {}
      for _, mode in ipairs({ "n", "i" }) do
        for _, map in ipairs(vim.api.nvim_buf_get_keymap(question_editor, mode)) do
          question_maps[mode .. ":" .. map.lhs:lower()] = true
        end
      end
      assert_true(question_maps["n:<c-s>"], "Ctrl-S applies a long field from Normal mode")
      assert_true(question_maps["i:<c-s>"], "Ctrl-S applies a long field from Insert mode")
      assert_true(question_maps["n:<esc>"], "Esc cancels a long field from Normal mode")
      assert_true(question_maps["i:<esc>"], "Esc cancels a long field from Insert mode")

      local blocked_save_messages = {}
      local blocked_save_notify = vim.notify
      vim.notify = function(message)
        table.insert(blocked_save_messages, tostring(message))
      end
      vim.api.nvim_set_current_win(multiline_form_win)
      local blocked_save = form.save()
      vim.notify = blocked_save_notify
      assert_true(not blocked_save, "the parent form cannot save while a long-field editor is open")
      assert_equal(vim.api.nvim_get_current_buf(), question_editor, "blocked save keeps focus in the long-field editor")
      assert_contains(
        decoration_text(multiline_form),
        "Apply or cancel the open long field before saving",
        "blocked save leaves a clear status on the parent form"
      )
      assert_contains(
        table.concat(blocked_save_messages, "\n"),
        "Apply or cancel the open long field before saving",
        "blocked save notifies the user how to continue"
      )
      assert_equal(
        table.concat(vim.api.nvim_buf_get_lines(multiline_target, 0, -1, false), "\n"),
        multiline_target_before_save,
        "blocked save leaves the target source unchanged"
      )

      vim.api.nvim_buf_set_lines(question_editor, 0, -1, false, { " ", " " })
      assert_true(form.apply_long_field(), "a whitespace-only long value can return to the parent form")
      assert_contains(
        vim.api.nvim_buf_get_lines(multiline_form, 0, 1, false)[1],
        "…",
        "the whitespace-only structured value has a non-empty preview"
      )
      assert_contains(
        decoration_text(multiline_form),
        "2 required fields remaining",
        "required status reads the empty structured long value instead of its preview"
      )

      assert_true(form.open_long_field(1), "the question field reopens after required-status verification")
      question_editor = vim.api.nvim_get_current_buf()

      local question_value = "Why does a hash table resize?\nExplain the load factor."
      vim.api.nvim_buf_set_lines(question_editor, 0, -1, false, {
        "Why does a hash table resize?",
        "Explain the load factor.",
      })
      assert_true(form.apply_long_field(), "the long-field API applies question text")
      assert_equal(vim.api.nvim_get_current_buf(), multiline_form, "applying returns to the parent form")
      assert_equal(
        vim.api.nvim_buf_get_lines(multiline_form, 0, 1, false)[1],
        "Why does a hash table resize? …",
        "the form shows a compact first-line preview"
      )
      local question_decoration = decoration_text(multiline_form)
      assert_contains(question_decoration, "↳ 2 lines · Enter to edit", "the preview reports its hidden line count")
      assert_contains(question_decoration, "Question", "the virtual question label remains visible")

      vim.api.nvim_buf_set_lines(multiline_form, 0, 1, false, { "deleted label and preview" })
      assert_true(
        vim.wait(200, function()
          return vim.api.nvim_buf_get_lines(multiline_form, 0, 1, false)[1] == "Why does a hash table resize? …"
        end),
        "direct edits cannot replace a protected multiline preview"
      )
      local protected_decoration = decoration_text(multiline_form)
      assert_contains(protected_decoration, "Question", "preview repair keeps the virtual field label")
      assert_contains(
        protected_decoration,
        "opens in its own editor; press Enter",
        "preview repair tells the user where editing belongs"
      )

      form.goto_field(2)
      form.edit_field()
      local answer_editor = vim.api.nvim_get_current_buf()
      assert_equal(vim.bo[answer_editor].filetype, "neorg_flashcards_field", "Enter opens the answer editor")
      local answer_value = "  To keep lookups close to constant time.\nToo many collisions make probes expensive."
      vim.api.nvim_buf_set_lines(answer_editor, 0, -1, false, {
        "  To keep lookups close to constant time.",
        "Too many collisions make probes expensive.",
      })
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-s>", true, false, true), "xt", false)
      assert_true(
        vim.wait(200, function()
          return vim.api.nvim_get_current_buf() == multiline_form
        end),
        "Ctrl-S applies the long answer and returns to the form"
      )
      assert_contains(
        decoration_text(multiline_form),
        "↳ 2 lines · Enter to edit",
        "Ctrl-S updates the answer preview"
      )

      form.goto_field(3)
      assert_true(form.open_long_field(3), "optional long notes open in the same editor")
      local notes_editor = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(notes_editor, 0, -1, false, { "draft note", "not applied" })
      local long_select_original = vim.ui.select
      local cancel_choices, cancel_callback
      vim.ui.select = function(items, _, callback)
        cancel_choices = items
        cancel_callback = callback
      end
      assert_true(not form.cancel_long_field(), "cancelling changed long text waits for a decision")
      assert_equal(cancel_choices[1], "Keep editing", "dirty long-field cancel keeps the safe choice first")
      assert_equal(cancel_choices[2], "Discard changes", "dirty long-field cancel offers explicit discard")
      assert_true(not form.close(), "the parent form cannot close behind an unresolved long field")
      assert_equal(vim.api.nvim_get_current_buf(), notes_editor, "blocked parent close returns focus to the long field")
      cancel_callback("Keep editing", 1)
      assert_equal(vim.api.nvim_get_current_buf(), notes_editor, "keeping changes returns to the long editor")

      cancel_callback = nil
      form.cancel_long_field()
      assert_true(cancel_callback ~= nil, "a second dirty cancel asks again")
      cancel_callback("Discard changes", 2)
      vim.ui.select = long_select_original
      assert_equal(vim.api.nvim_get_current_buf(), multiline_form, "discarding field changes returns to the form")
      assert_equal(vim.api.nvim_buf_get_lines(multiline_form, 2, 3, false)[1], "", "discard leaves notes unchanged")

      assert_true(form.save(), "a complete multiline card saves from the parent form")
      assert_true(not form.is_open(), "multiline add closes after a successful save")
      assert_equal(vim.api.nvim_get_current_buf(), multiline_target, "multiline add returns to its source")
      local added_text = table.concat(vim.api.nvim_buf_get_lines(multiline_target, 0, -1, false), "\n")
      assert_contains(
        added_text,
        "question: |\n  Why does a hash table resize?\n  Explain the load factor.",
        "add stores every question line in the explicit block format"
      )
      assert_contains(
        added_text,
        "answer: |\n    To keep lookups close to constant time.\n  Too many collisions make probes expensive.",
        "add stores every answer line in the explicit block format"
      )
      assert_true(not added_text:find("draft note", 1, true), "discarded long-field text never reaches the source")

      local added_cards = parser.parse_buffer(multiline_target)
      assert_equal(#added_cards, 1, "multiline add creates one card")
      local added_card = added_cards[1]
      assert_equal(added_card.values.question, question_value, "added question parses back exactly")
      assert_equal(added_card.values.answer, answer_value, "added answer parses back exactly")
      local original_id = added_card.id

      assert_true(
        flashcards.edit_card(added_card, { cards = added_cards }),
        "structured edit reopens a valid multiline card"
      )
      local edit_form = vim.api.nvim_get_current_buf()
      assert_contains(
        decoration_text(edit_form),
        "↳ 2 lines · Enter to edit",
        "edit mode restores multiline previews"
      )
      assert_true(form.open_long_field(1), "edit mode opens the stored question")
      local edit_question = vim.api.nvim_get_current_buf()
      assert_true(
        vim.deep_equal(vim.api.nvim_buf_get_lines(edit_question, 0, -1, false), {
          "Why does a hash table resize?",
          "Explain the load factor.",
        }),
        "the long editor restores every stored line"
      )
      local edited_question = "When should a hash table resize?\nDiscuss its load factor.\nKeep the answer practical."
      vim.api.nvim_buf_set_lines(edit_question, 0, -1, false, {
        "When should a hash table resize?",
        "Discuss its load factor.",
        "Keep the answer practical.",
      })
      assert_true(form.apply_long_field(), "edit mode applies a changed multiline question")

      form.goto_field(2)
      assert_true(form.open_long_field(2), "edit mode can inspect an unchanged multiline answer")
      assert_true(form.cancel_long_field(), "an unchanged long field cancels without a prompt")
      assert_equal(vim.api.nvim_get_current_buf(), edit_form, "clean cancel returns directly to the edit form")
      assert_true(form.save(), "structured edit saves multiline changes")
      assert_equal(vim.api.nvim_get_current_buf(), multiline_target, "multiline edit returns to the source")

      local edited_cards = parser.parse_buffer(multiline_target)
      assert_equal(#edited_cards, 1, "multiline edit keeps one physical card")
      assert_equal(edited_cards[1].id, original_id, "multiline edit preserves the stable card ID")
      assert_equal(edited_cards[1].values.question, edited_question, "edited question parses back exactly")
      assert_equal(
        edited_cards[1].values.answer,
        answer_value,
        "structured editing preserves edge indentation in another long field"
      )
      local edited_text = table.concat(vim.api.nvim_buf_get_lines(multiline_target, 0, -1, false), "\n")
      assert_true(not edited_text:find("Why does a hash table resize?", 1, true), "edit removes the old block span")
      assert_contains(
        edited_text,
        "question: |\n  When should a hash table resize?\n  Discuss its load factor.\n  Keep the answer practical.",
        "edit writes the complete replacement block"
      )

      vim.cmd("silent! bwipeout!")
      vim.fn.delete(multiline_path)
      T.setup(config)
    end
  end
end
