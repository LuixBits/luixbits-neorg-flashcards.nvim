return function(T)
  local history = require("neorg_flashcards.history")
  local parser = require("neorg_flashcards.parser")
  local store = require("neorg_flashcards.store")
  local review_engine = require("neorg_flashcards.review")
  local flashcards = require("neorg_flashcards")

  local assert_true = T.assert_true
  local assert_equal = T.assert_equal
  local assert_contains = T.assert_contains
  local canonical_path = T.canonical_path
  local config = T.config

  local modified_path = vim.fn.tempname() .. ".norg"
  vim.fn.writefile({
    "@flashcard japanese",
    "id: fc_modified_dog",
    "japanese: 犬",
    "english: dog",
    "@end",
  }, modified_path)

  vim.cmd.edit(vim.fn.fnameescape(modified_path))
  vim.api.nvim_buf_set_lines(0, 2, 2, false, {
    "notes: edited in an open buffer",
  })

  local modified_cards = parser.parse_buffer(0)
  local modified_valid, modified_errors = parser.valid_cards(config, modified_cards)
  assert_equal(#modified_errors, 0, "modified open-buffer card validates")
  assert_equal(#modified_valid, 1, "modified open-buffer card is valid")

  local modified_ok, modified_message, modified_persisted = store.set_card_fields(modified_valid[1], {
    { field = "score", value = "1" },
    { field = "reviewed", value = "2026-07-01" },
  }, { cards = modified_valid })

  assert_true(modified_ok, modified_message)
  assert_equal(modified_persisted, false, "modified open buffer is not written automatically")
  assert_contains(modified_message, "open modified buffer", "modified buffer warning is explicit")

  local modified_buffer_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  local modified_disk_text = table.concat(vim.fn.readfile(modified_path), "\n")
  assert_contains(modified_buffer_text, "score: 1", "score is applied to the modified buffer")
  assert_true(not modified_disk_text:find("score: 1", 1, true), "score is not written to disk while buffer is modified")
  vim.cmd("silent! bwipeout!")

  do
    local protected_path = vim.fn.tempname() .. ".norg"
    local protected_lines = {
      "@flashcard japanese",
      "id: fc_write_rollback",
      "japanese: 守",
      "english: protect",
      "@end",
    }
    vim.fn.writefile(protected_lines, protected_path)
    vim.cmd.edit(vim.fn.fnameescape(protected_path))
    local protected_card = parser.parse_buffer(0)[1]

    vim.bo.readonly = true
    local readonly_ok, readonly_message, readonly_persisted = store.set_card_fields(protected_card, {
      { field = "score", value = "3" },
    })
    assert_true(not readonly_ok, "read-only source buffers reject scheduling writes")
    assert_contains(readonly_message, "read-only", "read-only failure is explicit")
    assert_equal(readonly_persisted, false, "rejected read-only writes are not persisted")
    assert_equal(
      table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"),
      table.concat(protected_lines, "\n"),
      "read-only rejection leaves the buffer untouched"
    )
    vim.bo.readonly = false

    vim.bo.modifiable = false
    local unmodifiable_ok = store.set_card_fields(protected_card, { { field = "score", value = "3" } })
    assert_true(not unmodifiable_ok, "unmodifiable source buffers reject scheduling writes")
    assert_equal(
      table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"),
      table.concat(protected_lines, "\n"),
      "unmodifiable rejection leaves the buffer untouched"
    )
    vim.bo.modifiable = true

    vim.api.nvim_create_autocmd("BufWritePre", {
      buffer = 0,
      once = true,
      callback = function()
        vim.api.nvim_buf_set_lines(0, 0, 1, false, { "write hook mutation" })
        vim.bo.modifiable = false
        error("forced write failure")
      end,
    })
    local failed_ok, failed_message, failed_persisted = store.set_card_fields(protected_card, {
      { field = "score", value = "3" },
    })
    assert_true(not failed_ok, "a failing write hook rejects the scheduling update")
    assert_contains(failed_message, "forced write failure", "write failure keeps the original error")
    assert_equal(failed_persisted, false, "a rolled-back write is not reported as persisted")
    assert_equal(
      table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"),
      table.concat(protected_lines, "\n"),
      "failed writes restore the exact original buffer lines"
    )
    assert_true(not vim.bo.modified, "failed writes restore the clean modified flag")
    assert_true(vim.bo.modifiable, "failed writes restore the original modifiable flag")
    assert_equal(
      table.concat(vim.fn.readfile(protected_path), "\n"),
      table.concat(protected_lines, "\n"),
      "failed writes leave the source file unchanged"
    )

    vim.api.nvim_create_autocmd("BufWritePost", {
      buffer = 0,
      once = true,
      callback = function()
        error("forced post-write failure")
      end,
    })
    local post_ok, post_message, post_persisted = store.set_card_fields(protected_card, {
      { field = "score", value = "3" },
    })
    assert_true(post_ok, "a post-write hook error does not reject metadata already saved to disk")
    assert_true(post_persisted, "post-write hook errors still report matching disk content as persisted")
    assert_contains(post_message, "post-write hook failed", "post-write errors return an explicit warning")
    assert_contains(
      table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"),
      "score: 3",
      "post-write errors keep the persisted update in the buffer"
    )
    assert_contains(
      table.concat(vim.fn.readfile(protected_path), "\n"),
      "score: 3",
      "post-write errors keep the persisted update on disk"
    )
    vim.cmd("silent! bwipeout!")
  end

  do
    local uv = vim.uv or vim.loop
    local swap_root = vim.fn.tempname()
    local outside_root = vim.fn.tempname()
    local swap_path = swap_root .. "/cards.norg"
    local moved_path = swap_root .. "/cards-moved.norg"
    local outside_path = outside_root .. "/outside.norg"
    local swap_lines = {
      "@flashcard japanese",
      "id: fc_loaded_path_swap",
      "japanese: 内",
      "english: inside",
      "@end",
    }
    local outside_lines = {
      "@flashcard japanese",
      "id: fc_outside_path_swap",
      "japanese: 外",
      "english: outside",
      "@end",
    }
    vim.fn.mkdir(swap_root, "p")
    vim.fn.mkdir(outside_root, "p")
    vim.fn.writefile(swap_lines, swap_path)
    vim.fn.writefile(outside_lines, outside_path)
    vim.cmd.edit(vim.fn.fnameescape(swap_path))
    local swap_buffer = vim.api.nvim_get_current_buf()
    local swap_card = parser.parse_buffer(swap_buffer)[1]
    local swapped = false
    local swap_error
    vim.api.nvim_buf_attach(swap_buffer, false, {
      on_lines = function()
        if swapped or swap_error then
          return
        end
        local renamed, rename_error = uv.fs_rename(swap_path, moved_path)
        if not renamed then
          swap_error = "could not move the source: " .. tostring(rename_error)
          return
        end
        local linked, link_error = uv.fs_symlink(outside_path, swap_path)
        if not linked then
          swap_error = "could not replace the source with a symlink: " .. tostring(link_error)
          return
        end
        swapped = true
      end,
    })

    local call_ok, swap_ok, swap_message, swap_persisted = pcall(store.set_card_fields, swap_card, {
      { field = "score", value = "3" },
    }, { allowed_root = swap_root })
    pcall(vim.api.nvim_buf_detach, swap_buffer)

    assert_true(call_ok, "loaded-buffer path replacement is rejected without crashing: " .. tostring(swap_ok))
    assert_true(swapped, "on_lines fixture replaces the source path synchronously: " .. tostring(swap_error))
    assert_true(not swap_ok, "clean loaded-buffer writes reject a source path replaced during the update")
    assert_equal(swap_persisted, false, "a rejected loaded-buffer path replacement is not persisted")
    assert_contains(swap_message, "flashcards_dir", "loaded-buffer path rejection names the collection boundary")
    assert_equal(
      table.concat(vim.fn.readfile(outside_path), "\n"),
      table.concat(outside_lines, "\n"),
      "the rejected write leaves the outside symlink target untouched"
    )
    assert_equal(
      table.concat(vim.fn.readfile(moved_path), "\n"),
      table.concat(swap_lines, "\n"),
      "the rejected write leaves the moved original source untouched"
    )
    assert_equal(
      table.concat(vim.api.nvim_buf_get_lines(swap_buffer, 0, -1, false), "\n"),
      table.concat(swap_lines, "\n"),
      "the rejected write restores the exact clean buffer contents"
    )
    assert_true(not vim.bo[swap_buffer].modified, "the rejected write restores the clean buffer state")
    assert_equal(swap_card.values.score, nil, "the rejected write does not mutate cached card metadata")
    vim.cmd("silent! bwipeout!")
  end

  do
    local uv = vim.uv or vim.loop
    local swap_root = vim.fn.tempname()
    local outside_root = vim.fn.tempname()
    local swap_path = swap_root .. "/cards.norg"
    local moved_path = swap_root .. "/cards-moved.norg"
    local outside_path = outside_root .. "/outside.norg"
    local disk_lines = {
      "@flashcard japanese",
      "id: fc_dirty_loaded_path_swap",
      "japanese: 内",
      "english: inside",
      "@end",
    }
    local outside_lines = {
      "@flashcard japanese",
      "id: fc_dirty_outside_path_swap",
      "japanese: 外",
      "english: outside",
      "@end",
    }
    vim.fn.mkdir(swap_root, "p")
    vim.fn.mkdir(outside_root, "p")
    vim.fn.writefile(disk_lines, swap_path)
    vim.fn.writefile(outside_lines, outside_path)
    vim.cmd.edit(vim.fn.fnameescape(swap_path))
    local swap_buffer = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(swap_buffer, 2, 2, false, { "notes: preserve this unsaved edit" })
    local dirty_lines = vim.api.nvim_buf_get_lines(swap_buffer, 0, -1, false)
    local original_modified = vim.bo[swap_buffer].modified
    local original_modifiable = vim.bo[swap_buffer].modifiable
    local original_readonly = vim.bo[swap_buffer].readonly
    local swap_card = parser.parse_buffer(swap_buffer)[1]
    local swapped = false
    local swap_error
    vim.api.nvim_buf_attach(swap_buffer, false, {
      on_lines = function()
        if swapped or swap_error then
          return
        end
        local renamed, rename_error = uv.fs_rename(swap_path, moved_path)
        if not renamed then
          swap_error = "could not move the source: " .. tostring(rename_error)
          return
        end
        local linked, link_error = uv.fs_symlink(outside_path, swap_path)
        if not linked then
          swap_error = "could not replace the source with a symlink: " .. tostring(link_error)
          return
        end
        swapped = true
      end,
    })

    local call_ok, swap_ok, swap_message, swap_persisted = pcall(store.set_card_fields, swap_card, {
      { field = "score", value = "2" },
    }, { allowed_root = swap_root })
    pcall(vim.api.nvim_buf_detach, swap_buffer)

    assert_true(call_ok, "dirty-buffer path replacement is rejected without crashing: " .. tostring(swap_ok))
    assert_true(swapped, "dirty on_lines fixture replaces the source path synchronously: " .. tostring(swap_error))
    assert_true(not swap_ok, "dirty loaded-buffer writes reject a source path replaced during the update")
    assert_equal(swap_persisted, false, "a rejected dirty-buffer path replacement is not persisted")
    assert_contains(swap_message, "flashcards_dir", "dirty-buffer path rejection names the collection boundary")
    assert_equal(
      table.concat(vim.fn.readfile(outside_path), "\n"),
      table.concat(outside_lines, "\n"),
      "the rejected dirty write leaves the outside symlink target untouched"
    )
    assert_equal(
      table.concat(vim.fn.readfile(moved_path), "\n"),
      table.concat(disk_lines, "\n"),
      "the rejected dirty write leaves the moved original source untouched"
    )
    assert_equal(
      table.concat(vim.api.nvim_buf_get_lines(swap_buffer, 0, -1, false), "\n"),
      table.concat(dirty_lines, "\n"),
      "the rejected dirty write restores the exact unsaved buffer contents"
    )
    assert_equal(vim.bo[swap_buffer].modified, original_modified, "dirty rollback restores the modified flag")
    assert_equal(vim.bo[swap_buffer].modifiable, original_modifiable, "dirty rollback restores the modifiable flag")
    assert_equal(vim.bo[swap_buffer].readonly, original_readonly, "dirty rollback restores the read-only flag")
    assert_equal(swap_card.values.score, nil, "the rejected dirty write does not mutate cached card metadata")
    vim.cmd("silent! bwipeout!")
  end

  do
    local custom_path = vim.fn.tempname() .. ".norg"
    local custom_lines = {
      "@flashcard japanese",
      "id: fc_custom_writer",
      "japanese: 書く",
      "english: write",
      "@end",
    }
    vim.fn.writefile(custom_lines, custom_path)
    vim.cmd.edit(vim.fn.fnameescape(custom_path))
    local custom_buffer = vim.api.nvim_get_current_buf()
    local custom_card = parser.parse_buffer(custom_buffer)[1]
    local writer_calls = 0
    local custom_group = vim.api.nvim_create_augroup("neorg_flashcards_test_custom_writer", { clear = true })
    vim.api.nvim_create_autocmd("BufWriteCmd", {
      group = custom_group,
      pattern = custom_path,
      callback = function(args)
        writer_calls = writer_calls + 1
        vim.fn.writefile(vim.api.nvim_buf_get_lines(args.buf, 0, -1, false), custom_path)
        vim.bo[args.buf].modified = false
      end,
    })

    local custom_ok, custom_message, custom_persisted = store.set_card_fields(custom_card, {
      { field = "score", value = "2" },
    })
    assert_true(
      custom_ok,
      string.format(
        "%s\npath=%s\nname=%s\nautocmds=%s",
        tostring(custom_message),
        custom_path,
        vim.api.nvim_buf_get_name(custom_buffer),
        vim.inspect(vim.api.nvim_get_autocmds({ event = "BufWriteCmd" }))
      )
    )
    assert_equal(custom_persisted, false, "custom-write buffers remain explicitly unpersisted")
    assert_contains(custom_message, "custom-write buffer", "custom-write ownership is explained to the user")
    assert_equal(writer_calls, 0, "the plugin does not invoke an existing matching BufWriteCmd")
    assert_true(vim.bo[custom_buffer].modified, "the plugin leaves the custom-write buffer modified")
    assert_true(
      not table.concat(vim.fn.readfile(custom_path), "\n"):find("score: 2", 1, true),
      "the plugin does not bypass the custom writer to update disk"
    )
    assert_contains(
      table.concat(vim.api.nvim_buf_get_lines(custom_buffer, 0, -1, false), "\n"),
      "score: 2",
      "the pending metadata remains visible in the custom-write buffer"
    )

    vim.cmd("write")
    assert_equal(writer_calls, 1, "a manual write invokes the authoritative custom BufWriteCmd")
    assert_true(not vim.bo[custom_buffer].modified, "the custom writer can mark its manual write clean")
    assert_contains(
      table.concat(vim.fn.readfile(custom_path), "\n"),
      "score: 2",
      "the custom writer persists the buffered metadata on manual write"
    )
    vim.api.nvim_del_augroup_by_id(custom_group)
    vim.cmd("silent! bwipeout!")
  end

  do
    local pending_path = config.flashcards_dir .. "/persistence-pending.norg"
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_pending_first",
      "japanese: 東",
      "english: east",
      "@end",
      "",
      "@flashcard japanese",
      "id: fc_pending_second",
      "japanese: 西",
      "english: west",
      "@end",
    }, pending_path)
    vim.cmd.edit(vim.fn.fnameescape(pending_path))
    vim.api.nvim_buf_set_lines(0, 2, 2, false, { "notes: unsaved user edit" })
    assert_true(vim.bo.modified, "pending-history fixture begins with a modified source buffer")

    local before_entries, before_errors = history.read(config)
    assert_equal(#before_errors, 0, "pending-history baseline is readable")
    vim.cmd("Flashcards review file")
    assert_true(review_engine.rate_current(3), "first rating is accepted in a modified source buffer")
    assert_true(review_engine.rate_current(2), "second rating is accepted in the same modified source buffer")
    assert_true(flashcards.get_review_state().completed, "modified-buffer review reaches finite completion")
    flashcards.close_review()

    local queued_entries, queued_errors = history.read(config)
    assert_equal(#queued_errors, 0, "queued history remains readable")
    assert_equal(
      #queued_entries,
      #before_entries,
      "ratings in an unsaved modified buffer do not enter durable history early"
    )

    vim.cmd("write")
    local flushed_entries, flushed_errors = history.read(config)
    assert_equal(#flushed_errors, 0, "history remains readable after pending ratings flush")
    assert_equal(#flushed_entries, #before_entries + 2, "BufWritePost flushes every pending rating exactly once")
    assert_equal(flushed_entries[#flushed_entries - 1].rating, 3, "pending ratings preserve their original order")
    assert_equal(flushed_entries[#flushed_entries].rating, 2, "later pending ratings remain later in history")
    assert_true(flushed_entries[#flushed_entries - 1].persisted, "flushed events are marked persisted")
    assert_true(flushed_entries[#flushed_entries].persisted, "every flushed event is marked persisted")
    vim.cmd("silent! bwipeout!")
    assert_equal(vim.fn.delete(pending_path), 0, "pending-history fixture is removed from the collection")
  end

  do
    local undo_path = config.flashcards_dir .. "/persistence-undo.norg"
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_pending_undo",
      "japanese: 北",
      "english: north",
      "@end",
    }, undo_path)
    vim.cmd.edit(vim.fn.fnameescape(undo_path))
    vim.api.nvim_buf_set_lines(0, 2, 2, false, { "notes: another unsaved edit" })

    local before_entries, before_errors = history.read(config)
    assert_equal(#before_errors, 0, "undo-cancellation history baseline is readable")
    vim.cmd("Flashcards review file")
    assert_true(review_engine.rate_current(3), "modified-buffer rating can be queued before undo")
    assert_true(flashcards.undo_last_rating(), "queued rating can be undone before the source is saved")
    flashcards.close_review()

    vim.cmd("write")
    local after_entries, after_errors = history.read(config)
    assert_equal(#after_errors, 0, "history remains readable after saving an undone rating")
    assert_equal(
      #after_entries,
      #before_entries,
      "undo before save cancels its pending rating instead of writing a rated/undo pair"
    )
    vim.cmd("silent! bwipeout!")
    assert_equal(vim.fn.delete(undo_path), 0, "undo fixture is removed from the collection")
  end

  do
    local undo_path = config.flashcards_dir .. "/persistence-durable-then-dirty-undo.norg"
    local original_lines = {
      "@flashcard japanese",
      "id: fc_durable_then_dirty_undo",
      "japanese: 戻す",
      "english: restore",
      "@end",
    }
    vim.fn.writefile(original_lines, undo_path)
    vim.cmd.edit(vim.fn.fnameescape(undo_path))
    local source_buffer = vim.api.nvim_get_current_buf()

    local before_entries, before_errors = history.read(config)
    assert_equal(#before_errors, 0, "durable-then-dirty undo history baseline is readable")
    vim.cmd("Flashcards review file")
    assert_true(review_engine.rate_current(3), "clean-buffer rating persists before the undo fixture becomes dirty")
    local rated_entries, rated_errors = history.read(config)
    assert_equal(#rated_errors, 0, "durable rating history remains readable")
    assert_equal(#rated_entries, #before_entries + 1, "clean-buffer rating enters durable history immediately")
    assert_equal(rated_entries[#rated_entries].event, "rated", "first durable event records the rating")
    local rated_disk_lines = vim.fn.readfile(undo_path)
    assert_contains(table.concat(rated_disk_lines, "\n"), "score: 3", "clean-buffer rating reaches disk")
    assert_equal(
      table.concat(vim.api.nvim_buf_get_lines(source_buffer, 0, -1, false), "\n"),
      table.concat(rated_disk_lines, "\n"),
      "source buffer and disk match before marking the source modified"
    )

    vim.bo[source_buffer].modified = true
    local undo_ok, undo_message, undo_persisted = flashcards.undo_last_rating()
    assert_true(undo_ok, undo_message)
    assert_equal(undo_persisted, false, "undo reports that its dirty-buffer reversal is not yet persisted")
    assert_true(vim.bo[source_buffer].modified, "unpersisted undo leaves the source buffer modified")
    assert_equal(
      table.concat(vim.api.nvim_buf_get_lines(source_buffer, 0, -1, false), "\n"),
      table.concat(original_lines, "\n"),
      "unpersisted undo restores the source text in the dirty buffer"
    )
    assert_equal(
      table.concat(vim.fn.readfile(undo_path), "\n"),
      table.concat(rated_disk_lines, "\n"),
      "unpersisted undo leaves the durable rating on disk until save"
    )
    local pending_entries, pending_errors = history.read(config)
    assert_equal(#pending_errors, 0, "history remains readable while the undo waits for source persistence")
    assert_equal(#pending_entries, #rated_entries, "unpersisted undo does not enter durable history early")

    flashcards.close_review()
    vim.api.nvim_set_current_buf(source_buffer)
    vim.cmd("write")
    local after_entries, after_errors = history.read(config)
    assert_equal(#after_errors, 0, "history remains readable after the undo source is saved")
    assert_equal(#after_entries, #before_entries + 2, "saved reversal retains both the rated and undo events")
    assert_equal(after_entries[#after_entries - 1].event, "rated", "durable history keeps the original rating")
    assert_equal(after_entries[#after_entries].event, "undo", "durable history appends the later undo")
    assert_equal(
      after_entries[#after_entries].undo_of,
      after_entries[#after_entries - 1].event_id,
      "durable undo identifies the rating it compensates"
    )
    assert_true(after_entries[#after_entries].persisted, "flushed undo history is marked persisted")
    assert_equal(
      table.concat(vim.fn.readfile(undo_path), "\n"),
      table.concat(original_lines, "\n"),
      "saving the unpersisted undo leaves the source fully reverted"
    )
    vim.cmd("silent! bwipeout!")
    assert_equal(vim.fn.delete(undo_path), 0, "durable-then-dirty undo fixture is removed")
  end

  do
    local discarded_path = config.flashcards_dir .. "/persistence-discarded.norg"
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_pending_discarded",
      "japanese: 南",
      "english: south",
      "@end",
    }, discarded_path)
    vim.cmd.edit(vim.fn.fnameescape(discarded_path))
    vim.api.nvim_buf_set_lines(0, 2, 2, false, { "notes: edit that will be discarded" })

    local before_entries, before_errors = history.read(config)
    assert_equal(#before_errors, 0, "discarded-buffer history baseline is readable")
    vim.cmd("Flashcards review file")
    assert_true(review_engine.rate_current(3), "modified-buffer rating is queued before buffer deletion")
    flashcards.close_review()

    vim.cmd("bdelete!")
    vim.cmd.edit(vim.fn.fnameescape(discarded_path))
    vim.api.nvim_buf_set_lines(0, 2, 2, false, { "notes: unrelated saved edit" })
    vim.cmd("write")

    local after_entries, after_errors = history.read(config)
    assert_equal(#after_errors, 0, "history remains readable after a dirty buffer is discarded")
    assert_equal(
      #after_entries,
      #before_entries,
      "deleting a dirty source buffer discards its queued rating before a later write to the same path"
    )
    vim.cmd("silent! bwipeout!")
    assert_equal(vim.fn.delete(discarded_path), 0, "discarded-history fixture is removed from the collection")
  end

  do
    local original_path = config.flashcards_dir .. "/persistence-saveas-original.norg"
    local renamed_path = config.flashcards_dir .. "/persistence-saveas-renamed.norg"
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_pending_saveas",
      "japanese: 上",
      "english: up",
      "@end",
    }, original_path)
    vim.cmd.edit(vim.fn.fnameescape(original_path))
    vim.api.nvim_buf_set_lines(0, 2, 2, false, { "notes: save under a new name" })

    local before_entries, before_errors = history.read(config)
    assert_equal(#before_errors, 0, "saveas history baseline is readable")
    vim.cmd("Flashcards review file")
    assert_true(review_engine.rate_current(2), "modified-buffer rating is queued before saveas")
    flashcards.close_review()
    vim.cmd("saveas! " .. vim.fn.fnameescape(renamed_path))

    local after_entries, after_errors = history.read(config)
    assert_equal(#after_errors, 0, "history remains readable after saveas")
    assert_equal(#after_entries, #before_entries + 1, "saveas flushes the queued rating exactly once")
    assert_equal(
      after_entries[#after_entries].path,
      canonical_path(renamed_path),
      "saveas history follows the buffer to its persisted path"
    )
    assert_equal(after_entries[#after_entries]._source_bufnr, nil, "internal buffer identity is not serialized")
    local stale_original_buf = vim.fn.bufnr(original_path)
    if stale_original_buf > 0 and vim.api.nvim_buf_is_valid(stale_original_buf) then
      vim.api.nvim_buf_delete(stale_original_buf, { force = true })
    end
    vim.cmd("silent! bwipeout!")
    assert_equal(vim.fn.delete(original_path), 0, "saveas source fixture is removed from the collection")
    assert_equal(vim.fn.delete(renamed_path), 0, "saveas destination fixture is removed from the collection")
  end

  do
    local reentry_path = config.flashcards_dir .. "/persistence-setup-reentry.norg"
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_pending_setup_reentry",
      "japanese: 中",
      "english: middle",
      "@end",
    }, reentry_path)
    vim.cmd.edit(vim.fn.fnameescape(reentry_path))
    vim.api.nvim_buf_set_lines(0, 2, 2, false, { "notes: pending across setup" })

    local before_entries, before_errors = history.read(config)
    assert_equal(#before_errors, 0, "setup-reentry history baseline is readable")
    vim.cmd("Flashcards review file")
    assert_true(review_engine.rate_current(3), "modified-buffer rating is queued before setup reentry")
    flashcards.close_review()

    local alternate_dir = vim.fn.tempname()
    local alternate_config = vim.tbl_deep_extend("force", {}, config, {
      flashcards_dir = alternate_dir,
      default_file = alternate_dir .. "/cards.norg",
    })
    flashcards.setup(alternate_config)
    vim.cmd("write")

    local after_entries, after_errors = history.read(config)
    assert_equal(#after_errors, 0, "history remains readable after setup reentry")
    assert_equal(#after_entries, #before_entries + 1, "setup reentry preserves and flushes pending ratings")
    local alternate_entries = history.read(alternate_config)
    assert_equal(#alternate_entries, 0, "pending history keeps its original destination across setup reentry")
    flashcards.setup(config)
    vim.cmd("silent! bwipeout!")
    assert_equal(vim.fn.delete(reentry_path), 0, "setup-reentry fixture is removed from the collection")
  end
end
