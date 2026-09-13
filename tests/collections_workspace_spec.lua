return function(T)
  local collections = require("neorg_flashcards.collections")
  local presets = require("neorg_flashcards.presets")
  local schedule = require("neorg_flashcards.schedule")

  local assert_true = T.assert_true
  local assert_equal = T.assert_equal
  local assert_contains = T.assert_contains

  local test_root = vim.fn.tempname()
  vim.fn.mkdir(test_root, "p")

  local function collection(path, card_type)
    card_type = card_type or "japanese"
    return {
      path = path,
      default_card_type = card_type,
      schemas = presets.only(card_type),
    }
  end

  local function valid_options(name)
    local root = test_root .. "/" .. name
    return {
      default_collection = "japanese",
      collections = {
        computer_science = collection(root .. "/computer-science", "chinese"),
        japanese = vim.tbl_extend("force", collection(root .. "/japanese"), { label = "Japanese" }),
      },
    }
  end

  local function error_text(errors)
    return table.concat(errors or {}, "\n")
  end

  do
    local observed = function() end
    local options = valid_options("defaults")
    options.on_review = observed
    local workspace, errors = collections.prepare(options)
    assert_true(workspace ~= nil, "a valid named workspace is prepared: " .. error_text(errors))
    assert_equal(#errors, 0, "a valid named workspace has no diagnostics")
    assert_equal(collections.active(workspace).id, "japanese", "default_collection becomes active")
    assert_equal(collections.active(workspace).label, "Japanese", "the configured collection label is retained")
    assert_equal(
      collections.get(workspace, "computer_science").label,
      "computer_science",
      "a missing label falls back to the collection ID"
    )
    local collection_ids = collections.ids(workspace)
    assert_equal(#collection_ids, 2, "the workspace exposes every collection ID")
    assert_equal(collection_ids[1], "computer_science", "collection IDs are exposed in stable sorted order")
    assert_equal(collection_ids[2], "japanese", "collection IDs are exposed in stable sorted order")

    local japanese = collections.get(workspace, "japanese")
    assert_equal(japanese.default_file, japanese.path .. "/cards.norg", "default_file is relative to the collection")
    assert_equal(
      japanese.history_file,
      japanese.path .. "/reviews.jsonl",
      "history_file defaults inside the collection"
    )
    assert_equal(japanese.leech_threshold, 8, "collections inherit the leech threshold default")
    assert_equal(japanese.scheduling.hard_hours, schedule.DEFAULTS.hard_hours, "collections inherit scheduler defaults")
    assert_true(japanese._root ~= nil, "a prepared collection captures its root identity")
    assert_equal(japanese.on_review, observed, "the review observer is captured by each context")

    local selected, select_error = collections.select(workspace, "computer_science")
    assert_equal(select_error, nil, "a configured collection can be selected")
    assert_equal(selected.id, "computer_science", "select returns the chosen context")
    assert_equal(collections.active(workspace).id, "computer_science", "selection changes the active context")
    local missing, missing_error = collections.select(workspace, "missing")
    assert_equal(missing, nil, "an unknown collection is not selected")
    assert_contains(missing_error, "Unknown flashcard collection", "unknown selection returns a useful diagnostic")
    assert_equal(
      collections.active(workspace).id,
      "computer_science",
      "a failed selection does not change the active collection"
    )

    local ids = collections.ids(workspace)
    ids[1] = "changed"
    assert_equal(collections.ids(workspace)[1], "computer_science", "the public ID list is a copy")

    local public = collections.public(japanese)
    assert_equal(public._root, nil, "the public context hides the pinned filesystem identity")
    assert_equal(public.on_review, nil, "the public context does not expose callback functions")
    public.ui.show_shortcuts = false
    public.schemas.japanese.label = "Changed"
    assert_true(japanese.ui.show_shortcuts, "mutating a public UI copy cannot change the runtime context")
    assert_true(
      japanese.schemas.japanese.label ~= "Changed",
      "mutating a public schema copy cannot change the runtime context"
    )
  end

  do
    local original_cwd = vim.fn.getcwd()
    local relative_cwd = test_root .. "/relative-cwd"
    vim.fn.mkdir(relative_cwd, "p")
    vim.cmd("cd " .. vim.fn.fnameescape(relative_cwd))
    -- getcwd resolves symlinks such as macOS /var, so anchor expectations to
    -- the cwd seen during prepare rather than to the tempname path.
    local prepare_cwd = vim.fn.getcwd()
    local workspace, errors = collections.prepare({
      default_collection = "notes",
      collections = {
        notes = vim.tbl_extend("force", collection("notes/japanese"), {
          default_file = "deck/cards.norg",
          history_file = "state/reviews.jsonl",
        }),
      },
    })
    vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))

    assert_true(workspace ~= nil, "relative collection paths are accepted: " .. error_text(errors))
    local context = collections.active(workspace)
    local expected_root = vim.fs.normalize(prepare_cwd .. "/notes/japanese")
    assert_equal(context.path, expected_root, "a relative collection path is frozen during prepare")
    assert_equal(
      context.default_file,
      expected_root .. "/deck/cards.norg",
      "a relative default file resolves below the collection root"
    )
    assert_equal(
      context.history_file,
      expected_root .. "/state/reviews.jsonl",
      "a relative history file resolves below the collection root"
    )
  end

  do
    for index, option in ipairs({
      "flashcards_dir",
      "default_kind",
      "path",
      "default_file",
      "default_card_type",
      "schemas",
      "scheduling",
      "history_file",
      "leech_threshold",
      "languages",
      "legacy_history_file",
      "schemaPresets",
      "collectons",
    }) do
      local options = valid_options("unknown-" .. index)
      options[option] = option == "schemas" and {} or "removed"
      local workspace, errors = collections.prepare(options)
      assert_equal(workspace, nil, "a removed or unknown top-level option is rejected: " .. option)
      assert_contains(error_text(errors), "unknown setup option: " .. option, "the rejected option is named")
    end
  end

  do
    local missing_default = valid_options("missing-default")
    missing_default.default_collection = nil
    local workspace, errors = collections.prepare(missing_default)
    assert_equal(workspace, nil, "default_collection is required")
    assert_contains(error_text(errors), "default_collection is required", "missing default_collection is explained")

    local unknown_default = valid_options("unknown-default")
    unknown_default.default_collection = "missing"
    workspace, errors = collections.prepare(unknown_default)
    assert_equal(workspace, nil, "default_collection must identify a configured collection")
    assert_contains(
      error_text(errors),
      "default_collection does not name a configured collection: missing",
      "an unknown default collection is named"
    )

    local invalid_id = valid_options("invalid-id")
    invalid_id.collections.Japanese = invalid_id.collections.japanese
    invalid_id.collections.japanese = nil
    invalid_id.default_collection = "Japanese"
    workspace, errors = collections.prepare(invalid_id)
    assert_equal(workspace, nil, "collection IDs use one stable lowercase format")
    assert_contains(error_text(errors), "collection id must use lowercase", "an invalid collection ID is explained")

    local mixed_ids = valid_options("mixed-ids")
    mixed_ids.collections[1] = collection(test_root .. "/mixed-ids/numeric")
    workspace, errors = collections.prepare(mixed_ids)
    assert_equal(workspace, nil, "non-string collection IDs are rejected without crashing")
    assert_contains(
      error_text(errors),
      "collection id must use lowercase",
      "a non-string ID receives the ID diagnostic"
    )

    local invalid_card_type = valid_options("invalid-card-type")
    invalid_card_type.collections.japanese.default_card_type = "missing"
    workspace, errors = collections.prepare(invalid_card_type)
    assert_equal(workspace, nil, "the default card type must exist in the collection schemas")
    assert_contains(
      error_text(errors),
      "does not name a configured schema",
      "an unknown default card type is explained"
    )

    local empty_card_type = valid_options("empty-card-type")
    empty_card_type.collections.japanese.default_card_type = ""
    workspace, errors = collections.prepare(empty_card_type)
    assert_equal(workspace, nil, "every collection requires a default card type")
    assert_contains(
      error_text(errors),
      "collection japanese.default_card_type is required",
      "a missing default card type uses the public option name"
    )

    local invalid_scheduling = valid_options("invalid-scheduling")
    invalid_scheduling.collections.japanese.scheduling = "fast"
    workspace, errors = collections.prepare(invalid_scheduling)
    assert_equal(workspace, nil, "invalid scheduling configuration is rejected without crashing")
    assert_contains(
      error_text(errors),
      "collection japanese.scheduling must be a table",
      "invalid scheduling names the collection and option"
    )
  end

  do
    local options = {
      default_collection = "first",
      collections = {
        first = collection(test_root .. "/overlap"),
        second = collection(test_root .. "/overlap/nested"),
      },
    }
    local workspace, errors = collections.prepare(options)
    assert_equal(workspace, nil, "nested collection roots are rejected")
    assert_contains(
      error_text(errors),
      "collection paths must not overlap: first and second",
      "overlap names both roots"
    )
  end

  do
    local uv = vim.uv or vim.loop
    local physical = test_root .. "/physical-root"
    local first_alias = test_root .. "/physical-first"
    local second_alias = test_root .. "/physical-second"
    vim.fn.mkdir(physical, "p")
    local first_linked, first_link_error = uv.fs_symlink(physical, first_alias)
    local second_linked, second_link_error = uv.fs_symlink(physical, second_alias)
    assert_true(first_linked, "the first collection-root symlink is created: " .. tostring(first_link_error))
    assert_true(second_linked, "the second collection-root symlink is created: " .. tostring(second_link_error))

    local workspace, errors = collections.prepare({
      default_collection = "first",
      collections = {
        first = collection(first_alias),
        second = collection(second_alias),
      },
    })
    assert_equal(workspace, nil, "two path spellings of one physical root are rejected")
    assert_contains(error_text(errors), "collection paths must not overlap", "physical root aliases are detected")
  end

  do
    local first_root = test_root .. "/shared-ledger/first"
    local second_root = test_root .. "/shared-ledger/second"
    local shared_ledger = first_root .. "/reviews.jsonl"
    vim.fn.mkdir(first_root, "p")
    vim.fn.mkdir(second_root, "p")
    vim.fn.writefile({}, shared_ledger)
    local workspace, errors = collections.prepare({
      default_collection = "first",
      collections = {
        first = vim.tbl_extend("force", collection(first_root), { history_file = shared_ledger }),
        second = vim.tbl_extend("force", collection(second_root), { history_file = shared_ledger }),
      },
    })
    assert_equal(workspace, nil, "one ledger path cannot be configured for two collection roots")
    assert_contains(
      error_text(errors),
      "review history destination must be inside the collection path",
      "a shared path outside one collection is rejected at its write boundary"
    )
  end

  do
    local uv = vim.uv or vim.loop
    local first_root = test_root .. "/hard-linked-ledger/first"
    local second_root = test_root .. "/hard-linked-ledger/second"
    local first_ledger = first_root .. "/reviews.jsonl"
    local second_ledger = second_root .. "/reviews.jsonl"
    vim.fn.mkdir(first_root, "p")
    vim.fn.mkdir(second_root, "p")
    vim.fn.writefile({}, first_ledger)
    local linked, link_error = uv.fs_link(first_ledger, second_ledger)
    assert_true(linked, "the review-ledger hard link is created: " .. tostring(link_error))

    local workspace, errors = collections.prepare({
      default_collection = "first",
      collections = {
        first = collection(first_root),
        second = collection(second_root),
      },
    })
    assert_equal(workspace, nil, "hard-linked collection ledgers are rejected")
    assert_contains(
      error_text(errors),
      "collections must not share review history: first and second",
      "hard-linked ledgers are detected by filesystem identity"
    )
  end

  do
    local flashcards = require("neorg_flashcards")
    local overview = require("neorg_flashcards.overview")
    local actions = require("neorg_flashcards.ui.actions")
    local runtime_root = test_root .. "/runtime"
    local japanese_root = runtime_root .. "/japanese"
    local computer_root = runtime_root .. "/computer-science"
    vim.fn.mkdir(japanese_root, "p")
    vim.fn.mkdir(computer_root, "p")
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_shared_between_collections",
      "japanese: 猫",
      "english: cat",
      "@end",
    }, japanese_root .. "/cards.norg")
    vim.fn.writefile({
      "@flashcard chinese",
      "id: fc_shared_between_collections",
      "chinese: 猫",
      "english: cat",
      "@end",
    }, computer_root .. "/cards.norg")

    assert_true(
      flashcards.setup({
        default_collection = "japanese",
        collections = {
          japanese = {
            label = "Japanese",
            path = japanese_root,
            default_card_type = "japanese",
            schemas = presets.only("japanese"),
          },
          computer_science = {
            label = "Computer Science",
            path = computer_root,
            default_card_type = "chinese",
            schemas = presets.only("chinese"),
          },
        },
      }),
      "the runtime accepts two independent collections"
    )
    assert_equal(flashcards.active_collection().id, "japanese", "the public API reports the active collection")
    assert_equal(flashcards.active_collection().flashcards_dir, nil, "removed setup names are not public aliases")

    assert_true(flashcards.cards(), "the active collection opens in Cards")
    assert_contains(T.current_tab_text(), "Cards · Japanese", "the hub names the active collection")
    assert_contains(T.current_tab_text(), "猫", "the active collection card is shown")
    local hub = vim.api.nvim_get_current_buf()
    T.assert_buffer_maps(hub, { "C" })
    assert_contains(actions.footer("cards", 120, { collection = true }), "C collection", "the switch is visible")
    assert_contains(
      table.concat(actions.help_lines("cards", { collection = true }), "\n"),
      "Switch collection",
      "context help explains the collection switch"
    )

    assert_true(flashcards.select_collection("computer_science"), "a collection can be selected by ID")
    assert_equal(
      flashcards.active_collection().id,
      "computer_science",
      "direct selection changes the active collection"
    )
    assert_contains(T.current_tab_text(), "Cards · Computer Science", "the open hub switches in place")

    local chosen = nil
    local original_select = vim.ui.select
    vim.ui.select = function(items, _, callback)
      chosen = vim.deepcopy(items)
      callback("japanese")
    end
    assert_true(flashcards.choose_collection(), "the collection picker opens")
    vim.ui.select = original_select
    assert_equal(chosen[1], "computer_science", "the picker uses stable sorted collection IDs")
    assert_equal(chosen[2], "japanese", "the picker includes the default collection")
    assert_equal(flashcards.active_collection().id, "japanese", "the picker switches without another command")
    overview.show("overview")
    overview.close()
  end

  vim.fn.delete(test_root, "rf")
end
