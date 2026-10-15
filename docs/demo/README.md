# Study desk visual checks

These images show the actual Neovim UI with synthetic Japanese cards. They
were captured from Neovim's external line-grid redraw events and rasterized
with a monospace font. They contain no personal collection data or invented
terminal output.

Run the same disposable fixture from the repository root:

```sh
nvim -u NONE -i NONE -n -c 'colorscheme habamax' \
  -c 'luafile scripts/study-desk-demo.lua'
```

The fixture writes eight cards into a temporary directory, disables the deck
registry, and opens Desk. Set `FLASHCARDS_DEMO_MOTION=1` to exercise animations
or `FLASHCARDS_DEMO_ASCII=1` for plain borders. Use `:colorscheme peachpuff` for
the light-theme variant. It does not change your normal setup or collections.

| View | Terminal | Theme | Image |
| --- | --- | --- | --- |
| Desk | 140 × 45 | habamax | [Desk](desk.png) |
| Desk | 100 × 32 | peachpuff | [Light desk](desk-light.png) |
| ASCII Desk | 80 × 24 | default | [ASCII desk](desk-ascii.png) |
| Revealed card | 80 × 24 | habamax | [Study](study.png) |
| Calendar | 80 × 24 | habamax | [Calendar](calendar.png) |
| Overview | 100 × 32 | peachpuff | [Manager](overview.png) |

Image review on 2026-10-16 caught and corrected repeated shortcut strips,
paper shadows crossing card content, hidden page headings after tab changes,
and rating labels losing color when wrapped. A 60 × 20 fallback was also
reviewed; its rating choices use separate lines. Longer cards and detail panes
scroll. Calendar explanations wrap in the sidebar; this was checked again in
a real 108 × 27 terminal recording. On small desks, j/k and PageDown bring further category rows into view.

Interaction tests exercise live animation cancellation, Again, undo, completion,
calendar drilldown, deck creation/reload, stale prompts, and repeated resizes.
The existing background-tab close regression exposed a Neovim 0.11 crash with
the new floating strip; closing the float before its host fixes it on the
tested 0.10.4, 0.11.5, and 0.12.4 builds.
