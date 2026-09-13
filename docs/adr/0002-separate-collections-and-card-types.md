# ADR 0002: Separate collections and card types

- Status: Accepted
- Date: 2026-08-21
- Accepted: 2026-08-22

## Context

Version 0.2 uses `flashcards_dir` as both the configured root and the only study
collection. That works for one subject, but Japanese and computer-science cards
share reviews, statistics, and default settings.

The current `schemas` option maps card kinds to field schemas. Some useful
schemas, such as question/answer or code/output, are not languages. A study
collection and a card shape are different concepts and should not be coupled.

## Decision

- Setup requires a `default_collection` and a non-empty `collections` table.
  The only other top-level options are the shared `ui` settings and `on_review`
  observer.
- A collection is an isolated study context such as `japanese` or
  `computer_science`. Each collection has a stable lowercase ID.
- A card type defines fields, validation, the front, and the revealed answer.
  The on-disk `@flashcard <kind>` format stays unchanged; `kind` is the stable
  card-type identifier.
- Each collection owns its root, default file, allowed card types, default
  card type, scheduler settings, leech threshold, and history destination.
  `default_file` and `history_file` may be relative to the collection root and
  default to `cards.norg` and `reviews.jsonl`.
- One collection is active for normal add, review, Cards, Stats, and Check
  actions. Reviews never mix collections implicitly.
- The hub always shows the active collection. A buffer-local `C` action opens
  a picker, while `:Flashcards collection [id]` supports scripts and command
  completion without adding another global shortcut.
- Collection roots and history destinations must be unique and non-overlapping.

A configuration looks like this:

```lua
local presets = require("neorg_flashcards.presets")

require("neorg_flashcards").setup({
  default_collection = "japanese",
  collections = {
    japanese = {
      label = "Japanese",
      path = "~/notes/japanese/flashcards",
      default_file = "cards.norg",
      default_card_type = "japanese",
      schemas = presets.only("japanese"),
    },
    computer_science = {
      label = "Computer Science",
      path = "~/notes/computer-science/flashcards",
      default_file = "cards.norg",
      default_card_type = "question_answer",
      schemas = presets.only("question_answer", "term_definition", "code_output"),
    },
  },
})
```

## Migration

This is a breaking configuration migration. The top-level `flashcards_dir`,
`default_file`, `default_kind`, `schemas`, scheduling, and history options do
not create an implicit collection. They are rejected as unknown setup options;
there is no `default` collection alias or parallel legacy shape.

Each v0.2 root must be wrapped in one named collection. Existing card blocks
keep their on-disk `@flashcard <kind>` shape. A `reviews.jsonl` file that belongs
to that root can stay in place. A ledger that mixed subjects must be split by
the user; the plugin does not infer ownership from card text or paths.

The exact procedure is recorded in `docs/UPGRADING.md`.

## Consequences

Japanese and computer-science study remain separate by default, but they use
the same hub and card engine. A typo or stale v0.2 option stops setup instead of
silently selecting the wrong root. Aggregate, cross-collection study can be
added later only as an explicit action.
