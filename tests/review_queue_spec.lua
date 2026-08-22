return function(T)
  local flashcards = require("neorg_flashcards")

  local assert_true = T.assert_true
  local assert_contains = T.assert_contains
  local current_popup = T.current_popup
  local collection_dir = T.collection_dir

  vim.fn.writefile({
    "@flashcard japanese",
    "id: fc_due_past",
    "japanese: 過去",
    "english: past",
    "due: 2020-01-01 00:00",
    "@end",
    "",
    "@flashcard japanese",
    "id: fc_due_future",
    "japanese: 未来",
    "english: future",
    "due: 2999-01-01 00:00",
    "@end",
  }, collection_dir .. "/due-check.norg")

  vim.cmd("Flashcards review due")
  local _, due_text = current_popup()
  assert_contains(due_text, "due | 1/3", "due review keeps only due and new cards")
  assert_true(not due_text:find("未来", 1, true), "due review skips cards scheduled in the future")
  flashcards.close_review()

  local requeue_path = collection_dir .. "/requeue.norg"
  vim.fn.writefile({
    "@flashcard japanese",
    "id: fc_requeue_morning",
    "japanese: 朝",
    "english: morning",
    "@end",
    "",
    "@flashcard japanese",
    "id: fc_requeue_night",
    "japanese: 夜",
    "english: night",
    "@end",
  }, requeue_path)
  vim.cmd.edit(vim.fn.fnameescape(requeue_path))

  vim.cmd("Flashcards review file")
  local _, requeue_initial = current_popup()
  assert_contains(requeue_initial, "file | 1/2", "requeue fixture starts with two cards")
  flashcards.rate_current(1)
  local _, requeue_text = current_popup()
  assert_contains(requeue_text, "file | 2/3", "Again requeues the card within the session")
  flashcards.close_review()

  local requeue_disk = table.concat(vim.fn.readfile(requeue_path), "\n")
  assert_contains(requeue_disk, "score: 1", "Again persists the score")
  assert_contains(requeue_disk, "due: ", "Again persists a due timestamp")
  assert_contains(requeue_disk, "interval: 0", "Again persists the reset interval")
  assert_contains(requeue_disk, "ease: 2.3", "Again persists the lowered ease")
  vim.cmd("silent! bwipeout!")
  vim.fn.delete(requeue_path)

  vim.fn.writefile({
    "@flashcard japanese",
    "id: fc_overview_mountain",
    "japanese: 山",
    "english: mountain",
    "tags: nature hiking",
    "score: 1",
    "due: 2020-01-01 00:00",
    "@end",
    "",
    "@flashcard japanese",
    "id: fc_overview_river",
    "japanese: 川",
    "english: river",
    "tags: nature",
    "@end",
  }, collection_dir .. "/overview-check.norg")
end
