# Furball Codex v2 Image Pet

This directory preserves traceable generation and QA material for the Furball image-animation atlas. It is organized by purpose:

- `source/canonical-base.png` locks identity, coat color, and proportions.
- `source/rows/` keeps the accepted generated action and direction strips for targeted regeneration.
- `package/` contains the standalone atlas and layout metadata.
- `qa/` contains contact sheets, direction previews, loop GIFs, and deterministic reports.

The copy loaded by the app at runtime is:

```text
Sources/Furball2D/Assets/Pets/Nina/Sprites/Nina/cute/spritesheet.webp
```

The runtime asset preserves the Codex `spriteVersionNumber: 2` 8×11 semantic layout and uses Furball's `assetScale: 2` HD extension: a 3072×4576 transparent lossless WebP with 384×416 cells. Older 1536×2288 files remain only as generation records and compatibility references.

- Row 0: six-frame idle.
- Row 1: eight-frame running-right.
- Row 2: eight-frame running-left, generated independently to preserve real asymmetric markings rather than mirroring row 1.
- Rows 3–8: waving, jumping, failed, waiting, working, and review.
- Rows 9–10: 16 gaze directions at 22.5° intervals from 0°. Zero is up, 90° screen-right, 180° down, and 270° screen-left.

`qa/contact-sheet.png` is the full contact sheet, `qa/look-directions.png` is the labeled semantic sheet, `qa/look-continuity.json` contains adjacent-direction metrics, and `qa/validation.json` plus `qa/chroma-despill.json` are the deterministic structure, alpha, and blue-edge reports.

Runtime behavior is not hardcoded by row name. `Sources/Furball2D/Assets/Pets/Nina/manifest.json` declares timing in `spriteAtlas.animations`, maps all 27 standard semantics through `bindings`, defines gaze through `lookDirections`, and publishes localized gestures through `actions`. A new dog or cat should replace the atlas and manifest metadata without adding pet-specific Swift paths.
