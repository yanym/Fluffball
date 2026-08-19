# Generated Assets

This directory contains material produced from user-provided sources: prepared AI references, aligned image views, generated sprite rows, generation records, and QA reports.

- `AIReferenceImages/generation-ready/` contains standardized 1440×1080 references for image-to-video generation.
- `ImageTurn/normalized/` contains aligned 1280×720 transparent image-view keyframes rebuilt directly from the approved 1440×1080 generation-ready sources. Regenerate them with `Scripts/rebuild-nina-standing-keyframes.py`; the matching bounds and detail report is under `ImageTurn/qa/`.
- `SpritePets/` contains generated atlases, intermediate rows, contact sheets, and validation artifacts.

`SpritePets/HD-QA/ground-baseline.json` records the planted-cell baseline audit for both production atlases. `Scripts/validate-pet-pack.swift` repeats this check and rejects more than 2 px of stable-cell drift.

Final resources bundled by Swift Package Manager live under `Sources/Furball2D/Assets/`. Treat that directory as compiled runtime output; rebuild it from documented inputs and scripts rather than editing source material in place.
