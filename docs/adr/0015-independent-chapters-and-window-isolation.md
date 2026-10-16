# ADR 0015: Separate chapters from tags and isolate app windows

Status: Accepted, 2026-10-16

## Context

Collections are subjects; chapters group cards inside a collection. Tags such
as travel and household categorize cards across those chapters. Treating tags
or filenames as chapters obscured that distinction. The first Desk preview also
inherited visible whitespace and Neorg concealment from a real configuration.

## Decision

Extend the version-1 workspace sidecar with optional `chapters` (stable IDs and
display labels) and `chapter_cards` (card ID to chapter ID). Validate membership
before writing. Missing fields mean no chapters. Do not add a card field or
rewrite source syntax. Unassigned cards remain accessible in Unfiled.

Overview navigates collections, chapters, and cards. Rename changes a label;
move changes membership; removing a chapter clears membership and keeps cards.
Creating a chapter from a tag is explicit and confirmed, and preserves tags.
Cards added in a chapter still use the collection's configured default file.

This supersedes ADR 0014's flat Overview and tag-only Desk. Its persistence,
tag-editing, registry ownership, and daily-goal decisions remain in force.
Desk switches between chapter notes and tag notes. Stats puts analytics in the
main pane with a bounded calendar and selected-day details alongside it.

Use `neorg_flashcards` for app scratch buffers, with window-local `nolist`,
zero concealment, no spell checking, and no folding. Leave source-note settings
alone. Review resizing preserves the active review window's keyboard focus.

## Consequences

Chapter organization requires the workspace sidecar in backups. It survives
source file renames and card edits because membership uses stable IDs. Removing
the sidecar loses organization, labels, and saved goals, but preserves source
cards and review history. Existing cards are never assigned by guessing from
filenames or tag spelling. Renaming an underlying collection ID remains a
configuration change; a UI rename changes only its display label.
