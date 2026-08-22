return function(T)
  local health = require("neorg_flashcards.health")
  local history = require("neorg_flashcards.history")
  local parser = require("neorg_flashcards.parser")
  local schedule = require("neorg_flashcards.schedule")
  local stats = require("neorg_flashcards.stats")

  local assert_true = T.assert_true
  local assert_equal = T.assert_equal
  local assert_contains = T.assert_contains
  local test_root = T.test_root
  local collection_dir = T.collection_dir
  local collection_config = T.collection_config

  local fixed_now = os.time({ year = 2026, month = 8, day = 20, hour = 12, min = 0, sec = 0 })

  local function updates_map(updates)
    local map = {}
    for _, update in ipairs(updates) do
      map[update.field] = update.value
    end
    return map
  end

  local good_updates, good_due = schedule.review_updates({ values = {} }, 3, fixed_now)
  local good_map = updates_map(good_updates)
  assert_equal(good_map.score, "3", "rating keeps its score field")
  assert_equal(good_map.interval, "3", "first good rating uses the three-day interval")
  assert_equal(good_map.ease, "2.55", "good rating nudges ease up")
  assert_equal(good_map.reviewed, "2026-08-20", "rating stamps the review date")
  assert_equal(good_due, fixed_now + 3 * 86400, "good rating is due three days out")
  assert_equal(good_map.due, schedule.format_due(fixed_now + 3 * 86400), "due field matches the due epoch")

  local grown = updates_map(schedule.review_updates({ values = { interval = "3", ease = "2.5" } }, 3, fixed_now))
  assert_equal(grown.interval, "7.5", "good rating multiplies the interval by ease")

  local hard_updates, hard_due = schedule.review_updates({ values = {} }, 2, fixed_now)
  local hard_map = updates_map(hard_updates)
  assert_equal(hard_map.interval, "0.25", "first Hard rating preserves the six-hour interval")
  assert_equal(hard_map.ease, "2.5", "Hard keeps the starting ease")
  assert_equal(hard_due, fixed_now + 6 * 3600, "Hard is due six hours out")

  local hard_grown = updates_map(schedule.review_updates({ values = { interval = "0.25" } }, 2, fixed_now))
  assert_equal(hard_grown.interval, "0.3", "Hard grows the interval slowly")

  local again_updates, again_due = schedule.review_updates({ values = {} }, 1, fixed_now)
  local again_map = updates_map(again_updates)
  assert_equal(again_map.interval, "0", "Again resets the interval")
  assert_equal(again_map.ease, "2.3", "Again lowers ease")
  assert_equal(again_due, fixed_now + 600, "Again is due within minutes")

  local clamped = updates_map(schedule.review_updates({ values = { ease = "1.3" } }, 1, fixed_now))
  assert_equal(clamped.ease, "1.3", "ease never drops below the minimum")
  local custom_scheduling = vim.tbl_extend("force", {}, schedule.DEFAULTS, {
    hard_hours = 2,
    min_ease = 1.5,
    max_ease = 2.6,
    max_interval_days = 30,
  })
  local _, custom_hard_due = schedule.review_updates({ values = {} }, 2, fixed_now, custom_scheduling)
  assert_equal(custom_hard_due, fixed_now + 2 * 3600, "hard_hours overrides the first Hard interval")
  local clamped_state = schedule.card_state({ values = { interval = "999", ease = "9" } }, fixed_now, custom_scheduling)
  assert_equal(clamped_state.interval, 30, "card state clamps stored intervals to the configured maximum")
  assert_equal(clamped_state.ease, 2.6, "card state clamps stored ease to the configured maximum")
  local low_clamped_state = schedule.card_state({ values = { ease = "0.1" } }, fixed_now, custom_scheduling)
  assert_equal(low_clamped_state.ease, 1.5, "card state clamps stored ease to the configured minimum")

  assert_equal(schedule.parse_due("2026-08-20 12:00"), fixed_now, "datetime due parses")
  assert_equal(
    schedule.parse_due("2026-08-20"),
    os.time({ year = 2026, month = 8, day = 20, hour = 0, min = 0, sec = 0 }),
    "date-only due parses as the start of the day"
  )
  assert_equal(schedule.parse_due(schedule.format_due(fixed_now)), fixed_now, "due format roundtrips")
  assert_equal(schedule.parse_due("garbage"), nil, "garbage due is rejected")
  assert_equal(schedule.parse_due("2026-02-30"), nil, "normalized impossible dates are rejected")
  assert_equal(schedule.parse_due("2026-08-20 24:00"), nil, "hours outside local clock range are rejected")
  assert_equal(schedule.parse_due("2026-08-20 23:60"), nil, "minutes outside local clock range are rejected")
  assert_true(schedule.is_due({ values = { due = "2020-01-01 00:00" } }, fixed_now), "past card is due")
  assert_true(not schedule.is_due({ values = { due = "2999-01-01 00:00" } }, fixed_now), "future card is not due")
  assert_true(schedule.is_due({ values = {} }, fixed_now), "new card is due")
  assert_equal(schedule.due_key({ values = { due = "2026-08-20 12:00" } }), fixed_now, "due key uses the due epoch")
  assert_equal(schedule.due_key({ values = {} }), 0, "new cards sort first by due key")

  do
    local new_state = schedule.card_state({ values = {} }, fixed_now, schedule.DEFAULTS)
    assert_equal(new_state.lifecycle, "new", "cards without review evidence are new")
    assert_equal(new_state.timing, "due", "new cards are ready immediately")
    assert_equal(new_state.availability, "active", "new cards start active")

    local learning_state = schedule.card_state({
      values = { reps = "1", interval = "0", lifecycle = "learning" },
    }, fixed_now, schedule.DEFAULTS)
    assert_equal(learning_state.lifecycle, "learning", "short first intervals are learning")
    local relearning_state = schedule.card_state({
      values = { reps = "4", lapses = "1", lifecycle = "relearning", due = "2026-08-20 10:00" },
    }, fixed_now, schedule.DEFAULTS)
    assert_equal(relearning_state.lifecycle, "relearning", "explicit relearning state is preserved")
    assert_equal(relearning_state.timing, "due", "a card due earlier today is due, not overdue")
    local overdue_state = schedule.card_state({
      values = { reps = "4", interval = "5", due = "2026-08-19 23:59" },
    }, fixed_now, schedule.DEFAULTS)
    assert_equal(overdue_state.lifecycle, "review", "mature cards use the review lifecycle")
    assert_equal(overdue_state.timing, "overdue", "a card due before today is overdue")

    local suspended_card = {
      values = { availability = "suspended", due = "2020-01-01 00:00" },
    }
    local buried_card = {
      values = {
        availability = "buried",
        available_at = "2026-08-21 00:00",
        due = "2020-01-01 00:00",
      },
    }
    assert_equal(
      schedule.card_state(suspended_card, fixed_now, schedule.DEFAULTS).availability,
      "suspended",
      "suspension is explicit state"
    )
    assert_equal(
      schedule.card_state(buried_card, fixed_now, schedule.DEFAULTS).availability,
      "buried",
      "burial is explicit state"
    )
    assert_true(not schedule.is_due(suspended_card, fixed_now), "suspended cards are excluded from due queues")
    assert_true(not schedule.is_due(buried_card, fixed_now), "buried cards are excluded from due queues")
    assert_equal(
      schedule.next_due({ suspended_card, buried_card }, fixed_now),
      schedule.parse_due("2026-08-21 00:00"),
      "next-due hints use a buried card's availability time and ignore suspended cards"
    )
  end

  do
    local malformed = parser.parse_lines({
      "@flashcard japanese",
      "id: fc_malformed_schedule",
      "japanese: 壊",
      "english: broken",
      "due: never",
      "interval: -1",
      "ease: enormous",
      "reps: 1.5",
      "lapses: -2",
      "@end",
    }, collection_dir .. "/malformed-schedule.norg")[1]
    local valid, errors, invalid = parser.valid_cards(collection_config, { malformed })
    assert_equal(#valid, 0, "cards with malformed scheduling metadata are excluded")
    assert_equal(#invalid, 1, "malformed schedule remains available for repair")
    local messages = table.concat(invalid[1].messages, "\n")
    for _, field in ipairs({ "due", "interval", "ease", "reps", "lapses" }) do
      assert_contains(messages, "invalid " .. field, "malformed schedule reports " .. field)
    end
    assert_equal(#errors, 1, "malformed scheduling fields are grouped under their card")
  end

  do
    local history_dir = test_root .. "/history-isolated"
    local history_config = { flashcards_dir = history_dir }
    local history_card = { values = { id = "fc_history_card" } }
    local rated_event = assert(history.new_event(history_card, 3, fixed_now - 60, {
      event_id = "review-1",
      duration_ms = 4200,
      hint_used = true,
      before = { lifecycle = "learning" },
      after = { lifecycle = "review" },
    }))
    local append_ok, appended = history.append(rated_event, history_config)
    assert_true(append_ok, appended)
    assert_equal(appended.card_id, "fc_history_card", "history events use the stable card ID")
    assert_equal(appended.rating, 3, "history records the answer rating")

    local second_event = assert(history.new_event(history_card, 1, fixed_now, {
      event_id = "review-2",
      duration_ms = 1800,
    }))
    assert_true(history.append(second_event, history_config), "a second JSONL history event appends")
    local undo_event = assert(history.new_event(history_card, 1, fixed_now + 1, {
      event = "undo",
      event_id = "undo-1",
      undo_of = "review-2",
    }))
    assert_true(history.append(undo_event, history_config), "undo is stored as a compensating history event")

    local history_entries, history_errors = history.read(history_config)
    assert_equal(#history_errors, 0, "valid JSONL history reads without errors")
    assert_equal(#history_entries, 3, "JSONL history preserves rated and compensating events")
    local effective_history = stats.effective_entries(history_entries)
    assert_equal(#effective_history, 1, "analytics removes a rating cancelled by undo")
    assert_equal(effective_history[1].event_id, "review-1", "undo compensation targets the matching event")
    assert_contains(
      table.concat(vim.fn.readfile(history.path(history_config)), "\n"),
      '"card_id":"fc_history_card"',
      "history is stored as structured JSONL"
    )

    local externally_appended = assert(history.new_event(history_card, 2, fixed_now + 2, {
      event_id = "review-external",
    }))
    vim.fn.writefile({ vim.json.encode(externally_appended) }, history.path(history_config), "a")
    assert_true(
      history.append(externally_appended, history_config),
      "append rechecks event IDs written by another process"
    )
    local externally_read = history.read(history_config)
    local external_count = 0
    for _, entry in ipairs(externally_read) do
      if entry.event_id == "review-external" then
        external_count = external_count + 1
      end
    end
    assert_equal(external_count, 1, "an externally appended event ID is not duplicated by a stale cache")

    local recreated_config = { flashcards_dir = test_root .. "/history-recreated" }
    local recreated_event = assert(history.new_event(history_card, 3, fixed_now + 3, {
      event_id = "review-recreated",
    }))
    assert_true(history.append(recreated_event, recreated_config), "recreated-history fixture appends once")
    assert_equal(vim.fn.delete(history.path(recreated_config)), 0, "history fixture can be removed externally")
    assert_true(
      history.append(recreated_event, recreated_config),
      "an event ID is written again after its history file is removed"
    )
    local recreated_entries, recreated_errors = history.read(recreated_config)
    assert_equal(#recreated_errors, 0, "recreated history remains readable")
    assert_equal(#recreated_entries, 1, "a stale event-ID cache cannot suppress recreation")
    assert_equal(recreated_entries[1].event_id, "review-recreated", "recreated history keeps the requested event")

    local recovered_lock_config = { flashcards_dir = test_root .. "/history-dead-lock" }
    local recovered_lock_path = history.path(recovered_lock_config)
    vim.fn.mkdir(vim.fn.fnamemodify(recovered_lock_path, ":h"), "p")
    vim.fn.writefile({ "99999999:dead-history-owner" }, recovered_lock_path .. ".lock")
    local recovered_lock_event = assert(history.new_event(history_card, 2, fixed_now + 4, {
      event_id = "review-after-dead-lock",
    }))
    assert_true(
      history.append(recovered_lock_event, recovered_lock_config),
      "a demonstrably dead history-lock owner is recovered"
    )
    assert_equal(vim.fn.filereadable(recovered_lock_path .. ".lock"), 0, "recovered history lock is released")
    local recovered_lock_entries = history.read(recovered_lock_config)
    assert_equal(#recovered_lock_entries, 1, "dead-lock recovery preserves the waiting event")
  end

  do
    local invalid_epoch_config = { flashcards_dir = test_root .. "/history-invalid-epoch" }
    local invalid_epoch_path = history.path(invalid_epoch_config)
    vim.fn.mkdir(vim.fn.fnamemodify(invalid_epoch_path, ":h"), "p")
    vim.fn.writefile({
      vim.json.encode({
        version = 1,
        type = "review",
        event = "rated",
        event_id = "review-unrepresentable-epoch",
        card_id = "fc_history_epoch",
        rating = 3,
        epoch = 1e300,
      }),
      vim.json.encode({
        version = 1,
        type = "review",
        event = "rated",
        event_id = "review-missing-epoch",
        card_id = "fc_history_epoch",
        rating = 2,
      }),
    }, invalid_epoch_path)

    local invalid_epoch_entries, invalid_epoch_errors = history.read(invalid_epoch_config)
    assert_equal(#invalid_epoch_entries, 0, "invalid epochs are excluded from analytics input")
    assert_equal(#invalid_epoch_errors, 2, "invalid epochs are reported per history line")
    assert_contains(
      invalid_epoch_errors[1],
      "representable date range",
      "unrepresentable epoch errors explain the platform date limit"
    )
    assert_contains(
      invalid_epoch_errors[2],
      "requires an epoch or timestamp",
      "persisted events cannot acquire a different timestamp on every read"
    )
    local metrics_ok = pcall(stats.metrics, {}, invalid_epoch_entries, fixed_now)
    assert_true(metrics_ok, "rejected history epochs cannot crash analytics")
    local invalid_event, invalid_event_error = history.new_event(
      { values = { id = "fc_history_epoch" } },
      3,
      1e300,
      { event_id = "review-unrepresentable-new" }
    )
    assert_equal(invalid_event, nil, "new events reject unrepresentable epochs")
    assert_contains(invalid_event_error, "representable date range", "new-event validation reports the epoch limit")
    for label, invalid_epoch in pairs({
      nan = math.huge - math.huge,
      positive_infinity = math.huge,
      negative_infinity = -math.huge,
    }) do
      local finite_event, finite_error = history.new_event(
        { values = { id = "fc_history_epoch" } },
        3,
        invalid_epoch,
        { event_id = "review-nonfinite-" .. label }
      )
      assert_equal(finite_event, nil, label .. " is rejected as a history epoch")
      assert_contains(finite_error, "finite number", label .. " reports finite-epoch validation")
    end
  end

  do
    local strict_history_config = { flashcards_dir = test_root .. "/history-strict-shape" }
    local strict_history_path = history.path(strict_history_config)
    vim.fn.mkdir(vim.fn.fnamemodify(strict_history_path, ":h"), "p")
    vim.fn.writefile({
      vim.json.encode({
        type = "review",
        event = "rated",
        card_id = "fc_history_shape",
        rating = 3,
        epoch = fixed_now,
      }),
      vim.json.encode({
        version = 1,
        event = "rated",
        card_id = "fc_history_shape",
        rating = 3,
        epoch = fixed_now,
      }),
      vim.json.encode({
        version = 1,
        type = "review",
        card_id = "fc_history_shape",
        rating = 3,
        epoch = fixed_now,
      }),
    }, strict_history_path)
    local strict_entries, strict_errors = history.read(strict_history_config)
    assert_equal(#strict_entries, 0, "incomplete history records are excluded")
    assert_equal(#strict_errors, 3, "every incomplete history record is reported")
    assert_contains(strict_errors[1], "numeric version", "unversioned history is rejected")
    assert_contains(strict_errors[2], "type must be", "history type is required")
    assert_contains(strict_errors[3], "action is invalid", "history event name is required")
  end

  do
    local analytic_entries = {
      { type = "review", event = "rated", event_id = "a", epoch = fixed_now - 86400, rating = 1, duration_ms = 1000 },
      {
        type = "review",
        event = "rated",
        event_id = "b",
        epoch = fixed_now - 2 * 86400,
        rating = 2,
        duration_ms = 3000,
      },
      {
        type = "review",
        event = "rated",
        event_id = "c",
        epoch = fixed_now - 3 * 86400,
        rating = 3,
        duration_ms = 5000,
        hint_used = true,
      },
      { type = "review", event = "undo", epoch = fixed_now, rating = 1, undo_of = "a" },
    }
    local analytic_cards = {
      { values = { id = "fc_a", japanese = "A" } },
      {
        values = {
          id = "fc_b",
          japanese = "B",
          reps = "3",
          interval = "4",
          due = "2026-08-19 08:00",
        },
      },
      {
        values = {
          id = "fc_c",
          japanese = "C",
          reps = "3",
          interval = "4",
          due = "2026-08-22 12:00",
        },
      },
      {
        values = {
          id = "fc_d",
          japanese = "D",
          reps = "3",
          interval = "4",
          availability = "suspended",
          due = "2020-01-01 00:00",
        },
      },
      {
        values = {
          id = "fc_e",
          japanese = "E",
          reps = "3",
          interval = "4",
          availability = "buried",
          available_at = "2026-08-21 00:00",
          due = "2020-01-01 00:00",
        },
      },
    }
    local metrics = stats.metrics(analytic_cards, analytic_entries, fixed_now)
    assert_equal(metrics.reviews, 2, "analytics excludes an undone answer")
    assert_equal(metrics.retention_7, 100, "retention treats Hard and Good as successful recalls")
    assert_equal(metrics.retention_7_count, 2, "retention reports its sample size")
    assert_equal(metrics.median_duration_ms, 4000, "analytics reports median answer duration")
    assert_equal(metrics.hints, 1, "analytics counts answers that used hints")
    assert_equal(metrics.new, 1, "analytics counts lifecycle states")
    assert_equal(metrics.review, 4, "analytics counts mature review cards")
    assert_equal(metrics.due, 2, "analytics due count excludes buried and suspended cards")
    assert_equal(metrics.overdue, 1, "analytics separates overdue from due-today cards")
    assert_equal(metrics.suspended, 1, "analytics counts suspended cards")
    assert_equal(metrics.buried, 1, "analytics counts buried cards")
    local forecast = stats.forecast_counts(analytic_cards, fixed_now, 7)
    assert_equal(forecast[1], 2, "forecast puts new and overdue active cards in today's bucket")
    assert_equal(vim.tbl_count(forecast), 7, "forecast returns the requested horizon")
  end

  do
    local health_cards = {
      {
        kind = "japanese",
        path = collection_dir .. "/health.norg",
        start_line = 1,
        values = { id = "fc_health_duplicate", japanese = "same", english = "one" },
      },
      {
        kind = "japanese",
        path = collection_dir .. "/health.norg",
        start_line = 7,
        values = {
          id = "fc_health_duplicate",
          japanese = "same",
          english = "two",
          due = "never",
          interval = "minus",
          lifecycle = "forgotten",
          lapses = "8",
        },
      },
      {
        kind = "japanese",
        path = collection_dir .. "/health.norg",
        start_line = 15,
        values = { japanese = "missing id", english = "three" },
      },
    }
    local health_issues = health.inspect(collection_config, health_cards)
    local issue_codes = {}
    for _, issue in ipairs(health_issues) do
      issue_codes[issue.code] = true
    end
    for _, code in ipairs({
      "duplicate_id",
      "duplicate_front",
      "invalid_due",
      "invalid_interval",
      "invalid_lifecycle",
      "leech",
      "missing_id",
    }) do
      assert_true(issue_codes[code], "collection health reports " .. code)
    end
    local health_counts = health.counts(health_issues)
    assert_true(health_counts.error >= 3, "collection health distinguishes hard errors")
    assert_true(health_counts.warn >= 3, "collection health distinguishes actionable warnings")
  end

  T.fixed_now = fixed_now
end
