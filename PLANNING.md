# Planning

The plugin is moving in small vertical slices. Each slice must leave the
existing Japanese collection usable, keep plain-text cards as the source of
truth, and include the UI, data path, tests, and documentation needed to make
the feature understandable.

The architectural choices behind this plan live in
[`docs/adr/`](docs/adr/README.md).

## 0.2: Finish the unified workspace

Status: release candidate (2026-08-22)

The 0.2 release replaces the command-per-action interface with one workspace.

- Keep one command, `:Flashcards`, and one optional NVF shortcut.
- Remove old `:NeorgFlashcard*` aliases, hidden route nicknames, the NVF suffix
  keymap mode, review `n`/`p`, and the hub's obsolete `s` pane bridge.
- Generate buffer-local mappings, persistent hints, and `?` help from one
  action catalogue across the hub, review window, and card form.
- Replace the prefix-based add buffer with a target-aware composer: immutable
  virtual labels, field hints, inline validation, dirty-draft protection,
  explicit save and save-and-new actions, and transactional persistence.
- Add `ui.show_shortcuts`, defaulting to `true`, to hide persistent shortcut
  chrome without hiding the mappings or contextual help.
- Keep the broader guide at `:Flashcards help` and hub `H`.
- Require users upgrading from v0.1 to back up and manually convert ID-less
  blocks and aliased fields before switching. UI commands, keymaps,
  configuration aliases, and an automatic data migration are not carried
  forward.
- Keep the finished Overview, Cards, Stats, finite review queue, stable IDs,
  health checks, and JSONL analytics from the unified-hub work.

Release checks:

1. Exercise every `:Flashcards` route and its completion.
2. Compare installed mappings, compact hints, and `?` output in every UI state.
3. Test visible and hidden shortcut chrome at narrow and wide widths.
4. Exercise the composer on Neovim 0.10 with Unicode labels, structural edits,
   dirty targets, failed writes, and save-and-new entry.
5. Run headless, clean-install, Neorg integration, formatting, documentation,
   and Nix flake checks.
6. Evaluate the real NVF configuration and confirm that it emits only
   `<leader>nc`.

## 0.3: Named collections

Goal: Japanese and computer-science study never mix unless the user explicitly
asks for an aggregate view.

1. Replace today's top-level setup with an explicit `default_collection` and
   `collections` table through the documented breaking migration.
2. Add collection validation, canonical path resolution, and immutable
   collection contexts.
3. Pass that context through parser, card form, review, history, health, Cards,
   and Stats before exposing a collection switcher.
4. Store one history ledger per collection and add collection identity to new
   events.
5. Show the active collection in the hub, add local `C` selection, and add
   `:Flashcards collection [id]` for scripts.
6. Test two roots with separate ledgers, dirty buffers, failed history retries,
   and identical card IDs. Reject overlapping roots and shared ledger paths.

Named collections require an explicit configuration and ledger migration.
There is no implicit `default` collection compatibility mode; the migration
must validate roots and history destinations before changing data.

## 0.4: General card types

Goal: use the same engine for languages and technical subjects without making
one universal, awkward schema.

1. Keep `schemas` as the canonical schema registry and move it under each
   collection in a breaking configuration migration; do not add a parallel
   option name.
2. Add built-in `question_answer`, `term_definition`, and `code_output` types.
3. Add a type picker to the form and a type filter to Cards.
4. Add Japanese recognition, production, kanji, and sentence presets where
   they can reuse the same one-block/one-scheduled-card model.
5. Record card type in new history events and show per-type counts and
   retention.

Automatic forward/reverse siblings and cloze siblings need a separate note
identity design. They should not silently duplicate scheduling state inside
the current card block.

## 0.5: Daily study plans and scheduler adapters

Goal: control workload without confusing queue selection with interval math.

1. Wrap the current scheduler as `simple-v1` without changing its behavior.
2. Add unlimited-by-default `new_per_day` and `reviews_per_day` limits per
   collection.
3. Build queues oldest-due first, count unique cards, and keep `review all` as
   an explicit limit-free cram mode.
4. Show quota progress and held-back cards in Overview and Stats.
5. Record scheduler name/version in history so later algorithms are auditable.

The present three ratings remain:

| Rating | New card | Later reviews |
| --- | --- | --- |
| `1` Again | 10 minutes | 10 minutes; lowers ease and enters relearning |
| `2` Hard | 6 hours | Previous interval × 1.2 |
| `3` Good | 3 days | Previous interval × ease, initially 2.5 |

These defaults are configurable. FSRS is a later candidate, not a silent
replacement: its rating scale, state migration, and dependency choice need a
separate ADR.

## Later candidates

- Saved browser filters and named study plans.
- Audio attachments, pronunciation playback, and optional TTS hooks.
- Import and export helpers that preserve stable IDs and plain-text ownership.
- Per-tag interval growth and retention views.
- Explicit cross-collection analytics and study sessions.
- FSRS after the scheduler adapter and event metadata exist.

Sync, accounts, and a database remain outside the core direction. Notes and
append-only review history stay local and user-owned.
