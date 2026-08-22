return function(T)
  local form = require("neorg_flashcards.form")
  local history = require("neorg_flashcards.history")
  local overview = require("neorg_flashcards.overview")
  local parser = require("neorg_flashcards.parser")
  local presets = require("neorg_flashcards.presets")
  local review_engine = require("neorg_flashcards.review")
  local util = require("neorg_flashcards.util")
  local flashcards = require("neorg_flashcards")

  local assert_true = T.assert_true
  local assert_equal = T.assert_equal
  local assert_contains = T.assert_contains
  local current_popup = T.current_popup
  local assert_buffer_maps = T.assert_buffer_maps
  local window_footer = T.window_footer
  local decoration_text = T.decoration_text

  do
    local uv = vim.uv or vim.loop
    local configured_root = vim.fn.tempname()
    local moved_root = configured_root .. "-moved"
    local outside_root = vim.fn.tempname()
    local card_path = configured_root .. "/cards.norg"
    local moved_card_path = moved_root .. "/cards.norg"
    local outside_card_path = outside_root .. "/cards.norg"
    local card_lines = {
      "@flashcard japanese",
      "id: fc_retargeted_root",
      "japanese: 境界",
      "english: boundary",
      "@end",
    }
    vim.fn.mkdir(configured_root, "p")
    vim.fn.mkdir(outside_root, "p")
    vim.fn.writefile(card_lines, card_path)
    vim.fn.writefile(card_lines, outside_card_path)

    flashcards.setup({
      flashcards_dir = configured_root,
      default_file = card_path,
      default_kind = "japanese",
      schemas = presets.only("japanese"),
    })
    local retargeted_card = parser.parse_file(card_path)[1]
    local renamed, rename_error = uv.fs_rename(configured_root, moved_root)
    assert_true(renamed, "configured collection can be moved for the retarget fixture: " .. tostring(rename_error))
    local linked, link_error = uv.fs_symlink(outside_root, configured_root, { dir = true })
    assert_true(linked, "configured collection path can be retargeted: " .. tostring(link_error))

    local source_ok, source_error = flashcards.toggle_suspend(retargeted_card, {
      cards = { retargeted_card },
    })
    assert_true(not source_ok, "card writes refuse a collection path retargeted after setup")
    assert_contains(source_error, "flashcards_dir", "retargeted card writes explain which boundary changed")
    assert_equal(
      table.concat(vim.fn.readfile(outside_card_path), "\n"),
      table.concat(card_lines, "\n"),
      "refused card writes leave the replacement collection untouched"
    )
    assert_equal(
      table.concat(vim.fn.readfile(moved_card_path), "\n"),
      table.concat(card_lines, "\n"),
      "refused card writes also leave the original collection untouched"
    )

    local retargeted_event = assert(history.new_event(retargeted_card, 3, os.time(), {
      event_id = "retargeted-root-history",
    }))
    local history_ok, history_error = history.append(retargeted_event)
    assert_true(not history_ok, "history append refuses a collection path retargeted after setup")
    assert_contains(history_error, "flashcards_dir", "retargeted history explains which boundary changed")
    assert_equal(
      vim.fn.filereadable(outside_root .. "/" .. history.FILENAME),
      0,
      "refused history append does not create history in the replacement collection"
    )
    flashcards.setup(T.config)
  end

  do
    local uv = vim.uv or vim.loop
    local configured_root = vim.fn.tempname()
    local moved_root = configured_root .. "-moved"
    vim.fn.mkdir(configured_root, "p")
    flashcards.setup({
      flashcards_dir = configured_root,
      default_file = configured_root .. "/cards.norg",
      default_kind = "japanese",
      schemas = presets.only("japanese"),
    })

    local captured_destination, capture_error = history.path()
    assert_true(
      captured_destination ~= nil,
      "configured history destination can be captured: " .. tostring(capture_error)
    )
    local baseline_event = assert(history.new_event({ values = { id = "fc_captured_root_baseline" } }, 3, os.time(), {
      event_id = "captured-root-baseline",
    }))
    local baseline_ok, baseline_error = history.append(baseline_event)
    assert_true(baseline_ok, "baseline history is stored before replacing its directory: " .. tostring(baseline_error))
    local baseline_lines = vim.fn.readfile(captured_destination)

    local renamed, rename_error = uv.fs_rename(configured_root, moved_root)
    assert_true(renamed, "captured-history root can be moved for the replacement fixture: " .. tostring(rename_error))
    assert_equal(vim.fn.mkdir(configured_root, "p"), 1, "a fresh ordinary directory replaces the captured root path")
    assert_equal(uv.fs_lstat(configured_root).type, "directory", "captured root replacement is not a symbolic link")
    vim.fn.writefile({ "replacement root sentinel" }, configured_root .. "/keep.txt")
    local replacement_entries = vim.fn.readdir(configured_root)

    local replacement_event =
      assert(history.new_event({ values = { id = "fc_captured_root_replacement" } }, 2, os.time(), {
        event_id = "captured-root-replacement",
      }))
    local append_ok, append_error = history.append(replacement_event, captured_destination)
    assert_true(not append_ok, "captured history strings reject an ordinary parent directory replacement")
    assert_contains(append_error, "setup again", "captured history replacement explains how to recover")
    assert_equal(
      table.concat(vim.fn.readdir(configured_root), "\n"),
      table.concat(replacement_entries, "\n"),
      "refused captured history append creates no files in the replacement root"
    )
    assert_equal(
      table.concat(vim.fn.readfile(moved_root .. "/" .. history.FILENAME), "\n"),
      table.concat(baseline_lines, "\n"),
      "refused captured history append does not mutate the moved original history"
    )
    flashcards.setup(T.config)
  end

  do
    local uv = vim.uv or vim.loop
    local configured_root = vim.fn.tempname()
    local moved_root = configured_root .. "-moved"
    local same_path_config = {
      flashcards_dir = configured_root,
      default_file = configured_root .. "/cards.norg",
      default_kind = "japanese",
      schemas = presets.only("japanese"),
    }
    vim.fn.mkdir(configured_root, "p")
    flashcards.setup(same_path_config)

    local old_destination, old_capture_error = history.capture()
    assert_true(
      old_destination ~= nil,
      "first setup captures an immutable history destination: " .. tostring(old_capture_error)
    )
    local baseline_event = assert(history.new_event({ values = { id = "fc_old_setup_baseline" } }, 3, os.time(), {
      event_id = "old-setup-baseline",
    }))
    local baseline_ok, baseline_error = history.append(baseline_event, old_destination)
    assert_true(baseline_ok, "first setup stores baseline history: " .. tostring(baseline_error))
    local baseline_lines = vim.fn.readfile(configured_root .. "/" .. history.FILENAME)

    local renamed, rename_error = uv.fs_rename(configured_root, moved_root)
    assert_true(renamed, "first setup root can be moved for same-path reconfiguration: " .. tostring(rename_error))
    assert_equal(vim.fn.mkdir(configured_root, "p"), 1, "same-path reconfiguration receives a fresh ordinary directory")
    flashcards.setup(same_path_config)
    local new_destination, new_capture_error = history.capture()
    assert_true(
      new_destination ~= nil,
      "second setup captures its new history destination: " .. tostring(new_capture_error)
    )
    assert_true(
      history.destination_key(old_destination) ~= history.destination_key(new_destination),
      "same-path setups have distinct immutable destination identities"
    )

    local replacement_event = assert(history.new_event({ values = { id = "fc_new_setup_history" } }, 2, os.time(), {
      event_id = "new-setup-history",
    }))
    local replacement_ok, replacement_error = history.append(replacement_event, new_destination)
    assert_true(replacement_ok, "the fresh setup can write its own history: " .. tostring(replacement_error))
    local replacement_lines = vim.fn.readfile(configured_root .. "/" .. history.FILENAME)

    local stale_event = assert(history.new_event({ values = { id = "fc_stale_setup_history" } }, 1, os.time(), {
      event_id = "stale-setup-history",
    }))
    local stale_ok, stale_error = history.append(stale_event, old_destination)
    assert_true(not stale_ok, "a same-path setup cannot re-authorize an older destination token")
    assert_contains(stale_error, "setup again", "stale immutable destination explains how to recover")
    assert_equal(
      table.concat(vim.fn.readfile(configured_root .. "/" .. history.FILENAME), "\n"),
      table.concat(replacement_lines, "\n"),
      "stale destination cannot append to the replacement setup history"
    )
    assert_equal(
      table.concat(vim.fn.readfile(moved_root .. "/" .. history.FILENAME), "\n"),
      table.concat(baseline_lines, "\n"),
      "stale destination cannot mutate the moved original history"
    )
    flashcards.setup(T.config)
  end

  do
    local uv = vim.uv or vim.loop
    local collection_root = vim.fn.tempname()
    local default_path = collection_root .. "/cards.norg"
    local outside_path = vim.fn.tempname() .. ".norg"
    local sentinel_path = vim.fn.tempname() .. ".norg"
    local outside_lines = { "* Outside file", "do not touch" }
    vim.fn.mkdir(collection_root, "p")
    vim.fn.writefile(outside_lines, outside_path)
    vim.fn.writefile({ "* Safe buffer" }, sentinel_path)

    flashcards.setup({
      flashcards_dir = collection_root,
      default_file = default_path,
      default_kind = "japanese",
      schemas = presets.only("japanese"),
    })
    local linked, link_error = uv.fs_symlink(outside_path, default_path)
    assert_true(linked, "post-setup default-file symlink fixture is created: " .. tostring(link_error))
    vim.cmd.edit(vim.fn.fnameescape(sentinel_path))
    local sentinel_buffer = vim.api.nvim_get_current_buf()

    local messages = {}
    local notify_original = vim.notify
    vim.notify = function(message)
      table.insert(messages, tostring(message))
    end
    local open_ok = flashcards.open_flashcards()
    flashcards.add_to_default("japanese")
    vim.notify = notify_original

    assert_true(not open_ok, "open refuses a default-file symlink whose target is outside the collection")
    assert_equal(
      vim.api.nvim_get_current_buf(),
      sentinel_buffer,
      "refused open keeps the user's current buffer focused"
    )
    assert_true(not form.is_open(), "add-to-default rejects the unsafe destination before opening the composer")
    assert_equal(
      table.concat(vim.fn.readfile(outside_path), "\n"),
      table.concat(outside_lines, "\n"),
      "refused open and add leave the outside target untouched"
    )
    assert_equal(uv.fs_lstat(default_path).type, "link", "refused commands leave the unsafe link in place for repair")
    assert_contains(
      table.concat(messages, "\n"),
      "flashcards_dir",
      "unsafe open and add report the configured collection boundary"
    )
    vim.cmd("silent! bwipeout!")
    flashcards.setup(T.config)
  end

  do
    local boundary_dir = vim.fn.tempname()
    vim.fn.mkdir(boundary_dir, "p")
    local boundary_config = { flashcards_dir = boundary_dir }
    local captured_destination = history.path(boundary_config)
    local outside_history = vim.fn.tempname() .. ".jsonl"
    vim.fn.writefile({ "outside evidence" }, outside_history)
    local linked, link_error = (vim.uv or vim.loop).fs_symlink(outside_history, captured_destination)
    assert_true(linked, "post-setup history symlink fixture is created: " .. tostring(link_error))
    local boundary_event = assert(history.new_event({ values = { id = "fc_history_boundary" } }, 3, os.time(), {
      event_id = "history-boundary-event",
    }))
    local config_ok, config_error = history.append(boundary_event, boundary_config)
    assert_true(not config_ok, "history refuses a configured destination redirected outside its collection")
    assert_contains(config_error, "inside flashcards_dir", "history boundary failure names the collection constraint")
    local captured_ok, captured_error = history.append(boundary_event, captured_destination)
    assert_true(not captured_ok, "history refuses a captured destination replaced by a symbolic link")
    assert_contains(captured_error, "symbolic link", "captured history refusal names the unsafe replacement")
    assert_equal(
      table.concat(vim.fn.readfile(outside_history), "\n"),
      "outside evidence",
      "refused history writes leave the symlink target untouched"
    )
  end

  do
    local merge_dir = vim.fn.tempname()
    local merge_config = { flashcards_dir = merge_dir }
    local first = assert(history.new_event({ values = { id = "fc_outbox_merge_first" } }, 3, os.time(), {
      event_id = "outbox-merge-first",
    }))
    local second = assert(history.new_event({ values = { id = "fc_outbox_merge_second" } }, 2, os.time() + 1, {
      event_id = "outbox-merge-second",
    }))
    local merge_outbox = history.outbox_path(merge_config)
    vim.fn.mkdir(vim.fn.fnamemodify(merge_outbox, ":h"), "p")
    vim.fn.writefile({ "99999999:dead-outbox-owner" }, merge_outbox .. ".lock")
    vim.fn.writefile({ "99999998:dead-outbox-reaper" }, merge_outbox .. ".lock.reap")
    assert_true(history.write_outbox(merge_config, { first }), "first instance writes its outbox event")
    assert_equal(vim.fn.filereadable(merge_outbox .. ".lock"), 0, "a demonstrably dead outbox owner is recovered")
    assert_equal(
      vim.fn.filereadable(merge_outbox .. ".lock.reap"),
      0,
      "a demonstrably dead reaper cannot permanently block recovery"
    )
    assert_true(history.write_outbox(merge_config, { second }), "second instance merges its outbox event")
    assert_true(history.write_outbox(merge_config, { first }), "repeated outbox writes are idempotent by event ID")

    local merged, merge_errors = history.read_outbox(merge_config)
    assert_equal(#merge_errors, 0, "merged outbox remains readable")
    assert_equal(#merged, 2, "independent outbox updates do not replace one another")
    assert_equal(merged[1].event_id, "outbox-merge-first", "merged outbox retains the first writer")
    assert_equal(merged[2].event_id, "outbox-merge-second", "merged outbox retains the second writer")

    assert_true(history.remove_outbox(merge_config, { first }), "delivered events can be removed precisely")
    local remaining = history.read_outbox(merge_config)
    assert_equal(#remaining, 1, "targeted removal preserves another instance's event")
    assert_equal(remaining[1].event_id, "outbox-merge-second", "targeted removal keeps the unrelated event")
    assert_true(history.remove_outbox(merge_config, { second }), "the final delivered event can be removed")
    assert_equal(vim.fn.filereadable(history.outbox_path(merge_config)), 0, "an empty clean outbox is removed")
  end

  do
    local corrupt_dir = vim.fn.tempname()
    local corrupt_path = corrupt_dir .. "/cards.norg"
    vim.fn.mkdir(corrupt_dir, "p")
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_outbox_corrupt",
      "japanese: 証",
      "english: evidence",
      "@end",
    }, corrupt_path)
    local corrupt_config = {
      flashcards_dir = corrupt_dir,
      default_file = corrupt_path,
      default_kind = "japanese",
      schemas = presets.only("japanese"),
    }
    local valid_event = assert(history.new_event({ values = { id = "fc_outbox_corrupt" } }, 3, os.time(), {
      event_id = "outbox-valid-peer",
    }))
    local corrupt_line = '{"version":1,"event":"rated"'
    local corrupt_outbox = history.outbox_path(corrupt_config)
    vim.fn.mkdir(vim.fn.fnamemodify(corrupt_outbox, ":h"), "p")
    vim.fn.writefile({ vim.json.encode(valid_event), corrupt_line }, corrupt_outbox)

    flashcards.setup(corrupt_config)
    local drained_entries, drained_errors = history.read(corrupt_config)
    assert_equal(#drained_errors, 0, "valid peer from a mixed outbox reaches history")
    assert_equal(#drained_entries, 1, "setup drains the valid line beside corrupt evidence")
    assert_equal(drained_entries[1].event_id, "outbox-valid-peer", "mixed-outbox drain keeps event identity")
    assert_equal(
      vim.fn.readfile(corrupt_outbox)[1],
      corrupt_line,
      "draining valid peers preserves the exact corrupt outbox line"
    )
    local pending_after_drain, corrupt_errors = history.read_outbox(corrupt_config)
    assert_equal(#pending_after_drain, 0, "only the corrupt evidence remains queued")
    assert_equal(#corrupt_errors, 1, "preserved corrupt evidence remains visible to health checks")

    flashcards.setup(corrupt_config)
    assert_equal(
      vim.fn.readfile(corrupt_outbox)[1],
      corrupt_line,
      "a later startup never deletes previously reported corrupt evidence"
    )
  end

  do
    local real_dir = vim.fn.tempname()
    local alias_dir = vim.fn.tempname()
    local real_path = real_dir .. "/cards.norg"
    vim.fn.mkdir(real_dir, "p")
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_outbox_symlink",
      "japanese: 結",
      "english: link",
      "@end",
    }, real_path)
    local linked, link_error = (vim.uv or vim.loop).fs_symlink(real_dir, alias_dir, { dir = true })
    assert_true(linked ~= nil, "symlink fixture can be created: " .. tostring(link_error))
    local real_config = {
      flashcards_dir = real_dir,
      default_file = real_path,
      default_kind = "japanese",
      schemas = presets.only("japanese"),
    }
    local alias_config = vim.tbl_deep_extend("force", {}, real_config, {
      flashcards_dir = alias_dir,
      default_file = alias_dir .. "/cards.norg",
    })
    assert_equal(history.path(alias_config), history.path(real_config), "symlink spellings share history identity")
    assert_equal(
      history.outbox_path(alias_config),
      history.outbox_path(real_config),
      "symlink spellings share one durable outbox"
    )

    local linked_event = assert(history.new_event({ values = { id = "fc_outbox_symlink" } }, 3, os.time(), {
      event_id = "outbox-symlink-event",
    }))
    assert_true(history.write_outbox(real_config, { linked_event }), "real-path spelling writes the retry event")
    flashcards.setup(alias_config)
    local linked_entries, linked_errors = history.read(real_config)
    assert_equal(#linked_errors, 0, "symlink-drained history remains readable")
    assert_equal(#linked_entries, 1, "alias setup discovers and drains the real-path retry")
    assert_equal(linked_entries[1].event_id, "outbox-symlink-event", "symlink drain preserves event identity")
    assert_equal(vim.fn.filereadable(history.outbox_path(real_config)), 0, "symlink drain clears the shared outbox")
  end

  do
    local restart_dir = vim.fn.tempname()
    local restart_path = restart_dir .. "/cards.norg"
    vim.fn.mkdir(restart_dir, "p")
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_outbox_restart",
      "japanese: 再開",
      "english: restart",
      "@end",
    }, restart_path)
    local restart_config = {
      flashcards_dir = restart_dir,
      default_file = restart_path,
      default_kind = "japanese",
      schemas = presets.only("japanese"),
    }
    local restart_event = assert(history.new_event({ values = { id = "fc_outbox_restart" } }, 3, os.time(), {
      event_id = "fc_outbox_restart_event",
    }))
    local outbox_ok, outbox_error = history.write_outbox(restart_config, { restart_event })
    assert_true(outbox_ok, "failed review history can be persisted: " .. tostring(outbox_error))
    assert_equal(vim.fn.filereadable(history.outbox_path(restart_config)), 1, "restart outbox exists before setup")

    flashcards.setup(restart_config)
    local restarted_entries, restarted_errors = history.read(restart_config)
    assert_equal(#restarted_errors, 0, "restart-drained history remains readable")
    assert_equal(#restarted_entries, 1, "setup loads and drains persisted retry events")
    assert_equal(restarted_entries[1].event_id, "fc_outbox_restart_event", "restart drain preserves event identity")
    assert_equal(vim.fn.filereadable(history.outbox_path(restart_config)), 0, "successful restart drain clears outbox")
  end

  do
    local failure_dir = vim.fn.tempname()
    local failure_path = failure_dir .. "/cards.norg"
    vim.fn.mkdir(failure_dir, "p")
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_history_append_failure",
      "japanese: 失",
      "english: fail",
      "@end",
    }, failure_path)

    local observed_event = nil
    flashcards.setup({
      flashcards_dir = failure_dir,
      default_file = failure_path,
      default_kind = "japanese",
      schemas = presets.only("japanese"),
      on_review = function(event)
        observed_event = event
      end,
    })
    vim.cmd.edit(vim.fn.fnameescape(failure_path))

    local append_original = history.append
    local refresh_original = overview.refresh
    local append_attempts, refreshes = 0, 0
    history.append = function()
      append_attempts = append_attempts + 1
      return false, "forced history append failure"
    end
    overview.refresh = function()
      refreshes = refreshes + 1
    end
    local failure_messages = {}
    local failure_notify_original = vim.notify
    vim.notify = function(message)
      table.insert(failure_messages, tostring(message))
    end

    vim.cmd("Flashcards review file")
    assert_true(review_engine.rate_current(3), "source rating succeeds when history append fails")
    flashcards.close_review()
    local queued_outbox, queued_outbox_errors = history.read_outbox({ flashcards_dir = failure_dir })
    assert_equal(#queued_outbox_errors, 0, "failed-history outbox remains readable")
    assert_equal(#queued_outbox, 1, "failed persisted rating is durably queued before retry")

    vim.notify = failure_notify_original
    history.append = append_original
    overview.refresh = refresh_original
    vim.cmd("doautocmd FocusGained")
    local recovered_entries, recovered_errors = history.read({
      flashcards_dir = failure_dir,
    })
    assert_equal(append_attempts, 1, "persisted rating attempts history append once")
    assert_true(
      observed_event ~= nil and observed_event.persisted,
      "user review callback still observes the persisted rating"
    )
    assert_true(refreshes > 0, "history failure still refreshes the hub state")
    assert_contains(
      table.concat(failure_messages, "\n"),
      "forced history append failure",
      "history failure is reported"
    )
    assert_equal(#recovered_errors, 0, "retried review history remains readable")
    assert_equal(#recovered_entries, 1, "a transient history failure is retried instead of losing the persisted rating")
    assert_equal(recovered_entries[1].card_id, "fc_history_append_failure", "history retry preserves card identity")
    assert_contains(
      table.concat(vim.fn.readfile(failure_path), "\n"),
      "score: 3",
      "history failure does not roll back a successfully persisted source rating"
    )
    vim.cmd("silent! bwipeout!")
  end

  do
    local contention_dir = vim.fn.tempname()
    local contention_path = contention_dir .. "/cards.norg"
    vim.fn.mkdir(contention_dir, "p")
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_history_double_contention",
      "japanese: 保",
      "english: retain",
      "@end",
    }, contention_path)
    local contention_config = {
      flashcards_dir = contention_dir,
      default_file = contention_path,
      default_kind = "japanese",
      schemas = presets.only("japanese"),
    }
    flashcards.setup(contention_config)
    vim.cmd.edit(vim.fn.fnameescape(contention_path))

    local append_original = history.append
    local outbox_original = history.write_outbox
    history.append = function()
      return false, "forced history lock contention"
    end
    history.write_outbox = function()
      return false, "forced outbox lock contention"
    end
    vim.cmd("Flashcards review file")
    assert_true(review_engine.rate_current(3), "source rating persists during simultaneous history/outbox contention")
    flashcards.close_review()
    assert_contains(
      table.concat(vim.fn.readfile(contention_path), "\n"),
      "score: 3",
      "double contention does not roll back the persisted source rating"
    )

    history.append = append_original
    history.write_outbox = outbox_original
    vim.cmd("doautocmd FocusGained")
    local contention_entries, contention_errors = history.read(contention_config)
    assert_equal(#contention_errors, 0, "in-memory emergency retry reaches readable history")
    assert_equal(#contention_entries, 1, "append and outbox contention does not lose the persisted event")
    assert_equal(
      contention_entries[1].card_id,
      "fc_history_double_contention",
      "emergency retry preserves the contended event identity"
    )
    local contention_outbox = history.read_outbox(contention_config)
    assert_equal(#contention_outbox, 0, "successful emergency retry drains its durable outbox")
    vim.cmd("silent! bwipeout!")
  end

  do
    local old_dir = vim.fn.tempname()
    local old_path = old_dir .. "/cards.norg"
    local new_dir = vim.fn.tempname()
    local new_path = new_dir .. "/cards.norg"
    vim.fn.mkdir(old_dir, "p")
    vim.fn.mkdir(new_dir, "p")
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_retry_order_one",
      "japanese: 一",
      "english: one",
      "@end",
      "",
      "@flashcard japanese",
      "id: fc_retry_order_two",
      "japanese: 二",
      "english: two",
      "@end",
    }, old_path)
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_retry_new_destination",
      "japanese: 新",
      "english: new",
      "@end",
    }, new_path)

    local old_config = {
      flashcards_dir = old_dir,
      default_file = old_path,
      default_kind = "japanese",
      schemas = presets.only("japanese"),
    }
    local new_config = {
      flashcards_dir = new_dir,
      default_file = new_path,
      default_kind = "japanese",
      schemas = presets.only("japanese"),
    }
    local old_history_path = history.path(old_config)
    local append_original = history.append
    local retry_order = {}
    old_config.on_review = function(event)
      if event.event == "rated" then
        table.insert(retry_order, event.card_id)
      end
    end
    history.append = function(event, destination)
      if history.path(destination) == old_history_path then
        return false, "old history destination remains unavailable"
      end
      return append_original(event, destination)
    end

    flashcards.setup(old_config)
    vim.cmd.edit(vim.fn.fnameescape(old_path))
    vim.cmd("Flashcards review file")
    assert_true(review_engine.rate_current(3), "first failed-history rating persists its source")
    assert_true(review_engine.rate_current(2), "second failed-history rating persists its source")
    flashcards.close_review()

    flashcards.setup(new_config)
    vim.cmd.edit(vim.fn.fnameescape(new_path))
    vim.cmd("Flashcards review file")
    assert_true(review_engine.rate_current(3), "a stale history path does not block the new destination")
    flashcards.close_review()

    local new_entries, new_errors = history.read(new_config)
    assert_equal(#new_errors, 0, "the reconfigured destination remains readable")
    assert_equal(#new_entries, 1, "the reconfigured destination receives its review immediately")
    assert_equal(new_entries[1].card_id, "fc_retry_new_destination", "the new destination receives the right event")

    history.append = append_original
    vim.cmd("doautocmd FocusGained")
    local old_entries, old_errors = history.read(old_config)
    assert_equal(#old_errors, 0, "the recovered old destination remains readable")
    assert_equal(#old_entries, 2, "both queued events reach the recovered old destination")
    assert_equal(old_entries[1].card_id, retry_order[1], "same-destination retry keeps first-in order")
    assert_equal(old_entries[2].card_id, retry_order[2], "same-destination retry keeps second-in order")

    vim.cmd("doautocmd FocusGained")
    old_entries = history.read(old_config)
    new_entries = history.read(new_config)
    assert_equal(#old_entries, 2, "repeated drains do not duplicate old-destination events")
    assert_equal(#new_entries, 1, "repeated drains do not duplicate new-destination events")
    vim.cmd("silent! bwipeout!")
  end

  do
    local state_dir = vim.fn.tempname()
    local state_path = state_dir .. "/cards.norg"
    vim.fn.mkdir(state_dir, "p")
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_state_event",
      "japanese: 別",
      "english: separate",
      "@end",
    }, state_path)

    local state_events = {}
    flashcards.setup({
      flashcards_dir = state_dir,
      default_file = state_path,
      default_kind = "japanese",
      schemas = presets.only("japanese"),
      on_review = function(event)
        table.insert(state_events, event)
      end,
    })
    vim.cmd.edit(vim.fn.fnameescape(state_path))
    vim.cmd("Flashcards review file")
    assert_true(flashcards.suspend_current(), "review can suspend a canonically identified card")

    local suspended_event = state_events[#state_events]
    assert_equal(suspended_event.event, "suspended", "suspend emits a card-state event")
    assert_equal(suspended_event.card_id, "fc_state_event", "card-state events keep the canonical card ID")
    local stored_state_events, stored_state_errors = history.read({ flashcards_dir = state_dir })
    assert_equal(#stored_state_errors, 0, "persisted state events remain readable")
    assert_equal(#stored_state_events, 1, "state events are written to history")
    assert_true(
      not util.isempty(stored_state_events[1].event_id),
      "durable state events receive a stable ID before append or retry"
    )
    flashcards.close_review()
    vim.cmd("silent! bwipeout!")

    local pending_state_path = state_dir .. "/pending-state.norg"
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_pending_state_event",
      "japanese: 未保存",
      "english: unsaved",
      "@end",
    }, pending_state_path)
    vim.cmd.edit(vim.fn.fnameescape(pending_state_path))
    vim.api.nvim_buf_set_lines(0, 2, 2, false, { "notes: keep this edit" })
    vim.cmd("Flashcards review file")
    assert_true(flashcards.suspend_current(), "dirty-buffer state changes are accepted in memory")
    flashcards.close_review()
    local before_state_save = history.read({ flashcards_dir = state_dir })
    assert_equal(#before_state_save, 1, "dirty-buffer state events wait for their source save")
    vim.cmd("write")
    local after_state_save = history.read({ flashcards_dir = state_dir })
    assert_equal(#after_state_save, 2, "saving a dirty source flushes its pending state event")
    assert_equal(after_state_save[2].card_id, "fc_pending_state_event", "pending state history keeps card identity")
    vim.cmd("silent! bwipeout!")

    local direct_state_path = state_dir .. "/direct-state.norg"
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_direct_state_event",
      "japanese: 直接",
      "english: direct",
      "@end",
    }, direct_state_path)
    local direct_card = parser.parse_file(direct_state_path)[1]
    local before_direct = history.read({ flashcards_dir = state_dir })
    local direct_ok, direct_message, direct_persisted = flashcards.toggle_suspend(direct_card, {
      cards = { direct_card },
    })
    assert_true(direct_ok, direct_message)
    assert_true(direct_persisted, "public card-state changes persist an unloaded source")
    local after_direct, direct_errors = history.read({ flashcards_dir = state_dir })
    assert_equal(#direct_errors, 0, "public card-state history remains readable")
    assert_equal(#after_direct, #before_direct + 1, "public card-state changes append history")
    assert_equal(after_direct[#after_direct].event, "suspended", "public state history names the transition")
    assert_equal(
      after_direct[#after_direct].card_id,
      "fc_direct_state_event",
      "public state history keeps card identity"
    )

    vim.cmd("Flashcards cards")
    local before_hub = history.read({ flashcards_dir = state_dir })
    overview.toggle_suspend()
    local after_hub, hub_errors = history.read({ flashcards_dir = state_dir })
    assert_equal(#hub_errors, 0, "hub card-state history remains readable")
    assert_equal(#after_hub, #before_hub + 1, "hub card-state changes append history")
    assert_equal(after_hub[#after_hub].type, "card_state", "hub writes a card-state event")
    overview.close()
  end
  do
    local hidden_dir = vim.fn.tempname()
    local hidden_path = hidden_dir .. "/cards.norg"
    vim.fn.mkdir(hidden_dir, "p")
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_hidden_shortcuts",
      "japanese: 隠",
      "english: hidden",
      "@end",
    }, hidden_path)

    flashcards.setup({
      flashcards_dir = hidden_dir,
      default_file = hidden_path,
      default_kind = "japanese",
      schemas = presets.only("japanese"),
      ui = { show_shortcuts = false },
    })

    vim.cmd("Flashcards cards")
    local hidden_hub_buf = vim.api.nvim_get_current_buf()
    assert_buffer_maps(hidden_hub_buf, { "?" })
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local statusline = vim.wo[win].statusline
      assert_true(not statusline:find("keys", 1, true), "hidden hub chrome omits shortcut labels")
      local winbar = vim.wo[win].winbar
      assert_true(not winbar:find("keys", 1, true), "hidden hub chrome omits the shortcut ribbon")
      assert_contains(winbar, "Flashcards", "hidden shortcut chrome retains page navigation")
    end
    overview.context_help()
    local _, hidden_hub_help = current_popup()
    assert_contains(hidden_hub_help, "Cards keys", "hub help remains available when shortcut chrome is hidden")
    overview.help_close()
    overview.close()

    vim.cmd.edit(vim.fn.fnameescape(hidden_path))
    vim.cmd("Flashcards review file")
    local hidden_review_buf = vim.api.nvim_get_current_buf()
    assert_buffer_maps(hidden_review_buf, { "?" })
    assert_equal(util.trim(window_footer()), "", "review shortcut footer can be hidden")
    review_engine.context_help()
    local _, hidden_review_help = current_popup()
    assert_contains(hidden_review_help, "Review keys · question", "review help remains available without its footer")
    review_engine.help_close()
    flashcards.close_review()

    flashcards.add_to_default("japanese")
    local hidden_form_buf = vim.api.nvim_get_current_buf()
    assert_buffer_maps(hidden_form_buf, { "?" })
    assert_equal(util.trim(window_footer()), "", "form shortcut footer can be hidden")
    local hidden_form_imaps = {}
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(hidden_form_buf, "i")) do
      hidden_form_imaps[map.lhs:lower()] = true
    end
    assert_true(hidden_form_imaps["<c-s>"], "hidden form chrome keeps save mapping")
    assert_true(hidden_form_imaps["<c-n>"], "hidden form chrome keeps save-and-new mapping")
    assert_contains(decoration_text(hidden_form_buf), "Target", "hidden shortcuts do not hide composer context")
    form.context_help()
    local _, hidden_form_help = current_popup()
    assert_contains(hidden_form_help, "Card form keys", "form help remains available without its footer")
    assert_contains(hidden_form_help, "Save and start another", "hidden form help still exposes save-and-new")
    form.help_close()
    form.close()
    vim.cmd("silent! bwipeout!")
  end
end
