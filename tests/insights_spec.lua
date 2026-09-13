return function(T)
  local answer_diff = require("neorg_flashcards.answer_diff")
  local card_insights = require("neorg_flashcards.card_insights")
  local stats = require("neorg_flashcards.stats")

  local assert_true = T.assert_true
  local assert_equal = T.assert_equal

  do
    local exact = answer_diff.compare("  TOKYO   station ", "tokyo station")
    assert_equal(exact.status, "exact", "answer comparison ignores case and repeated whitespace")
    assert_equal(exact.distance, 0, "normalized equal answers have no edit distance")
    assert_equal(exact.actual.start_col, nil, "exact answers have no changed range")

    local missing = answer_diff.compare("とうきょ", "とうきょう")
    assert_equal(missing.status, "close", "one missing Japanese character is a close answer")
    assert_equal(missing.actual.text, "とうきょ·", "missing text is visible without relying on color")
    assert_equal(missing.expected.text, "とうきょう", "expected Japanese text stays intact")
    assert_equal(missing.actual.start_col, 12, "UTF-8 changed ranges use byte columns")
    assert_equal(missing.actual.end_col, 14, "the missing marker has an exact byte range")
    assert_equal(missing.expected.start_col, 12, "expected UTF-8 change starts at the same character")
    assert_equal(missing.expected.end_col, 15, "expected UTF-8 change covers the missing character")

    assert_equal(answer_diff.compare("", "猫").status, "miss", "a blank one-character answer is not close")
    assert_equal(answer_diff.compare("犬", "猫").status, "miss", "a wrong one-character answer is not close")

    local extra = answer_diff.compare("caat", "cat")
    assert_equal(extra.actual.text, "caat", "extra input remains readable")
    assert_equal(extra.expected.text, "ca·t", "the expected line aligns an extra input character")
    assert_equal(extra.actual.start_col, 2, "extra character range starts after the common prefix")
    assert_equal(extra.expected.end_col - extra.expected.start_col, 2, "gap marker reports its byte width")

    local best, index = answer_diff.best("とうきょう", { "Tokyo", "とうきょう" })
    assert_equal(index, 2, "closest-answer matching selects the correct reveal candidate")
    assert_equal(best.status, "exact", "the closest reveal candidate keeps its comparison result")
    assert_equal(answer_diff.best("anything", { "", "   " }), nil, "empty reveal candidates are ignored")

    local long_answer = string.rep("a", answer_diff.MAX_COMPARE_CHARS + 1)
    local long_exact = answer_diff.compare(long_answer, long_answer)
    assert_equal(long_exact.status, "exact", "long exact answers do not need fuzzy matching")
    assert_true(long_exact.truncated, "long typed-answer output is bounded for display")
    local long_miss = answer_diff.compare(long_answer, long_answer .. "b")
    assert_equal(long_miss.status, "miss", "long non-exact answers skip expensive fuzzy matching")
    assert_true(long_miss.truncated, "long fuzzy comparisons report their bounded result")
  end

  do
    local now = os.time({ year = 2026, month = 8, day = 22, hour = 12 })
    local rating_lines = stats.ratings_section({
      {
        type = "review",
        event = "rated",
        event_id = "once-hard",
        card_id = "fc_once_hard",
        rating = 2,
        epoch = now,
      },
      {
        type = "review",
        event = "rated",
        event_id = "once-good",
        card_id = "fc_once_good",
        rating = 3,
        epoch = now,
        hint_used = true,
      },
    }, now, 42)
    assert_true(rating_lines[3]:match("%s1$") ~= nil, "30-day Hard totals count each review once")
    assert_true(rating_lines[4]:match("%s1$") ~= nil, "30-day Good totals count each review once")
    assert_true(rating_lines[5]:find("1 hint-assisted", 1, true) ~= nil, "30-day hint totals count each review once")
  end

  do
    local now = os.time({ year = 2026, month = 8, day = 22, hour = 12 })
    local struggling = {
      values = { id = "fc_struggling", score = "1", lapses = "8", availability = "active" },
    }
    local steady = { values = { id = "fc_steady", score = "3", availability = "active" } }
    local suspended = {
      values = { id = "fc_suspended", score = "1", lapses = "9", availability = "suspended" },
    }
    local preledger = { values = { id = "fc_preledger", score = "1", availability = "active" } }
    local entries = {
      {
        type = "review",
        event = "rated",
        event_id = "struggle-1",
        card_id = "fc_struggling",
        rating = 1,
        epoch = now - 300,
        due = now + 300,
        hint_used = true,
      },
      {
        type = "review",
        event = "undo",
        undo_of = "steady-undone",
        card_id = "fc_steady",
        rating = 1,
        epoch = now - 260,
      },
      {
        type = "review",
        event = "rated",
        event_id = "steady-undone",
        card_id = "fc_steady",
        rating = 1,
        epoch = now - 250,
      },
      {
        type = "review",
        event = "rated",
        event_id = "struggle-2",
        card_id = "fc_struggling",
        rating = 2,
        epoch = now - 200,
        due = now + 6 * 3600 - 200,
        hints_used = 1,
      },
      {
        type = "review",
        event = "rated",
        event_id = "struggle-3",
        card_id = "fc_struggling",
        rating = 1,
        epoch = now - 100,
        due = now + 500,
      },
      {
        type = "review",
        event = "rated",
        event_id = "steady-good",
        card_id = "fc_steady",
        rating = 3,
        epoch = now - 50,
        after = { interval = "3" },
      },
    }

    local result = card_insights.build(
      { leech_threshold = 8 },
      { struggling, steady, suspended, preledger },
      entries,
      now
    )
    local struggle = result.by_card[struggling]
    assert_equal(#struggle.reviews, 3, "per-card insight keeps only that card's effective ratings")
    assert_equal(#struggle.recent_reviews, 3, "attention signals use a bounded recent window")
    assert_equal(struggle.reasons[1].code, "leech", "leech state is the strongest attention reason")
    assert_equal(struggle.reasons[2].code, "repeated_again", "two recent Again ratings are explicit")
    assert_equal(struggle.reasons[3].code, "frequent_hints", "repeated hint use is explicit")
    assert_true(struggle.needs_attention, "an active struggling card enters Card clinic")
    assert_equal(#result.by_card[steady].reviews, 1, "an undo removes its original rating from card history")
    assert_equal(#result.by_card[steady].reasons, 0, "a steady card has no clinic reason")
    assert_true(not result.by_card[suspended].needs_attention, "suspending a card removes it from Card clinic")
    assert_equal(result.by_card[preledger].reasons[1].code, "last_again", "stored score covers pre-ledger cards")
    assert_equal(#result.attention, 2, "only active cards with reasons enter the clinic list")
    assert_equal(result.attention[1].card, struggling, "clinic cards sort by strongest signal first")

    local trail = card_insights.recall_trail(struggle, 2)
    assert_equal(#trail, 2, "recall trail respects its display limit")
    assert_equal(trail[1].rating, 2, "recall trail remains chronological after trimming")
    assert_equal(trail[1].interval_seconds, 6 * 3600, "trail derives intervals from due and review epochs")
    assert_equal(trail[2].rating, 1, "newest recall stays on the right")
    assert_equal(trail[2].interval_seconds, 600, "Again trail keeps its short interval")

    local steady_trail = card_insights.recall_trail(result.by_card[steady], 5)
    assert_equal(steady_trail[1].interval_seconds, 3 * 86400, "trail falls back to the saved interval snapshot")
  end
end
