# Architecture decisions

These records separate choices we have made from ideas that are still being
tested. An accepted record describes the direction of the plugin. A proposed
record is a design target and may change before implementation.

| ADR | Status | Decision |
| --- | --- | --- |
| [0001](0001-one-entry-point-and-contextual-help.md) | Accepted | One global entry point and contextual help |
| [0002](0002-separate-collections-and-card-types.md) | Proposed | Separate study collections from card types |
| [0003](0003-scope-state-and-history-to-a-collection.md) | Proposed | Scope identity, history, and analytics to a collection |
| [0004](0004-separate-study-limits-from-scheduling.md) | Proposed | Keep workload limits separate from scheduling |
| [0005](0005-value-only-card-composer.md) | Accepted | Use one protected, structured composer for adding and editing valid cards |
| [0006](0006-confirm-source-range-card-deletion.md) | Accepted | Confirm exact source-range deletion and leave a recoverable on-disk copy |
| [0007](0007-strict-v02-contract.md) | Accepted | Ship one canonical v0.2 interface and require a manual v0.1 upgrade |
| [0008](0008-source-and-history-persistence.md) | Accepted | Separate source commits from history delivery and persist failed events in an outbox |
| [0009](0009-semantic-rating-highlights.md) | Accepted | Use configurable semantic highlight groups for ratings |
