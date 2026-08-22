# ADR 0007: Ship one strict v0.2 contract

- Status: Accepted
- Date: 2026-08-22

## Context

Version 0.2 replaces the command-heavy v0.1 interface and tightens the setup
and card formats. Keeping old names or guessing how an old card should be
interpreted would create two public interfaces just as the project is trying
to make one interface discoverable. Some v0.1 data is also ambiguous: an
ID-less card has no stable history identity, and aliased field names may map
to different custom schemas.

## Decision

- `:Flashcards` and its documented routes are the only Ex command interface.
  Removed `:NeorgFlashcard*` commands, route nicknames, suffix keymaps, and Lua
  pane names do not receive compatibility aliases.
- Setup uses `schemas`, `scheduling.hard_hours`, and canonical schema fields.
  The NVF module uses `schemaPresets` and emits `opts.schemas`. The removed
  `languages`, `mid_hours`, `languagePresets`, and schema `aliases` names are
  rejected instead of translated. Merely enabling the NVF module selects the
  bundled Japanese schema and matching `default_kind`; custom-only setups opt
  out with an empty `schemaPresets` list.
- Review score filters use `new`, `again`, `hard`, and `good`, with numeric
  `1`, `2`, and `3` accepted for the ratings. Removed score words are rejected.
- Every card must use a configured schema and have a valid, collection-unique
  `id:`. ID-less and old-format blocks stay visible as invalid source but do
  not enter review.
- Version 0.2 does not contain a compatibility reader, automatic migration, or
  one-off migration command. Users back up their collection, convert v0.1
  blocks and configuration manually, then run `:Flashcards check` before
  reviewing.
- `default_file`, add targets, and a configured `history_file` must stay inside
  `flashcards_dir`; setup or add fails instead of writing outside that root.
  A custom history destination must be a `.jsonl` file, which keeps the
  append-only ledger separate from every `.norg` card source. Setup creates a
  missing collection root, freezes the configured paths as absolute paths, and
  pins the resolved root identity. A later `:cd`, rename, replacement, or
  symlink retarget cannot redirect the active collection.

## Consequences

The documented interface is also the tested runtime interface, so help,
completion, and failures do not imply that an obsolete path is supported.
Upgrading from v0.1 requires deliberate configuration and data work, recorded
in `docs/UPGRADING.md`. Future breaking formats must likewise have an explicit
release upgrade procedure rather than a permanent compatibility layer.
Moving or replacing the configured root also requires another `setup()` call
or a Neovim restart; the running setup fails closed instead of adopting it.
