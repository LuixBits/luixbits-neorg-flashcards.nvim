# ADR 0009: Use semantic rating highlights

- Status: Accepted
- Date: 2026-08-22

## Context

Again, Hard, and Good carry the same meaning in review controls, hub summaries,
and statistics. Hard-coded colors can disagree with a colorscheme, lose
contrast, and make the same rating look different between those surfaces.

## Decision

- Rating text uses the public groups `NeorgFlashcardsAgain`,
  `NeorgFlashcardsHard`, and `NeorgFlashcardsGood` wherever the UI presents
  those rating semantics.
- Defaults link those groups to `DiagnosticError`, `DiagnosticWarn`, and
  `DiagnosticOk`. Links let the active colorscheme supply accessible colors
  instead of the plugin choosing RGB values.
- `ui.rating_highlights` accepts Neovim highlight-definition tables for the
  `again`, `hard`, and `good` entries. A user may change the links or provide
  normal `nvim_set_hl()` attributes without patching a UI module.
- Setup validates all three entries. Review and hub rendering define the same
  groups from the same configuration, and invalid runtime definitions fall
  back to the corresponding diagnostic link.

## Consequences

Rating colors remain consistent across review and statistics while following
the colorscheme by default. Colors are a redundant cue: the rating name and
number remain visible, so the interface does not depend on color alone.
