# ADR 0006: Confirm source-range card deletion

- Status: Accepted
- Date: 2026-08-22
- Amended: 2026-08-22

## Context

Deleting a card previously meant opening its `.norg` source and manually
removing the complete `@flashcard` block. That was easy to get wrong and was
especially awkward for invalid cards, which remain visible in the browser so
they can be repaired but cannot enter review.

A stable card ID cannot safely identify a deletion target. Duplicate IDs make
both cards invalid, yet the user must be able to choose either physical block.
The confirmation UI is asynchronous, so the source can also change between
selection and acceptance. Loaded source buffers may contain unsaved work that
must not be overwritten.

## Decision

- Uppercase `D` is a Cards-page-local action. It is generated from the shared
  action catalogue, so its mapping, shortcut ribbon, and `?` help stay aligned.
- The confirmation names the card and its exact source location. Cancelling is
  the first and safe choice.
- Deletion targets the parsed path and inclusive start/end lines, never an ID.
  It verifies the cached source fingerprint, opening directive, and exact end
  boundary before changing anything. An unclosed block is never a safe range;
  the user must add its missing `@end` before deleting it.
- Source access uses the same buffer-aware transaction as ratings and card
  creation. Clean sources are written, dirty loaded buffers are changed only
  in memory, and read-only or stale sources reject the operation.
- Before changing an unloaded source on disk, deletion writes the complete
  previous source to `<source>.flashcards-backup`. Failure to create that
  backup aborts deletion. A later clean deletion for the same source replaces
  this single recovery file rather than accumulating hidden copies. A backup
  inherits the source permissions, and a symbolic-link backup destination is
  rejected instead of followed.
- Only the selected block and one doubled blank-line separator at its join are
  removed. The surrounding file and heading remain even when the last card is
  deleted.
- Review events are historical, append-only records. Deleting a card does not
  rewrite or cascade-delete `reviews.jsonl`.

## Consequences

Valid, closed malformed, and duplicate-ID cards can be removed from the same
browser without adding another global command or NVF shortcut. A clean
on-disk source has one immediately recoverable pre-delete copy. A deletion
made in a dirty buffer remains unsaved for inspection or undo and does not
overwrite the on-disk backup. Statistics may continue to include past reviews
of a deleted card; this is intentional provenance rather than a dangling
mutable record.
