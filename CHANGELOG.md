# Changelog

All notable changes to this project will be documented here.

## Unreleased

- Removed the local planning checklist from the tracked public repo.
- Expanded the README with project goals, quick start, configuration details,
  and NVF/Nix install examples.
- Added a real screen-recorded README demo using sample Japanese flashcards.
- Fixed collection reviews to use unsaved changes from loaded chapter files and
  guard against stale rating writes.
- Added source-file context to the review popup and documented
  file-per-chapter collections.
- Expanded regression coverage for recursive collections, tags, loaded
  buffers, and stale sources, and added formatting and Nix CI checks.
- Added command, popup-keymap, Neorg-free, isolated-Neorg, and checksum-pinned
  Neovim 0.10.4 minimum and 0.12.4 current-version compatibility tests.
- Clarified setup with and without Neorg, `.norg` file behavior, configuration
  paths, and global versus popup-local keymaps.
- Made `NeorgFlashcardOpen` create nested parent directories for `default_file`.
- Normalized symlinked collection paths so chapter source labels stay relative
  and loaded files are not counted twice on macOS or other symlinked roots.
- Hardened test exit handling and temporary-directory isolation so startup
  errors and concurrent runs cannot report false success.
- Added a runnable 90-second Remotion explainer with burned-in captions, a full
  narration and clip plan, a NixOS render helper, and CI composition checks.

## 0.1.0 - 2026-07-01

- Extracted the flashcard workflow into a standalone Neovim plugin.
- Added opt-in Japanese and Chinese language presets.
- Added generic `:NeorgFlashcardAdd [kind]` support.
- Added in-editor help, review-by-tag, review-by-score, and 1/2/3 ratings.
- Added headless Neovim tests, clean-config checks, and CI.
