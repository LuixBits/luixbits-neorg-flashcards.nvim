# Study desk visual checks

The [animated demo](study-desk.gif) shows a Japanese study stack, a hint,
answer reveal, and an Again rating. It uses synthetic cards from the screen
recordings made for the video. The 13-second loop is 1280 × 720 and about
411 KiB. The footage was recorded on v0.3.0; these review controls also apply
to v0.3.2. [View a still](desk.png).

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

## Card entry refinement

Captured on 2026-10-16 from runtime `cb0eba6` using the configured NVF editor
and temporary synthetic collections. These images come from Neovim's external
line grid. These changes are included in v0.3.1.

| View | Terminal | Theme | Image |
| --- | --- | --- | --- |
| Previous composer | 122 × 30 | Kanagawa | [Before](composer-before.png) |
| New card, with collection and chapter | 122 × 30 | Kanagawa | [Composer](composer.png) |
| Completed required fields | 122 × 30 | Kanagawa | [Filled form](composer-filled.png) |
| Compact field layout | 80 × 24 | peachpuff | [Light form](composer-light.png) |
| Missing required fields | 80 × 24 | peachpuff | [Validation](composer-errors.png) |
| Last field in a short ASCII window | 60 × 20 | habamax | [Small form](composer-compact.png) |
| Inline multiline Notes | 122 × 30 | Kanagawa | [Notes](composer-notes.png) |
| Inline Notes in a light theme | 80 × 24 | peachpuff | [Light Notes](composer-notes-light.png) |

The composer keeps labels and inputs together and distinguishes required and
optional values. Every field, including Notes, is directly editable. Multiline
values expand in place; there is no preview row, second editor, or apply step.
Narrow windows reduce spacing. Tab and Shift-Tab select fields, while native
j/k and arrows move through their lines.

The configured-editor interaction check used actual keys to enter two Japanese
cards, including Notes and Tags, without leaving Insert mode. Ctrl-N saved the
first and Ctrl-S saved the second; both retained their chapter assignment.
Editing Notes inline with o, resizing to 60 × 20, and saving once preserved
line breaks, indentation, and the card ID. Backspace stopped at field boundaries.

The regression suite covers multiline paste, o/O, line deletion, undo/redo after
moving to another field, rejected cross-field joins, required validation,
discard protection, and a fresh undo history after save-and-new. It passed on
Neovim 0.10.4, 0.11.5, and 0.12.4. The x86_64-linux Nix flake checks also passed,
including the package and Neorg integration checks.

## Workspace dialogs

Captured on 2026-10-16 from runtime `4105033`, through the configured NVF editor
with the same synthetic collections. These are rasterized Neovim line-grid
captures. The dialog changes are included in v0.3.2.

| View | Terminal | Theme | Image |
| --- | --- | --- | --- |
| Collection actions | 122 × 30 | Kanagawa | [Collection menu](dialog-collection.png) |
| Card actions | 122 × 30 | Kanagawa | [Card menu](dialog-card.png) |
| Remove a chapter | 122 × 30 | Kanagawa | [Chapter confirmation](dialog-chapter-delete.png) |
| Delete a card, ASCII borders | 60 × 20 | habamax | [Compact confirmation](dialog-card-delete.png) |
| Rename a chapter | 80 × 24 | peachpuff | [Rename input](dialog-chapter-rename.png) |
| Correct an invalid goal | 80 × 24 | peachpuff | [Inline error](dialog-error.png) |
| Tags and card counts | 80 × 24 | Kanagawa | [Tag menu](dialog-tags.png) |

Image review caught a blank input and a validation message disappearing after
submission. The input now renders its value and keeps the error until it is
changed. Dialog text uses the theme's normal foreground for readable
consequences; boundaries, headings, and selection reuse the desk's groups.

The configured-editor keyboard check creates a card with Japanese text and
inline Notes, renames its chapter, opens card actions, cancels deletion,
resizes to 60 × 20, and confirms deletion. Regression tests also exercise
tag backups, collection creation and detachment, stale prompts, invalid
blocks, focus changes, native close, long names, and replaced popup buffers.
