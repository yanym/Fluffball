---
name: furball-live-motion-creator
description: Create, repair, normalize, validate, and package Furball Live Motion appearances from pet identity photos and AI-generated or user-recorded continuous MP4 action videos. Use when a Furball pet needs continuous-video clips, Gemini video prompts, chromakey removal, 120 fps interpolation, stable loops, action-port alignment, or a dual image/video Pet Pack. Do not use for image-only sprite-atlas creation; use the Furball Realistic 2D creator instead.
---

# Furball Live Motion Creator

Build a production-quality Furball `continuous-video` appearance from original source videos. Read [the complete contract](references/LIVE_MOTION_CONTRACT.md) before inspecting, renaming, processing, or replacing any asset. When video generation is still needed, also use the [one-video prompt template](references/VIDEO_PROMPT_TEMPLATE.md).

## Required order

1. Read the target repository's `AGENTS.md` and Pet Pack standard.
2. Inventory identity photos and every original video. Never infer content from filenames.
3. Preserve originals under `Assets/Pets/<PetName>/UserProvided/SourceVideos/<native-facing>/` using lowercase kebab-case names.
4. Make a contact sheet, watch every source, measure its timeline, and record a segmentation table.
5. Reject identity changes, duplicate animals, direction changes, deformed frames, watermarks, and incompatible action ports. A crossfade is not a repair.
6. Interpolate the original 24 fps footage bidirectionally before keying; duplicated frames are not 120 fps motion.
7. Key and color-normalize against explicit black/tan/white coat anchors. Use one fixed monotonic grade per source batch and verify that opaque-fur alpha is consistent across every action.
8. Measure alpha center and ground on sampled frames throughout every clip, not only at its endpoints. Remove low-frequency camera/generation drift with smoothed translation on an oversized transparent canvas while preserving authored paw, tail, and breathing motion. Construct valid loops, then encode 1280×720 120 fps HEVC with Alpha.
9. Register all semantic clips and the source's native horizontal facing in `manifest.json`. Never hardcode a pet path in Swift.
10. Run manifest validation, Live Motion QA, behavior QA, safety audit, build, and package checks.
11. Deliver QA evidence and disclose any source limitation or substituted segment.

If AI video must be generated, issue one prompt per source video. Lock identity, posture ports, camera, subject size, ground baseline, screen direction, lighting, key background, and the absence of props/text/extra animals. Use two to four compatible reference photos and never mix opposite profile views unless the requested action turns.
