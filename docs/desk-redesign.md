# ASCII study desk redesign

Status: shipped in v0.3.0 on 2026-10-16. This document preserves the
agreed design and its original sketches. The [README](../README.md),
[chapter ADR](adr/0015-independent-chapters-and-window-isolation.md), and
[release checklist](release-checklist.md) describe the shipped behavior and
verification. Some optional extensions below remain future work.

The implementation uses a canvas for Desk and two responsive panes for
Overview/Stats. On Desk, `g` switches between chapters and tags. In Overview,
`g` filters by tag and `m` opens actions for the selection. Source tag edits are
available through each card's composer and confirmed whole-category actions;
there is no bulk card-selection mode. The calendar keeps the existing seven-day
forecast; thirty-day forecasts and historical category breakdowns remain later
extensions. Weekly comparisons use explicitly labeled card-days. These are
presentation choices, not new scheduler limits.

The update gives flashcards three pages: Desk for choosing and studying cards,
Overview for managing them, and Stats for understanding progress. Studying
should feel like taking a labeled box off a shelf, choosing a category, and
working through a stack of paper cards on the same desk.

## Agreed direction

- Use a cozy ASCII study desk with paper cards, storage boxes, sticky notes,
  borders, and subtle color.
- Keep gamification light: a daily goal, progress stamps, streaks, and
  satisfying card movement.
- Show each existing collection as one deck box. Its tags become the category
  notes inside that box.
- Replace the existing Overview / Cards / Stats navigation with
  Desk / Overview / Stats. Move the current card browser into Overview.
- Keep management simple and functional. Give Stats a real calendar and more
  useful ways to explore the existing history.

The update is a Neovim interface redesign. Cards remain plain `.norg` files,
and collection review history remains local JSONL.

## Objects on the desk

| Object | Meaning | Interaction |
| --- | --- | --- |
| Deck box | One existing collection, such as Japanese | Open it to see its categories and study actions |
| Category note | An existing tag, with an optional display label and accent | Select it to prepare a stack |
| All due tray | Every active new or due card in the open deck | Start the ordinary due session |
| Untagged tray | Cards with no tags | Study them or organize them in Overview |
| Pending stack | Attempts still in the current session | Shrinks as the queue advances |
| Current card | The question and, after reveal, its answer | Reveal, hint, type an answer, rate, edit, bury, or suspend |
| Reviewed stack | Rated cards with no pending attempt in this session | Grows as rated cards leave the queue |
| Progress note | Today's goal and unique cards reviewed in this deck | Open the associated Stats view |

Deck is the user-facing name for a collection. Collection IDs, configured
roots, and history ownership retain their existing meaning. Card types still
describe the fields and practice direction of a card; they are separate from
categories.

Categories overlap. A card tagged `food` and `chapter-03` appears under both
notes. An All due session includes it once before any deliberate Again retry.
Deck totals count unique cards; they are never calculated by adding category
totals. The same rule applies if combined category selection is added later.

## Desk page

The header holds the three page names and the active deck. A shelf of boxes
sits above the working area. The selected box is open, with category notes
visible below it. Opening the workspace restores the last selected existing
deck and category when possible. The configured default supplies the first
selection.

This keeps choosing a deck and choosing a category on the same canvas. A
deck switch visibly changes the open box and its notes. The shelf remains a
compact context strip while studying.

Illustrative layout; all labels and counts in the sketches are synthetic:

```text
  [1 Desk]       2 Overview       3 Stats                 FLASHCARDS
  _______________________________________________________________

       .-----------------.         .-----------------.
      /    JAPANESE     /|         / COMPUTER SCIENCE/|
     +----------------+ |        +----------------+ |
     |  24 ready      | /        |  open deck     | /
     +----------------+/         +----------------+/

      JAPANESE                                      .------------.
                                                    | TODAY      |
      .--------------.   .--------------.           | 12 / 20    |
      | All due      |   | Food         |           | ######---- |
      | 24 ready     |   |  8 ready     |           '------------'
      '--------------'   '------------ /'

      .--------------.   .--------------.
      | Grammar      |   | Chapter 03   |
      |  6 ready     |   | 14 ready     |
      '------------ /'   '------------ /'

  _______________________________________________________________
  h/j/k/l select    Enter study    / find category    ? keys
```

Counts on inactive deck boxes can load lazily. A box awaiting a scan displays
an unknown/loading state instead of an invented zero. Reading a box summary
must not activate its collection or reconfigure the running modules.

Category notes show the label, ready count, and total card count when space
allows. The selected note lifts by one character cell and gets a distinct
border. Its full label remains visible in a detail line when the note is too
narrow. Accent color reinforces selection; the border and text carry the
same information without color.

All due is the first study action. Category selection starts only its new and
due cards. A category with nothing ready offers its next scheduled review and
an explicit Review all action. It does not silently start a cram session.
The existing Review all behavior changes schedules when cards are rated;
this redesign does not turn it into an unscheduled practice mode.

For many categories, use a paged grid with `/` search and a visible page
indicator. Keep selection by category identity across reloads and resizing.
Pinned favorites are a useful extension after the basic grid works.

### Studying on the same desk

Selecting a category pulls its stack into the working area. The pending pile
sits on the left, the current card is central, and the reviewed pile sits on
the right. A small label keeps the deck, category, and session scope visible.

```text
  Desk            Overview       Stats                 Japanese
  _______________________________________________________________
  FOOD                                      5 finished / 13 cards

   PENDING          .--------------------------.        REVIEWED
    _______        /__________________________/|         _______
   |_______|      |                            |        |_______|
   |_______|      |  What does "taberu" mean?   |        |_______|
   |_______|      |                            |        |_______|
      8           |       [ Space: reveal ]    |            5
                  |                            |
                  '----------------------------'

  _______________________________________________________________
  l/Space reveal    H hint    t type answer    ? keys    h return
```

After reveal, show the answer inside the same card and the three familiar
ratings underneath, including their actual next-interval previews. Long
answers and code get readable scrolling space. Decorative margins shrink
before content does.

The physical movement must match the real session state:

- Hard and Good move the card to Reviewed when no attempt remains for it.
- The first Again rating tucks the card back into Pending. The current engine
  permits one retry per card; preserve that finite behavior.
- After an Again retry, a card can finish this session while still being due
  later. Call the pile Reviewed, never Mastered.
- Bury and suspend remove a card from the queue and show their own small
  confirmation. They do not increase the reviewed-card goal.
- Undo restores the queue, counters, and appropriate pile from engine state.
- A failed source update leaves the card in place. A successful source change
  with pending history delivery retains the existing outbox behavior and its
  visible status.

Show unique cards and retry attempts separately. A session of 13 cards can
have more than 13 answers. Keep the progress denominator understandable when
a retry is added, and expose skipped, buried, and suspended counts in the
completion receipt.

On completion, the central card becomes a small paper receipt with the deck,
category, unique cards reviewed, answer distribution, retry count, and elapsed
session time. A short SESSION COMPLETE stamp lands on it. The actions are
Return to categories, Open Stats, and Undo last rating while still available.

### Motion and materials

Use box-drawing characters for the default polished style and provide a plain
ASCII character set using `+`, `-`, `|`, `/`, and `_`. The UI must work with the
user's existing font and colorscheme.

Proposed motion timings are short enough to test and adjust:

| Action | Animation | Initial duration target |
| --- | --- | --- |
| Select a box or note | Border change and one-cell lift | Instant or about 60 ms |
| Start a session | Stack slides into the working area | 120–180 ms |
| Reveal | Card narrows briefly, then the answer appears | 80–120 ms |
| Rate | Card moves toward Reviewed or back into Pending | 100–150 ms |
| Complete | Stamp appears on the receipt | 150–220 ms |

Limit animation to a few meaningful frames. The desk stays still while the
user reads or thinks. Input must remain responsive; repeated rating keys must
never rate an unseen next card or write a rating twice. Reduced motion keeps
all state changes visible with static borders and text.

## Overview page

Overview becomes the manager for decks, categories, and cards. Reuse the
current searchable browser and protected composer. Keep table rows dense and
readable, with restrained borders matching the Desk palette.

```text
  1 Desk         [2 Overview]       3 Stats

  DECKS / CATEGORIES     CARDS                         DETAILS
  Japanese              Search: ____________          Front
    All cards           Front       Category  State   Answer
    Food                taberu      food      due     Notes
    Grammar             ...         ...       ...     Categories
    Untagged                                          Card type
    Needs attention                                   Schedule
    Invalid cards                                     Recent reviews
  Computer Science                                    Source

  a add    e edit    / search    f filter    ? keys
```

In a wide window, show navigation, the card list, and details. In a medium
window, retain the card list and switchable navigation/details. A narrow
window shows one useful pane at a time with a breadcrumb. Adding a third
permanent split to every terminal would make the editor harder to use.

Keep the existing card actions: add, edit, preview, source jump, search,
sorting, state/type filters, suspend/resume, bury/unbury, and confirmed
deletion. Invalid cards remain visible and repairable. Card Clinic moves into
Overview as Needs attention, retaining its evidence and recall trail.

Proposed category management includes:

- Create an empty category note, then add cards into it.
- Edit its display label, accent, and shelf order.
- Add or remove category tags on selected cards.
- Rename the underlying tag as an explicit operation showing affected cards.
- Merge categories by replacing source tags with the destination tag and
  removing duplicates.
- Remove a category by removing its tag from cards. Removing a category never
  deletes its cards.

Display-label edits and underlying-tag edits must be separate actions. The
first is cosmetic; the second changes card source. Source edits use token
matching, so renaming `food` cannot accidentally rename `seafood`.

Category changes spanning several files need a preflight, conflict detection,
and a recoverable write plan. Reuse existing buffer-aware source operations.
If a partial failure occurs, report exactly which files changed and which did
not; never present a partial batch as a completed rename or merge.

Deck management should include its display label, goal, category appearance,
default card type, and access to its source/settings. Creating a deck in the
UI needs additional persistence because collections currently come from Lua
configuration. That work is a defined implementation slice below, rather than
an implied capability of the existing collection picker.

## Stats page

The month calendar is the primary addition. Keep the existing heatmap,
review totals, streak, rating distribution, card states, answer-time median,
forecast, and Needs attention evidence.

```text
  1 Desk          2 Overview       [3 Stats]           Japanese

              OCTOBER 2026                 THURSDAY 15
   Mon   Tue   Wed   Thu   Fri   Sat   Sun
                      1     2     3     4    20 unique cards
     5     6     7     8     9    10    11    24 answers
    12    13    14   [15]   16    17    18    3 Again / 5 Hard / 16 Good
    19    20    21    22    23    24    25    8m recorded answer time
    26    27    28    29    30    31          Goal reached

   * activity     # goal reached            [Open reviewed cards]

   LAST 12 WEEKS                            UPCOMING
   ...##..#...###...                         Fri 16   ####  8
   .##..##.##....##                         Sat 17   ##    4
   ...                                      Sun 18   ##### 10
```

The calendar needs distinct selected-day, today, activity, and goal markers;
the sketch omits most cell decoration for legibility. Default to a Monday
week start. Provide previous/next month, return to today, and keyboard day
selection.

Selecting a past or current day shows unique cards reviewed, answer count,
Again/Hard/Good distribution, available durations, hint usage, and the cards
reviewed. Selecting a future day shows currently scheduled cards. Label that
as a schedule snapshot: later ratings can change it.

Use local calendar dates consistently for the calendar, daily goal, and
streak. Advance dates through calendar arithmetic so daylight-saving changes
do not move reviews into neighboring cells. Overdue work stays in the
current backlog; the future calendar must not repeatedly count it as a new
assignment on every day.

Useful additions, in priority order:

1. A selected-day detail panel and a link to the corresponding cards in
   Overview. Deleted cards retain their historical entry with an unavailable
   source indicator.
2. Seven-day and thirty-day workload views using current due dates.
3. A weekly comparison of unique cards, answers, active days, and recorded
   answer time, with sample counts.
4. Category and card-type breakdowns that lead to the same Overview filters.
5. A compact recall trail and Needs attention explanation for a selected card.

Prefer names that describe the actual measure. The current retention metric
is the percentage of effective ratings that were Hard or Good. Explain that
definition; it is not a measured probability of future recall. Recorded answer
time includes time while a card is open and is not proof of focused study.
Missing durations stay missing instead of being converted into zero.

Historical category breakdowns require care because source tags can change.
For the first version, label them as the history of cards currently in each
category. Do not imply that today's category membership was recorded in old
events. Overlapping category totals are not additive. Card-type breakdowns
can use the type field already present in newer events; older events may be
unknown.

Stats stays scoped to the active deck. Showing several deck boxes is not
permission to merge their histories or study queues.

## Light gamification

The default progress system should reward showing up and working through
cards. An Again rating contributes just as much to the daily activity goal
as a Good rating. Ratings remain honest scheduling choices.

- Suggest a configurable goal of 20 unique cards per day, with an off option.
  Repeated attempts on the same card count once for that deck and date.
- Show the goal as a small paper meter on the desk and a fuller view in Stats.
- Stamp completed sessions and mark study days on the calendar.
- Retain the current streak and add active days this week, so progress remains
  visible after a missed day.
- If the available due stack is smaller than the goal, show Caught up after
  it is finished. Do not push a cram session to satisfy the meter.
- Derive counts from effective review events after undo. Undo updates the
  meter and any goal marker that depended on the reversed event.

Store the day's chosen goal when it first becomes active so later changes to
the default do not rewrite historical goal markers. Historical days without
a saved goal can still show activity, but cannot claim a goal was reached.
Show progress provisionally when a valid review awaits history delivery;
reconcile with the existing outbox instead of awarding it again on replay.

The daily goal is a visual target. It does not limit queue size or change due
dates. The existing roadmap's daily new/review limits and scheduler adapter
remain separate work.

Ideas worth keeping for a later polish pass are a weekly stamp strip,
user-chosen note accents, and a small decorative plant whose appearance
reflects study days. The initial update has no XP economy or cosmetic unlock
system; the user selected light gamification.

## Keyboard and window behavior

Outside an active review, `1`, `2`, and `3` open Desk, Overview, and Stats.
`Tab` and `Shift-Tab` continue to move between pages. Desk selection uses
`h/j/k/l` and arrows. Enter opens the selected box or starts the selected
stack. Contextual `?` help and compact hints come from the existing action
catalogue.

While reviewing, `1/2/3` are exclusively ratings. Remove conflicting numbered
page hints from the header, and retain the existing restriction on collection
switching during a session. `q` or Escape returns to the same deck/category;
completed ratings remain saved. Page navigation becomes available again once
the session ends. A separate durable pause/resume feature is not required for
this redesign.

Preserve review hints, typed answers, reveal-before-rating, undo, bury,
suspend, and edit. Preserve native text editing inside the composer. Editing
a card follows the existing session exit behavior unless a later slice
explicitly changes and tests it.

The layouts should be checked at 60x20, 80x24, 120x35, and 160x50, with a
compact fallback below those sizes. At narrow widths, hide shelf decoration
and secondary piles before reducing the current card's readable area.
Display-width calculations must handle Japanese, combining characters, and
long labels. Resize and colorscheme changes must leave selection and the
review attempt intact.

## Persistence and architecture

### Reuse the existing behavior

The current workspace rendering and interaction state are concentrated in
`lua/neorg_flashcards/overview.lua`. Split the page renderers from their
shared shell as part of this change. Avoid adding an independent second
review engine or moving schedule updates into animation callbacks.

The implementation boundaries should be:

| Responsibility | Existing foundation | Proposed change |
| --- | --- | --- |
| Workspace and navigation | `overview.lua`, `init.lua` | Shared shell with Desk, Overview, and Stats renderers |
| Collection ownership | `collections.lua` | Read-only deck summaries and validated deck activation |
| Category membership | Tags in card values | Shared tag grouping plus optional presentation metadata |
| Review state and writes | `review.lua`, `store.lua`, `schedule.lua` | Render the existing session inside the desk |
| Review history | `history.lua` | Reuse effective events, undo, and outbox delivery |
| Calendar and progress | `stats.lua`, `card_insights.lua` | Pure date/aggregation helpers and selected-day state |
| Controls and colors | `ui/actions.lua`, `highlights.lua` | New contexts and semantic desk groups |
| Card editing | `form.lua`, existing source handlers | Reuse composer and add category-aware entry |

A small canvas renderer should return lines, highlight spans, and focusable
object regions from a layout model. Layout calculations use display cells;
Neovim highlight ranges must still use the correct byte offsets. Animation
works with display snapshots and never owns card identity or persistence.

Cancel timers when the workspace closes, its generation changes, the active
deck changes, or a layout becomes invalid. No recurring redraw loop should
run while the desk is idle. Tests can inject a clock/frame scheduler instead
of sleeping through animations.

### Deck and category metadata

Proposed storage adds a versioned, readable JSON sidecar per collection for
category labels, empty categories, order, accent choices, and daily-goal
settings/snapshots. Card tags remain the membership source of truth. Derive
category membership again after external source edits. A missing sidecar
uses defaults and cannot make existing cards disappear.

For in-app deck creation, add an explicitly owned local JSON registry for
decks created through Overview. The wizard asks for a name, destination
directory, and enabled bundled card types, then validates them through the
same collection preparation rules. Its file location should be configurable;
the default can live under the plugin's Neovim data directory.

Configured collections remain authoritative for their structural settings.
ID/root/history collisions between the registry and configuration must fail
visibly. Display metadata and goals can be edited for either kind of deck.
UI-created decks can also edit their serializable defaults. Arbitrary custom
schema functions and externally managed Lua/Nix configuration are not rewritten
by the manager; the relevant settings identify their configuration source.

Removing a UI-managed deck means removing its registry entry, with a clear
confirmation that explains what will happen. Its card directory and history
remain available for reattachment. File deletion is a separate operation and
is outside this UI update.

Sidecar and registry writes need validation, atomic replacement, and stale
write detection. Invalid metadata should produce an actionable diagnostic
while preserving access to unaffected cards and collections.

### Public routes and decision records

Propose `:Flashcards` and `:Flashcards desk` for the Desk;
`:Flashcards overview` for management; and `:Flashcards stats` for analytics.
The existing `:Flashcards cards` route and Lua entry point need an explicit
compatibility decision in the implementation ADR. The working recommendation
is to retain them as documented entry points into Overview's card list,
without a fourth tab. This requires revisiting the repository's strict
interface policy, not silently introducing a hidden alias.

Record the new navigation and Card Clinic location in an ADR that supersedes
the relevant page-specific parts of ADR 0001 and ADR 0013. Record registry and
metadata ownership before implementing persistent deck creation. Keep the
existing collection isolation, source/history persistence, and schema
capability contracts intact.

## Implementation sequence for a sustained run

Each slice should produce usable behavior with the matching tests and docs.
Once implementation is requested, proceed through the core slices without
stopping at a scaffold or a static mockup. Complete the core before optional
polish; an unfinished core slice remains explicitly unfinished at handoff.

1. **Navigation and shared shell.** Establish Desk / Overview / Stats, move the
   browser into Overview, update routes/actions/help, and preserve the current
   collection and selection behavior. Add the decision records.
2. **Static desk.** Build boxes, category notes, search/paging, counts, compact
   layouts, and due-stack selection with the existing review engine. Verify
   overlapping tags and collection isolation before adding motion.
3. **Integrated study.** Render questions, answers, hints, comparisons, ratings,
   piles, and the completion receipt on the desk. Preserve undo, Again retry,
   edit, bury/suspend, and source/history failure behavior.
4. **Motion and visual polish.** Add selection lift, stack movement, reveal,
   rating transitions, and the completion stamp. Add reduced motion and ASCII
   fallback. Check input during transitions and clean timer shutdown.
5. **Management.** Add category presentation metadata and category editing,
   then validated batch tag operations. Add the owned registry and new-deck
   wizard, including clear behavior for configuration-managed collections.
6. **Calendar and progress.** Add the month view and day drilldown, unique-card
   goal, goal snapshots, study-day markers, and weekly totals. Reuse effective
   history so undo and replay remain consistent across all pages.
7. **Review and delivery.** Exercise the full workflow interactively, finish
   docs and upgrade notes, run repository checks, and record a synthetic-data
   demo that shows all three pages and the study transitions.

Optional work after those slices: pinned category notes, combined-category
queues, a longer forecast, category comparisons, a weekly stamp strip, and
additional desk decoration. A separate scheduler, daily queue limits, durable
session resume, audio, sync, and cross-collection study are separate features.

No release number is assigned by this draft. Reconcile this scope with the
existing 0.4 workload-planning milestone before labeling a release.

## Acceptance checks

The redesign is ready for review when all of these behaviors work:

- Open `:Flashcards`, select a deck, choose a category, finish its due stack,
  and return to the same category on the desk.
- Use every core path entirely from the keyboard, with matching installed
  mappings, compact hints, and contextual help in every state.
- Add and edit a multiline or Japanese card in Overview; its category count
  and desk stack update correctly.
- Rename/merge categories without changing unrelated tags, IDs, schedules, or
  history. Empty categories and untagged cards remain reachable.
- Create and reopen a UI-managed deck. Detect conflicts with configured decks
  and preserve collection ownership through delayed callbacks.
- Exercise Again retry, undo, hints, typed answers, long answers, bury,
  suspend, edits, invalid cards, source errors, and history outbox replay.
- The desk, goal, selected-day Stats, and Overview agree about the same cards
  after rating, undo, external source edits, and refresh.
- Calendar fixtures cover month/year boundaries, leap days, local midnight,
  daylight-saving transitions, missing history fields, and deleted cards.
- Category overlap never inflates deck totals or duplicates a starting queue.
- Animation on/off produces the same queue, rating, source, and history
  results. Rapid input cannot commit a second rating accidentally.
- Narrow/wide layouts, dark/light themes, ASCII fallback, Japanese display
  widths, resizing during animation, and closing mid-transition are usable.
- Idle and closed workspaces leave no animation timers or global keymaps.

Run `bash scripts/test.sh` and `bash scripts/check-clean-install.sh` after
runtime changes. Use the repository's `nix flake check --print-build-logs` for
its full check environment when available. These are plugin checks; this
update does not require a host NixOS rebuild. Refresh the Graphify index after
supported source changes, as required by `AGENTS.md`.

Update the README, Vim help, changelog, upgrade guide, and affected ADR links
to describe the final interface. Use synthetic cards and ledgers for tests
and demos. Deliver the implementation with its validation results and a short
recording of the actual interface; a design sketch alone is not the finished
update.

## Existing code and decisions used for this draft

- [Workspace and browser](../lua/neorg_flashcards/overview.lua)
- [Review queue and rating persistence](../lua/neorg_flashcards/review.lua)
- [Collection configuration and isolation](../lua/neorg_flashcards/collections.lua)
- [Statistics and calendar-day helpers](../lua/neorg_flashcards/stats.lua)
- [Review history and delivery](../lua/neorg_flashcards/history.lua)
- [Action catalogue](../lua/neorg_flashcards/ui/actions.lua)
- [Central theme highlights](../lua/neorg_flashcards/highlights.lua)
- [Existing roadmap](../PLANNING.md)
- [Architecture decisions](adr/README.md)
