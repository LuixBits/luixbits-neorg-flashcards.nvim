# Workspace refinement

Follow-up to the 2026-10-16 review in the user's actual NVF setup.

- [x] Isolate app buffers from whitespace markers, concealment and source-file hooks.
- [ ] Frame the desk, use compact spacing, and remove filler text.
- [ ] Show useful pending/reviewed stacks with session counts and rating totals.
- [ ] Make Overview a collection → chapter/category → card manager with contextual actions.
- [ ] Rebalance Stats around useful summaries, a compact calendar and day details.
- [ ] Verify the full user configuration, themes, resizes, keyboard navigation and persistence.
- [ ] Review images, run release checks and make scoped commits throughout.
- [ ] Update documentation, video facts and the temporary Neovim build.

The screenshots exposed inherited `listchars` markers and Neorg concealment in
app scratch buffers. UI buffers need their own filetype and local display
options. Normal note buffers must retain the user's editing preferences.

The chapter/category hierarchy is being clarified with the user. Collection
metadata and tagged cards remain the existing sources of truth; the redesign
must preserve card IDs, review history and configured collection ownership.
