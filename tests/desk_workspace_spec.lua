return function(T)
  local metadata = require("neorg_flashcards.metadata")
  local registry = require("neorg_flashcards.registry")
  local calendar = require("neorg_flashcards.calendar")
  local parser = require("neorg_flashcards.parser")
  local collections = require("neorg_flashcards.collections")
  local presets = require("neorg_flashcards.presets")
  local manage = require("neorg_flashcards.manage")
  local canvas = require("neorg_flashcards.ui.canvas")
  local motion = require("neorg_flashcards.ui.motion")
  local equal, truth, contains = T.assert_equal, T.assert_true, T.assert_contains
  local root = vim.fn.tempname()
  local opts = {
    default_collection = "demo",
    deck_registry = root .. "/settings/decks.json",
    collections = {
      demo = { path = root .. "/demo", default_card_type = "japanese", schemas = presets.only("japanese") },
    },
  }
  local workspace = assert(collections.prepare(opts))
  local config = collections.active(workspace)
  local source = config.path .. "/cards.norg"
  vim.fn.writefile({
    "* Notes about food must stay untouched",
    "@flashcard japanese",
    "id: fc_desk_one",
    "japanese: 猫",
    "english: cat",
    "tags: food seafood",
    "@end",
    "@flashcard japanese",
    "id: fc_desk_two",
    "japanese: 水",
    "english: water",
    "tags: food drinks food",
    "@end",
    "@flashcard japanese",
    "id: fc_desk_three",
    "japanese: 鳥",
    "english: bird",
    "@end",
  }, source)
  local original = table.concat(vim.fn.readfile(source), "\n")
  local cards = parser.collect_flashcards(config)
  equal(#cards, 3, "fixture contains three reviewable cards")

  local data, err = metadata.load(config)
  equal(err, nil, "a missing sidecar uses defaults")
  equal(data.goal, 20, "default goal is twenty unique cards")
  truth(
    metadata.update(config, function(next_data)
      next_data.categories.empty = { label = "日本語", accent = "hard", order = -1 }
      next_data.categories.food = { label = "Food", order = 2 }
      next_data.goal = 2
    end),
    "metadata can be saved beside the collection"
  )
  data = metadata.load(config)
  local groups = metadata.groups(cards, data, config, os.time())
  equal(groups[1].name, "empty", "explicit shelf order is respected")
  equal(#groups[1].cards, 0, "empty category notes survive without source tags")
  equal(groups[#groups].label, "Untagged", "untagged cards have their own note")
  for _, group in ipairs(groups) do
    if group.name == "food" then
      equal(#group.cards, 2, "duplicate tags do not duplicate category cards")
    end
  end
  local day = os.time({ year = 2026, month = 3, day = 29, hour = 12 })
  truth(metadata.begin_day(config, day), "starting a study day captures its goal")
  truth(metadata.update(config, function(value)
    value.goal = 9
  end))
  truth(metadata.begin_day(config, day))
  data = metadata.load(config)
  equal(data.goals["2026-03-29"], 2, "changing the default does not rewrite a historical goal")
  equal(calendar.day(calendar.shift(day, 1)), "2026-03-30", "day arithmetic crosses DST using local dates")
  equal(calendar.day(calendar.month(day, -1)), "2026-02-01", "month navigation anchors at day one")

  local function event(id, card_id, rating, epoch)
    return { type = "review", event = "rated", event_id = id, card_id = card_id, rating = rating, epoch = epoch or day }
  end
  local entries = { event("a", "fc_desk_one", 1), event("b", "fc_desk_one", 3), event("c", "fc_desk_two", 2) }
  entries[1].duration_ms = 1000
  entries[2].hint_used = true
  local progress = calendar.progress(entries, data, day)
  equal(progress.unique, 2, "Again retries count once toward the daily goal")
  equal(progress.answers, 3, "answer count retains retries")
  equal(progress.days["2026-03-29"].timed, 1, "missing durations are not invented zeros")
  equal(progress.days["2026-03-29"].hints, 1, "day details count hinted answers")
  table.insert(entries, { type = "review", event = "undo", undo_of = "c", card_id = "fc_desk_two", epoch = day })
  equal(calendar.progress(entries, data, day).unique, 1, "undo reverses daily goal progress")
  local calendar_lines = calendar.render(entries, data, day, 60, false, day, 16)
  contains(table.concat(calendar_lines, "\n"), "[29]", "calendar marks the selected date")
  local dashboard_lines = require("neorg_flashcards.ui.dashboard").render({
    width = 77,
    height = 28,
    label = "Japanese",
    now = day,
    date = day,
    cards = cards,
    history = entries,
    progress = entries,
    metadata = data,
    errors = {},
    health_lines = {},
    health_spans = {},
  })
  local visible = table.concat(vim.list_slice(dashboard_lines, 1, 28), "\n")
  contains(visible, "[29]", "the compact dashboard retains the selected date")
  contains(visible, "3 Good", "all three rating totals fit above the fold at 122 by 30")
  contains(visible, "LAST WEEK", "medium dashboards use the space beside the calendar for weekly comparisons")
  local due = calendar.scheduled(cards, day, day, config)
  equal(#due, 3, "today includes new cards")
  equal(
    #calendar.scheduled(cards, calendar.shift(day, 1), day, config),
    0,
    "overdue/new work is not copied onto future dates"
  )

  local renamed, message = manage.change_tag(config, cards, "food", "drinks")
  truth(renamed, message)
  local changed = table.concat(vim.fn.readfile(source), "\n")
  contains(changed, "Notes about food", "category edits do not replace arbitrary prose")
  contains(changed, "tags: seafood drinks", "renaming food leaves the seafood token alone")
  truth(not changed:find("drinks drinks", 1, true), "merging deduplicates destination tags")
  equal(
    table.concat(vim.fn.readfile(source .. ".flashcards-tags-backup"), "\n"),
    original,
    "tag changes preserve a recoverable source snapshot"
  )
  cards = parser.collect_flashcards(config)
  truth(manage.change_tag(config, cards, "drinks", nil), "removing a category succeeds")
  equal(#parser.collect_flashcards(config), 3, "removing a category never deletes cards")
  truth(not metadata.load(config).categories.food, "renaming removes the old presentation entry")

  local metadata_path = metadata.path(config)
  vim.fn.writefile({ "{broken" }, metadata_path)
  local accepted = metadata.update(config, function(value)
    value.goal = 99
  end)
  truth(not accepted, "malformed metadata must be repaired rather than overwritten")
  equal(vim.fn.readfile(metadata_path)[1], "{broken", "malformed metadata remains recoverable")
  vim.fn.delete(metadata_path)
  local external = root .. "/external.json"
  vim.fn.writefile({ "do not modify" }, external)
  assert((vim.uv or vim.loop).fs_symlink(external, metadata_path))
  truth(not metadata.update(config, function(value)
    value.goal = 1
  end), "metadata refuses a redirected sidecar")
  equal(vim.fn.readfile(external)[1], "do not modify", "a symlink target is untouched")
  vim.fn.delete(metadata_path)

  truth(
    registry.update(opts, function(decks)
      decks.science = { label = "Science", path = root .. "/science", types = { "question_answer", "code_output" } }
    end),
    "the UI registry validates and creates an isolated deck"
  )
  local merged = assert(registry.merge(opts))
  truth(merged.collections.science.schemas.code_output, "registered bundled card types survive reload")
  equal(merged.collections.science.default_card_type, "question_answer", "first bundled type is the default")
  local before = table.concat(vim.fn.readfile(opts.deck_registry), "\n")
  truth(not registry.update(opts, function(decks)
    decks.demo = { path = root .. "/collision", types = { "japanese" } }
  end), "registry cannot replace a configured deck ID")
  truth(not registry.update(opts, function(decks)
    decks.overlap = { path = config.path, types = { "japanese" } }
  end), "UI deck creation rejects shared source roots")
  equal(
    table.concat(vim.fn.readfile(opts.deck_registry), "\n"),
    before,
    "rejected definitions leave the registry intact"
  )
  truth(
    not registry.update({ deck_registry = false }, function() end),
    "registry can be disabled for declarative setups"
  )

  local c = canvas.new(18, true)
  c:box(1, 1, 18, 4, "Comment")
  c:put(2, 3, "日本語 é", "String")
  local lines, spans = c:finish()
  for _, line in ipairs(lines) do
    equal(vim.fn.strdisplaywidth(line), 18, "wide text keeps borders aligned")
  end
  for _, span in ipairs(spans) do
    truth(span.start_col >= 0 and span.end_col <= #lines[span.line], "highlight spans use valid byte offsets")
  end
  contains(table.concat(lines, "\n"), "+----------------+", "plain ASCII replaces box-drawing borders")
  local frames = 0
  motion.play("test", true, function()
    frames = frames + 1
  end)
  truth(motion.active("test"), "an animation owns a timer only while moving")
  truth(
    vim.wait(400, function()
      return not motion.active("test")
    end),
    "animation releases its timer when finished"
  )
  equal(frames, 4, "motion uses a finite four-frame sequence")
  motion.play("test", true, function()
    frames = frames + 1
  end)
  motion.cancel("test")
  vim.wait(80, function()
    return false
  end)
  equal(frames, 4, "cancelled callbacks cannot paint a closed view")
  motion.play("test", false, function(phase)
    equal(phase, 1, "reduced motion paints the final state")
  end)
  truth(not motion.active("test"), "reduced motion creates no timer")
  vim.fn.delete(root, "rf")
end
