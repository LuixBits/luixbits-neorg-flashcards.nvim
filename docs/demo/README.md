# Study desk visual checks

These images show actual Neovim redraws with synthetic Japanese cards. They
were captured on 2026-10-16 through the full NVF configuration, with the local
plugin loaded before its installed version. The editor had visible whitespace
and concealment enabled. App windows suppress those settings locally; source
windows keep them. Images are rasterized from the external line grid.
The native Kitty captures below also check the actual font, box joins and
cursor placement. They use the same synthetic fixture in the recording VM.

Run `nvim -u NONE -c 'luafile scripts/study-desk-demo.lua'` from the checkout
for an isolated fixture. It creates temporary collections, disables the deck
registry, and opens Desk. It replaces the running editor's plugin setup, so
use a separate Neovim process. `FLASHCARDS_DEMO_MOTION=1` enables animation;
`FLASHCARDS_DEMO_ASCII=1` uses plain borders and chart glyphs. For the synthetic
activity fixture shown here, set `FLASHCARDS_DEMO_HISTORY=1`. Its seeded events
are demonstration data, not an actual person's study record.

| View | Terminal | Theme | Image |
| --- | --- | --- | --- |
| Framed Desk | 180 × 42 | Kanagawa | [Desk](desk.png) |
| Light Desk | 100 × 32 | peachpuff | [Light desk](desk-light.png) |
| ASCII Desk | 80 × 24 | peachpuff | [ASCII desk](desk-ascii.png) |
| Question with navigation and hint keys | 150 × 42 | Kanagawa | [Question](study-question.png) |
| Revealed card and session stacks | 150 × 42 | Kanagawa | [Study](study.png) |
| Compact card with source outside its border | 70 × 24 | peachpuff | [Compact study](study-compact.png) |
| Review keyboard help | 122 × 30 | Kanagawa | [Review keys](review-keys.png) |
| Wrapped help with inherited nowrap | 70 × 24 | peachpuff | [Compact keys](review-keys-compact.png) |
| Calendar and main analytics | 180 × 42 | Kanagawa | [Stats](calendar.png) |
| Analytics after Ctrl-D | 122 × 30 | Kanagawa | [Scrolled Stats](stats-scrolled.png) |
| Compact ASCII calendar | 80 × 24 | peachpuff | [Compact Stats](calendar-compact.png) |
| Chapter management | 150 × 38 | Kanagawa | [Chapters](chapters.png) |
| Cards within a chapter | 150 × 38 | Kanagawa | [Cards](overview.png) |
| Native Desk | 122 × 30 | habamax | [Native desk](native-desk.png) |
| Native session after Again and Good | 122 × 30 | habamax | [Native stacks](native-study.png) |
| Native compact dashboard | 122 × 30 | habamax | [Native Stats](native-stats.png) |

Review caught and corrected inherited whitespace dots, concealed border
characters, an oversized calendar, a clipped calendar in short windows, and
review focus returning to Desk during a resize. The session test checks unseen,
retry, finished, and rating totals across an actual resize. Chapter tests use
the real composer and keyboard actions to create, rename, move, and remove.
The native probe caught a Unicode cursor offset and singular stack labels.
The final stack shows six unseen cards, one retry, one finished card, and
Again 1 / Hard 0 / Good 1. The smaller Stats layout retains all three rating
totals above the fold and adds weekly comparisons alongside the calendar.

The latest grid captures show the source filename in muted workspace chrome,
outside the question/answer card, and the visible `Ctrl-D/U scroll` hint.
Keyboard tests exercise Ctrl-D, Ctrl-U, G and gg in the main Stats pane and
verify that scrolling leaves the selected calendar day unchanged. The native
Kitty images above predate these two small placement/hint changes.

The review captures now show `h` back, `l`/Enter reveal, `j/k` browse and `H`
hint. The `?` images include arrow aliases. Narrow help wraps descriptions
locally when the user's source windows use nowrap. Keyboard tests cover both
Ctrl-h/j/k/l and native Ctrl-W motions in columns and stacked layouts, pane
edges, date preservation, review navigation and Insert-mode Ctrl-H backspace.
Earlier workspace and native captures predate these shortcut changes.

Small desks scroll to later notes and the progress panel. The header retains
today's progress. A 60 × 20 interaction regression checks paging past the last
note; long cards and detail panes also scroll. Light and dark themes, ASCII,
Japanese text, animation cancellation, undo, and stale prompts are covered.

The retained `live-desk.png`, `live-calendar.png`, and earlier review media are
historical captures from the previous candidate. They are not evidence of the
current chapter hierarchy or Stats layout. Updated video takes belong in the
private Remotion capture inventory.
