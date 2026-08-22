# Upgrade from v0.1 to v0.2

Version 0.2 replaces the old command-per-action interface. It does not install
aliases for the v0.1 commands or remove mappings from your Neovim
configuration, so update those mappings before loading v0.2.

## Before updating

1. Commit or back up the directory containing your flashcards.
2. Rename the setup option `languages` to `schemas`. For NVF, rename
   `languagePresets` to `schemaPresets`. Version 0.2 does not accept the old
   option names.
3. Set `default_file` to a `.norg` file inside `flashcards_dir`. Version 0.2
   rejects add targets outside the collection root.
4. Convert every v0.1 card block as described below. Version 0.2 does not have
   an automatic data migration command.
5. Replace every `:NeorgFlashcard*` command and remove the old suffix keymaps.
6. Confirm that your Neovim version is 0.10.4 or newer.

## Convert the card blocks

Every v0.2 card needs a stable `id:` that is unique inside the collection.
Add one to each block before switching versions. A canonical Japanese block
from v0.1 looks like this after conversion:

```norg
@flashcard japanese
id: fc_0123456789abcdef01234567
japanese: 勉強
reading: べんきょう
english: study
notes: noun / suru verb
tags: jlpt vocab
score: 2
reviewed: 2026-07-01
@end
```

Use a different, stable ID for every card. The `score:` and `reviewed:` lines
are optional; do not invent scheduling state for a card that did not have it.

Schema aliases are also removed. Rename stored v0.1 fields to their canonical
schema keys:

- Japanese `word:` becomes `japanese:`.
- Chinese `hanzi:` or `word:` becomes `chinese:`.
- Chinese `reading:` becomes `pinyin:`.
- Custom schemas must remove their `aliases` table and rename matching stored
  fields before setup.

## Handle old review history

Version 0.2 reads only canonical `reviews.jsonl` events. It does not read
`reviews.log`. Those aggregate log lines do not contain stable card IDs, so
they cannot be converted losslessly; keep the file as an archive if you need
it. New Stats history begins with canonical JSONL events.

Some pre-release unified-hub builds wrote both `rating` and a duplicate
top-level `score` in `reviews.jsonl`. Version 0.2 rejects those events instead
of treating the old field as an alias. If your ledger contains both keys,
close Neovim, run these commands from the collection directory, and keep the
backup:

```sh
cp reviews.jsonl reviews.pre-v0.2.jsonl.backup
jq -c 'del(.score)' reviews.jsonl > reviews.v0.2.jsonl
jq -e -s 'all(.[]; has("score") | not)' reviews.v0.2.jsonl >/dev/null
mv reviews.v0.2.jsonl reviews.jsonl
```

The validation command must print no error and exit successfully before the
final `mv`. It removes only the redundant top-level key; nested card snapshots
may still contain the canonical scheduling field named `score`.

## Command changes

| v0.1 command | v0.2 replacement |
| --- | --- |
| `:NeorgFlashcardOpen` | `:Flashcards open` |
| `:NeorgFlashcardAdd [kind]` | `:Flashcards add [kind]` |
| `:NeorgFlashcardAddJapanese` | `:Flashcards add japanese` |
| `:NeorgFlashcardInsertJapanese` | `:Flashcards add japanese` |
| `:NeorgFlashcardReview` | `:Flashcards review all` |
| `:NeorgFlashcardReviewFile` | `:Flashcards review file` |
| `:NeorgFlashcardReviewTag [tag]` | `:Flashcards review tag [tag]` |
| `:NeorgFlashcardReviewScore [score]` | `:Flashcards review score [score]` |
| `:NeorgFlashcardValidate` | `:Flashcards check` |
| `:NeorgFlashcardHelp` | `:Flashcards help` |

`:Flashcards check` checks the whole configured collection. The public
`validate_file()` Lua function remains available when a script specifically
needs current-buffer validation. Score filters are now named `again`, `hard`,
`good`, and `new`; the old `bad` and `mid` words are rejected.

Replace the old group of global mappings with one optional hub mapping:

```lua
vim.keymap.set("n", "<leader>nc", "<cmd>Flashcards<CR>", {
  desc = "Open flashcards",
})
```

Hub, review, and composer actions are buffer-local. Their visible shortcut
ribbon shows the useful actions for the current page, and `?` shows the full
list. In review, `j` / `k` replace the old `n` / `p` navigation; `h` now reveals
a progressive hint.

## Validate after updating

After installing v0.2:

1. Run `:Flashcards check` and repair reported parser, schema, ID, or scheduling
   errors before reviewing.
2. Open the Cards page and use its `invalid` filter to inspect any remaining
   blocks that v0.2 rejected.
3. Open `:Flashcards`, press `?`, and run a short due review to verify your
   mappings and colorscheme.

The converted `@flashcard` blocks remain the source of truth. Version 0.2
writes new review events to `reviews.jsonl`; it does not recreate v0.1
commands, keymaps, schema aliases, or prompt-by-prompt card creation.

The review flow also changed: reveal first, then rate with `1`, `2`, or `3`.
Again retries a card at most once in the current session, and the composer uses
one protected form with immutable labels instead of sequential prompts.
