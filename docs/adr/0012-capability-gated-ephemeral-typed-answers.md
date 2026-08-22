# ADR 0012: Gate typed answers by schema and keep attempts in memory

- Status: Accepted
- Date: 2026-08-22

## Context

Version 0.2 offers typed checking for every card with a revealed field. A short
reading or translation is a useful comparison target; a paragraph of prose is
not. The action is useful on some cards and misleading on others.

A learner's typed attempt is also different from a rating. The rating changes
the schedule and belongs in the append-only history. The attempt is temporary
review text, may be sensitive, and has no defined analytics or migration
contract.

## Decision

- A schema field opts in with `typed_answer = true`. Schema validation requires
  that field to also use `reveal = true`.
- The visible `t` hint and help entry appear only while the current card has a
  non-empty opted-in field and the answer is still hidden. Invoking the
  buffer-local action for another card refuses the check.
- Comparison trims the input, folds case and repeated whitespace, unwraps cloze
  markers, and chooses the closest non-empty opted-in value. The review shows
  exact, close, or miss feedback and marks the differing span. The learner
  still chooses rating 1, 2, or 3; a text match never schedules the card.
- The raw attempt and comparison live only on the current in-memory review
  attempt. They are not written to the card source, `reviews.jsonl`, the retry
  outbox, or the `on_review` event. Entries created by the built-in prompt are
  removed from Neovim's input history; a custom `vim.ui.input` implementation
  controls any storage of its own.
- Fuzzy comparison is bounded. An exact long string can still match, while a
  non-exact value above the limit is revealed for manual comparison instead of
  running an unbounded edit-distance calculation.
- Persisting attempts or typed-answer accuracy later requires a separate
  privacy, retention, and history-schema decision.

## Consequences

Language presets can opt in for readings, meanings, or production answers,
while long generic answers can decline the capability. Shortcut help now
describes an action that the selected card can actually run. Closing the review
discards the typed text, and Stats cannot imply a typed-answer success rate that
the plugin did not record.
