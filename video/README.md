# Remotion Explainer

This directory contains the 90-second concept video for the plugin. The video
is rendered entirely from React components; it does not require the terminal
recording assets under `docs/demo/`.

The narration, timestamps, and clip directions are in
[`docs/VIDEO_PLAN.md`](../docs/VIDEO_PLAN.md). Scene timings and caption text
live in [`src/timeline.ts`](src/timeline.ts), which is the source of truth used
by the composition.

## Run

```sh
cd video
npm ci
npm run check
npm run studio
```

Render the poster frame and final MP4:

```sh
npm run still
npm run render
```

Outputs are written to `video/out/` and intentionally ignored by Git.

### NixOS

Remotion downloads dynamically linked browser and FFmpeg binaries, which do
not run directly on a stock NixOS host. From the repository root, use:

```sh
bash scripts/render-video-nixos.sh
```

The helper resolves a Nix-native Chromium and runs the render in `steam-run`.
It requires flakes plus access to the unfree `steam-run` package; the generated
MP4 is still written to `video/out/flashcards-explainer.mp4`.

## Composition

- ID: `FlashcardsExplainer`
- Size: 1920×1080
- Frame rate: 30 fps
- Duration: 90 seconds
- Audio: narration script provided separately; no voice recording is committed

Remotion captions are burned into the composition so it remains understandable
when muted. Add a separately recorded narration track only after the scene
timings are locked; moving both pixels and phonemes at once is how timelines
become haunted.
