# Changelog

All notable changes to this project will be documented here.

## Unreleased

- Changed the first Hard (`2`) interval from 12 hours to 6 hours and preserved
  quarter-day precision for sub-day scheduling.
- Rebuilt flashcard creation as a target-aware composer with immutable virtual
  labels, field hints, inline validation, dirty-draft confirmation, explicit
  save and save-and-new actions, hard deletion boundaries, and failure-safe
  transactional writes.

## 0.2.0 - 2026-08-21

- Replaced the command-per-action interface with one `:Flashcards` command and
  routes for overview, cards, stats, review, add, open, check, migrate, and
  help. Removed the old `:NeorgFlashcard*` aliases before release.
- Rebuilt the dashboard as a responsive full-tab hub with Overview, Cards, and
  Stats pages, contextual statusline hints, generated `?` help, page shortcuts,
  and stacked or column layouts based on the available width.
- Added a complete card browser with text search, state filters, due/front/
  state/source sorting, card details, preview, source editing, suspend/resume,
  and bury/unbury actions. Invalid blocks, including duplicate-ID cards, stay
  visible for repair but are excluded from review and scheduling actions.
- Expanded analytics with total and daily activity, streak, 7/30/90-day
  retention, 30-day answer distribution, lifecycle and availability counts,
  leeches, median answer time, estimated workload, a responsive heatmap, a
  seven-day forecast, tag-group sizes, and weak-card hints.
- Made review sessions finite. Again retries each card at most once per
  session; the popup now shows queue progress, progressive `h` hints, next
  intervals, `u` undo, `b` bury, `x` suspend, contextual `?` help, and a
  completion summary.
- Added stable opaque card IDs. New cards receive IDs automatically, ratings
  backfill them when needed, and `:Flashcards migrate` performs a previewed,
  confirmed, all-source-preflight migration for legacy collections.
- Split displayed card state into lifecycle (`new`, `learning`, `review`,
  `relearning`), timing, and availability (`active`, `suspended`, `buried`).
  Ratings now also maintain `reps`, `lapses`, and `lifecycle`.
- Replaced new aggregate log writes with versioned append-only
  `reviews.jsonl` events carrying stable card, timing, duration, hint, state,
  and session context. Analytics still reads the legacy `reviews.log`, and
  undo is recorded as a compensating event.
- Added collection health inspection for IDs, duplicate fronts, scheduling
  metadata, lifecycle values, and leeches through `:Flashcards check` and
  `:checkhealth neorg_flashcards`.
- Reduced the opt-in NVF keymaps to one exact hub mapping at `<leader>nc` and
  removed the older suffix layout and which-key registration options.
- Added contextual shortcut help to the hub, review, and add form. Persistent
  hints are on by default and can be hidden with `ui.show_shortcuts = false`
  without disabling mappings or `?` help.
- Replaced sequential add prompts with a reusable editable form buffer and
  added cloze masking, UTF-8-aware typed-answer checking, due-review queues,
  next-due hints, and source context in review.
- Preserved unsaved loaded-buffer edits during collection, review, and ID
  migration; stale sources stop metadata writes before the wrong card can be
  changed. Review history for a modified source waits until that source is
  saved, and undo before the save cancels the pending event.
- Expanded the README, Vim help, public Lua API documentation, headless and
  clean-install coverage, Neovim compatibility checks, and Nix flake checks.

## 0.1.0 - 2026-07-01

- Extracted the flashcard workflow into a standalone Neovim plugin.
- Added opt-in Japanese and Chinese language presets.
- Added generic `:NeorgFlashcardAdd [kind]` support.
- Added in-editor help, review-by-tag, review-by-score, and 1/2/3 ratings.
- Added headless Neovim tests, clean-config checks, and CI.
