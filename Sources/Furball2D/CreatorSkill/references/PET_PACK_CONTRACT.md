# Furball Pet Pack v2 Contract

`ACTION_REGISTRY_VERSION: 2026-08-19.1`

`IMAGE_STATE_MODEL: furball-image-state-v1`

This file is authoritative for assets produced by `furball-pet-creator`.

## Runtime package

- Folder suffix: `.furballpet`
- `petPackVersion`: `2`
- `formatVersion`: `11` or newer
- `capabilities.imageMode`: `true`
- `capabilities.videoMode`: `false`
- Production sprite atlas: lossless WebP with alpha, exactly 3072×4576
- Layout: 8×11, 384×416 cells, `assetScale: 2`; creator output must never use the 192×208 legacy form
- Transparent pixels: RGBA must be 0,0,0,0
- Paths: relative, forward slashes, no `..`, no absolute paths, no symlinks
- Maximum import size: 2,000 files and 800 MB
- `pet.bodySize`: required integer 1–100; 60 is the medium reference size. It sets relative animal size before the independent 60%–140% display scale.
- `spriteAtlas.stateModel`: required exact value `furball-image-state-v1`. It applies only to sprite-atlas appearances; MP4 clips keep their independent video ports and state graph.

## Rows

| Row | ID | Frames | Purpose |
|---:|---|---:|---|
| 0 | idle | 6 | breathing, blink, subtle tail/ear motion |
| 1 | running-right | 8 | true right gait cycle |
| 2 | running-left | 8 | true left gait cycle |
| 3 | waving | 4 | friendly paw wave |
| 4 | jumping | 5 | anticipation, lift, apex, landing, settle |
| 5 | failed | 8 | fixed stages: 0 stand; 1 lower; 2–3 horizontal awake lie; 4 head/eyes lower; 5–7 horizontal closed-eye sleep ports |
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

Published optional menu actions in registry version 2026-08-19.1:

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
gesture.stretch
gesture.sneeze
gesture.paw-tap
gesture.happy-dance
gesture.yawn
gesture.drowsy
gesture.tail-chase
```

Every published action has a binding, an English `en` title, a resulting posture, and an autonomous Boolean.

## Gesture cadence and temporal in-betweens

The atlas contains authored key poses; Furball produces the visible intermediate samples at the
display refresh rate with premultiplied-alpha smootherstep blending. Calm gestures use a
`frameBlendFraction` of roughly 0.55–0.72. Jumping, locomotion, sneezing, and tail chasing use
roughly 0.08–0.32 because long overlaps between dissimilar silhouettes create ghost limbs.
The accepted field range is 0–0.82. Duplicating an atlas cell is not an intermediate frame.

| Binding | Accepted duration |
|---|---:|
| wave | 2.2–3.0 s |
| jump | 1.2–1.8 s |
| failed | 1.8–2.7 s |
| waiting / working / review | 2.4–3.6 s |
| play bow | 2.0–3.0 s |
| head tilt | 1.8–2.8 s |
| sniff | 2.4–3.6 s |
| high five | 1.8–2.8 s |
| stretch | 2.3–3.5 s |
| sneeze | 0.55–1.2 s |
| paw tap | 1.2–2.0 s |
| happy dance | 2.1–3.2 s |
| yawn | 3.0–4.8 s |
| drowsy | 2.8–4.2 s |
| tail chase | 2.0–3.2 s |

Adjacent cells are registered by visible alpha height, horizontal center, and ground contact.
The renderer may ease out a correction no larger than 12%; a larger mismatch is a source-row
failure. `gesture.jump`, `gesture.play-bow`, `gesture.stretch`, and `gesture.happy-dance` must
enter and exit through jumping-row stable stand frame 4.

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

Never loop awake and sleeping cells together. `sleep.idle` holds canonical closed-eye frame 5 and uses only restrained procedural `sleep` motion: one continuous eight-second sine wave with no atlas-frame switches. Frames 6–7 remain optional alternate closed-eye source poses but never enter autonomous sleep. A nominally slow multi-frame loop still creates one visible body pulse at every frame transition and is rejected.
A low head while the torso remains standing or sitting belongs to `gesture.drowsy` (or `gesture.sniff`) and must never be bound to `lie.idle` or `sleep.idle`.

All 2D profiles and appearances use these exact posture bindings:

```text
stand.idle      idle                         loop
stand.to.sit    waiting [0]
sit.idle        waiting                     loop
sit.to.lie      failed [1,2,3]
lie.idle        failed [2,3,2]              loop
lie.to.sleep    failed [2,3,4,5]
sleep.idle      failed [5]                  loop, motion=sleep
sleep.to.stand  failed [5,4,3,2,1,0]
```

The app importer and release validator reject a sprite atlas whose state-model identifier, row stages, bindings, or lie/sleep silhouette do not conform.

## Manifest notes

- Put common layout, animation, binding, direction, and action metadata in top-level `spriteAtlas`.
- Each appearance may reuse that metadata via `atlasFile`.
- Exactly one appearance has `isDefault: true`.
- The only creator output appearance ID is `realistic-2d`.
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
9. `QA/clarity.json` certifies native 384×416 generation, direct highest-resolution-source to final-cell processing with no downsample/upscale intermediate, lossless output, no registration enlargement above 1.25×, native-scale eye/fur/paw inspection, and no accepted blur, halo, ringing, stair-step, color-fringe, or compression defects.
10. Every gesture passes its semantic duration range and an animated preview/contact-sheet review; static atlas inspection alone is insufficient.
