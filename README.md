# luixbits-neorg-flashcards.nvim

![Creating and reviewing Japanese flashcards](docs/demo/review.gif?raw=true&v=5c58e1c)

Local flashcards for Neorg notes in Neovim.

`luixbits-neorg-flashcards.nvim` keeps language-learning cards in plain `.norg`
files, then gives you a full-tab hub for browsing, adding, and analyzing them
plus a floating review UI for studying them. It is intentionally
local-first: no Anki, no server, no sync account, and no database outside your
notes.

## Index

- [Features](#features)
- [Requirements](#requirements)
- [Neorg or Plain Neovim?](#neorg-or-plain-neovim)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Files and Chapters](#files-and-chapters)
- [Commands](#commands)
- [Review Keys](#review-keys)
- [Card Format](#card-format)
- [Scheduling](#scheduling)
- [Collection Health and Migration](#collection-health-and-migration)
- [Flashcard Hub and Stats](#flashcard-hub-and-stats)
- [Cloze and Typed Answers](#cloze-and-typed-answers)
- [Configuration](#configuration)
- [Language Presets](#language-presets)
- [Suggested Keymaps](#suggested-keymaps)
- [Lua API](#lua-api)
- [Concept Video](#concept-video)
- [Development](#development)
- [Platform Support](#platform-support)
- [License](#license)
- [Module Layout](#module-layout)

## Features

- Plain-text flashcards stored as Neorg `@flashcard` blocks.
- A target-aware card composer with immutable labels, placeholders, inline
  validation, draft protection, and separate save or save-and-new actions.
- One command, `:Flashcards`, opens a full-tab hub with Overview,
  Cards, and Stats pages. Its winbar keeps useful current-page keys visible,
  and `?` opens the complete local key list.
- A searchable card browser with lifecycle, timing, and availability states;
  filtering, sorting, preview, source editing, bury, and suspend actions.
- Invalid blocks, including every copy of a duplicate stable ID, stay visible
  in the Cards page for repair but cannot enter a review queue.
- A finite review queue with progressive hints, typed answers, next-interval
  previews, one-step undo, and a completion summary. `1` (Again) retries a
  card once later in the same session instead of creating an endless queue.
- Spaced repetition with persisted stable card IDs, review counts, lapses,
  lifecycle, availability, and due metadata.
- Analytics for activity, streak, retention, answer distribution, card states,
  leeches, review time, heatmap, and a seven-day due forecast.
- Versioned, append-only review history in `reviews.jsonl`; existing
  `reviews.log` entries remain readable.
- Cloze markers (`{{c1::answer}}`) and a typed-answer mode with fuzzy matching.
- Review all active cards, due cards, the current file, a tag, or a score bucket.
- Opt-in Japanese and Chinese presets.
- Custom schemas for any language or subject.
- Lazy.nvim and Nix/NVF setup examples.

## Requirements

- Neovim 0.10 or newer.
- Read/write access to the directory that will contain your cards.

Neorg is optional. The plugin reads and writes the card blocks itself; it does
not require a Neorg workspace, Anki, SQLite, a server, or an account.

## Neorg or Plain Neovim?

The files must use the `.norg` extension in both modes. Neorg is the editing
experience around those files, not the storage engine for this plugin.

| Capability | Plain Neovim | Neovim with Neorg |
| --- | --- | --- |
| Add, review, filter, and rate cards | Yes | Yes |
| `.norg` files required | Yes | Yes |
| Neorg syntax, concealing, and note features | No | Yes |
| Neorg workspace required | No | No |

Without Neorg, a card file is ordinary text with a `.norg` name. The suffix is
the protocol here; no note-taking mothership has to be docked. Files ending in
`.md` or `.txt` are not discovered by collection reviews.

## Installation

### lazy.nvim with Neorg

Configure Neorg as its own plugin spec. This follows Neorg's stable lazy.nvim
setup; customize its modules separately if you want more than the defaults:

```lua
{
  "nvim-neorg/neorg",
  lazy = false,
  version = "*",
  config = true,
}
```

Then add the flashcard plugin:

```lua
{
  "LuixBits/luixbits-neorg-flashcards.nvim",
  dependencies = {
    "nvim-neorg/neorg",
  },
  config = function()
    local presets = require("neorg_flashcards.presets")

    require("neorg_flashcards").setup({
      flashcards_dir = vim.fn.expand("~/notes/flashcards"),
      default_file = vim.fn.expand("~/notes/flashcards/cards.norg"),
      default_kind = "japanese",
      languages = presets.only("japanese"),
    })
  end,
}
```

Neorg handles editing and rendering; `neorg_flashcards` handles card parsing,
review state, and rating writeback. Run `:checkhealth neorg` if Neorg itself is
unhappy.

### lazy.nvim without Neorg

Omit the dependency when you only want the flashcard workflow:

```lua
{
  "LuixBits/luixbits-neorg-flashcards.nvim",
  config = function()
    local presets = require("neorg_flashcards.presets")

    require("neorg_flashcards").setup({
      flashcards_dir = vim.fn.expand("~/notes/flashcards"),
      default_file = vim.fn.expand("~/notes/flashcards/cards.norg"),
      default_kind = "japanese",
      languages = presets.only("japanese"),
    })
  end,
}
```

The source file will be plain text, while the review and help windows still
work normally.

### Local Checkout

Use the same setup while developing from a local directory. Add Neorg as a
dependency only if your normal Neovim configuration uses it:

```lua
{
  dir = "~/projects/nvim-plugins/luixbits-neorg-flashcards.nvim",
  name = "luixbits-neorg-flashcards.nvim",
  config = function()
    local presets = require("neorg_flashcards.presets")

    require("neorg_flashcards").setup({
      flashcards_dir = vim.fn.expand("~/notes/flashcards"),
      default_file = vim.fn.expand("~/notes/flashcards/cards.norg"),
      default_kind = "japanese",
      languages = presets.only("japanese"),
    })
  end,
}
```

### NVF / Nix

The repository exposes a flake package and a small NVF module. Add it as a
flake input:

```nix
inputs.luixbits-neorg-flashcards.url = "github:LuixBits/luixbits-neorg-flashcards.nvim";
```

Import the module next to your NVF/Home Manager setup:

```nix
{
  imports = [
    inputs.luixbits-neorg-flashcards.homeManagerModules.nvf
  ];

  programs.nvf.neorg-flashcards = {
    enable = true;
    languagePresets = [ "japanese" ];
    setupOpts = {
      flashcards_dir = "~/notes/flashcards";
      default_file = "~/notes/flashcards/cards.norg";
      default_kind = "japanese";
      ui.show_shortcuts = true;
    };

    keymaps = {
      enable = true;
      prefix = "<leader>nc";
    };
  };
}
```

The module adds the plugin package to NVF, emits the Lua `setup` call, and only
creates a keymap when `keymaps.enable = true`. The exact `prefix` key opens
`:Flashcards`, so this example creates one global shortcut: `<leader>nc`. The
module does not install or configure Neorg; enable Neorg separately in NVF if
you want its editing features.

If you do not want to import the module, use the package directly:

```nix
{
  inputs,
  pkgs,
  ...
}:
let
  neorgFlashcards =
    inputs.luixbits-neorg-flashcards.packages.${pkgs.stdenv.hostPlatform.system}.default;
in {
  programs.nvf.settings.vim = {
    startPlugins = [
      neorgFlashcards
    ];

    luaConfigRC.neorg-flashcards = ''
      local presets = require("neorg_flashcards.presets")

      require("neorg_flashcards").setup({
        flashcards_dir = vim.fn.expand("~/notes/flashcards"),
        default_file = vim.fn.expand("~/notes/flashcards/cards.norg"),
        default_kind = "japanese",
        languages = presets.only("japanese"),
      })
    '';
  };
}
```

## Quick Start

1. Choose the Neorg or plain-Neovim installation.
2. Configure `flashcards_dir`, `default_file`, and at least one language.
3. Run `:Flashcards`, or map it to `<leader>nc`, to open the hub.
4. Press `a` to add a card. The form writes a stable ID automatically.
5. Press `Enter` on Overview to study the due queue.
6. In review, reveal with `Space` or `Enter`, then press `1`, `2`, or `3`.

`default_file` may be nested; its parent directories are created when it is
opened. Keeping it under `flashcards_dir` makes it part of collection reviews.

## Files and Chapters

Use one `.norg` file per chapter and keep those files under `flashcards_dir`:

```text
flashcards/
├── chapter-01.norg
├── chapter-02.norg
└── course-b/
    └── chapter-01.norg
```

Open a chapter with your normal Neovim file picker or `:edit`, then use
`:Flashcards add` to add to that file and `:Flashcards review file` to study
only that chapter. `:Flashcards review all` recursively combines active cards
from every chapter under `flashcards_dir` into one cram session.

Tags are best used for topics that cross chapter boundaries. For example,
cards in several files can use `tags: grammar difficult`, then
`:Flashcards review tag grammar` reviews that topic across the collection.
Tag matching is case-insensitive and accepts one exact whitespace- or
comma-separated tag at a time.

`:Flashcards open` still opens only `default_file`. Keep that file under
`flashcards_dir` if it should be included in all-card and filtered reviews.

## Commands

`:Flashcards` is the plugin's one command. With no arguments it opens the
Overview page; command-line completion exposes the other routes.

| Command | Action |
| --- | --- |
| `:Flashcards` / `:Flashcards overview` | Open the hub at Overview |
| `:Flashcards cards` | Open the searchable Cards page |
| `:Flashcards stats` | Open the Stats page |
| `:Flashcards review due` | Review due and new active cards, oldest first |
| `:Flashcards review all` | Review every active, valid card as a cram session |
| `:Flashcards review file` | Review valid cards in the current buffer |
| `:Flashcards review tag [tag]` | Review one exact tag; prompt when omitted |
| `:Flashcards review score [bad\|mid\|good\|new]` | Review one score bucket |
| `:Flashcards add [kind]` | Add to the current `.norg` file, or `default_file` |
| `:Flashcards open` | Create or open `default_file` |
| `:Flashcards check` | Check parser, schema, ID, scheduling, and collection health |
| `:Flashcards migrate` | Preview and confirm stable IDs for legacy cards |
| `:Flashcards help` | Open the in-editor guide |

The composer shows the destination file before anything is saved. Labels,
required markers, placeholders, and validation errors are UI decorations, so
only field values can be edited. Backspace, word deletion, and Delete stop at
the current value's boundaries instead of joining field rows. In Insert mode,
`Enter` moves to the next field and saves and closes from the last;
`Tab` / `Shift-Tab` cycle fields.
Use `<C-s>` to save and close from anywhere, or `<C-n>` to save and start
another card. In Normal mode, `j` / `k` select fields and `Enter` or `i`
returns to editing. `q` / `Esc` asks before discarding a changed draft, and
`?` shows every current shortcut. Composer fields are currently single-line.

## Review Keys

These mappings exist only inside the review popup; they do not occupy global
normal-mode keys.

- `Space` / `Enter`: reveal the answer. A revealed card must be rated.
- `j` / `k`: browse the next or previous pending card.
- `?`: show the shortcuts available in the current review state.
- `h`: reveal a progressively larger part of the answer as a hint.
- `t`: type the answer and check it against the reveal fields.
- `1`: Again; save score 1 and retry this card once later in the session.
- `2`: Hard; save score 2 and remove the card from the queue.
- `3`: Good; save score 3 and remove the card from the queue.
- `u`: undo the most recent rating, while it is still the latest action.
- `b`: bury the card until tomorrow and remove it from this session.
- `x`: suspend the card and remove it from this session.
- `e`: open the source card for editing.
- `q` / `Esc`: close review.

Pressing `1`, `2`, or `3` before revealing only reveals the answer; press the
rating again after checking it. Once revealed, the popup shows the next
interval beside every rating. An Again card is requeued only once per session,
so every queue finishes. The completion screen reports elapsed time, ratings,
retries, hints, buries, and suspensions; `u` can still undo the last rating.

If the source card file is already open and has unsaved edits, ratings update
that buffer but do not write it automatically. The matching history event is
queued in memory and appended to `reviews.jsonl` when you save the source.
Undoing the rating before that save cancels the queued event. If appending the
history fails after a source save, the event stays queued and is retried on
later writes, focus, setup, and exit. Collection reviews read loaded buffers so
the card shown matches those edits. If a source changes after the review
starts, rating stops and asks you to restart the review rather than risk
changing the wrong card.

## Card Format

Cards are plain Neorg blocks:

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
due: 2026-07-02 08:30
interval: 0.5
ease: 2.5
reps: 6
lapses: 1
lifecycle: review
availability: active
@end
```

Only fields marked `required = true` in the language schema are required.
New cards get an opaque, stable `id:` automatically. A rating maintains
`score:`, `reviewed:`, `due:`, `interval:`, `ease:`, `reps:`, `lapses:`, and
`lifecycle:`. Bury and suspend actions maintain `availability:` and, for a
buried card, `available_at:`. You do not need to fill these fields in by hand.

## Scheduling

Ratings schedule the next review with a small SM-2-style rule set:

- `1` (bad): the card requeues a few positions later in the current session and
  becomes due again after `scheduling.again_minutes` (default 10 minutes). Its
  ease drops by 0.2, never below `min_ease` (default 1.3).
- `2` (mid): the interval grows slowly (`×1.2`), starting at
  `scheduling.mid_hours` (default 6 hours), so a mid card can appear again
  later the same day. Ease stays unchanged.
- `3` (good): the interval multiplies by the card's ease, starting at
  `scheduling.good_days` (default 3 days). Ease rises by 0.05, up to
  `max_ease` (default 2.8).

New cards and active cards whose `due:` has passed make up
`:Flashcards review due`, sorted oldest due first. `:Flashcards review all`
reviews every active card regardless of due time—treat it as the cram mode.

The hub presents card state as three separate axes:

| Axis | Values | Meaning |
| --- | --- | --- |
| Lifecycle | `new`, `learning`, `review`, `relearning` | Learning progress; inferred for legacy cards and written after ratings |
| Timing | `new`, `due`, `overdue`, `soon`, `scheduled` | A display state derived from `due:` and the current time |
| Availability | `active`, `suspended`, `buried` | Whether normal due review can select the card |

Suspended cards stay out of due review until resumed. Buried cards stay out
until `available_at:`—the built-in bury action uses midnight tomorrow—then
become active again.

## Collection Health and Migration

Every newly created or rated card has a stable ID. For an existing collection,
run `:Flashcards migrate` once. It previews the number of missing IDs, asks for
confirmation, checks every source before the first write, and only adds IDs to
legacy cards. If a loaded source already has unsaved changes, the migration
updates that buffer and tells you it still needs saving.

`:Flashcards check` checks the entire collection for parser and schema errors,
missing or duplicate IDs, duplicate fronts, malformed due dates or numeric
fields, invalid lifecycle values, and leeches. The leech threshold is
configurable and defaults to eight lapses. Invalid schema blocks and every copy
of a duplicate ID are excluded from review; the Cards page keeps them visible
as `[INVALID]` rows so you can press `e` to repair the source. Other warnings do
not make an otherwise valid card unreviewable. `:checkhealth neorg_flashcards`
reports the same setup and collection health through Neovim's health UI.

## Flashcard Hub and Stats

`:Flashcards` opens a full-tab hub. The layout uses side-by-side panels on a
wide screen and stacks them in a narrow Neovim window. `1`, `2`, and `3` open
Overview, Cards, and Stats; `Tab` / `Shift-Tab` cycle pages. The winbar shows
the active page and keeps a compact current-page shortcut ribbon visible even
with a global statusline. Press `?` for all keys available on the current page.

Navigation follows the pane under the cursor. In the primary Overview and
Cards pane, `j` / `k` and the arrow keys change the selected card. In
Stats, or while the secondary pane is focused, they scroll normally. Use
`Ctrl-D` / `Ctrl-U` or PageDown / PageUp for half pages and `gg` / `G` for the
top or bottom. The same keys are listed in the contextual `?` window.

Overview groups cards by tag, shows due-state colors, and puts the due queue in
the primary action. Cards with several tags appear in each group.

- `j` / `k`: move between cards (headers are skipped).
- `Enter`: review the complete due queue.
- `r`: review the due cards in the selected tag group.
- `d` / `A`: review due cards / cram the active collection.
- `a`: add a card; `p`: preview; `e`: edit the source.

Cards is a complete browser rather than a second command list:

- `/`: search fronts, answers, tags, sources, dates, and states.
- `f`: filter by ready, timing, lifecycle, suspended, or buried state.
- `o`: cycle due, front, state, and source sorting; `X` clears search/filter.
- `Enter` / `r`: review the selected active card.
- `x`: suspend or resume; `b`: bury until tomorrow or unbury.
- `D`: confirm and delete the selected source block.
- `p`: preview; `e`: edit the source; `j` / `k`: change selection.
- Invalid blocks are searchable and available through the `invalid` filter.
  They can be opened with `e` or deleted with `D`, but review and scheduling
  actions are disabled.

Deletion removes only the selected `@flashcard` block. It works for malformed
and duplicate-ID rows because it targets the exact source range shown in the
Cards page, checks that the file has not changed, and asks before writing. If
the source is already open with unsaved edits, the block is removed in that
buffer and remains unsaved for you to inspect. Existing `reviews.jsonl` events
are historical records and are not erased with the card.

Stats combines total and today's reviews, streak, 7/30/90-day retention,
30-day answer distribution, lifecycle and availability counts, leeches,
median answer time, estimated due workload, a width-adaptive heatmap, and a
seven-day forecast. It also shows the largest tag groups and cards with the
lowest rating. Use `d` to start due review, `A` for all active cards, or `R`
to reload.

Common hub actions include `c` for a collection check, `m` for ID migration,
`H` for the plugin guide, `R` to reload, and `q` to close the tab. `Esc` first
clears a Cards search/filter, then closes.

Successfully persisted ratings are appended as versioned JSON objects to
`reviews.jsonl` inside `flashcards_dir`. Each event can include its stable card
ID, rating, timestamp, duration, hint use, scheduling states, and session
context. Undo adds a compensating event instead of rewriting history. The
analytics reader also includes an existing tab-separated `reviews.log`, so an
upgrade does not reset the activity timeline. For a modified source buffer,
the event waits in memory until that source is saved; undo before the save
removes it instead.

## Cloze and Typed Answers

Any field may contain Anki-style cloze markers:

```norg
@flashcard japanese
japanese: 東京は{{c1::日本}}の首都です
english: Tokyo is the capital of {{c1::Japan|country}}
@end
```

Before the reveal the marker shows as `[...]`, or `[country]` with a hint;
after the reveal it unwraps to the plain answer. Pressing `t` during review
prompts for the answer and compares it against the reveal fields with a
UTF-8-aware fuzzy match: exact answers, near misses, and wrong answers each
get distinct feedback, and you still rate the card yourself with `1`/`2`/`3`.

## Configuration

Default options:

```lua
require("neorg_flashcards").setup({
  flashcards_dir = vim.fn.expand("~/notes/flashcards"),
  default_file = vim.fn.expand("~/notes/flashcards/cards.norg"),
  default_kind = nil,
  languages = {},
  leech_threshold = 8,
  ui = {
    show_shortcuts = true,
  },
  scheduling = {
    again_minutes = 10,
    mid_hours = 6,
    good_days = 3,
    starting_ease = 2.5,
    min_ease = 1.3,
    max_ease = 2.8,
  },
})
```

| Option | Meaning |
| --- | --- |
| `flashcards_dir` | Root recursively scanned by all-card, tag, and score reviews. |
| `default_file` | File opened by `:Flashcards open` and used when adding outside a `.norg` buffer. |
| `default_kind` | Schema used by `:Flashcards add` when no kind argument is given. |
| `languages` | Map of supported card kinds to their schemas. At least one is required for useful cards. |
| `scheduling` | Spaced-repetition knobs; every key is optional. |
| `history_file` | Optional path overriding `<flashcards_dir>/reviews.jsonl`. |
| `leech_threshold` | Lapse count used by stats and health checks; defaults to 8. |
| `ui.show_shortcuts` | Show compact hub, review, and form hints; `?` help remains available when false. |

Set `flashcards_dir` and `default_file` together. Changing the directory does
not silently rewrite the independently configured default file—configuration
telepathy remains out of scope.

`languages` maps a flashcard kind, such as `japanese`, to a schema:

```lua
{
  label = "Japanese",
  front = "japanese",
  aliases = {
    japanese = { "word" },
  },
  fields = {
    { key = "japanese", label = "Japanese: ", title = "Japanese", required = true },
    { key = "reading", label = "Reading: ", title = "Reading", reveal = true },
    { key = "english", label = "English: ", title = "English", required = true, reveal = true },
    { key = "notes", label = "Notes: ", title = "Notes", reveal = true },
    { key = "tags", label = "Tags: ", title = "Tags" },
  },
}
```

Fields with `required = true` must exist before a card can be reviewed. Fields
with `reveal = true` appear after you reveal the answer. Optional `title`,
`placeholder`, and `help` values control the composer's virtual label, empty
field example, and selected-field hint without changing the stored card.

## Language Presets

Japanese:

```lua
local presets = require("neorg_flashcards.presets")

require("neorg_flashcards").setup({
  default_kind = "japanese",
  languages = presets.only("japanese"),
})
```

Chinese:

```lua
local presets = require("neorg_flashcards.presets")

require("neorg_flashcards").setup({
  default_kind = "chinese",
  languages = presets.only("chinese"),
})
```

Multiple languages:

```lua
local presets = require("neorg_flashcards.presets")

require("neorg_flashcards").setup({
  default_kind = "japanese",
  languages = presets.only("japanese", "chinese"),
})
```

Custom language:

```lua
require("neorg_flashcards").setup({
  default_kind = "spanish",
  languages = {
    spanish = {
      label = "Spanish",
      front = "spanish",
      fields = {
        { key = "spanish", label = "Spanish: ", title = "Spanish", required = true },
        { key = "english", label = "English: ", title = "English", required = true, reveal = true },
        { key = "notes", label = "Notes: ", title = "Notes", reveal = true },
        { key = "tags", label = "Tags: ", title = "Tags" },
      },
    },
  },
})
```

## Suggested Keymaps

The plugin creates commands but no global keymaps. The NVF module is the one
exception when its opt-in `keymaps.enable` setting is true. The hub keeps the
global surface to one shortcut because its actions and hints are buffer-local:

```lua
vim.keymap.set("n", "<leader>nc", "<cmd>Flashcards<CR>", { desc = "Open flashcards" })
```

With the NVF module, `keymaps.enable = true` creates that exact mapping. Change
`keymaps.prefix` if you prefer another key.

## Lua API

Every command above is a thin wrapper around a public function on the plugin
module, so keymaps and custom workflows can call them directly:

```lua
local flashcards = require("neorg_flashcards")
vim.keymap.set("n", "<leader>nc", flashcards.overview, { desc = "Open flashcards" })
```

| Function | Action |
| -------- | ------ |
| `setup(opts)` | Configure the plugin (see [Configuration](#configuration)) |
| `command(args?)` | Dispatch the same routes as `:Flashcards` |
| `open_flashcards()` | Create or open `default_file` |
| `add_kind(kind?)` | Add-card form targeting the current `.norg` file |
| `add_to_default(kind?)` | Add-card form targeting `default_file` |
| `validate_file()` | Validate `@flashcard` blocks in the current buffer |
| `validate_collection()` | Run parser, schema, ID, scheduling, and health checks |
| `migrate_ids(opts?)` | Preview/confirm stable-ID migration; supports `dry_run` or `apply` |
| `review_all()` | Review every active, valid card under `flashcards_dir` |
| `review_due()` | Review due and new cards, oldest due first |
| `review_file()` | Review the current file |
| `review_tag(tag?)` | Review one tag (prompts when omitted) |
| `review_score(score?)` | Review a score bucket: `bad`/`mid`/`good`/`new` (prompts when omitted) |
| `overview(opts?)` | Open the hub; `opts.view` accepts `overview`, `cards`, or `stats` |
| `cards()` / `stats()` | Open the matching hub page |
| `close_review()` | Close the review popup |
| `flip_or_next()` | Reveal the current answer |
| `next_card()` / `previous_card()` | Move within the review session |
| `rate_current(1\|2\|3)` | Score the current card and schedule its next review |
| `edit_current_card()` | Open the source of the current card |
| `type_answer()` | Typed-answer mode for the current card |
| `hint_current()` | Reveal the next progressive hint for the current card |
| `undo_last_rating()` | Undo the latest accepted rating |
| `bury_current()` | Bury the current review card until tomorrow |
| `suspend_current()` | Suspend the current review card |
| `get_review_state()` | Return a copy of the active review session state |
| `toggle_suspend(card)` | Suspend or resume a card |
| `delete_card(card)` | Delete one parsed card's exact source block; no confirmation at this low-level API |
| `bury_card(card)` / `toggle_bury(card)` | Bury a card until tomorrow or toggle burial |
| `open_card(card)` | Open a parsed card at its source block |
| `help()` | Short in-editor guide |

The review, hub, and form keymaps are buffer-local — they only exist
while those UI elements are open and never occupy your global keys.

## Concept Video

The repository includes a runnable 90-second Remotion explainer for the
file-per-chapter workflow, collection reviews, tags, plain-Neovim support, and
rating writeback.

- [`docs/VIDEO_PLAN.md`](docs/VIDEO_PLAN.md) contains the complete narration,
  timed clip plan, optional live-insert directions, and publishing chapters.
- [`video/`](video/) contains the Remotion composition and its own run guide.

The visuals and captions are generated from React components, so the video can
be revised without negotiating with a pile of mystery timeline layers.

## Development

Run the local checks:

```sh
bash scripts/test.sh
```

Check the plugin from an isolated Neovim config:

```sh
bash scripts/check-clean-install.sh
```

The clean-install check intentionally runs without Neorg. CI also runs the same
suite on the declared minimum Neovim version, 0.10.4.

Test another Neovim binary explicitly:

```sh
NVIM=/path/to/nvim bash scripts/test.sh
NVIM=/path/to/nvim bash scripts/check-clean-install.sh
```

Run every Nix package, module, formatting, workflow, headless, and isolated
Neorg-integration check:

```sh
nix flake check --print-build-logs
```

If `stylua` is installed, `scripts/test.sh` also checks formatting.

Record the README demo from your real desktop session:

```sh
bash scripts/record-real-demo.sh
```

Check or render the concept video:

```sh
npm ci --prefix video
npm run check --prefix video
npm run compositions --prefix video
npm run still --prefix video
npm run render --prefix video
```

On NixOS, use `bash scripts/render-video-nixos.sh`; it supplies a native
Chromium and a compatibility environment for Remotion's FFmpeg binary.

## Platform Support

The current release targets Linux and macOS. Windows is not a `0.2.0` release
target; path handling should be treated as best effort there until a Windows
user can validate it.

## License

MIT. See [`LICENSE`](LICENSE).

## Module Layout

```text
lua/neorg_flashcards/init.lua     public setup, commands, add/open actions
lua/neorg_flashcards/presets.lua  bundled language presets
lua/neorg_flashcards/schema.lua   schema lookup, validation, render fields
lua/neorg_flashcards/identity.lua stable card ID validation and generation
lua/neorg_flashcards/parser.lua   @flashcard parsing, collection, ID migration
lua/neorg_flashcards/review.lua   finite review queue, hints, undo, typed answers
lua/neorg_flashcards/overview.lua full-tab Overview, Cards, and Stats hub
lua/neorg_flashcards/ui/actions.lua UI mappings, contextual help, footer hints
lua/neorg_flashcards/history.lua  versioned JSONL review event ledger
lua/neorg_flashcards/stats.lua    retention, state, heatmap, forecast sections
lua/neorg_flashcards/health.lua   collection inspection and :checkhealth report
lua/neorg_flashcards/form.lua     editable add-card form
lua/neorg_flashcards/store.lua    safe metadata writeback, undo, batch migration
lua/neorg_flashcards/schedule.lua scheduling plus lifecycle/availability state
lua/neorg_flashcards/help.lua     short guide popup
lua/neorg_flashcards/popup.lua    shared floating window helper
lua/neorg_flashcards/util.lua     shared helpers
```
