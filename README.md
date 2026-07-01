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
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Commands](#commands)
- [Review Keys](#review-keys)
- [Card Format](#card-format)
- [Configuration](#configuration)
- [Language Presets](#language-presets)
- [Suggested Keymaps](#suggested-keymaps)
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
- Neorg, if you want normal Neorg editing/rendering for the `.norg` files.

The plugin itself reads and writes plain files. It does not require a running
Neorg workspace, Anki, SQLite, or external services.

## Installation

### lazy.nvim

```lua
{
  "devluixos/luixbits-neorg-flashcards.nvim",
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

### Local Checkout

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
inputs.luixbits-neorg-flashcards.url = "github:devluixos/luixbits-neorg-flashcards.nvim";
```

Import the module next to your NVF/Home Manager setup:

```nix
{
  imports = [
    inputs.luixbits-neorg-flashcards.homeManagerModules.nvf
  ];

  programs.nvf.settings.vim.notes.neorg-flashcards = {
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
creates keymaps when `keymaps.enable = true`.

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

1. Configure at least one language preset or custom schema.
2. Run `:NeorgFlashcardOpen` to create or open the configured flashcard file.
3. Run `:NeorgFlashcardAdd` to add a card.
4. Run `:NeorgFlashcardReview` to study all cards.
5. During review, press `1`, `2`, or `3` to save how well you know the card.

## Commands

- `:NeorgFlashcardOpen` opens the configured default file.
- `:NeorgFlashcardAdd [kind]` prompts for a new card. Without `[kind]`, it uses `default_kind`.
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
both your edits and the rating.

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

## Development

Run the local checks:

```sh
bash scripts/test.sh
```

Check the plugin from an isolated Neovim config:

```sh
bash scripts/check-clean-install.sh
```

If `stylua` is installed, the test script also checks formatting.

Record the README demo from your real desktop session:

```sh
bash scripts/record-real-demo.sh
```

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
