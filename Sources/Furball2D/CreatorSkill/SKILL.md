---
name: furball-pet-creator
description: Create import-ready Furball2D Pet Pack v2 image pets from 6–12 real pet photos or a Furball creation REQUEST.json. Generate cute 2D and/or photorealistic 2D sprite atlases, all required actions and 16 directions, validate identity, alpha, layout, clarity, and semantics, and return one .furballpet folder. Never generate video or standalone PNG animation fallbacks.
---

# Furball Pet Creator

Turn photos of a dog, cat, or other pet into an import-ready Pet Pack v2 folder named
pet-id.furballpet. Produce image animation only. Never call a video model.

## Non-negotiable scope

- Set capabilities.imageMode to true and capabilities.videoMode to false.
- Generate cute-2d, realistic-2d, or both, as requested.
- Give every style its own lossless transparent WebP v2 atlas.
- Do not generate or declare imageAnimations, standalone PNG runtime frames, empty videos, or compatibility atlases.
- Preserve one animal identity across every cell: face, ears, eyes, markings, coat, proportions, tail, and accessories.
- Finish only after the included validator and visual QA pass.

## Read first

Read all of references/PET_PACK_CONTRACT.md. If REQUEST.json is present, treat its name,
species, requested styles, and expected output as authoritative. Never edit or overwrite the
user's reference photos.

## Required inputs

Accept either:

1. A Furball creation-request folder containing REQUEST.json and ReferencePhotos/; or
2. A pet name, species (dog, cat, or other), desired style, and 6–12 clear photos covering
   front, both profiles, both three-quarter views, and a full body with tail.

Stop and request better photos when fewer than four useful viewpoints are present, multiple
animals appear, the face is occluded, or full-body proportions cannot be inferred. Never
hallucinate a close-enough identity.

## Production workflow

1. Inventory every reference. Reject blur, occlusion, heavy filters, thumbnails, aggressive
   denoise, and already-upscaled images as sole identity sources.
2. Create a front/profile/full-body identity board for each requested style. Ask for approval
   before generating action rows when interaction is possible. For unattended approved
   requests, record anchors in QA/identity.json.
3. Generate the nine standard rows in this exact order: idle, running-right, running-left,
   waving, jumping, failed, waiting, working, and review.
4. Generate and approve four cardinal look directions first: 0° away/up, 90° screen-right,
   180° toward viewer/down, and 270° screen-left.
5. Generate both direction rows as one coherent 16-direction turn in 22.5° increments. Keep
   paws, lower torso, scale, and ground baseline fixed. Let eyes lead, followed by muzzle,
   head, neck, ears, and ruff. Never rotate a complete sprite to fake a head turn.
6. Assemble each production atlas deterministically at 3072×4576: 8 columns × 11 rows,
   384×416 cells, assetScale 2. Fill unused cells with transparent black RGBA 0,0,0,0.
7. Remove the solid key background, despill edges, preserve true alpha, and remove RGB residue
   under fully transparent pixels.
8. Build manifest.json from the supplied template and action registry. Use English-only
   title.en and subtitle.en fields. A complete 16-direction map satisfies the nine facing
   semantic slots.
9. Record native-generation and sharpness evidence in QA/clarity.json. Run
   python3 scripts/validate_pet_pack.py PACK_PATH and correct every error.
10. Review the contact sheet, every loop, and the 16-direction sheet at 100% plus simulated
    60% and 140% display sizes.
11. Deliver only the validated .furballpet folder plus QA/summary.md. Keep intermediate
    prompts and identity boards in QA/, never in runtime sprite directories.

## Style requirements

### Cute 2D

- Use friendly modern editorial illustration, rounded shapes, a readable silhouette,
  restrained detail, and a deliberate soft palette.
- Preserve asymmetric markings. Generate true left and right gaits unless the animal is
  visually symmetric and the user explicitly accepts mirroring.
- Avoid generic emoji, identity-erasing chibi distortion, heavy outlines, and inconsistent eyes.

### Realistic 2D

- Produce a high-fidelity studio cutout with natural fur edges and anatomically plausible poses.
- Fix lens, camera height, exposure, white balance, scale, shadow policy, and ground baseline.
- Reject painterly reinterpretation, extra limbs, fused paws, changed patches, and lighting drift.

## Resolution and clarity gate

- Prefer source photos at least 1600 px on the long edge and one full-body anchor at least 2000 px.
- Generate complete rows natively so every extracted cell contains 384×416 useful source pixels.
  Never enlarge a 192×208 cell to fabricate a production atlas.
- Fill at least 70% of cell height or 55% of cell width while preserving an 8 px transparent
  safety margin at 2×.
- Inspect eyes, nose, paws, markings, whiskers, and long fur at native scale. Reject halos,
  stair-stepping, waxy denoise, ringing, smearing, color fringe, and compression blocks.
- Allow one deterministic registration resample. Regenerate any row requiring more than 1.25×
  enlargement.
- Require QA/clarity.json to declare native 384×416 cells, native row generation, lossless
  atlas output, native-scale review, maximumRegistrationUpscale no greater than 1.25, and no
  accepted rejected artifacts.

## Animation requirements

- Close locomotion loops on the same contact phase. Never reverse walking or running.
- Keep sleep.idle closed-eyed with subtle procedural breathing. Put eye closure in
  lie.to.sleep and the complete wake-up chain in sleep.to.stand.
- Keep start/loop/stop subject-height drift below 2%, center drift below 5 px, and ground drift
  below 2 px in cell coordinates.
- Use short image blending. Never hide mismatched cells with long dissolves.
- Publish all registry menu actions with English titles, resulting posture, and autonomous flags.

## Output contract

    pet-id.furballpet/
    ├── manifest.json
    ├── Sprites/pet-id/cute/spritesheet.webp        # when requested
    ├── Sprites/pet-id/realistic/spritesheet.webp   # when requested
    └── QA/
        ├── identity.json
        ├── clarity.json
        ├── contact-sheet.png
        ├── look-directions.png
        └── summary.md

Import the folder from Furball menu → Pet Library → Import Pet Pack. Do not zip it unless the
user separately requests an archive.

## Future actions

references/PET_PACK_CONTRACT.md contains ACTION_REGISTRY_VERSION. When the app adds a required
action, update that registry, the manifest template, validator semantic IDs, generation
instructions, and QA checklist together. Never omit a required action or hardcode a pet path in
Swift.
