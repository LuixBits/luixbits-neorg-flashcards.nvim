# ADR 0002: Separate collections and card types

- Status: Proposed
- Date: 2026-08-21

## Context

Today, `flashcards_dir` is both the configured root and the only study
collection. That works for one subject, but Japanese and computer-science
cards would share reviews, statistics, and default settings.

The current `schemas` option maps card kinds to field schemas. Some useful
schemas, such as question/answer or code/output, are not languages. A study
collection and a card shape are different concepts and should not be coupled.

## Decision

- A collection is an isolated study context such as `japanese` or
  `computer_science`.
- A card type defines fields, validation, the front, and the revealed answer.
  The on-disk `@flashcard <kind>` format stays unchanged; `kind` is the stable
  card-type identifier.
- Each collection owns its root, default file, allowed card types, default
  card type, scheduler settings, limits, and history destination.
- One collection is active for normal add, review, Cards, Stats, and Check
  actions. Reviews never mix collections implicitly.
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

This proposed change is a breaking configuration migration. The top-level
`flashcards_dir`, `default_file`, `default_kind`, and `schemas` shape does not
create an implicit collection. Release work must include a preflight migration
for roots, default files, schemas, and history destinations before named
collections can ship; no parallel configuration names remain active.

Existing card blocks keep their on-disk `@flashcard <kind>` shape. Any ledger
changes require an explicit migration rather than inferring ownership from a
mixed history file.

## Consequences

Japanese and computer-science study remain separate by default, but they use
the same hub and card engine. Aggregate, cross-collection study can be added
later only as an explicit action.
