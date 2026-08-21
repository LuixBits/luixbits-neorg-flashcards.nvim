# ADR 0001: One entry point and contextual help

- Status: Accepted
- Date: 2026-08-21

## Context

The first plugin interface grew one command and one optional global shortcut
per action. It was quick to build, but hard to remember. The full-tab hub now
has enough context to own those actions itself, so the old command aliases and
NVF suffix keymap mode add two competing ways to use the same feature.

The hub already builds its mappings, footer, and `?` window from an action
catalogue. Review and add-card windows still have separate mapping and footer
definitions, which can drift apart.

This is an interaction migration, not a data migration. Old card fields,
ID-less cards, and `reviews.log` files may exist in real note collections.

## Decision

- `:Flashcards` is the only Ex command. Its routes cover the hub, review, add,
  open, check, migration, and general help.
- NVF may create one exact global mapping, `<leader>nc` by default, which opens
  the hub. The command-per-suffix mode and which-key prefix registration are
  removed.
- Actions inside the hub, review window, and add form are buffer-local.
- `?` shows the shortcuts that work in the current window and state.
  `:Flashcards help` and hub `H` open the broader guide.
- Mappings, compact hints, and contextual help come from one action catalogue.
- Persistent hints are visible by default. `ui.show_shortcuts = false` hides
  that chrome without disabling mappings or `?` help.
- Old `:NeorgFlashcard*` aliases, hidden route nicknames, review `n`/`p`, and
  the hub's old `s` pane bridge are removed before the 0.2 release.
- Stored-data compatibility remains: the plugin continues to read missing
  IDs, old scheduling fields, schema aliases, and legacy review history.

## Consequences

The normal path is small and teachable: open the hub, read the visible hints,
and press `?` when stuck. Shortcut text cannot disagree with the mappings that
are actually installed.

Configurations and scripts using an old command must switch to a
`:Flashcards` route. Existing notes and review history require no rewrite.
