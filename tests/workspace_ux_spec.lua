return function(T)
  local flashcards = require("neorg_flashcards")
  local form = require("neorg_flashcards.form")
  local overview = require("neorg_flashcards.overview")
  local presets = require("neorg_flashcards.presets")

  local assert_true = T.assert_true
  local assert_equal = T.assert_equal
  local assert_contains = T.assert_contains

  local test_root = vim.fn.tempname()
  vim.fn.mkdir(test_root, "p")

  local function one_type_workspace(name)
    return {
      default_collection = "japanese",
      collections = {
        japanese = {
          label = "Japanese",
          path = test_root .. "/" .. name .. "/japanese",
          default_card_type = "japanese",
          schemas = presets.only("japanese"),
        },
      },
    }
  end

  local function two_type_workspace(name)
    local options = one_type_workspace(name)
    options.collections.japanese.schemas = presets.only("japanese", "term_definition")
    return options
  end

  local function two_collection_workspace(name)
    return {
      default_collection = "japanese",
      collections = {
        computer_science = {
          label = "Computer Science",
          path = test_root .. "/" .. name .. "/computer-science",
          default_card_type = "term_definition",
          schemas = presets.only("term_definition"),
        },
        japanese = {
          label = "Japanese",
          path = test_root .. "/" .. name .. "/japanese",
          default_card_type = "japanese",
          schemas = presets.only("japanese", "term_definition"),
        },
      },
    }
  end

  local function with_select(replacement, callback)
    local original = vim.ui.select
    vim.ui.select = replacement
    local ok, result = xpcall(callback, debug.traceback)
    vim.ui.select = original
    if not ok then
      error(result, 0)
    end
    return result
  end

  local function current_title()
    local title = vim.api.nvim_win_get_config(0).title
    if type(title) == "string" then
      return title
    end
    local chunks = {}
    for _, chunk in ipairs(title or {}) do
      table.insert(chunks, type(chunk) == "table" and tostring(chunk[1] or "") or tostring(chunk))
    end
    return table.concat(chunks)
  end

  local function contains(values, expected)
    for _, value in ipairs(values or {}) do
      if value == expected then
        return true
      end
    end
    return false
  end

  do
    assert_true(flashcards.setup(one_type_workspace("one-type")), "the one-type workspace is configured")
    local select_calls = 0
    local opened = with_select(function()
      select_calls = select_calls + 1
    end, function()
      return flashcards.add_to_default("")
    end)
    assert_true(opened, "one configured card type opens the form directly")
    assert_equal(select_calls, 0, "one card type does not show an unnecessary picker")
    assert_true(form.is_open(), "the direct one-type path opens the composer")
    assert_contains(current_title(), "Japanese recognition", "the direct path uses the only configured card type")
    assert_true(form.close({ force = true }), "the one-type composer closes cleanly")
  end

  do
    assert_true(flashcards.setup(two_type_workspace("two-types")), "the multi-type workspace is configured")
    local picker_items, picker_options, picker_callback
    local launched = with_select(function(items, options, callback)
      picker_items = vim.deepcopy(items)
      picker_options = options
      picker_callback = callback
    end, function()
      return flashcards.add_to_default("")
    end)
    assert_true(launched, "multiple card types launch the picker")
    assert_true(not form.is_open(), "opening the picker does not create a draft before a choice")
    assert_equal(picker_items[1], "japanese", "the default card type appears first")
    assert_equal(picker_items[2], "term_definition", "the picker contains every configured card type")
    assert_contains(
      picker_options.format_item("japanese"),
      "● Japanese recognition",
      "the picker marks and labels the default card type"
    )
    assert_true(type(picker_callback) == "function", "the picker provides a selection callback")
    picker_callback("term_definition")
    assert_true(form.is_open(), "choosing a card type opens the composer")
    assert_contains(current_title(), "Term and definition", "the composer uses the selected card type")
    assert_true(form.close({ force = true }), "the selected-type composer closes cleanly")

    local cancelled = with_select(function(_, _, callback)
      callback(nil)
    end, function()
      return flashcards.add_to_default("")
    end)
    assert_true(cancelled, "a cancellable card-type picker reports that it launched")
    assert_true(not form.is_open(), "cancelling the card-type picker leaves no draft behind")

    local explicit_select_calls = 0
    local explicit = with_select(function()
      explicit_select_calls = explicit_select_calls + 1
    end, function()
      return flashcards.add_to_default("term_definition")
    end)
    assert_true(explicit, "an explicit card type opens the composer")
    assert_equal(explicit_select_calls, 0, "an explicit card type bypasses the picker")
    assert_contains(current_title(), "Term and definition", "the explicit type reaches the matching composer")
    assert_true(form.close({ force = true }), "the explicit-type composer closes cleanly")
  end

  do
    local options = two_collection_workspace("collection-command")
    assert_true(flashcards.setup(options), "the two-collection workspace is configured")
    assert_equal(flashcards.active_collection().id, "japanese", "the configured default starts active")

    local direct_picker_calls = 0
    local switched = with_select(function()
      direct_picker_calls = direct_picker_calls + 1
    end, function()
      return flashcards.command("collection computer_science")
    end)
    assert_true(switched, "an explicit collection command switches directly")
    assert_equal(direct_picker_calls, 0, "an explicit collection ID bypasses the picker")
    assert_equal(flashcards.active_collection().id, "computer_science", "the direct command changes collection")

    local completions = vim.fn.getcompletion("Flashcards collection jap", "cmdline")
    assert_true(contains(completions, "japanese"), "collection IDs are available through command completion")
    assert_true(not contains(completions, "computer_science"), "collection completion respects the typed prefix")

    local collection_items, collection_options, collection_callback
    local picker_opened = with_select(function(items, picker_opts, callback)
      collection_items = vim.deepcopy(items)
      collection_options = picker_opts
      collection_callback = callback
    end, function()
      return flashcards.command("collection")
    end)
    assert_true(picker_opened, "the collection command without an ID opens the picker")
    assert_equal(collection_items[1], "computer_science", "collection choices use stable sorted IDs")
    assert_equal(collection_items[2], "japanese", "the picker includes every collection")
    assert_contains(
      collection_options.format_item("computer_science"),
      "● Computer Science",
      "the collection picker marks the active item"
    )
    collection_callback("japanese")
    assert_equal(flashcards.active_collection().id, "japanese", "the picker switches to its selected collection")

    local cancelled = with_select(function(_, _, callback)
      callback(nil)
    end, function()
      return flashcards.command("collection")
    end)
    assert_true(cancelled, "the collection picker reports that it launched before cancellation")
    assert_equal(flashcards.active_collection().id, "japanese", "cancelling leaves the active collection unchanged")

    assert_true(not flashcards.command("collection missing"), "an unknown collection command is rejected")
    assert_equal(
      flashcards.active_collection().id,
      "japanese",
      "a failed switch leaves the active collection unchanged"
    )

    assert_true(flashcards.add_to_default("japanese"), "the form-blocking fixture opens")
    local blocked_type_picker_calls = 0
    local blocked_add = with_select(function()
      blocked_type_picker_calls = blocked_type_picker_calls + 1
    end, function()
      return flashcards.add_to_default("")
    end)
    assert_true(not blocked_add, "an open form blocks another bare add")
    assert_equal(blocked_type_picker_calls, 0, "a blocked bare add does not open the card-type picker")
    assert_true(not flashcards.select_collection("computer_science"), "an open form blocks direct collection switching")
    local blocked_picker_calls = 0
    local blocked_picker = with_select(function()
      blocked_picker_calls = blocked_picker_calls + 1
    end, function()
      return flashcards.choose_collection()
    end)
    assert_true(not blocked_picker, "an open form blocks the collection picker")
    assert_equal(blocked_picker_calls, 0, "a blocked collection switch does not flash a picker")
    assert_equal(flashcards.active_collection().id, "japanese", "the form keeps its original collection active")
    local form_reconfigure = two_collection_workspace("blocked-form-setup")
    local form_setup_ok, form_setup_error = pcall(flashcards.setup, form_reconfigure)
    assert_true(not form_setup_ok, "setup refuses to replace the workspace behind an open form")
    assert_contains(form_setup_error, "close the open flashcard form or review", "blocked setup explains what to close")
    assert_equal(
      vim.fn.isdirectory(form_reconfigure.collections.japanese.path),
      0,
      "blocked setup does not create collection directories"
    )
    assert_true(form.close({ force = true }), "the blocking form closes cleanly")

    local japanese_root = options.collections.japanese.path
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_workspace_switch_guard",
      "japanese: 守る",
      "english: protect",
      "@end",
    }, japanese_root .. "/review.norg")
    assert_true(flashcards.review_all(), "the review-blocking fixture starts")
    assert_true(flashcards.get_review_state().active, "the review session is active")
    blocked_type_picker_calls = 0
    blocked_add = with_select(function()
      blocked_type_picker_calls = blocked_type_picker_calls + 1
    end, function()
      return flashcards.add_to_default("")
    end)
    assert_true(not blocked_add, "an active review blocks a bare add")
    assert_equal(blocked_type_picker_calls, 0, "a review-blocked add does not open the card-type picker")
    assert_true(not flashcards.command("collection computer_science"), "an active review blocks collection commands")
    assert_equal(flashcards.active_collection().id, "japanese", "the review stays attached to its collection")
    local review_setup_ok, review_setup_error =
      pcall(flashcards.setup, two_collection_workspace("blocked-review-setup"))
    assert_true(not review_setup_ok, "setup refuses to replace the workspace behind an active review")
    assert_contains(review_setup_error, "close the open flashcard form or review", "review-blocked setup is actionable")
    assert_true(flashcards.close_review(), "the blocking review closes cleanly")
  end

  do
    overview.close()
    assert_true(
      flashcards.setup(two_collection_workspace("stale-collection")),
      "the stale-picker fixture is configured"
    )
    local collection_callback
    with_select(function(_, _, callback)
      collection_callback = callback
    end, function()
      return flashcards.choose_collection()
    end)
    assert_true(type(collection_callback) == "function", "the stale collection picker is captured")
    assert_true(
      flashcards.setup(two_collection_workspace("replacement-collection")),
      "a new workspace can replace an idle one"
    )
    collection_callback("computer_science")
    assert_equal(
      flashcards.active_collection().id,
      "japanese",
      "a callback from the replaced workspace cannot switch the new workspace"
    )

    assert_true(flashcards.setup(two_type_workspace("stale-card-type")), "the stale card-type fixture is configured")
    local card_type_callback
    with_select(function(_, _, callback)
      card_type_callback = callback
    end, function()
      return flashcards.add_to_default("")
    end)
    assert_true(type(card_type_callback) == "function", "the stale card-type picker is captured")
    assert_true(flashcards.setup(one_type_workspace("replacement-card-type")), "the card-type workspace is replaced")
    card_type_callback("term_definition")
    assert_true(not form.is_open(), "a stale card-type callback cannot open a form in another collection")

    local input_original = vim.ui.input
    local tag_callback
    vim.ui.input = function(_, callback)
      tag_callback = callback
    end
    assert_true(flashcards.review_tag(""), "the tag prompt opens")
    assert_true(flashcards.setup(one_type_workspace("replacement-tag")), "setup can replace an idle tag prompt context")
    tag_callback("verbs")
    assert_true(not flashcards.get_review_state().active, "a stale tag prompt cannot start a review")

    local score_callback
    vim.ui.input = function(_, callback)
      score_callback = callback
    end
    assert_true(flashcards.review_score(""), "the rating prompt opens")
    assert_true(
      flashcards.setup(one_type_workspace("replacement-rating")),
      "setup can replace an idle rating prompt context"
    )
    score_callback("good")
    assert_true(not flashcards.get_review_state().active, "a stale rating prompt cannot start a review")
    vim.ui.input = input_original
  end

  do
    overview.close()
    local first = one_type_workspace("hub-first")
    first.collections.japanese.label = "First Japanese"
    assert_true(flashcards.setup(first), "the first hub workspace is configured")
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_hub_first",
      "japanese: 古い",
      "english: old",
      "@end",
    }, first.collections.japanese.path .. "/cards.norg")
    assert_true(flashcards.overview({ view = "cards", reset_browser = true }), "the Cards page opens")
    assert_equal(overview.current_view(), "cards", "the hub starts on Cards")

    local second = one_type_workspace("hub-second")
    second.collections.japanese.label = "Fresh Japanese"
    vim.fn.mkdir(second.collections.japanese.path, "p")
    vim.fn.writefile({
      "@flashcard japanese",
      "id: fc_hub_second",
      "japanese: 新しい",
      "english: new",
      "@end",
    }, second.collections.japanese.path .. "/cards.norg")
    assert_true(flashcards.setup(second), "an idle open hub can be reconfigured")
    assert_equal(overview.current_view(), "cards", "reconfiguration preserves the current hub page")
    local hub_text = T.current_tab_text()
    assert_contains(hub_text, "Fresh Japanese", "the open hub adopts the new collection label")
    assert_contains(hub_text, "新しい", "the open hub reloads cards from the new collection")
    assert_true(not hub_text:find("古い", 1, true), "the open hub does not retain cards from the old provider")
    overview.show("overview")
  end

  form.close({ force = true })
  flashcards.close_review()
  overview.close()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local path = vim.api.nvim_buf_get_name(bufnr)
    if path ~= "" and path:sub(1, #test_root) == test_root then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end
  vim.fn.delete(test_root, "rf")
end
