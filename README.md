# luixbits-neorg-flashcards.nvim

![Creating and reviewing Japanese flashcards](docs/demo/review.gif?raw=true&v=5c58e1c)

Local flashcards for Neorg notes in Neovim.

`luixbits-neorg-flashcards.nvim` keeps language-learning cards in plain `.norg`
files, then gives you a small prompt for creating cards and a floating review
UI for studying them. It is intentionally local-first: no Anki, no server, no
sync account, and no database outside your notes.

## Index

- [Features](#features)
- [Requirements](#requirements)
- [Neorg or Plain Neovim?](#neorg-or-plain-neovim)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Chapters and Collections](#chapters-and-collections)
- [Commands](#commands)
- [Review Keys](#review-keys)
- [Card Format](#card-format)
- [Configuration](#configuration)
- [Language Presets](#language-presets)
- [Suggested Keymaps](#suggested-keymaps)
- [Concept Video](#concept-video)
- [Development](#development)
- [Platform Support](#platform-support)
- [License](#license)
- [Module Layout](#module-layout)

## Features

- Plain-text flashcards stored as Neorg `@flashcard` blocks.
- Prompt-based card creation with configurable fields.
- Floating review popup with reveal, next, previous, edit, and quit actions.
- `1`, `2`, `3` scoring for bad, mid, and good cards.
- Review all cards, the current file, a tag, or a score bucket.
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
    };

    keymaps = {
      enable = true;
      prefix = "<leader>nc";
    };
  };
}
```

The module adds the plugin package to NVF, emits the Lua `setup` call, and only
creates keymaps when `keymaps.enable = true`. It does not install or configure
Neorg; enable Neorg separately in NVF if you want its editing features.

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
3. Run `:NeorgFlashcardOpen` to create or open the default card file.
4. Run `:NeorgFlashcardAdd` to add a card.
5. Run `:NeorgFlashcardReview` to study all cards.
6. Press `1`, `2`, or `3` during review to save how well you know the card.

`default_file` may be nested; its parent directories are created when it is
opened. Keeping it under `flashcards_dir` makes it part of collection reviews.

## Chapters and Collections

Use one `.norg` file per chapter and keep those files under `flashcards_dir`:

```text
flashcards/
├── chapter-01.norg
├── chapter-02.norg
└── course-b/
    └── chapter-01.norg
```

Open a chapter with your normal Neovim file picker or `:edit`, then use
`:NeorgFlashcardAdd` to add to that file and `:NeorgFlashcardReviewFile` to
study only that chapter. `:NeorgFlashcardReview` recursively combines every
chapter under `flashcards_dir` into one review session.

Tags are best used for topics that cross chapter boundaries. For example,
cards in several files can use `tags: grammar difficult`, then
`:NeorgFlashcardReviewTag grammar` reviews that topic across the collection.
Tag matching is case-insensitive and accepts one exact whitespace- or
comma-separated tag at a time.

`:NeorgFlashcardOpen` still opens only `default_file`. Keep that file under
`flashcards_dir` if it should be included in all-card and filtered reviews.

## Commands

- `:NeorgFlashcardOpen` creates or opens `default_file`.
- `:NeorgFlashcardAdd [kind]` adds to the current `.norg` file. From another
  buffer, it opens `default_file` first. Without `[kind]`, it uses
  `default_kind`.
- `:NeorgFlashcardHelp` opens a short in-editor guide.
- `:NeorgFlashcardReview` reviews all valid cards under `flashcards_dir`.
- `:NeorgFlashcardReviewFile` reviews valid cards in the current file.
- `:NeorgFlashcardReviewTag [tag]` reviews cards with a matching `tags:` value.
- `:NeorgFlashcardReviewScore [bad|mid|good|new]` reviews cards by score.
- `:NeorgFlashcardValidate` validates flashcards in the current file.

Compatibility aliases `:NeorgFlashcardAddJapanese` and
`:NeorgFlashcardInsertJapanese` are available when the Japanese preset is
configured.

## Review Keys

These mappings exist only inside the review popup; they do not occupy global
normal-mode keys.

- `Space` / `Enter`: reveal the answer, then advance.
- `1`: save `score: 1` and advance.
- `2`: save `score: 2` and advance.
- `3`: save `score: 3` and advance.
- `n`: advance without changing score.
- `p`: previous card.
- `e`: open the source card for editing.
- `q`: close review.

If the source card file is already open and has unsaved edits, ratings update
that buffer but do not write it automatically. Save the file normally to persist
both your edits and the rating. Collection reviews read loaded buffers so the
card shown matches those edits. If a source changes after the review starts,
rating stops and asks you to restart the review rather than risk changing the
wrong card.

## Card Format

Cards are plain Neorg blocks:

```norg
@flashcard japanese
japanese: 勉強
reading: べんきょう
english: study
notes: noun / suru verb
tags: jlpt vocab
score: 2
reviewed: 2026-07-01
@end
```

Only fields marked `required = true` in the language schema are required.
`score:` and `reviewed:` are maintained by the review UI when you press `1`,
`2`, or `3`.

## Configuration

Default options:

```lua
require("neorg_flashcards").setup({
  flashcards_dir = vim.fn.expand("~/notes/flashcards"),
  default_file = vim.fn.expand("~/notes/flashcards/cards.norg"),
  default_kind = nil,
  languages = {},
})
```

| Option | Meaning |
| --- | --- |
| `flashcards_dir` | Root recursively scanned by all-card, tag, and score reviews. |
| `default_file` | File opened by `NeorgFlashcardOpen` and used when adding outside a `.norg` buffer. |
| `default_kind` | Schema used by `NeorgFlashcardAdd` when no kind argument is given. |
| `languages` | Map of supported card kinds to their schemas. At least one is required for useful cards. |

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
with `reveal = true` appear after you reveal the answer.

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
exception when its opt-in `keymaps.enable` setting is true. For normal Lua
configuration, these mappings use `<leader>nc` as a mnemonic namespace and
provide descriptions for which-key-style helpers:

```lua
vim.keymap.set("n", "<leader>nco", "<cmd>NeorgFlashcardOpen<CR>", { desc = "Open flashcards" })
vim.keymap.set("n", "<leader>nci", "<cmd>NeorgFlashcardAdd<CR>", { desc = "Add flashcard" })
vim.keymap.set("n", "<leader>nch", "<cmd>NeorgFlashcardHelp<CR>", { desc = "Flashcard help" })
vim.keymap.set("n", "<leader>ncr", "<cmd>NeorgFlashcardReview<CR>", { desc = "Review flashcards" })
vim.keymap.set("n", "<leader>ncf", "<cmd>NeorgFlashcardReviewFile<CR>", { desc = "Review file flashcards" })
vim.keymap.set("n", "<leader>nct", "<cmd>NeorgFlashcardReviewTag<CR>", { desc = "Review flashcards by tag" })
vim.keymap.set("n", "<leader>ncs", "<cmd>NeorgFlashcardReviewScore<CR>", { desc = "Review flashcards by score" })
vim.keymap.set("n", "<leader>ncv", "<cmd>NeorgFlashcardValidate<CR>", { desc = "Validate flashcards" })
```

Change the prefix freely. Your leader key is sovereign territory.

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

The first release targets Linux and macOS. Windows is not a `0.1.0` release
target; path handling should be treated as best effort there until a Windows
user can validate it.

## License

MIT. See [`LICENSE`](LICENSE).

## Module Layout

```text
lua/neorg_flashcards/init.lua     public setup, commands, add/open actions
lua/neorg_flashcards/presets.lua  bundled language presets
lua/neorg_flashcards/schema.lua   schema lookup, validation, render fields
lua/neorg_flashcards/parser.lua   @flashcard parsing and collection
lua/neorg_flashcards/review.lua   review popup and rating actions
lua/neorg_flashcards/store.lua    score/reviewed writeback
lua/neorg_flashcards/help.lua     short guide popup
lua/neorg_flashcards/popup.lua    shared floating window helper
lua/neorg_flashcards/util.lua     shared helpers
```
