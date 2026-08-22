return function(T)
  local parser = require("neorg_flashcards.parser")
  local store = require("neorg_flashcards.store")

  local assert_true = T.assert_true
  local assert_equal = T.assert_equal
  local assert_contains = T.assert_contains
  local config = T.config

  local card_path = vim.fn.tempname() .. ".norg"
  vim.fn.writefile({
    "@flashcard japanese",
    "id: fc_stored_cat",
    "japanese: 猫",
    "english: cat",
    "@end",
  }, card_path)

  local stored_cards = parser.parse_file(card_path)
  local stored_valid, stored_errors = parser.valid_cards(config, stored_cards)
  assert_equal(#stored_errors, 0, "stored card validates")
  assert_equal(#stored_valid, 1, "stored card is valid")

  local ok, message = store.set_card_fields(stored_valid[1], {
    { field = "score", value = "3" },
    { field = "reviewed", value = "2026-07-01" },
  }, { cards = stored_valid })

  assert_true(ok, message)

  local updated = table.concat(vim.fn.readfile(card_path), "\n")
  assert_contains(updated, "score: 3", "score was written")
  assert_contains(updated, "reviewed: 2026-07-01", "review date was written")
  local temporary_pattern = vim.fn.fnamemodify(card_path, ":h")
    .. "/."
    .. vim.fn.fnamemodify(card_path, ":t")
    .. ".neorg-flashcards-*.tmp"
  assert_equal(#vim.fn.glob(temporary_pattern, false, true), 0, "atomic unloaded writes leave no temporary debris")

  do
    local race_path = vim.fn.tempname() .. ".norg"
    local race_lines = {
      "@flashcard japanese",
      "id: fc_external_race",
      "japanese: 古い",
      "english: old",
      "@end",
    }
    local external_lines = {
      "* Written by another process",
      "",
      "@flashcard japanese",
      "id: fc_external_race",
      "japanese: 新しい",
      "english: new",
      "@end",
    }
    vim.fn.writefile(race_lines, race_path)
    local race_card = parser.parse_file(race_path)[1]
    local race_destination = T.canonical_path(race_path)
    local race_directory = vim.fn.fnamemodify(race_destination, ":h")
    local race_basename = vim.fn.fnamemodify(race_destination, ":t")
    local race_temporary_prefix = race_directory .. "/." .. race_basename .. ".neorg-flashcards-"
    local original_writefile = vim.fn.writefile
    local raced = false
    vim.fn.writefile = function(lines, path, flags)
      local result
      if flags == nil then
        result = original_writefile(lines, path)
      else
        result = original_writefile(lines, path, flags)
      end
      if not raced and path:sub(1, #race_temporary_prefix) == race_temporary_prefix and path:match("%.tmp$") then
        raced = true
        original_writefile(external_lines, race_path)
      end
      return result
    end

    local call_ok, update_ok, update_message, update_persisted = pcall(store.set_card_fields, race_card, {
      { field = "score", value = "3" },
    })
    vim.fn.writefile = original_writefile

    assert_true(call_ok, "external-write race does not crash: " .. tostring(update_ok))
    assert_true(raced, "fixture changes the source after the plugin writes its temporary replacement")
    assert_true(not update_ok, "unloaded update rejects a source changed immediately before rename")
    assert_equal(update_persisted, false, "rejected external-write race is not reported as persisted")
    assert_contains(update_message, "source changed while preparing", "race rejection explains the stale snapshot")
    assert_equal(
      table.concat(vim.fn.readfile(race_path), "\n"),
      table.concat(external_lines, "\n"),
      "external contents survive the rejected plugin replacement"
    )
    assert_equal(race_card.values.score, nil, "a rejected replacement does not mutate cached card metadata")
    assert_equal(
      #vim.fn.glob(race_temporary_prefix .. "*.tmp", false, true),
      0,
      "rejected external-write race removes its temporary file"
    )
    assert_equal(
      vim.fn.filereadable(race_directory .. "/." .. race_basename .. ".neorg-flashcards.lock"),
      0,
      "rejected external-write race releases its destination lock"
    )
  end

  do
    local delete_path = vim.fn.tempname() .. ".norg"
    local delete_lines = {
      "* Delete cards safely",
      "",
      "@flashcard japanese",
      "id: fc_delete_first",
      "japanese: 一",
      "english: one",
      "@end",
      "",
      "@flashcard japanese",
      "id: fc_delete_middle",
      "japanese: 二",
      "english: two",
      "@end",
      "",
      "@flashcard japanese",
      "id: fc_delete_last",
      "japanese: 三",
      "english: three",
      "@end",
    }
    vim.fn.writefile(delete_lines, delete_path)
    local delete_cards = parser.parse_file(delete_path)
    local delete_ok, delete_message, delete_persisted = store.delete_card(delete_cards[2])
    assert_true(delete_ok, delete_message)
    assert_true(delete_persisted, "deleting from an unloaded source persists immediately")
    assert_contains(delete_message, ".flashcards-backup", "unloaded deletion reports its recovery backup")
    assert_equal(
      table.concat(vim.fn.readfile(delete_path .. ".flashcards-backup"), "\n"),
      table.concat(delete_lines, "\n"),
      "unloaded deletion backs up the exact pre-delete source"
    )
    assert_equal(
      table.concat(vim.fn.readfile(delete_path), "\n"),
      table.concat({
        "* Delete cards safely",
        "",
        "@flashcard japanese",
        "id: fc_delete_first",
        "japanese: 一",
        "english: one",
        "@end",
        "",
        "@flashcard japanese",
        "id: fc_delete_last",
        "japanese: 三",
        "english: three",
        "@end",
      }, "\n"),
      "deletion removes exactly the selected physical block and one doubled separator"
    )

    local private_path = vim.fn.tempname() .. ".norg"
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_private_delete",
      "japanese: 秘密",
      "english: secret",
      "@end",
    }, private_path)
    assert_equal(vim.fn.setfperm(private_path, "rw-------"), 1, "private deletion fixture sets source permissions")
    local private_ok, private_message = store.delete_card(parser.parse_file(private_path)[1])
    assert_true(private_ok, private_message)
    assert_equal(
      vim.fn.getfperm(private_path .. ".flashcards-backup"),
      "rw-------",
      "a new deletion backup inherits private source permissions"
    )

    local symlink_dir = vim.fn.tempname()
    vim.fn.mkdir(symlink_dir, "p")
    local symlink_source = symlink_dir .. "/cards.norg"
    local symlink_backup = symlink_source .. ".flashcards-backup"
    local unrelated_path = symlink_dir .. "/unrelated.txt"
    local symlink_source_lines = {
      "@flashcard japanese",
      "id: fc_symlink_backup",
      "japanese: 守る",
      "english: protect",
      "@end",
    }
    vim.fn.writefile(symlink_source_lines, symlink_source)
    vim.fn.writefile({ "unrelated content" }, unrelated_path)
    local linked, link_error = (vim.uv or vim.loop).fs_symlink(unrelated_path, symlink_backup)
    assert_true(linked, "backup symlink fixture is created: " .. tostring(link_error))
    local symlink_ok, symlink_message = store.delete_card(parser.parse_file(symlink_source)[1])
    assert_true(not symlink_ok, "deletion refuses a symbolic-link backup destination")
    assert_contains(symlink_message, "symbolic-link destination", "symlink refusal explains the unsafe backup path")
    assert_equal(
      table.concat(vim.fn.readfile(unrelated_path), "\n"),
      "unrelated content",
      "refused backup creation never overwrites the symlink target"
    )
    assert_equal(
      table.concat(vim.fn.readfile(symlink_source), "\n"),
      table.concat(symlink_source_lines, "\n"),
      "a failed backup leaves the source card untouched"
    )
    assert_equal((vim.uv or vim.loop).fs_lstat(symlink_backup).type, "link", "refused backup leaves its symlink intact")

    local linked_source_target = symlink_dir .. "/linked-source-target.norg"
    local linked_source_path = symlink_dir .. "/linked-source.norg"
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_linked_source",
      "japanese: 続く",
      "english: remain",
      "@end",
    }, linked_source_target)
    local source_linked, source_link_error = (vim.uv or vim.loop).fs_symlink(linked_source_target, linked_source_path)
    assert_true(source_linked, "source symlink fixture is created: " .. tostring(source_link_error))
    local linked_card = parser.parse_file(linked_source_path)[1]
    local linked_ok, linked_message = store.set_card_fields(linked_card, {
      { field = "score", value = "3" },
    }, { allowed_root = symlink_dir })
    assert_true(linked_ok, linked_message)
    assert_equal(
      (vim.uv or vim.loop).fs_lstat(linked_source_path).type,
      "link",
      "normal atomic source updates preserve an existing source symlink"
    )
    assert_contains(
      table.concat(vim.fn.readfile(linked_source_target), "\n"),
      "score: 3",
      "normal atomic source updates replace the resolved regular-file target"
    )

    local outside_dir = vim.fn.tempname()
    vim.fn.mkdir(outside_dir, "p")
    local outside_target = outside_dir .. "/outside.norg"
    local outside_lines = {
      "@flashcard japanese",
      "id: fc_outside_target",
      "japanese: 外",
      "english: outside",
      "@end",
    }
    vim.fn.writefile(outside_lines, outside_target)
    local escape_path = symlink_dir .. "/escape.norg"
    local escaped, escape_error = (vim.uv or vim.loop).fs_symlink(outside_target, escape_path)
    assert_true(escaped, "outside-root source symlink fixture is created: " .. tostring(escape_error))
    local escape_card = parser.parse_file(escape_path)[1]
    local escape_ok, escape_message = store.set_card_fields(escape_card, {
      { field = "score", value = "3" },
    }, { allowed_root = symlink_dir })
    assert_true(not escape_ok, "source updates refuse a symlink target outside allowed_root")
    assert_contains(escape_message, "flashcards_dir", "outside-root source refusal names the collection boundary")
    assert_equal(
      table.concat(vim.fn.readfile(outside_target), "\n"),
      table.concat(outside_lines, "\n"),
      "refused source updates leave an outside symlink target untouched"
    )

    local swap_path = symlink_dir .. "/swap-after-collect.norg"
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_swap_after_collect",
      "japanese: 内",
      "english: inside",
      "@end",
    }, swap_path)
    local swap_card = parser.parse_file(swap_path)[1]
    assert_equal(vim.fn.delete(swap_path), 0, "runtime boundary fixture removes its original source")
    local swapped, swap_error = (vim.uv or vim.loop).fs_symlink(outside_target, swap_path)
    assert_true(swapped, "runtime boundary fixture redirects its source: " .. tostring(swap_error))
    local swap_ok, swap_message = store.delete_card(swap_card, { allowed_root = symlink_dir })
    assert_true(not swap_ok, "deletion rechecks the source boundary after collection")
    assert_contains(swap_message, "flashcards_dir", "runtime boundary refusal explains the collection constraint")
    assert_equal(
      table.concat(vim.fn.readfile(outside_target), "\n"),
      table.concat(outside_lines, "\n"),
      "refused deletion leaves the redirected outside target untouched"
    )

    local stale_card = parser.parse_file(delete_path)[1]
    vim.fn.writefile(vim.list_extend({ "* changed after confirmation" }, vim.fn.readfile(delete_path)), delete_path)
    local stale_delete_ok, stale_delete_message = store.delete_card(stale_card)
    assert_true(not stale_delete_ok, "deletion refuses a source changed after selection")
    assert_contains(stale_delete_message, "refresh before deleting", "stale deletion explains how to recover")

    local duplicate_path = vim.fn.tempname() .. ".norg"
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_duplicate_delete",
      "japanese: 前",
      "english: first",
      "@end",
      "",
      "@flashcard japanese",
      "id: fc_duplicate_delete",
      "japanese: 後",
      "english: second",
      "@end",
    }, duplicate_path)
    local duplicate_cards = parser.parse_file(duplicate_path)
    local duplicate_ok, duplicate_message = store.delete_card(duplicate_cards[2])
    assert_true(duplicate_ok, duplicate_message)
    local duplicate_text = table.concat(vim.fn.readfile(duplicate_path), "\n")
    assert_contains(duplicate_text, "japanese: 前", "duplicate deletion keeps the other physical card")
    assert_true(not duplicate_text:find("japanese: 後", 1, true), "duplicate deletion removes the selected range")

    local unclosed_path = vim.fn.tempname() .. ".norg"
    vim.fn.writefile({
      "* Broken card",
      "",
      "@flashcard japanese",
      "id: fc_unclosed_delete",
      "japanese: 未完",
      "english: unfinished",
    }, unclosed_path)
    local unclosed_card = parser.parse_file(unclosed_path)[1]
    assert_equal(unclosed_card.closed, false, "fixture is an unclosed invalid block")
    local unclosed_ok, unclosed_message = store.delete_card(unclosed_card)
    assert_true(not unclosed_ok, "unclosed blocks are not safe deletion targets")
    assert_contains(unclosed_message, "missing @end", "unclosed deletion explains the required repair")
    assert_equal(
      table.concat(vim.fn.readfile(unclosed_path), "\n"),
      "* Broken card\n\n@flashcard japanese\nid: fc_unclosed_delete\njapanese: 未完\nenglish: unfinished",
      "rejected unclosed deletion leaves the source untouched"
    )

    local dirty_path = vim.fn.tempname() .. ".norg"
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_dirty_delete",
      "japanese: 消す",
      "english: delete",
      "@end",
    }, dirty_path)
    vim.cmd.edit(vim.fn.fnameescape(dirty_path))
    vim.api.nvim_buf_set_lines(0, -1, -1, false, { "", "* unrelated unsaved note" })
    local dirty_card = parser.parse_buffer(0)[1]
    local dirty_ok, dirty_message, dirty_persisted = store.delete_card(dirty_card)
    assert_true(dirty_ok, dirty_message)
    assert_equal(dirty_persisted, false, "deletion in a dirty source waits for the user to save")
    assert_contains(dirty_message, "open modified buffer", "dirty deletion warns that it is not persisted")
    local dirty_buffer_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    assert_contains(dirty_buffer_text, "unrelated unsaved note", "dirty deletion preserves unrelated buffer edits")
    assert_true(not dirty_buffer_text:find("@flashcard", 1, true), "dirty deletion removes the block in memory")
    assert_contains(
      table.concat(vim.fn.readfile(dirty_path), "\n"),
      "japanese: 消す",
      "dirty deletion leaves the on-disk source unchanged"
    )
    assert_true(vim.bo.modified, "dirty deletion keeps the source buffer modified")
    vim.cmd("silent! bwipeout!")
  end
end
