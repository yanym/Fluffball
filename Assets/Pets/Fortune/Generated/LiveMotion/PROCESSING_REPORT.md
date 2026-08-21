# Fortune Live Motion processing report

Build date: 2026-08-20  
Rebuild command: `./Scripts/build-fortune-live-motion-assets.sh`

## Source audit

Nine original Gemini videos are archived without recompression under `Assets/Pets/Fortune/UserProvided/SourceVideos/right-profile/`. Every source is 1280×720, constant 24 fps, approximately 8–10 seconds, with a magenta key background and an unused audio track. The retained action direction is screen-right, declared by `videoNativeFacing: "right"` in the runtime manifest.

Identity and motion are usable across the set. Two defects were handled explicitly:

- `stand-to-sit.mp4` contains a small duplicate Fortune in the upper-left during the latter portion. The build masks that source strip in place before motion interpolation; cropping it had incorrectly shifted the real dog about 260 px to the left. The repair never clones or synthesizes dog pixels.
- `stand-to-fast-run-to-stand.mp4` turns direction at its entrance and develops turn/ghost frames near its exit. Only its clean, fixed-right-profile middle gait is retained. The compatible Fortune slow-run source supplies physical fast-run start and stop ports. These substitutions are also recorded in `manifest.json`.

## Segmentation and normalization

| Runtime action | Source | Start | Duration | Port / loop strategy | Scale path |
|---|---|---:|---:|---|---|
| `stand.idle` | `stand-idle.mp4` | 0.400 | 8.800 | low-motion endpoint-deduplicated ping-pong, stand → stand | 1.000 → 1.001 |
| `stand.to.sit` | `stand-to-sit.mp4` | 0.200 | 3.200 | stand → sit; upper-left duplicate removed before interpolation | 1.030 → 1.010 |
| `sit.idle` | `sit-to-lie.mp4` | 0.200 | 1.600 | low-motion endpoint-deduplicated ping-pong, sit → sit | 1.000 → 1.001 |
| `sit.to.lie` | `sit-to-lie.mp4` | 1.600 | 3.200 | sit → horizontal awake lie | 1.000 → 1.080 |
| `lie.idle` | `lie-to-sleep.mp4` | 0.200 | 2.000 | low-motion endpoint-deduplicated ping-pong, lie → lie | 1.020 → 1.021 |
| `lie.to.sleep` | `lie-to-sleep.mp4` | 2.000 | 4.000 | awake lie → closed-eye sleep | 1.020 → 1.021 |
| `sleep.idle` | `sleep-idle.mp4` | 0.500 | 6.700 | quiet breathing-only endpoint-deduplicated ping-pong | 0.972 → 0.973 |
| `sleep.to.stand` | `sleep-to-stand.mp4` | 0.200 | 6.500 | horizontal sleep → stand | 1.046 → 1.022 |
| `walk.start` | `stand-to-walk-to-stand.mp4` | 0.200 | 2.550 | stand → first stable gait contact | 0.980 → 0.981 |
| `walk.loop` | same | 2.750 | 1.083 | true forward gait, matching contact phase | 0.980 → 0.981 |
| `walk.stop` | same | 5.833 | 1.667 | final gait contact → stand | 0.980 → 0.981 |
| `slow-run.start` | `stand-to-slow-run-to-stand.mp4` | 0.200 | 3.383 | stand → jog contact | 1.055 → 1.056 |
| `slow-run.loop` | same | 3.583 | 0.667 | true forward gait, matching contact phase | 1.055 → 1.056 |
| `slow-run.stop` | same | 5.542 | 1.958 | jog contact → stand | 1.055 → 1.056 |
| `fast-run.start` | slow-run source | 0.200 | 1.800 | compatible stand → accelerated contact | 1.055 → 1.056 |
| `fast-run.loop` | fast-run source | 2.792 | 0.542 | clean true forward fast gait only | 1.020 → 1.021 |
| `fast-run.stop` | slow-run source | 5.542 | 1.958 | compatible contact → stand | 1.055 → 1.056 |

All keyed segments are normalized on a 1600×900 transparent work canvas to runtime center x=640 and ground y=682. The small 0.1% scale change on otherwise fixed-scale segments is a timing carrier for smoothstep center/ground correction after FFmpeg rounds scaled dimensions to integer pixels; it is below visible scale variation. A lossless ProRes 4444 intermediate is then measured at 30 samples per second. Median-filtered center motion and a rolling ground envelope drive a second oversized-canvas translation pass. This removes low-frequency generation/camera drift throughout an action rather than aligning only its endpoints; loop corrections use circular smoothing.

## Key, color, and output

Each generation batch uses its independently sampled magenta key color; no key color is copied from another source. Keying occurs after bidirectional motion-compensated 24→120 fps interpolation. A magenta-only hue/saturation pass removes reflected screen spill without changing alpha or globally desaturating tan, black, and white fur. All batches receive the same fixed monotonic display curve and saturation correction. Warm-fur locomotion and lying sources use a narrower 0.045 key similarity so pink ears, white legs, and tan underfur are not removed with the magenta screen. Fixed per-source alpha restoration brings representative opaque-fur means to approximately 253–254/255 without runtime grading or opacity compensation.

Every runtime output is 1280×720 at 120 fps, HEVC VideoToolbox with Alpha, `hvc1`, no audio, alpha quality 0.98, and visual quality 82. View-anchor movies are generated from Fortune's current v2 atlas and are not standalone legacy PNG animations.

## QA

- `Scripts/validate-pet-pack.swift` validates all 27 video semantic slots, alpha decoding, dimensions/frame rate, loop flags, v2 atlas structure, and shared image state model.
- Representative frames are composited over middle gray to inspect identity, green/magenta fringe, scale, ground placement, and duplicate subjects.
- Before stabilization, measured center drift reached about 45.5 px in `stand.to.sit`, 81.7 px in `sleep.to.stand`, and 70.4 px in `slow-run.start`; `sleep.to.stand` ground drift reached 51 px. Final decoded low-motion center ranges are roughly 2–10 px, while larger gait ground ranges reflect authored paw lift rather than canvas drift.
- `Scripts/live-motion-qa.sh` runs with `FURBALL_PET_ID=fortune` to require real fast-run entry and sustained decoded-frame motion.
- `Scripts/behavior-qa.sh` exercises the menu-driven treat flow with Fortune active.
- `Scripts/audit-runtime-safety.sh` remains mandatory before packaging.
