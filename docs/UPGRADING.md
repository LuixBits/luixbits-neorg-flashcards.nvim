# Upgrade guide

## Upgrade from v0.2 to v0.3

Version 0.3 replaces the flat, single-root setup with named collections. It
does not translate v0.2 options or create an implicit `default` collection. An
old setup fails with the unknown option named in the error, before the plugin
registers a usable workspace.

Scalar card fields and the version-1 JSONL event format remain readable. Most
of this upgrade is configuration work unless one v0.2 root contains subjects
that you now want to split or cards with implicit multiline continuations.

### Before updating to v0.3

1. Commit or back up every card root, including its `reviews.jsonl` file.
2. Run `:checkhealth neorg_flashcards` under v0.2. Resolve any review-history
   warning and let the durable retry queue drain before changing the setup.
3. Choose a stable collection ID for each root. IDs use lowercase letters,
   numbers, `_`, and `-`, and must start with a letter.
4. Make sure the roots do not overlap and do not point their history settings
   at the same file. Physical aliases and hard-linked ledger files also count
   as shared destinations.
5. Convert the Lua or NVF setup as shown below. Do not load v0.3 with the old
   setup and expect a partial migration.
6. Keep only the optional hub mapping at `<leader>nc`. Collection and card-type
   selection are buffer-local or command routes; they need no global mappings.

### Convert the Lua setup

The v0.2 collection options move under `collections.<id>`:

| v0.2 option | v0.3 location |
| --- | --- |
| `flashcards_dir` | `collections.<id>.path` |
| `default_file` | `collections.<id>.default_file` |
| `default_kind` | `collections.<id>.default_card_type` |
| `schemas` | `collections.<id>.schemas` |
| `scheduling` | `collections.<id>.scheduling` |
| `history_file` | `collections.<id>.history_file` |
| `leech_threshold` | `collections.<id>.leech_threshold` |
| `ui` | `ui` at the top level |
| `on_review` | `on_review` at the top level |

For example, replace this v0.2 setup:

```lua
local presets = require("neorg_flashcards.presets")

require("neorg_flashcards").setup({
  flashcards_dir = "~/notes/japanese/flashcards",
  default_file = "~/notes/japanese/flashcards/cards.norg",
  default_kind = "japanese",
  schemas = presets.only("japanese"),
  ui = { show_shortcuts = true },
})
```

with one explicit collection:

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
  },
  ui = { show_shortcuts = true },
})
```

Relative `default_file` and `history_file` values resolve inside that
collection. Their defaults are `cards.norg` and `reviews.jsonl`, so the example
does not need an explicit history path.

Only `default_collection`, `collections`, `ui`, and `on_review` are valid at the
top level. Version 0.3 rejects the old flat keys, including a top-level
`schemas` or `scheduling`, instead of guessing which collection should receive
them.

### Convert the NVF setup

NVF now keys `schemaPresets` by collection ID. A one-collection setup looks like
this:

```nix
programs.nvf.neorg-flashcards = {
  enable = true;

  setupOpts = {
    default_collection = "japanese";
    collections.japanese = {
      label = "Japanese";
      path = "~/notes/japanese/flashcards";
      default_file = "cards.norg";
      default_card_type = "japanese";
    };
  };

  schemaPresets.japanese = [ "japanese" ];

  keymaps = {
    enable = true;
    prefix = "<leader>nc";
  };
};
```

For several collections, add one `setupOpts.collections.<id>` entry and one
matching `schemaPresets.<id>` list for each set of bundled schemas. Replace the
old empty list with `schemaPresets = { };` when every collection supplies only
custom schemas. `schemaPresets = [ "japanese" ];` is no longer valid.

The NVF module still emits at most one global mapping. `keymaps.prefix` is the
complete key used to open `:Flashcards`; it is not a prefix for generated
suffix mappings.

### Keep or split review history

If a v0.2 root becomes one named collection and keeps the same
`reviews.jsonl`, leave the ledger in place. Existing events without
`collection_id` or `card_type` are still read from that collection's ledger.
Version 0.3 adds both fields to new events without changing the event version.
An event that explicitly names another collection is reported and left out of
that collection's analytics.

If the old root contains several subjects that need separate collections, make
new non-overlapping roots and split both the card files and ledger yourself.
The plugin does not infer an old event's subject from its current path or card
text. Keep the untouched backup until each new collection passes validation and
its Stats totals match the events you assigned to it.

Do not carry a pending v0.2 retry queue through an identity change. Version 0.3
keys retries by the captured path, pinned root, and collection ID, so it does
not adopt an older queue merely because the ledger path has the same spelling.

### Update custom schemas and long fields

The `@flashcard <kind>` header and existing scalar `field: value` lines do not
need conversion. Version 0.3 adds bundled technical and Japanese card types,
but it does not change the kind of an existing block.

Version 0.2 treated an unlabelled line after a field as an implicit
continuation. Version 0.3 rejects that ambiguity. Convert a v0.2 value such as:

```norg
notes: First line.
Second line.
```

to the explicit block form:

```norg
notes: |
  First line.
  Second line.
```

Set `multiline = true` on a custom field that may contain line breaks. A stored
multiline value must use an explicit block with every content line two spaces
beyond its card directive:

```norg
question: |
  Why does a hash table resize?
  Explain the load factor.
answer: |
  To keep lookups close to constant time.
  Too many collisions make probes expensive.
```

An unindented continuation is invalid. Single-line values keep their scalar
form even when the schema permits multiline text. In the composer, press Enter
on a long field to open its focused editor, `Ctrl-S` to apply it, and `Esc` to
cancel it. If a field is not allowed to be multiline, collapse its old
continuation into one scalar line. A literal value consisting only of `|` also
needs a multiline-enabled field and an explicit block containing an indented
`|` line.

Version 0.2 showed typed checking for every revealed value. Version 0.3 shows
the `t` action only when at least one non-empty reveal field declares
`typed_answer = true`. Add that boolean to selected custom answer fields if
typed checking is useful; it requires `reveal = true`. Typed attempts remain in
memory and are not added to cards or review history. Entries created by the
built-in prompt are removed from Neovim input history; a custom `vim.ui.input`
implementation controls any storage of its own.

### Validate after updating to v0.3

1. Start Neovim and read the complete setup error, if any. A stale flat option
   is rejected by name.
2. Run `:Flashcards collection <id>` and `:Flashcards check` for every
   collection. Repair parser, schema, path, ID, or history errors before review.
3. Open Cards and Stats in each collection. Confirm the collection label,
   source files, due counts, and review totals change together.
4. If a schema has long fields, add and edit one test card and inspect its
   explicit block in the `.norg` source.
5. Start a short review. Confirm that `t` appears only on a card type that opts
   in, then open Cards and choose `f` followed by Card Clinic to inspect its
   evidence.
6. For NVF, confirm that `<leader>nc` opens the hub and that no old suffix
   mappings remain.

## Upgrade from v0.1 to v0.2

Version 0.2 replaces the old command-per-action interface. It does not install
aliases for the v0.1 commands or remove mappings from your Neovim
configuration, so update those mappings before loading v0.2.

### Before updating to v0.2

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

### Convert the card blocks

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

### Handle old review history

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

### Command changes

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

### Validate after updating to v0.2

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
