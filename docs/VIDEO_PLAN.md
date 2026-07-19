# Flashcards Explainer Video

## Goal

Explain the storage model and the three study scopes in about 90 seconds:

- current `.norg` file = current chapter;
- every `.norg` file under `flashcards_dir` = full collection;
- one tag = a topic spanning several chapters.

The video must also make one compatibility boundary unambiguous: the plugin
works in plain Neovim, but its flashcard files still use the `.norg` extension.
Neorg is an optional editing layer, not a runtime dependency.

## Format

- Composition: `FlashcardsExplainer`
- Canvas: 1920×1080
- Frame rate: 30 fps
- Duration: 90 seconds
- Visual style: dark editor UI, mint and purple accents, monospace technical labels
- Delivery: H.264 MP4, stereo narration, peaks below -1 dBFS
- Captions: the Remotion composition already displays the narration text inside the title-safe area

## Full Narration Script

### 00:00–00:06 — Hook

> Flashcards are useful. Rebuilding them in another app every time you take
> notes is not.

### 00:06–00:16 — Storage model

> This plugin treats a plain dot norg file as the database. Each flashcard
> block keeps the prompt, answer, tags, score, and review date beside your
> notes.

### 00:16–00:29 — Chapters and collections

> Put one file per chapter under a flashcards directory. The folder becomes the
> collection, while each file remains a chapter you can open, edit, move, diff,
> or sync normally.

### 00:29–00:40 — Current chapter

> Open chapter two and run Neorg Flashcard Review File. Only cards from the
> current file enter the session, so revision stays aligned with the chapter
> in front of you.

### 00:40–00:52 — Every chapter

> Run Neorg Flashcard Review to scan every dot norg file below the collection
> root. Nested courses and chapters become one review session without merging
> the source files.

### 00:52–01:02 — Tags across chapters

> Chapters describe where a card came from. Tags describe what it is about.
> Review the grammar tag to pull matching cards from several chapter files.

### 01:02–01:12 — Plain Neovim and Neorg

> Normal Neovim can add, review, filter, and rate the cards directly. Add Neorg
> when you want its syntax, concealing, and note features. The storage format
> stays dot norg in both modes.

### 01:12–01:21 — Rating and writeback

> Reveal the answer, then press one, two, or three. The score and review date
> are written back to the same card block. No mystery database hiding under the
> floorboards.

### 01:21–01:30 — Close

> Current chapter, every chapter, or a tag across all of them. Plain files in
> Git, a focused review popup, and your notes remain yours.

## Clip Plan

| Time | Clip | Visual | On-screen proof | Edit notes |
| --- | --- | --- | --- | --- |
| 00:00–00:06 | `01-hook` | Three chapter notes converge into one flashcard. | Notes already contain the answers. | Start on the first spoken word; no logo pre-roll. |
| 00:06–00:16 | `02-storage` | Annotated `@flashcard` block beside portable/inspectable/versionable callouts. | Prompt, answer, tags, score, and date are plain text. | Let each field enter as it is named. |
| 00:16–00:29 | `03-chapters` | File tree with `chapter-02.norg` highlighted. | File = chapter; folder = collection. | Hold the tree long enough to read nested `course-b/`. |
| 00:29–00:40 | `04-current-file` | Chapter source and review popup side by side. | `:NeorgFlashcardReviewFile` and `FILE · 1/23`. | Optional live insert: open the real chapter and run the command. |
| 00:40–00:52 | `05-collection` | Three chapter counts merge into a 56-card session. | `:NeorgFlashcardReview`, recursive scan, sources stay separate. | Animate toward the result; do not imply file merging. |
| 00:52–01:02 | `06-tags` | `#grammar` lights up in three files. | `:NeorgFlashcardReviewTag grammar`. | Amber is reserved for the selected tag. |
| 01:02–01:12 | `07-compatibility` | Plain Neovim and Neorg panels share one `.norg` badge. | Both modes support flashcards; only Neorg adds note rendering. | This is the key compatibility answer—leave the badge visible. |
| 01:12–01:21 | `08-scoring` | Card reveals, rating keys appear, source fields update. | `score: 3` and `reviewed: 2026-07-19`. | Time the writeback to the word “written”. |
| 01:21–01:30 | `09-outro` | Three review commands and the project name. | Current file, all files, or tag. | End on the repository name for at least two seconds. |

## Optional Real-Neovim Inserts

The Remotion composition is complete without screen recordings. If live proof
is useful, record three silent 1920×1080 clips and replace or overlay the
matching conceptual shots:

1. `04-current-file-live.mp4`: open `chapter-02.norg`, then run
   `:NeorgFlashcardReviewFile`.
2. `05-collection-live.mp4`: run `:NeorgFlashcardReview` and show the source
   label changing as cards advance.
3. `08-rating-live.mp4`: reveal a card, press `3`, close the popup, and show the
   updated `score:` and `reviewed:` lines.

Capture rules:

- use a clean temporary collection, not personal notes;
- disable notifications unrelated to the demo;
- keep the cursor away from the card text after the command runs;
- record at 30 or 60 fps with no scaling before the Remotion edit;
- leave one second of handles before and after every action;
- never type through a password prompt on camera—the shell remembers forever.

## Audio Plan

- Read at roughly 110–120 words per minute.
- Pause briefly after “current chapter”, “every chapter”, and “tags”.
- Pronounce `.norg` as “dot norg”; pronounce command names as words, not every
  CamelCase boundary.
- Keep music instrumental and sparse. Duck it by roughly 8–10 dB under speech.
- Record each scene as a separate take using the clip identifiers above. This
  makes timing changes local instead of turning the waveform into archaeology.

## Render Checklist

1. Run `npm ci` inside `video/`.
2. Run `npm run check`.
3. Open `npm run studio` and inspect every scene boundary.
4. Run `npm run still` and check text at full resolution.
5. Run `npm run render` and watch the entire MP4 once with sound and once muted.
6. Confirm the compatibility scene says `.norg` in both modes.
7. Confirm collection visuals never imply that source files are merged.
8. Confirm command spelling matches the plugin help.

## Suggested Published Chapters

```text
00:00 Why local flashcards?
00:06 The .norg storage model
00:16 Files as chapters
00:29 Review the current chapter
00:40 Review the full collection
00:52 Tags across chapters
01:02 Plain Neovim or Neorg?
01:12 Ratings and writeback
01:21 Local-first workflow
```
