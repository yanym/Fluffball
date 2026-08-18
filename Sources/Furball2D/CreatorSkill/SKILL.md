---
name: furball-pet-creator
description: Create import-ready Furball2D Pet Pack v2 image pets from 6-12 real pet photos or a Furball creation REQUEST.json. Generates cute 2D and/or photorealistic 2D sprite atlases, all required actions and 16 directions, validates identity/alpha/layout/semantics, and returns one .furballpet folder. Never generates video.
---

# Furball Pet Creator / Furball 宠物创建器

Use this Skill when a user asks to turn photos of a dog, cat, or other pet into a Furball2D desktop pet, or provides a `*-creation-request` folder exported by Furball2D. The only accepted final deliverable is an import-ready Pet Pack v2 folder named `<pet-id>.furballpet`.

当用户要求把狗、猫或其他宠物的照片制作成 Furball2D 桌宠，或者提供由 Furball2D 导出的 `*-creation-request` 文件夹时使用本 Skill。最终交付物必须是可以直接导入的 `<pet-id>.furballpet` 文件夹。

## Non-negotiable scope / 不可改变的范围

- Produce image animation only. Never call a video model and never set `capabilities.videoMode` to `true`.
- Requested styles are `cute-2d`, `realistic-2d`, or both. Each style gets an independent lossless transparent WebP v2 atlas.
- Preserve one animal identity across every cell: face, ears, eye color, markings, coat colors, body proportions, tail, and accessories.
- Do not call work complete until the pack passes the included validator and visual QA described below.
- 只制作图片动画，不生成视频；`capabilities.videoMode` 必须为 `false`。
- 风格只能是 `cute-2d`、`realistic-2d` 或两者都要。每种风格使用独立的透明无损 WebP v2 图集。
- 所有格子必须是同一只宠物，脸型、耳朵、眼睛、花纹、毛色、体型、尾巴和配饰不得漂移。

## Read first / 开始前必读

Read all of `references/PET_PACK_CONTRACT.md`. If a `REQUEST.json` is present, it is authoritative for name, species, requested styles, and expected output. Never edit or overwrite the user’s reference photos.

完整阅读 `references/PET_PACK_CONTRACT.md`。如果存在 `REQUEST.json`，其中的名称、物种、风格和输出路径是权威输入。不得修改或覆盖用户原始照片。

## Required inputs / 必需输入

Accept either:

1. A Furball creation-request folder containing `REQUEST.json` and `ReferencePhotos/`; or
2. Direct user input with:
   - pet name;
   - species: `dog`, `cat`, or `other`;
   - 6–12 clear photos covering front, left/right profiles, left/right three-quarter views, and full body with tail;
   - desired style: cute, realistic, or both.

If fewer than four useful viewpoints are present, more than one animal appears, the face is occluded, or the full-body proportions cannot be inferred, stop and request better photos. Do not hallucinate a “close enough” identity.

可以接收 Furball 创建请求文件夹，或直接接收宠物名称、种类、6–12 张多视角清晰照片和目标风格。若有效视角不足四个、画面里有多只动物、脸部被遮挡或无法判断全身比例，应暂停并要求补图，不能凭空猜测身份。

## Production workflow / 制作流程

1. Intake QA: inventory every reference, reject blur/occlusion/heavy filters, and identify the best front, both profiles, both three-quarter, and full-body sources.
2. Identity board: create one front/profile/full-body identity board for each requested style. Show it to the user for approval before generating action rows when interaction is possible. If running unattended from an approved request, record the selected identity anchors in `QA/identity.json`.
3. Generate the nine standard animation rows in this exact order: `idle`, `running-right`, `running-left`, `waving`, `jumping`, `failed`, `waiting`, `working`, `review`.
4. Generate four cardinal look directions first: 0° up/away, 90° screen-right, 180° down/toward viewer, 270° screen-left. Check identity and semantics before generating intermediates.
5. Generate both direction rows as a coherent 16-direction turn at 22.5° increments. Paws, lower torso, scale, and ground baseline remain fixed; eyes lead, then muzzle/head/neck, with subtle ear/ruff lag. Never rotate a whole sprite to fake a head turn.
6. Assemble the production atlas deterministically at `assetScale: 2`: 3072×4576, 8 columns × 11 rows, 384×416 per cell. The 1536×2288 / 192×208 form is legacy compatibility only and must not be the default for a new pet. Unused cells must be transparent black (`RGBA 0,0,0,0`).
7. Remove the solid key background, despill edges, and preserve true alpha. Do not leave RGB residue under fully transparent pixels.
8. Build `manifest.json` using the supplied template and action registry. A complete 16-direction map satisfies the nine legacy facing semantic slots; do not add placeholder PNGs.
9. Record the native-generation and sharpness audit in `QA/clarity.json`, then run `python3 scripts/validate_pet_pack.py <pack>` and correct every error. Review the contact sheet, per-row loops, and 16-direction sheet at 100% plus 60%/140% simulated display sizes.
10. Deliver only the validated `.furballpet` folder plus `QA/summary.md`. Intermediate prompts and identity boards remain in `QA/`, not in runtime sprite folders.

## Style requirements / 风格要求

### Cute 2D

- Friendly modern editorial illustration, rounded shapes, readable silhouette, restrained details, soft but deliberate palette.
- Preserve asymmetric markings; do not mirror the right gait unless the real animal is visually symmetric and the user explicitly accepts mirroring.
- Avoid generic emoji, chibi distortion that erases breed identity, heavy outlines, or inconsistent eye placement.

### Realistic 2D

- High-fidelity photorealistic studio cutout derived from the real animal, with natural fur edge detail and anatomically plausible poses.
- One fixed lens/camera height, exposure, white balance, scale, shadow policy, and ground baseline across every cell.
- No painterly reinterpretation, extra limbs, fused paws, changed coat patches, or lighting changes between rows.

## Resolution and clarity gate / 分辨率与清晰度门槛

- Prefer source photos whose long edge is at least 1600 px; at least one full-body identity anchor should be 2000 px or larger. Reject motion blur, social-media thumbnails, aggressive denoise, and already enlarged images as the only identity source.
- Generate and retain complete action rows at a native resolution that yields at least 384×416 useful pixels per extracted cell. Never enlarge a 192×208 runtime cell to fabricate the production atlas.
- The visible animal should use at least 70% of one cell's height or 55% of its width while keeping 8 px of transparent safety margin at 2×. Tiny subjects surrounded by empty pixels fail even when the canvas dimensions pass.
- Inspect eyes, nose, paw edges, facial markings, and long fur at 100% native pixels. Halos, stair-stepping, waxy denoise, ringing, smeared whiskers, color fringing, and compression blocks are rejection conditions.
- One resampling pass is allowed during deterministic registration. Any required enlargement above 1.25× means the generation source is too small and the affected whole row must be regenerated.
- `QA/clarity.json` must state `nativeCellWidth: 384`, `nativeCellHeight: 416`, `sourceRowsGeneratedNatively: true`, `losslessAtlas: true`, `reviewedAtNativeScale: true`, `maximumRegistrationUpscale <= 1.25`, and an empty `rejectedArtifacts` array. The validator rejects a missing or weaker declaration.
- 原始照片长边优先不低于 1600 px，至少一张完整身体身份图应达到 2000 px；模糊缩略图、强降噪图或二次放大图不能作为唯一身份依据。
- 每个动作整行必须以足够原生分辨率生成，使切格后至少拥有 384×416 的有效像素。禁止把旧 192×208 运行时格子放大冒充高清素材。
- 在 100% 像素下检查眼睛、鼻子、爪缘、花纹和长毛；光晕、锯齿、蜡感、锐化振铃、胡须糊掉、色边和压缩块都必须返工。

## Animation requirements / 动画要求

- Locomotion loops close on the same contact phase. Never use reverse playback for walking or running.
- `sleep.idle` is a closed-eye sleep frame with subtle procedural breathing. It must not alternate every second with an awake/open-eye pose.
- `lie.to.sleep` contains the deliberate eye-close transition; `sleep.to.stand` contains the full wake-up chain.
- Start/loop/stop geometry uses one ground anchor. Subject-height drift should remain under 2%, center drift under 5 px in atlas-cell coordinates, and ground drift under 2 px after assembly.
- Image frame blending remains short. Do not hide mismatched cells with long dissolves.
- Publish the registry’s sixteen menu actions. Subset-derived actions must still have believable timing and bilingual titles in the manifest rather than app code.

## Output contract / 输出合同

Return exactly:

```text
<pet-id>.furballpet/
├── manifest.json
├── Sprites/<pet-id>/cute/spritesheet.webp        # when requested
├── Sprites/<pet-id>/realistic/spritesheet.webp   # when requested
└── QA/
    ├── identity.json
    ├── clarity.json
    ├── contact-sheet.png
    ├── look-directions.png
    └── summary.md
```

The app imports the folder from **Furball menu → Pet Library → Import Pet Pack**. Do not zip it unless the user separately requests an archive. The `.furballpet` directory is the installable artifact.

用户在 **Furball 菜单 → 宠物素材库 → 导入宠物包** 中选择该文件夹。除非用户另行要求，不要压缩；`.furballpet` 文件夹本身就是安装文件。

## Adding future actions / 未来新增动作

`references/PET_PACK_CONTRACT.md` contains `ACTION_REGISTRY_VERSION`. When the Furball app adds a required action, update that registry, the manifest template, validator’s required semantic IDs, generation row/action instructions, and QA checklist together. Never silently omit a new required action or hardcode a pet-specific path in Swift.
