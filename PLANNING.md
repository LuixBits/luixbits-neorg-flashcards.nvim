# Planning

## 0.2: One Flashcard Workspace

The 0.2 design reduces the global interface to one command and, for NVF users,
one shortcut. `:Flashcards` opens the workspace; actions inside it are local,
visible, and contextual.

### Implemented scope

- One command router for Overview, Cards, Stats, review scopes, add, open,
  collection check, stable-ID migration, and help.
- A responsive full-tab hub with page tabs, contextual footer hints, and `?`
  help generated from the same action catalogue as the actual mappings.
- An Overview page for the due queue and tag groups.
- A Cards page for every card and state, with search, filters, sorting, card
  details, preview, source editing, suspend, and bury. Invalid blocks remain
  visible for repair but are excluded from review and scheduling actions.
- A Stats page for activity, retention, ratings, state counts, leeches, answer
  time, estimated workload, heatmap, forecast, tag groups, and weak cards.
- A finite review queue with reveal-before-rating, progressive hints, typed
  answers, Again retry, interval previews, undo, bury, suspend, and completion
  summary.
- Stable card IDs, lifecycle/repetition/lapse metadata, availability state,
  safe legacy migration, collection health checks, and versioned JSONL history.
- One opt-in NVF hub mapping at `<leader>nc`, with the old suffix mappings
  available through `keymaps.mode = "legacy"`.
- Compatibility aliases for existing `:NeorgFlashcard*` users and scripts.

### Interaction model

The hub has three pages because they answer different questions:

| Page | Question | Primary action |
| --- | --- | --- |
| Overview | What should I study now? | Start the due queue |
| Cards | What cards do I have, and what state are they in? | Find and act on one card |
| Stats | How is review going over time? | Inspect trends, then start a queue |

Only the hub shortcut is global. Page selection, search, filtering, card
actions, review controls, form controls, and help are buffer-local.

### State model

Card state is deliberately split instead of compressed into one overloaded
label:

- Lifecycle: `new`, `learning`, `review`, or `relearning`.
- Timing: `new`, `due`, `overdue`, `soon`, or `scheduled`, derived from `due`.
- Availability: `active`, `suspended`, or `buried`; buried cards can have an
  `available_at` time.

Stable IDs connect source cards to append-only review events. Legacy cards
remain readable before migration, while collection checks make missing and
duplicate IDs visible. Every copy of a duplicate ID is treated as invalid so
history and scheduling state cannot attach to the wrong block.

### Compatibility and migration

- Keep the `:NeorgFlashcard*` commands for compatibility, but document
  `:Flashcards` first.
- Generate an ID for every new card and when an ID-less card is rated.
- Keep `:Flashcards migrate` explicit, previewed, and confirmed. Preflight all
  source files before the first write and do not overwrite unsaved buffers.
- Continue reading `reviews.log`; write new persisted review events to
  `reviews.jsonl`. Queue history for modified source buffers until save, and
  cancel the pending event when a rating is undone before save.
- Keep the NVF legacy mapping layout as an opt-in mode rather than deleting it.

### Release gate

Before tagging 0.2.0:

1. Run `bash scripts/test.sh`.
2. Run `bash scripts/check-clean-install.sh`.
3. Run `nix flake check --print-build-logs`.
4. Smoke-test the hub in wide and narrow windows.
5. Test ID migration on clean files and on loaded, modified buffers.
6. Finish a review containing an Again retry, then test undo from the
   completion screen.
7. Confirm the NVF hub mode emits only `<leader>nc` and legacy mode still emits
   the suffix group.

## Later Candidates

These are ideas, not 0.2 promises:

- Saved browser filters as named study decks.
- Daily new-card and review limits.
- Sibling bury for related cloze cards.
- Tag and metadata editing without leaving the Cards page.
- A pluggable scheduler interface, with FSRS as an optional future model once
  the history contains enough useful review data.
- Import/export helpers that preserve stable IDs and plain-text ownership.
- Additional history views such as per-tag retention and interval growth.

Sync, accounts, and a database are still outside the core direction. The notes
remain the source of truth.
