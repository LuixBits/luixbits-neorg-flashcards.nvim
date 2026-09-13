# ADR 0003: Scope state and history to a collection

- Status: Accepted
- Date: 2026-08-21
- Accepted: 2026-08-22

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
  immutable collection context. An open form or review blocks collection
  switching, and delayed writes retain the context captured when they started.
- Stats read only the active collection's cards and history.
- Pending and failed writes are keyed by a captured destination identity that
  includes the canonical history path, pinned root, and collection ID.

## Migration

A v0.2 ledger can stay at the same path when its root becomes one named
collection. Existing version-1 events without `collection_id` or `card_type`
remain readable because the ledger itself belongs to that collection. New
events receive both fields when they are appended; the ledger does not need a
rewrite or a new event version.

A previously mixed ledger is not split automatically because old entries may
not contain enough evidence. The user must assign those events before using
separate roots. Any durable retry queue should also be drained before changing
the collection identity; queues are not adopted under a new identity by path
alone.

## Consequences

Retention, streaks, forecasts, due counts, and retry queues cannot leak from
one subject into another. The same card ID can exist in unrelated collections
without a collision. Renaming a collection after it has history requires an
explicit metadata and retry-queue migration to keep the audit trail coherent.
