# Workspace refinement

Follow-up to the 2026-10-16 review in the user's actual NVF setup.

- [x] Isolate app buffers from whitespace markers, concealment and source-file hooks.
- [x] Frame the desk, use compact spacing, and remove filler text.
- [x] Show useful pending/reviewed stacks with session counts and rating totals.
- [ ] Make Overview a collection → chapter → card manager with contextual actions.
- [ ] Rebalance Stats around useful summaries, a compact calendar and day details.
- [ ] Verify the full user configuration, themes, resizes, keyboard navigation and persistence.
- [ ] Review images, run release checks and make scoped commits throughout.
- [ ] Update documentation, video facts and the temporary Neovim build.

The screenshots exposed inherited `listchars` markers and Neorg concealment in
app scratch buffers. UI buffers need their own filetype and local display
options. Normal note buffers must retain the user's editing preferences.

Collections contain chapters; chapters contain cards. Tags independently
categorize cards across chapters. Chapter membership belongs in collection
metadata, keyed by stable card IDs, so existing note syntax stays compatible.
Unassigned cards remain in Unfiled. Preserve IDs, history and config ownership.
