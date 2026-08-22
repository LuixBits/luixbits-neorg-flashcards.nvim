# ADR 0006: Confirm source-range card deletion

- Status: Accepted
- Date: 2026-08-22

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
  boundary before changing anything. An invalid unclosed block may be removed
  only when its recorded range still reaches end of file.
- Source access uses the same buffer-aware transaction as ratings and card
  creation. Clean sources are written, dirty loaded buffers are changed only
  in memory, and read-only or stale sources reject the operation.
- Only the selected block and one doubled blank-line separator at its join are
  removed. The surrounding file and heading remain even when the last card is
  deleted.
- Review events are historical, append-only records. Deleting a card does not
  rewrite or cascade-delete `reviews.jsonl`.

## Consequences

Valid, malformed, and duplicate-ID cards can be removed from the same browser
without adding another global command or NVF shortcut. A user can inspect and
save a deletion made in a dirty buffer. Statistics may continue to include
past reviews of a deleted card; this is intentional provenance rather than a
dangling mutable record.
