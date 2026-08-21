# ADR 0002: Separate collections and card types

- Status: Proposed
- Date: 2026-08-21

## Context

Today, `flashcards_dir` is both the configured root and the only study
collection. That works for one subject, but Japanese and computer-science
cards would share reviews, statistics, and default settings.

The current `languages` option contains schemas. Some useful schemas, such as
question/answer or code/output, are not languages. A study collection and a
card shape are different concepts and should not be coupled.

## Decision

- A collection is an isolated study context such as `japanese` or
  `computer_science`.
- A card type defines fields, validation, the front, and the revealed answer.
  The on-disk `@flashcard <kind>` format stays unchanged; `kind` is the stable
  card-type identifier.
- Each collection owns its root, default file, allowed card types, default
  card type, scheduler settings, limits, and history destination.
- One collection is active for normal add, review, Cards, Stats, Check, and
  Migrate actions. Reviews never mix collections implicitly.
- The hub always shows the active collection. A buffer-local `C` action opens
  a picker, while `:Flashcards collection [id]` supports scripts and command
  completion without adding another global shortcut.
- Collection roots and history destinations must be unique and non-overlapping.

A target configuration looks like this:

```lua
require("neorg_flashcards").setup({
  default_collection = "japanese",
  collections = {
    japanese = {
      label = "Japanese",
      path = "~/notes/japanese/flashcards",
      default_file = "cards.norg",
      default_card_type = "japanese",
      card_types = presets.only("japanese"),
    },
    computer_science = {
      label = "Computer Science",
      path = "~/notes/computer-science/flashcards",
      default_file = "cards.norg",
      default_card_type = "question_answer",
      card_types = presets.only("question_answer", "term_definition", "code_output"),
    },
  },
})
```

## Compatibility

When `collections` is absent, the existing `flashcards_dir`, `default_file`,
`default_kind`, and `languages` options become one implicit `default`
collection. Existing card files are not changed. During the configuration
migration, `languages` remains an alias for `card_types`; mixing the old and
new top-level shapes is rejected instead of guessed.

## Consequences

Japanese and computer-science study remain separate by default, but they use
the same hub and card engine. Aggregate, cross-collection study can be added
later only as an explicit action.
