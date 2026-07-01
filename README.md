# luixbits-neorg-flashcards.nvim

Local flashcards for Neorg notes in Neovim.

`luixbits-neorg-flashcards.nvim` keeps language-learning cards in plain `.norg`
files, then gives you a small prompt for creating cards and a floating review
UI for studying them. It is intentionally local-first: no Anki, no server, no
sync account, and no database outside your notes.

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

For NVF, package the plugin with `pkgs.vimUtils.buildVimPlugin` and add it to
`programs.nvf.settings.vim.startPlugins`.

```nix
{
  config,
  pkgs,
  ...
}: let
  neorgFlashcards = pkgs.vimUtils.buildVimPlugin {
    pname = "luixbits-neorg-flashcards.nvim";
    version = "0.1.0";
    src = pkgs.fetchFromGitHub {
      owner = "devluixos";
      repo = "luixbits-neorg-flashcards.nvim";
      rev = "v0.1.0";
      hash = "sha256-0Sjl3BeDZKmNfVUZxnzgCVvkZ7OSO7HyEIVJQTdKKSo=";
    };
  };
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

To refresh the hash for a newer tag, prefetch it:

```sh
nix store prefetch-file --unpack \
  https://github.com/devluixos/luixbits-neorg-flashcards.nvim/archive/refs/tags/v0.1.0.tar.gz
```

In a flake-based config, you can also use the repository as a flake input with
`flake = false` and set `src = inputs.luixbits-neorg-flashcards`.

```nix
inputs.luixbits-neorg-flashcards = {
  url = "github:devluixos/luixbits-neorg-flashcards.nvim/v0.1.0";
  flake = false;
};
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

## Demo

![Creating and reviewing Japanese flashcards](docs/demo/review.gif)

The demo is a real screen recording captured with `wf-recorder` from an actual
kitty + Neovim session. The recording workflow lives in
[`scripts/record-real-demo.sh`](scripts/record-real-demo.sh) and uses the sample
Japanese cards in [`docs/demo/flashcards/cards.norg`](docs/demo/flashcards/cards.norg).
It creates cards for `languages` / `言語` and `linux` / `リナックス`, then reviews
and scores them.

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
