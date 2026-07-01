# Planning

## NVF/Nix Distribution Plan

### Summary

- Keep the Neovim plugin, Nix package, and NVF integration in this repository.
- Do not create a second packaging repo.
- Ship first-class Nix support through this repository's flake outputs.
- Keep lazy.nvim as the primary non-Nix installer.
- Defer nixpkgs and upstream NVF integration until the repo-owned module has stabilized.

### Key Changes

- Add a repository flake exposing:
  - `packages.${system}.default`
  - `packages.${system}.luixbits-neorg-flashcards-nvim`
  - `homeManagerModules.nvf`
  - `nixosModules.nvf`
  - flake checks for packaging, Lua syntax, headless tests, clean install, and NVF module evaluation
- Add an NVF module under `programs.nvf.settings.vim.notes.neorg-flashcards` with:
  - `enable`
  - `package`
  - `setupOpts`
  - `languagePresets`
  - `keymaps.enable`
  - `keymaps.prefix`
  - `keymaps.registerWhichKey`
- Keep the module generic:
  - no personal note paths
  - no Japanese defaults unless users opt into them
  - no default keymaps unless users enable them

### Installer Strategy

- lazy.nvim remains documented and supported.
- Nix users can build or import the plugin directly from this flake.
- NVF users can import `homeManagerModules.nvf` or `nixosModules.nvf`.
- nixpkgs packaging is optional later work.
- upstream NVF support is optional later work after this module interface settles.

### Test Plan

- Run `bash scripts/test.sh`.
- Run `bash scripts/check-clean-install.sh`.
- Run `nix flake check`.
- Build `.#packages.${system}.default`.
- Validate that the NVF module adds the plugin, emits setup Lua, and optionally emits keymaps.

### Follow-Up

- Migrate the personal Nix config to consume this flake module instead of hand-building the plugin.
- Consider a nixpkgs `vimPlugins` package after one functional release beyond README-only changes.
- Consider an upstream NVF PR after the module has been used locally for a while.
