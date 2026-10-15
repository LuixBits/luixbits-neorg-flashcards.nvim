# ADR 0014: Integrate study on a desk and separate workspace metadata

Status: Accepted, 2026-10-16

## Context

The group list and separate review popup made selecting a collection and
studying it feel disconnected. Management needed a clear home, and goals and
category labels needed persistence without changing card identity or scheduling.

## Decision

Use three pages: Desk for collection boxes, category notes, and integrated
review; Overview for the existing card browser and management; Stats for a
month calendar and existing analytics. This supersedes ADR 0013's page name
Cards; its evidence-filter decision remains unchanged. Preserve `cards` as an
Overview alias. Use display-cell layout with byte-indexed highlight spans,
theme-linked colors, optional ASCII borders, and finite cancellable animations.
Rating keys cannot reveal hidden answers; explicit reveal prevents key repeat
from rating the next card.

Keep source cards and version-1 review history unchanged. Store labels,
category accents/order, daily goals, and goal snapshots in a versioned
`.flashcards-workspace.json` sidecar inside each pinned collection root.
Category names remain source tag tokens. Display labels are independent;
renaming or removing tokens is an explicit confirmed source operation with
preflight, buffer-aware writes, snapshots, and partial-failure reporting.

Store UI-created deck definitions in a versioned registry under Neovim's data
directory, configurable or disabled with `deck_registry`. Definitions contain
bundled preset IDs, not executable Lua. Merge them before the existing setup
validation. Reject ID collisions, overlapping roots, and shared history.
Configured schemas/defaults retain ownership in Lua/Nix. Detach removes only
the registry definition.

Goals count unique card IDs per local date after effective undo reduction.
Retries count once; Again still counts as study. A goal snapshot is recorded
when the day becomes active, including a rating after midnight. Durable outbox
events count provisionally, deduplicated before undo reduction. Unsaved source
changes join daily history when persisted. Goals do not change queue selection
or scheduling. Calendar arithmetic uses local dates anchored at noon.

## Consequences

Backup instructions include the optional sidecar and registry. Invalid metadata
is reported without overwriting it. Whole-category edits can stop after a
partial source failure and must report that state; they are not a multi-file
transaction. Historical category membership is not fabricated from current
tags. The calendar drills into current source cards while preserving unavailable
historical IDs in day details. All activity remains scoped to one collection.
