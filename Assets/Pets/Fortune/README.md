# Fortune source workspace

Fortune is the second bundled pet profile: a tricolor Pembroke Welsh Corgi with a black saddle, warm tan head and haunches, a narrow asymmetric white forehead blaze, white muzzle/chest/legs, large upright ears, dark eyes, and a naturally very short tail.

- `UserProvided/ReferencePhotos/` contains the six immutable identity photos supplied by the user. Their filenames describe the visible view or posture.
- `UserProvided/SourceVideos/right-profile/` preserves the nine original Gemini MP4 action videos with normalized kebab-case names. These provenance sources are never used directly at runtime.
- `Generated/SpritePet/run/` contains the grounded `$hatch-pet` generation record, canonical identity image, native-HD action grids, and QA data.
- `Generated/SpritePets/HD-QA/realistic-atlas.png` is the complete 11-row visual review sheet.

The dual-mode runtime Pet Pack lives at `Sources/Furball2D/Assets/Pets/Fortune/`. Its generated 1280×720/120 fps HEVC-with-alpha files are grouped under `Clips/right-profile/`, while atlas-derived view anchors are under `Clips/image-views/`.

Use [`Docs/FORTUNE_GEMINI_LIVE_MOTION_PROMPTS.md`](../../../Docs/FORTUNE_GEMINI_LIVE_MOTION_PROMPTS.md) to regenerate the standardized source set, and `Scripts/build-fortune-live-motion-assets.sh` to rebuild runtime clips from those originals. The build applies fixed per-source color curves against common coat anchors, normalizes keyed alpha, and measures the alpha center/ground throughout each clip. A rolling low-frequency correction removes Gemini camera drift without canceling authored paw, tail, or breathing motion.
