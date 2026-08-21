# ADR 0004: Separate study limits from scheduling

- Status: Proposed
- Date: 2026-08-21

## Context

The built-in scheduler decides the next interval after a rating. The due
review currently selects every due and new card. Daily limits are a workload
policy, not part of interval calculation, and combining them would make both
harder to change.

## Decision

- Wrap the current algorithm in a pure scheduler interface named `simple-v1`.
- Add a separate study-plan layer that chooses today's queue.
- Configure both per collection:

```lua
scheduler = {
  name = "simple-v1",
  options = {},
},
limits = {
  new_per_day = nil,
  reviews_per_day = nil,
},
```

- `nil` remains unlimited, matching current behavior.
- Reviews are selected oldest-due first. New cards fill the remaining new-card
  allowance deterministically.
- Limits count unique cards, so an Again retry does not consume another slot.
- `review all` is an explicit cram mode and bypasses daily limits.
- Overview and Stats show quota progress and cards held back by limits.
- New history events record scheduler name and version.

## Consequences

Limits never rewrite due dates, and changing scheduler affects only future
ratings. FSRS can later implement the interface, but it needs a separate ADR
for its rating model, state migration, and dependency choice.
