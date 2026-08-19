---
name: furball-pet-creator
description: Create import-ready Furball Pet Pack v2 Realistic 2D image pets from 6–12 real pet photos or a Furball creation REQUEST.json. Generate one photorealistic sprite atlas with all required actions and 16 directions, validate identity, alpha, layout, clarity, and semantics, and return one .furballpet folder. Never generate illustrated styles, video, or standalone PNG animation fallbacks.
---

# Furball Pet Creator

Turn photos of a dog, cat, or other pet into an import-ready Pet Pack v2 folder named
pet-id.furballpet. Produce image animation only. Never call a video model.

## Non-negotiable scope

- Set capabilities.imageMode to true and capabilities.videoMode to false.
- Generate exactly one `realistic-2d` appearance. If an older request lists another style, migrate it to `realistic-2d` rather than producing a second atlas.
- Produce one lossless transparent WebP v2 atlas.
- Declare `spriteAtlas.stateModel: furball-image-state-v1`. Every 2D style and every pet uses the same posture-stage row and semantic frame bindings; profile-specific remapping of sleep is forbidden.
- Do not generate or declare imageAnimations, standalone PNG runtime frames, empty videos, or compatibility atlases.
- Preserve one animal identity across every cell: face, ears, eyes, markings, coat, proportions, tail, and accessories.
- Declare pet.bodySize as an integer from 1 through 100. Use 60 for a medium reference dog, smaller values for compact breeds and cats, and larger values only when the real animal should appear proportionally larger. This is independent of the user's 60%–140% display-scale setting.
- Finish only after the included validator and visual QA pass.

## Read first

Read all of references/PET_PACK_CONTRACT.md. If REQUEST.json is present, treat its name,
species and expected output as authoritative. The current contract always produces Realistic 2D even if a legacy request contains an older style field. Never edit or overwrite the
user's reference photos.

## Required inputs

Accept either:

1. A Furball creation-request folder containing REQUEST.json and ReferencePhotos/; or
2. A pet name, species (dog, cat, or other), and 6–12 clear photos covering
   front, both profiles, both three-quarter views, and a full body with tail.

Stop and request better photos when fewer than four useful viewpoints are present, multiple
animals appear, the face is occluded, or full-body proportions cannot be inferred. Never
hallucinate a close-enough identity.

## Production workflow

1. Inventory every reference. Reject blur, occlusion, heavy filters, thumbnails, aggressive
   denoise, and already-upscaled images as sole identity sources.
2. Create one photorealistic front/profile/full-body identity board. Ask for approval
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

## Realistic 2D requirements

- Produce a high-fidelity studio cutout with natural fur edges and anatomically plausible poses.
- Fix lens, camera height, exposure, white balance, scale, shadow policy, and ground baseline.
- Reject painterly reinterpretation, extra limbs, fused paws, changed patches, and lighting drift.

## Resolution and clarity gate

- Prefer source photos at least 1600 px on the long edge and one full-body anchor at least 2000 px.
- Generate complete rows natively so every extracted cell contains 384×416 useful source pixels.
  Never enlarge a 192×208 cell to fabricate a production atlas.
- Key, grade, register, and export from the highest-resolution approved source directly into the
  final runtime canvas or cell. Do not insert a smaller intermediate and enlarge it later; a
  960×540 cutout expanded to 1280×720 is a clarity failure even when the original was sharp.
- Fill at least 70% of cell height or 55% of cell width while preserving an 8 px transparent
  safety margin at 2×.
- Inspect eyes, nose, paws, markings, whiskers, and long fur at native scale. Reject halos,
  stair-stepping, waxy denoise, ringing, smearing, color fringe, and compression blocks.
- Inspect the exact first frame bound to `stand.idle` separately at native scale and in the
  real appearance-switch path. A sharp contact sheet does not excuse a soft entry cell. Rebuild
  the complete idle row from the native identity master when that entry frame is soft; never
  sharpen or replace only one atlas cell.
- Allow one deterministic registration resample. Regenerate any row requiring more than 1.25×
  enlargement.
- Sharpen only once, gently, at final resolution. Sharpening cannot rescue missing eye or fur
  detail and must not create ringing, crunchy whiskers, or bright alpha outlines.
- Require QA/clarity.json to declare native 384×416 cells, native row generation, lossless
  atlas output, native-scale review, maximumRegistrationUpscale no greater than 1.25, and no
  accepted rejected artifacts.

## Animation requirements

- Close locomotion loops on the same contact phase. Never reverse walking or running.
- Give every gait start at least four ordered authored poses and make its loop continue from the
  next contact phase. Publish all eight distinct gait poses in cyclic order. Walk/slow-run/fast-run
  may change timing, but they must share pose order so the runtime can preserve normalized gait
  phase while changing speed. Never restart at frame zero during a moving tier change, and never
  add a second whole-body bob or rotation on top of an already articulated gait row.
- Row 5 must visibly progress from standing through lowering into a genuinely horizontal lie, head-on-paws rest, half-closed eyes, and closed-eye sleep. A standing or sitting pet that merely lowers its head is a `gesture.drowsy`/sniff pose, never `sleep.idle`.
- Row 5 uses the fixed `furball-image-state-v1` stages: frame 0 standing, frame 1 lowering, frames 2–3 horizontal awake lie, frame 4 head-lowering/eye-close, and frames 5–7 horizontal closed-eye sleep ports. Do not put a wake/rise pose in frames 5–7.
- Use the exact shared bindings from `references/PET_PACK_CONTRACT.md`. Autonomous `sleep.idle` binds only canonical closed-eye frame `[5]`; the runtime supplies one continuous eight-second micro-breath. Never animate sleeping by cycling atlas poses—multiple image transitions read as repeated body pulses even when the nominal loop duration is long. Validate the actual bound cell, not only the row label.
- Keep start/loop/stop subject-height drift below 2%, center drift below 5 px, and ground drift
  below 2 px in cell coordinates.
- Author sparse poses as keyframes, then let Furball sample continuous temporal in-betweens at
  display refresh rate. For calm gestures use a 0.55–0.72 frame blend fraction; for jumping,
  locomotion, sneezing, and tail chasing use 0.08–0.32 so distinct silhouettes do not become
  double heads or paws. Never duplicate source cells to claim a higher frame rate.
- Match every adjacent pose by visible alpha height, horizontal center, and ground contact.
  Runtime registration may correct at most 12% while a blend resolves; regenerate any row that
  needs more. Gestures based on the jumping row must enter and exit through stable stand frame 4.
- Use the semantic duration ranges in `references/PET_PACK_CONTRACT.md`; a readable wave or bow
  must not be compressed into a sub-second slideshow merely because the atlas has few key poses.
- Prefer a complete anticipation → action → readable hold → recovery arc. When the source row
  is sparse, revisit compatible authored key poses in the binding instead of ending the action
  immediately after one pass. The app's overall animation-speed control is a user preference,
  not a substitute for meaningful source choreography or contract-compliant base timing.
- Run `Scripts/render-sprite-motion-qa.py` (or an equivalent renderer implementing the same
  smootherstep, premultiplied-alpha, and port-alignment rules), then inspect complete animated
  previews and 12-sample contact sheets. Never approve only the static atlas.
- Publish all registry menu actions with English titles, resulting posture, and autonomous flags.

## Output contract

    pet-id.furballpet/
    ├── manifest.json
    ├── Sprites/pet-id/realistic/spritesheet.webp
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
