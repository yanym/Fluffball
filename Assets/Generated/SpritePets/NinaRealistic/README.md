# Nina Realistic 2D Sprite Atlas

This directory preserves the traceable generation, frame extraction, and QA material for Nina's **Realistic 2D** appearance. The app only loads the compact runtime copy:

```text
Sources/Furball2D/Assets/Sprites/Nina/realistic/spritesheet.webp
```

- `package/spritesheet.webp` is the archival lossless transparent atlas.
- `run/references/` contains the Nina identity references used for generation.
- `run/prompts/` records the base, animation-row, and direction-repair prompts.
- `run/frames/` contains deterministically extracted animation frames.
- `run/final/` contains legacy candidate and accepted 1536×2288, 8×11 compatibility atlases. `Scripts/build-hd-sprite-assets.py` writes the current 2× runtime atlas into the app asset directory.
- `run/qa/` contains contact sheets, loop previews, direction semantics, and continuity reports.

The complete working tree is not bundled into the app. Before replacing the runtime atlas, rerun the repository validators and inspect the pet at 60%, 100%, and 140% display sizes.
