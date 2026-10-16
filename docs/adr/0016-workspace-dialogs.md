# ADR 0016: Keep workspace actions in shared dialogs

- Status: Accepted
- Date: 2026-10-16

## Context

Management and deletion used `vim.ui.select`. Its default command-area
presentation separated these actions from the desk and left long confirmations
hard to read. The management list also mixed collection, chapter, card, and tag
operations.

## Decision

- Use one plugin-local dialog module for workspace menus, confirmations, and
  small inputs. Reuse popup windows and the desk's highlights and ASCII option.
- Keep the first menu contextual. Put tag appearance and UI-created collection
  preferences in submenus. Hide operations owned by configuration.
- Use Neovim motions and arrows, Enter to choose, h to return to a parent menu,
  and q/Esc to cancel. Inputs support ordinary Insert and Normal editing.
- Keep validation errors beside the value. Select the safe choice initially
  for destructive confirmations and describe their consequences.
- Complete each callback once, restore the originating pane, and cancel on
  focus loss or closure. Keep the existing collection/generation checks and
  source transactions at the mutation boundary.

## Consequences

Workspace actions have the same presentation across installations without
another setup option or dependency. They do not override global `vim.ui`
functions. Typed-answer practice retains its separate input-history contract.
The plugin owns dialog resize, keyboard, Unicode, and lifecycle tests, including
real interaction through the configured editor.
