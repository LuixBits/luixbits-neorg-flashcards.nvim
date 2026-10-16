# Changelog

All notable changes to this project will be documented here.

## Unreleased

## 0.3.1 - 2026-10-16

- Reworked card entry with labels above each input, front/answer roles,
  explicit required/optional markers, and more space between fields. The
  header shows collection, chapter, type, and destination, including the
  previously hidden context above the first field.
- Made the form follow theme input colors and ASCII-border settings. Save
  controls appear first, and Tab/Shift-Tab navigate in both editing modes.
- Made Notes and other multiline fields directly editable in the same form.
  Tab and Enter preserve Insert mode across every field; Ctrl-S saves the whole
  card. Multiline paste, native o/O, and undo/redo preserve field boundaries,
  line breaks, and indentation. Paragraphs wrap within the composer.
- Protected composer controls from completion and pairing plugin mappings.
  Fixed Tab and Ctrl-N being replaced by Blink in a configured editor.

## 0.3.0 - 2026-10-16

- Added directional Ctrl-h/j/k/l pane navigation alongside native Ctrl-W keys.
  Review uses h/Left to return, l/Right to reveal, and j/k or arrows to browse.
  H now shows a hint; Enter/Space reveal and q/Esc close still work. The card
  form also accepts Up/Down in Normal mode.
- Wrapped shortcut help in narrow windows and aligned the key columns, even
  when the user's editing windows use nowrap.
- Kept Stats scrolling controls visible in narrow shortcut ribbons and moved
  review source filenames into workspace chrome outside the study card.
  Clarified the difference between burying until tomorrow and suspending until
  manually resumed.
- Added a collection → chapter → card manager with contextual create, rename,
  move, and confirmed removal. Chapters are independent of filenames and tags;
  existing cards appear in Unfiled. Chapter-from-tag preserves the source tags.
- Framed and tightened the Desk, removed decorative filler, and added useful
  pending/reviewed stack counts: unseen, retries, finished, set aside, and ratings.
- Rebalanced Stats around a bounded calendar, visible progress, ratings, recall
  trends, forecast, and a separate selected-day pane. Short windows retain the
  selected date and resizing keeps keyboard focus in active reviews.
- Isolated app buffers from inherited whitespace markers and Neorg concealment
  using their own filetype and local window options. Note editing is unchanged.

- Reworked the workspace into Desk, Overview, and Stats. Desk shows collection
  boxes and chapter/tag notes, opens due-only stacks, and keeps review on the same
  canvas with pending/reviewed piles and a completion receipt. `cards` remains
  an alias for the manager in Overview.
- Added theme-linked desk highlights, plain ASCII borders, responsive layouts,
  and short cancellable animations with `ui.motion = false` for reduced motion.
  Rating keys now require explicit Enter/Space reveal, preventing a held rating
  key from revealing and rating the next question.
- Added category labels, accents, ordering, empty notes, and confirmed tag
  rename/merge/removal with recoverable source snapshots. New cards inherit the
  selected category. Overview's `m` menu can create isolated decks, enable
  bundled types, choose defaults, and detach UI-created decks without deleting
  their files. Lua/Nix settings remain owned by the user's configuration.
- Added a navigable month calendar, day details and card drilldown, current
  schedule snapshots, weekly card-day comparisons, daily unique-card goals,
  saved goal stamps, and desk streak feedback. Retries count once per day;
  undo reverses progress. Durable pending history is shown provisionally and
  deduplicated on delivery.

- Replaced the flat single-root setup with required named collections. Each
  collection owns its path, default file, schemas, default card type, scheduler
  settings, leech threshold, and `reviews.jsonl`; overlapping roots and shared
  ledger files are rejected. Removed v0.2 setup keys are not translated into an
  implicit collection.
- Added a buffer-local collection picker on `C`, the
  `:Flashcards collection [id]` route, active-collection labels, command
  completion, and collection-scoped Cards, Stats, health, review, and history.
  The picker switches configured and UI-created collections; creation lives in
  Overview's management menu.
  An active form or review cannot be retargeted by switching collections or
  re-running setup. An open idle hub reloads against the new configuration.
- Changed the NVF `schemaPresets` option from a list to an attribute set keyed by
  collection ID. Its opt-in keymap remains one exact hub mapping, `<leader>nc`.
- Added bundled `question_answer`, `term_definition`, and `code_output` types.
  Japanese collections can opt into `English → Japanese word`,
  `Kanji → reading + meaning`, and `Japanese sentence → English` beside the
  default `Japanese word → reading + English` type. Default examples keep one
  type per collection. Bare add opens it directly and shows a picker only when
  the active collection explicitly enables several; Cards can filter by type.
- Added schema-gated multiline fields. Long values are stored as explicit
  `field: |` blocks with a two-space container indent relative to the card
  directive and edited in a focused scratch buffer from the protected composer.
  Scalar field syntax is unchanged; implicit v0.2 continuation lines require
  conversion.
- Added a `typed_answer` field capability. The `t` review action appears only
  for cards with opted-in reveal values, shows an aligned exact/close/miss
  comparison, removes built-in prompt entries from Neovim input history, bounds
  fuzzy-comparison work, and leaves the attempt in memory instead of card source
  or review history.
- Added Card Clinic inside the Cards filter picker. It derives transparent
  attention reasons from lapses, effective recent ratings, and hint use; the
  card detail pane shows those reasons and a recent recall trail. Stats points
  users from its Needs attention summary to the same Cards view.
- Added `collection_id` and `card_type` to new review events without changing
  the ledger version. A v0.2 ledger remains readable when its existing root is
  assigned to one named collection. An event that explicitly names another
  collection is reported and excluded from that ledger's analytics.

- Removed the generic Overview and Stats subtitles. Help popups now advertise
  their native `/` search and `n`/`N` match navigation.
- Centralized every plugin highlight group and restored them after colorscheme
  changes. Rating and heatmap colors can be overridden when a theme needs it.
- Replaced the fixed-green, color-only heatmap with theme-linked levels,
  distinct activity glyphs, and a compact legend.
- Removed the never-emitted `new` and `soon` timing branches. New remains a
  lifecycle state; timing is now consistently due, overdue, or scheduled.
- Limited rating colors to generated controls and summaries so words such as
  `Good` in card content keep the normal card highlight.
- Added lazy.nvim and Nix examples for the unreleased main branch, a
  native-package install path, an end-to-end first-card walkthrough, a full
  configuration reference, and practical troubleshooting steps.
- Added the canonical `:help neorg-flashcards` entry and made the shorter `H`
  window identify itself as a quick guide with current shortcuts.
- Moved the identical source and history token-lock lifecycle into one tested
  helper while keeping their path validation and write policies separate.
- Made the public Lua API return stable booleans, validation data, and
  `ok, message, persisted` mutation results. `command()` now preserves routed
  return values. Collection validation includes history diagnostics.
- Added Luacheck to local and Nix validation and fixed the complete initial
  warning set without broad per-file suppressions.
- Removed the Remotion explainer subproject under `video/` together with its
  CI job; the YouTube explainer content no longer lives in this repository.

## 0.2.0 - 2026-08-22

- Replaced the command-per-action interface with one `:Flashcards` command and
  routes for overview, cards, stats, review, add, open, check, and help. Removed
  the old `:NeorgFlashcard*` aliases before release.
- Renamed the setup schema registry from `languages` to `schemas` and the NVF
  preset option from `languagePresets` to `schemaPresets`; the old names are
  rejected instead of kept as aliases.
- Rebuilt the dashboard as a responsive full-tab hub with Overview, Cards, and
  Stats pages, contextual statusline hints, generated `?` help, page shortcuts,
  and stacked or column layouts based on the available width.
- Added a complete card browser with text search, state filters, due/front/
  state/source sorting, card details, preview, structured editing, source
  repair, suspend/resume, and bury/unbury actions. Invalid blocks, including
  duplicate-ID cards, stay visible for repair but are excluded from review and
  scheduling actions.
- Expanded analytics with total and daily activity, streak, 7/30/90-day
  retention, 30-day answer distribution, lifecycle and availability counts,
  leeches, median answer time, estimated workload, a responsive heatmap, a
  seven-day forecast, tag-group sizes, and weak-card hints.
- Made review sessions finite. Again retries each card at most once per
  session; the popup now shows queue progress, progressive `h` hints, next
  intervals, `u` undo, `b` bury, `x` suspend, contextual `?` help, and a
  completion summary.
- Added stable opaque card IDs. New cards receive IDs automatically; ID-less
  blocks are invalid and require manual conversion before upgrading from v0.1.
- Split displayed card state into lifecycle (`new`, `learning`, `review`,
  `relearning`), timing, and availability (`active`, `suspended`, `buried`).
  Ratings now also maintain `reps`, `lapses`, and `lifecycle`.
- Added versioned append-only `reviews.jsonl` events carrying stable card,
  timing, duration, hint, state, and session context. Undo is recorded as a
  compensating event.
- Added collection health inspection for IDs, duplicate fronts, scheduling
  metadata, lifecycle values, and leeches through `:Flashcards check` and
  `:checkhealth neorg_flashcards`.
- Reduced the opt-in NVF keymaps to one exact hub mapping at `<leader>nc` and
  removed the older suffix layout and which-key registration options.
- Added contextual shortcut help to the hub, review, and card form. Persistent
  hints are on by default and can be hidden with `ui.show_shortcuts = false`
  without disabling mappings or `?` help.
- Replaced sequential add prompts with a reusable editable form buffer and
  added cloze masking, UTF-8-aware typed-answer checking, due-review queues,
  next-due hints, and source context in review.
- Rebuilt flashcard creation as a target-aware composer with immutable virtual
  labels, field hints, inline validation, dirty-draft confirmation, explicit
  save and save-and-new actions, hard deletion boundaries, and failure-safe
  transactional writes. Valid cards now use the same composer for structured
  edits while preserving identity and scheduler metadata.
- Rejected add targets and configured history paths outside `flashcards_dir`,
  including a misconfigured `default_file`, so collection writes cannot
  silently land in unrelated notes. Setup creates and pins the collection root;
  configured relative paths are frozen, guarded open and add paths recheck the
  boundary, and a moved, replaced, or symlink-retargeted root is rejected until
  setup runs again.
- Preserved unsaved loaded-buffer edits during collection and review; stale
  sources stop metadata writes before the wrong card can be changed. Review
  history for a modified source waits until that source is saved, and undo
  before the save cancels the pending event. Failed history appends after a
  persisted source change enter a durable state-directory outbox for retry.
  Source, ledger, and outbox replacements are locked and revalidated against
  the snapshot read before their final atomic rename.
- Raised the declared minimum Neovim version to 0.10.4 and kept Linux and macOS
  as the supported v0.2 platforms.
- Changed the first Hard (`2`) interval from 12 hours to 6 hours and preserved
  quarter-day precision for sub-day scheduling. Added a configurable 365-day
  maximum interval so repeated successful reviews remain bounded.
- Kept contextual hub shortcuts visible in the winbar under global statuslines
  and added focus-aware line, half-page, and top/bottom navigation to both hub
  panes.
- Added theme-linked Again, Hard, and Good highlights with configuration hooks
  for colorschemes that need different rating colors.
- Added confirmed `D` deletion to the Cards page, including malformed and
  duplicate-ID blocks, with stale-source and unsaved-buffer protection while
  retaining append-only review history. Unloaded-source deletions first save
  one recoverable `<source>.flashcards-backup` copy.
- Expanded the README, Vim help, public Lua API documentation, headless and
  clean-install coverage, Neovim compatibility checks, and Nix flake checks.

## 0.1.0 - 2026-07-01

- Extracted the flashcard workflow into a standalone Neovim plugin.
- Added opt-in Japanese and Chinese language presets.
- Added generic `:NeorgFlashcardAdd [kind]` support.
- Added in-editor help, review-by-tag, review-by-score, and 1/2/3 ratings.
- Added headless Neovim tests, clean-config checks, and CI.
