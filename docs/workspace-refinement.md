# Workspace refinement

Follow-up to the 2026-10-16 review in the user's actual NVF setup.

- [x] Isolate app buffers from whitespace markers, concealment and source-file hooks.
- [x] Frame the desk, use compact spacing, and remove filler text.
- [x] Show useful pending/reviewed stacks with session counts and rating totals.
- [x] Make Overview a collection → chapter → card manager with contextual actions.
- [x] Rebalance Stats around useful summaries, a compact calendar and day details.
- [x] Verify the full user configuration, themes, resizes, keyboard navigation and persistence.
- [x] Review images, run release checks and make scoped commits throughout.
- [x] Update documentation, video facts and the temporary Neovim build.
- [x] Use Neovim motions and arrows consistently; verify Ctrl-h/j/k/l in both pane layouts.
- [x] Review shortcut help at narrow widths and keep all descriptions readable.

The screenshots exposed inherited `listchars` markers and Neorg concealment in
app scratch buffers. UI buffers need their own filetype and local display
options. Normal note buffers must retain the user's editing preferences.

Collections contain chapters; chapters contain cards. Tags independently
categorize cards across chapters. Chapter membership belongs in collection
metadata, keyed by stable card IDs, so existing note syntax stays compatible.
Unassigned cards remain in Unfiled. Preserve IDs, history and config ownership.

The short-window calendar now fits above the day details. A resize regression
also caught review focus returning to the desk; the active review keeps focus
while its stack counters and dimensions update.

Native terminal review also caught a cursor using display columns where Neovim
expects byte offsets. The cursor now follows the selected box with Unicode
borders. At 122 × 30, Stats uses the shorter calendar, keeps all rating totals
visible, and puts weekly comparisons in the space beside the calendar.

The isolated editor package was rebuilt from runtime revision `5c2d8f5` and
opened all three pages through the full personal NVF configuration. Regression
checks cover Neovim 0.10.4, 0.11.5 and 0.12.4; the x86_64 Linux flake checks
include Neorg integration and packaging. These changes shipped in v0.3.0.

The Remotion narration and private plan now describe independent chapters.
Two fresh silent probes preserve the revised interface and its subsequent
visual corrections. The final probe passes hash, frame-timing and full-decode
checks. Earlier footage needs a continuity/retake audit; narration and chapter
assembly remain production work. No publication or system activation occurred.

Further local testing exposed that the Stats ribbon dropped its scrolling
hint in narrow panes. It now keeps `Ctrl-D/U scroll` visible, with real keyboard
coverage for paging and top/bottom navigation. The source filename moved from
the study card to muted workspace chrome. Help and documentation explain
burying until local midnight and suspending until manually resumed.

The keyboard follow-up moves review hints to `H`, makes `h`/Left return and
`l`/Right reveal, and adds arrow browsing. Ctrl-h/j/k/l uses Neovim's directional
window commands; native Ctrl-W motions remain available. Real key tests cover
column and stacked layouts, pane edges, calendar-date preservation, review
navigation without ratings, and Insert-mode Ctrl-H backspace in the composer.
Image review caught clipped help under inherited nowrap; help now wraps locally.

Runtime `98a6bf0` passed the regression suite on Neovim 0.10.4, 0.11.5 and
0.12.4, the clean-install check and the full x86_64 Linux flake checks. The
separate personal NVF package was rebuilt and verified with the real collection
configuration: all three pages, Ctrl-H/L pane movement and wrapped help. The
video ledger and private capture cues now use the same keys. No new video
footage was recorded for this follow-up.
