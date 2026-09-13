# Planning

The plugin is moving in small vertical slices. Each slice must leave the
existing Japanese collection usable, keep plain-text cards as the source of
truth, and include the UI, data path, tests, and documentation needed to make
the feature understandable.

The architectural choices behind this plan live in
[`docs/adr/`](docs/adr/README.md).

## 0.2: Finish the unified workspace

Status: released as v0.2.0 (2026-08-22)

The 0.2 release replaced the command-per-action interface with one workspace.

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
- Keep the quick guide at `:Flashcards help` and hub `H`; keep the complete
  manual at `:help neorg-flashcards`.
- Require users upgrading from v0.1 to back up and manually convert ID-less
  blocks and aliased fields before switching. UI commands, keymaps,
  configuration aliases, and an automatic data migration are not carried
  forward.
- Keep the finished Overview, Cards, Stats, finite review queue, stable IDs,
  health checks, and JSONL analytics from the unified-hub work.

Release checks completed before v0.2.0:

1. Exercise every `:Flashcards` route and its completion.
2. Compare installed mappings, compact hints, and `?` output in every UI state.
3. Test visible and hidden shortcut chrome at narrow and wide widths.
4. Exercise the composer on Neovim 0.10 with Unicode labels, structural edits,
   dirty targets, failed writes, and save-and-new entry.
5. Run headless, clean-install, Neorg integration, formatting, documentation,
   and Nix flake checks.
6. Evaluate the real NVF configuration and confirm that it emits only
   `<leader>nc`.

## 0.3: Named study workspace

Status: implemented and validated for the next release; not released

Goal: Japanese and computer-science study never mix, while both subjects use
the same small interface. Any future aggregate view must be a separate,
explicit design.

The implemented slice includes:

- A strict `default_collection` plus `collections` setup. Flat v0.2 options are
  rejected; there is no implicit collection or compatibility alias.
- Pinned, non-overlapping collection roots; separate default files and ledgers;
  immutable operation contexts; and harmless reuse of a card ID in unrelated
  collections.
- The active collection in the hub, buffer-local `C` selection, command
  completion for `:Flashcards collection [id]`, and no new global shortcut.
- Per-collection schema registries and default card types. Bundled types include
  `question_answer`, `term_definition`, `code_output`, Japanese recognition,
  production, kanji, and sentence cards, plus the existing Chinese type.
- A card-type picker when a collection has more than one type and a type filter
  in Cards. New history events include the card type.
- Schema-gated multiline fields. Long values use explicit `field: |` blocks and
  a focused editor reached from the protected composer.
- Schema-gated typed answers. The review shows `t` only for opted-in reveal
  fields, displays an aligned comparison, and keeps the attempt in memory.
- Card Clinic as a Cards filter. It explains leeches, recent Again ratings, and
  repeated hint use from effective review history, then shows a recall trail in
  the existing detail pane.
- An NVF `schemaPresets` attribute set keyed by collection ID. NVF still exposes
  exactly one optional global mapping, `<leader>nc`, for the hub.

Named collections require an explicit configuration migration. A v0.2
`reviews.jsonl` can stay with the root that becomes a named collection; a mixed
ledger must be split manually. Existing scalar card fields remain valid.

Validation completed on 2026-08-23:

1. The upgrade guide covers Lua and NVF migration, old ledgers, long fields,
   and removal of v0.2 shortcuts and setup keys.
2. The real NVF configuration evaluates with the collection-keyed preset
   shape and emits exactly one flashcard mapping, `<leader>nc`.
3. Regression tests cover collection switching, stale prompt callbacks, card
   types, multiline add/edit, typed comparisons, Card Clinic, and old-ledger
   reads on the supported Neovim line.
4. Headless, clean-install, Neorg integration, formatting, documentation, Lua
   lint, package, and Nix flake checks pass. Tagging v0.3.0 remains a separate
   release action.

Automatic forward/reverse siblings and cloze siblings still need a separate
note identity design. They must not silently duplicate scheduling state inside
one card block.

## 0.4: Daily study plans and scheduler adapters

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
- Per-card-type counts and retention.
- Audio attachments, pronunciation playback, and optional TTS hooks.
- Import and export helpers that preserve stable IDs and plain-text ownership.
- Per-tag interval growth and retention views.
- Explicit cross-collection analytics and study sessions.
- FSRS after the scheduler adapter and event metadata exist.

Sync, accounts, and a database remain outside the core direction. Notes and
append-only review history stay local and user-owned.
