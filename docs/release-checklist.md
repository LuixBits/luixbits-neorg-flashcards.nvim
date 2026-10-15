# Study desk release checklist

Implementation started on 2026-10-15 from [the agreed design](desk-redesign.md).
This checklist records implementation, verification, and the accompanying
video preparation. Check items only after completing them.

## Plugin

- [x] Establish baseline checks and record the release target.
- [x] Add Desk / Overview / Stats navigation and update contextual controls.
- [x] Render theme-aware deck boxes, category notes, and responsive layouts.
- [x] Integrate review cards, piles, receipt, and short cancellable animations.
- [x] Preserve retries, undo, hints, typed answers, editing, and persistence.
- [x] Add category metadata and management, including safe tag operations.
- [x] Add validated UI-managed decks and editable deck preferences.
- [x] Add calendar selection, day details, forecast, and history drilldown.
- [x] Add unique-card daily goals and honest activity/streak feedback.
- [x] Verify narrow terminals, Unicode, dark/light themes, and reduced motion.
- [x] Capture actual UI images, inspect them, fix issues, and capture again.
- [x] Exercise real interaction and animation sequences.
- [x] Run regression, clean-install, formatting, lint, and full flake checks.
- [x] Review the final source and failure paths; resolve findings.
- [x] Update README, help, changelog, upgrading guide, ADRs, and roadmap.
- [x] Refresh the local Graphify index.
- [ ] Finish the scoped commits and verify a clean final plugin tree.
- [x] Record exact validation and release preparation status below.

## Flashcards video

- [ ] Read production instructions and the current preproduction plan/scripts.
- [ ] Update preproduction and capture cues from the implemented behavior.
- [ ] Revise the canonical chapter scripts using the repository writing skill.
- [ ] Check the factual claims, voice, and cross-chapter continuity.
- [ ] Run required Remotion checks and commit only the scoped script changes.
- [ ] Prepare the existing recording rig if capacity permits.
- [ ] Record and inspect a real capture probe, then useful clips if feasible.
- [ ] Record capture provenance and remaining narration/review work privately.

## Validation and handoff

Release target: **0.3.0**, prepared locally on `feat/ascii-study-desk`.
Tagging, merging, pushing, and publishing remain separate release actions.

Validated on 2026-10-16:

- Full regression suite on Neovim 0.10.4, 0.11.5, and 0.12.4.
- Clean install without Neorg on all three tested versions.
- Full `nix flake check --print-build-logs` passed on x86_64 Linux, including
  Neorg integration, package loading, NVF module evaluation, Lua syntax,
  formatting/lint, documentation lint, and workflow lint.
- Pinned formatter used: StyLua 2.5.2 from the flake. Lua lint: zero warnings.
- Actual UI image review: dark/light themes, plain ASCII, Japanese glyphs,
  widths 60/80/100/140, and repeated layout changes. See [images](demo/README.md).
- Review retries, undo, rapid rating input, receipts, category persistence,
  deck creation/reload, stale prompts, goal snapshots, pending-event replay,
  tag backups, symlink protection, and malformed metadata covered by tests.
- Fixed a Neovim 0.11 native crash found during the background-tab close test;
  the footer float now closes before its parent split.
- Local Graphify index refreshed: 815 nodes, 1,840 edges.

macOS, Windows, and ARM execution were not available in this validation run.
The implementation uses Neovim APIs and the existing portable storage layer.
