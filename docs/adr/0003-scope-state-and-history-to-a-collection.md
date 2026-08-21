# ADR 0003: Scope state and history to a collection

- Status: Proposed
- Date: 2026-08-21

## Context

Named collections are not isolated if reviews still write to one ledger or if
statistics read every event. Switching collections while a review or delayed
history write is open also risks sending state to the wrong destination.

## Decision

- Each collection has its own `reviews.jsonl` ledger.
- A card's scheduling identity is `(collection_id, card_id)`. Duplicate IDs
  are invalid within one collection, but the same generated ID in unrelated
  collections is harmless.
- New history events include `collection_id` and `card_type`. These additive
  fields do not require a new ledger version.
- Review, form, parser, history, health, and stats operations receive an
  immutable collection context. An open session keeps the context it started
  with even if the hub later switches collections.
- Stats read only the active collection's cards and history.
- Pending and failed writes remain keyed by canonical history path.

## Compatibility

An existing ledger stays at its current path. Events without a collection ID
inherit the collection that owns that ledger. The plugin continues to read
`reviews.log`, but never writes new events to it. A previously mixed ledger is
not split automatically because old entries may not contain enough evidence.

## Consequences

Retention, streaks, forecasts, due counts, and retry queues cannot leak from
one subject into another. Renaming a collection ID after it has history will
need an explicit migration.
