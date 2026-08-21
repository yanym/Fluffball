# Furball Asset Catalog

Assets are grouped by pet identity first. Every pet owns the same two provenance categories:

```text
Assets/Pets/<PetName>/
├── UserProvided/   # Immutable photos and videos supplied by the user
└── Generated/      # Generated art, intermediate files, records, and QA
```

The app never reads `UserProvided/` at runtime. Final compiled resources live in the matching runtime Pet Pack under `Sources/Furball2D/Assets/Pets/<PetName>/`.

- `Pets/Nina/` contains Nina's original photos/videos, the retained Realistic 2D generation work and atlas, and the complete Live Motion clip set.
- `Pets/Fortune/` contains Fortune's six identity photos, nine archived right-profile Gemini source videos, the native-Retina Realistic 2D generation run, and its Live Motion rebuild documentation.

Nina's identity references live in `Pets/Nina/UserProvided/SourceImagesForAIVideo/originals/`; see the [reference guide](Pets/Nina/UserProvided/SourceImagesForAIVideo/README.md). Prepared references live separately under `Pets/Nina/Generated/AIReferenceImages/generation-ready/`.

`Pets/Nina/Generated/ImageTurn/normalized/` contains Nina's aligned image views. `Pets/Nina/Generated/SpritePets/NinaRealistic/` preserves the retained Realistic 2D generation record and QA. `Pets/Fortune/Generated/SpritePet/` contains Fortune's grounded `$hatch-pet` run, native-HD pose grids, clarity report, and contact atlas.

Sprite-atlas image representation and video representation are parallel. `capabilities.imageMode` and `capabilities.videoMode` declare what each named pack supports; an image-only pack may omit `Clips/` completely. Nina and Fortune now both supply Live Motion and Realistic 2D. Standalone runtime PNG animations are no longer loaded or packaged.

## Original video mapping

| Legacy name | Current path | View and content | Status |
|---|---|---|---|
| `v2/1 2.MP4` | `Pets/Nina/UserProvided/SourceVideos/left-profile/sleep-to-stand.mp4` | Left profile, lying down to standing | Main action chain |
| `v2/1.mp4` | `Pets/Nina/UserProvided/SourceVideos/left-profile/stand-look-around-reference.mp4` | Left-profile stand with a brief look toward the camera | Alternate reference; appearance differs slightly from the main chain |
| `v2/2 2.MP4` | `Pets/Nina/UserProvided/SourceVideos/left-profile/stand-to-sit.mp4` | Left profile, standing to sitting | Main action chain |
| `v2/2.mp4` | `Pets/Nina/UserProvided/SourceVideos/three-quarter-to-front/stand-to-sit.mp4` | Left-front three-quarter view turning toward the camera and sitting | Alternate view; not used by the current main chain |
| `v2/3.MP4` | `Pets/Nina/UserProvided/SourceVideos/left-profile/stand-idle.mp4` | Left-profile standing idle | Main action chain |
| `v2/4.MP4` | `Pets/Nina/UserProvided/SourceVideos/left-profile/sit-to-lie.mp4` | Left profile, sitting to lying; the beginning also supplies the sit idle | Main action chain |
| `v2/5.MP4` | `Pets/Nina/UserProvided/SourceVideos/left-profile/lie-to-sleep.mp4` | Left profile, lying to sleeping; the beginning also supplies the lie idle | Main action chain |
| `v2/6.MP4` | `Pets/Nina/UserProvided/SourceVideos/left-profile/sleep-idle.mp4` | Left-profile sleep with a small head lift | Main action chain; only a low-motion window is used |
| `v2/Generated Video August 13, 2026 - 1_28AM.mp4` | `Pets/Nina/UserProvided/SourceVideos/archive/exact-duplicates/three-quarter-to-front-stand-to-sit.duplicate.mp4` | Byte-identical to the original `v2/2.mp4` | Archived only; excluded from builds |
| User-provided walk video | `Pets/Nina/UserProvided/SourceVideos/left-profile/stand-to-walk-to-stand.mp4` | Left profile, stand to walk to stand | Locomotion chain, split into start/loop/stop |
| User-provided jog video | `Pets/Nina/UserProvided/SourceVideos/left-profile/stand-to-slow-run-to-stand.mp4` | Left profile, stand to jog to stand | Locomotion chain, split into start/loop/stop |
| User-provided run video | `Pets/Nina/UserProvided/SourceVideos/left-profile/stand-to-fast-run-to-stand.mp4` | Left profile, stand to run to stand | Locomotion chain, split into start/loop/stop |

The archived duplicate and `Pets/Nina/UserProvided/SourceVideos/three-quarter-to-front/stand-to-sit.mp4` both have this SHA-256 digest:

```text
906fb512fccd3f10b91053877d4263a9b545cd6bdb790af329f90dff4eb34535
```

## Exported videos

`Sources/Furball2D/Assets/Pets/Nina/Clips/left-profile/` contains the 18 HEVC-with-alpha clips played by the app:

| File | Type | Source |
|---|---|---|
| `stand-idle.mov` | Seamless idle loop | `stand-idle.mp4` |
| `look-around-images.mov` | Image-only multi-angle turn | Nine PNGs under `Assets/Pets/Nina/Generated/ImageTurn/normalized/` |
| `stand-to-sit.mov` | One-shot transition | `stand-to-sit.mp4` |
| `sit-idle.mov` | Seamless idle loop | Stable beginning of `sit-to-lie.mp4` |
| `sit-to-lie.mov` | One-shot transition with sit/lie port correction | `sit-to-lie.mp4` |
| `lie-idle.mov` | Seamless idle loop | Stable beginning of `lie-to-sleep.mp4` |
| `lie-to-sleep.mov` | One-shot transition with lie/sleep port correction | `lie-to-sleep.mp4` |
| `sleep-idle.mov` | Low-motion breathing loop | A stable 0.55-second window from `sleep-idle.mp4` |
| `sleep-to-stand.mov` | One-shot transition with scale correction | `sleep-to-stand.mp4` |
| `walk-start/loop/stop.mov` | Walk start, phase-closed loop, and stop | `stand-to-walk-to-stand.mp4` |
| `slow-run-start/loop/stop.mov` | Jog start, phase-closed loop, and stop | `stand-to-slow-run-to-stand.mp4` |
| `fast-run-start/loop/stop.mov` | Run start, phase-closed loop, and stop | `stand-to-fast-run-to-stand.mp4` |

`Sources/Furball2D/Assets/Pets/Nina/Clips/image-views/` additionally contains nine angles from `left-profile.mov` through `right-profile.mov`; the `front-near-profile-*` and `front-near-center-*` files are the added intermediate views. Each is a 1280×720, 120 fps loop exported from its matching transparent PNG. At runtime the app changes only to an adjacent view and reaches the left- or right-profile port matching the next video action. Right-facing idle, transition, sleep, and gait footage is produced by mirroring the left-profile clips at runtime.

The start clips now begin near their first visible weight shift. On a fresh transition from standing to walking, jogging, or running, runtime translation waits only about 0.12, 0.07, or 0.10 seconds and ramps in over roughly 0.18, 0.13, or 0.10 seconds. This preserves planted-paw contact without making cursor response feel delayed.

`Scripts/build-assets.sh` can rebuild every export. Each locomotion source is keyed using its sampled green-screen color. The first and last frames of every start / loop / stop segment are independently normalized for subject height, alpha center, and ground baseline. Loop segments use matching footfall phases and are never reversed. Corrections are applied smoothly on a 1600×900 transparent work canvas before cropping back to the standard canvas; the pipeline does not apply one fixed scale to an entire source. Every locomotion source also shares one monotonic grading curve across start / loop / stop, matching the black, tan, and white fur anchors from `stand-idle`; all nine image views independently target the same reference during export. Use `Scripts/audit-png-color.swift` to re-audit representative transparent PNG frames. Cut points, port parameters, color references, loop strategies, and canvas metadata are recorded in the script and `Sources/Furball2D/Assets/Pets/Nina/manifest.json`.

## Shared 2D posture state model

Every runtime sprite atlas uses `stateModel: furball-image-state-v1`. Row 5 has the same physical meaning for Nina Realistic, Fortune Realistic, and future imported pets: frame 0 stand, frame 1 lower, frames 2–3 horizontal awake lie, frame 4 head/eye close, and frames 5–7 horizontal closed-eye source poses. `sleep.idle` binds only frame 5; the runtime adds a continuous eight-second micro-breath rather than cycling the source poses. The old Nina Realistic low-head row remains preserved as `generated-hd/drowsy-original-grid-1x8.png`; it is not a sleep source.

The runtime and validators use one exact posture binding map for all 2D appearances and reject non-horizontal lie/sleep silhouettes. MP4 actions remain independently segmented and bound under `Clips/`; do not copy the image frame indices into video manifests.

## Naming new assets

```text
Assets/Pets/Nina/UserProvided/SourceVideos/<view>/<action>.mp4
Assets/Pets/Nina/Generated/AIReferenceImages/generation-ready/<pose>/<view>.png
Assets/Pets/Nina/Generated/SpritePets/<pet>/qa/<artifact>.png
Sources/Furball2D/Assets/Pets/Nina/Sprites/<pet>/spritesheet.webp
Sources/Furball2D/Assets/Pets/Nina/Clips/<view>/<action>.mov
```

Recommended view names include `left-profile`, `right-profile`, `front`, `rear`, `three-quarter-left`, and `three-quarter-right`. If the view changes during an action, use a directional name such as `three-quarter-to-front`.
