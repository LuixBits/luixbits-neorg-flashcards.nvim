# Workspace dialogs

Follow-up to the management-menu and deletion review on 2026-10-16.

- [x] Build one small, theme-aware dialog for menus, confirmations, and inputs.
- [x] Keep collection, chapter, and card menus short and contextual.
- [x] Explain deletion consequences and select the safe choice first.
- [x] Preserve cancellation, stale-prompt guards, and source transactions.
- [x] Test keyboard use, resize, long names, and the configured editor.
- [x] Review dark, light, compact, and ASCII captures; correct visual issues.
- [x] Update help, the changelog, and the visual gallery.
- [x] Run compatibility and package checks, refresh Graphify, and commit.

Use the desk's existing colors and border style. No new theme, picker, or
layout settings. Menus use j/k or arrows, Enter, and Esc/q. Inputs use normal
Neovim editing, Enter to submit, and Esc to return to Normal mode.

Runtime `4105033` adds the shared dialogs and their interaction checks. The
[visual gallery](demo/README.md#workspace-dialogs) records the reviewed dark,
light, and ASCII layouts. Existing `vim.ui` overrides remain unchanged;
workspace actions use plugin-local dialogs without another setup option.

Validated on 2026-10-16:

- Regression suite passed on Neovim 0.10.4, 0.11.5, and 0.12.4.
- The configured NVF editor passed real keyboard entry, menu, resize, and
  persistence checks with Blink enabled.
- Full x86_64-linux `nix flake check --print-build-logs` passed, including
  formatting, lint, clean install, Neorg integration, and package loading.
- Seven final captures cover Kanagawa, peachpuff, and habamax at 122 × 30,
  80 × 24, and 60 × 20, including the ASCII mode and inline validation.
- Graphify was refreshed after the final source changes.

Implementation and documentation are committed on `improve/workspace-dialogs`.
No release was published and no system configuration was activated.
