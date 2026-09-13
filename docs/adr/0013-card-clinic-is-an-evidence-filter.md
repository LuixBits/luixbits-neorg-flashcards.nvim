# ADR 0013: Keep Card Clinic inside Cards and derive it from review evidence

- Status: Accepted
- Date: 2026-08-22

## Context

The hub already has Overview, Cards, and Stats. Adding a fourth page for weak
cards would duplicate Cards search, selection, detail, editing, and review
actions. A vague "weak" label would also hide why a card was selected and make
the feature hard to trust.

## Decision

- Card Clinic is a filter in the existing Cards page, reached through its `f`
  picker. It does not add a hub page, Ex command, global mapping, or NVF mapping.
- The clinic is scoped to the active collection and contains only valid, active
  cards. Suspended and buried cards stay out of the work list.
- Attention reasons are derived from card scheduling state and effective review
  evidence. Undo events remove the rating they compensate for before signals
  are calculated.
- A card is included when it reaches the configured leech threshold, has at
  least two Again ratings among its last three reviews, has a latest Again
  rating, or used hints in at least two of its last three reviews. The stored
  last score supplies the latest-rating signal for cards that predate the
  ledger.
- The Cards detail pane states the non-redundant matching reasons and shows a
  chronological recall trail with recent ratings and intervals. The reason list
  exposes repeated hint use. Stats shows a short Needs attention summary and
  points back to the Cards filter.
- Clinic membership is computed from the card source and collection ledger. It
  is not stored as another card field or history event. Typed attempts are not
  evidence because ADR 0012 keeps them out of history.

## Consequences

The feature reuses the browser's search, editing, scheduling, and review paths.
A learner can see why a card appears and can suspend it without leaving behind
a stale diagnosis. The current thresholds are product rules, not persisted
data, so later tuning does not require rewriting cards or ledgers.
