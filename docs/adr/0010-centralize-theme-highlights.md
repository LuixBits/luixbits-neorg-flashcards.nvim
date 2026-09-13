# ADR 0010: Centralize theme highlights

- Status: Accepted
- Date: 2026-08-22

## Context

The hub, form, review popup, and statistics page used to define their own
highlight groups. Only the hub restored its groups after `ColorScheme`, so a
theme change could leave the heatmap unstyled. The heatmap also used fixed
greens and one glyph for every non-zero level. Review highlighting searched
rendered text for rating words, which could color ordinary card content such as
"Good morning."

## Decision

One module owns every plugin highlight group and restores it after
`ColorScheme`. Defaults link to semantic groups from the active theme. Users
may replace the Again, Hard, Good, and heat-level definitions with exact
Neovim highlight attributes.

The heatmap uses distinct glyphs as well as color. Renderers attach rating
groups to known controls and summary spans instead of searching card text.

## Consequences

Colorscheme changes preserve the complete UI and exact overrides remain stable.
Activity levels remain distinguishable in monochrome themes. Adding a custom
group now requires registering it in the central module rather than defining it
inside a renderer.
