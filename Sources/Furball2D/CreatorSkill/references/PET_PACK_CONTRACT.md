# Furball Pet Pack v2 Contract / Furball 宠物包 v2 合同

`ACTION_REGISTRY_VERSION: 2026-08-17.2`

This file is authoritative for assets produced by `furball-pet-creator`. 本文件是创建 Skill 的权威输出合同。

## Runtime package

- Folder suffix: `.furballpet`
- `petPackVersion`: `2`
- `formatVersion`: `10` or newer
- `capabilities.imageMode`: `true`
- `capabilities.videoMode`: `false`
- Sprite atlas: lossless WebP with alpha, exactly 1536×2288
- Layout: 8×11, 192×208 cells
- Transparent pixels: RGBA must be 0,0,0,0
- Paths: relative, forward slashes, no `..`, no absolute paths, no symlinks
- Maximum import size: 2,000 files and 800 MB

## Rows

| Row | ID | Frames | Purpose |
|---:|---|---:|---|
| 0 | idle | 6 | breathing, blink, subtle tail/ear motion |
| 1 | running-right | 8 | true right gait cycle |
| 2 | running-left | 8 | true left gait cycle |
| 3 | waving | 4 | friendly paw wave |
| 4 | jumping | 5 | anticipation, lift, apex, landing, settle |
| 5 | failed | 8 | stand → lower/lie → closed-eye sleep → wake/stand chain |
| 6 | waiting | 6 | calm sit/anticipation |
| 7 | working | 6 | focused search/work motion |
| 8 | review | 6 | curious inspect/look motion |
| 9 | look-directions-a | 8 | 0°, 22.5° … 157.5° |
| 10 | look-directions-b | 8 | 180°, 202.5° … 337.5° |

## Required semantic IDs (27)

Posture/locomotion and look demonstration:

```text
stand.idle
stand.look.images
stand.to.sit
sit.idle
sit.to.lie
lie.idle
lie.to.sleep
sleep.idle
sleep.to.stand
walk.start
walk.loop
walk.stop
slow-run.start
slow-run.loop
slow-run.stop
fast-run.start
fast-run.loop
fast-run.stop
```

The complete 16-direction `lookDirections` map fulfills these nine legacy view slots:

```text
stand.facing.left-profile
stand.facing.front-near-profile-left
stand.facing.front-three-quarter-left
stand.facing.front-near-center-left
stand.facing.front
stand.facing.front-near-center-right
stand.facing.front-three-quarter-right
stand.facing.front-near-profile-right
stand.facing.right-profile
```

Published optional menu actions in registry version 2026-08-17.2:

```text
gesture.wave
gesture.jump
gesture.failed
gesture.waiting
gesture.working
gesture.review
gesture.play-bow
gesture.head-tilt
gesture.sniff
gesture.high-five
```

Every published action has a binding, bilingual `zh-Hans`/`en` title, resulting posture, and autonomous Boolean.

## Direction semantics

- 0°: away/up
- 90°: screen-right profile
- 180°: toward viewer/down
- 270°: screen-left profile
- Increment: clockwise 22.5°
- 337.5° and 0° must join continuously without size jump.

## Sleep flow

```text
lie.idle (awake, calm)
→ lie.to.sleep (deliberate eyelid close)
→ sleep.idle (closed eyes only, procedural breathing)
→ sleep.to.stand (eyes open, rise, settle)
```

Never loop awake and sleeping cells together. `sleep.idle` may use one closed-eye frame; subtle motion comes from manifest motion `sleep`.

## Manifest notes

- Put common layout, animation, binding, direction, and action metadata in top-level `spriteAtlas`.
- Each appearance may reuse that metadata via `atlasFile`.
- Exactly one appearance has `isDefault: true`.
- Appearance IDs: `cute-2d`, `realistic-2d`.
- Appearance kind: `sprite-atlas`.
- `systemImage` uses an SF Symbol name but is presentation-only.

## Acceptance gates

1. Identity board matches references and is user-approved when possible.
2. All rows contain the same animal and style.
3. Alpha background is fully transparent; no chroma fringe on white, black, and middle-gray.
4. All loops close at the correct phase.
5. 16 directions are semantically correct and adjacent directions are continuous.
6. Sleep never oscillates between open and closed eyes.
7. Pack passes the included validator without warnings.
8. Contact sheets are reviewed at simulated 60%, 100%, and 140% app size.
