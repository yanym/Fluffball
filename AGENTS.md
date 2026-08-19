# Furball Agent Guide: Processing Continuous Pet Action Video

This file is mandatory guidance for any Agent working on Furball. When a user provides one or more continuous pet-action videos, analyze, segment, normalize, and validate them with this workflow before replacing app assets. The goal is not merely successful playback. The desktop pet must remain natural, stable, and sharp across loops, action changes, and display sizes.

## 1. Core principles

1. Match action ports before considering a crossfade. A crossfade can soften two already similar frames; it cannot fix different subject sizes, foot positions, directions, or postures.
2. Never infer action semantics from filenames. Watch the full video, build a timeline, and verify every stable interval and movement direction.
3. Always rebuild from the user-provided original video. Never enlarge an older keyed or compressed `.mov`.
4. Every video action must use the same canvas, frame rate, subject scale, and ground anchor. The runtime standard is 1280×720 at 120 fps HEVC with Alpha. Bidirectionally motion-interpolate 24 fps sources before keying; duplicated frames do not qualify as high frame rate.
5. An “idle video” is not automatically loopable. If the first and last poses differ, a direct loop will jump every few seconds.
6. Fix quality problems in offline assets first. Do not hide bad cut points with a long runtime crossfade; realistic pets develop double heads, paws, and fur trails.
7. The shipping app must remain read-only toward user files, folders, and Finder layout. Desktop interaction may read names and system icons and must use app-owned visual proxies. Never add AppleScript, Finder icon movement, or runtime create/copy/move/rename/trash/delete paths. `Scripts/audit-runtime-safety.sh` is mandatory before packaging.

## 1.1 Identity references for new AI videos

If the task includes generating a new AI pet-action video, first read `Assets/Pets/Nina/UserProvided/SourceImagesForAIVideo/README.md`. Prefer references under `Assets/Pets/Nina/Generated/AIReferenceImages/generation-ready/<pose>/<view>.png` that match the target posture and view, and use the front view to lock face shape and markings. `Assets/Pets/Nina/UserProvided/SourceImagesForAIVideo/originals/` exists only for identity verification and provenance and must not be overwritten by generated results.

A typical action uses two to four references. Do not mix opposite profile views unless the shot explicitly turns around. The output must preserve the same dog, fixed view, stable subject size, and stable ground baseline. Face replacement, coat changes, tail-length changes, or flipped left/right markings are generation failures.

## 1.2 Building actions from images only

When the user explicitly rejects AI-generated video, use a Codex-compatible Pet Pack v2 sprite-atlas image mode. If `$hatch-pet` is available, follow that Skill for generation, registration, and QA; otherwise follow `Docs/PET_PACK_STANDARD.md` exactly. Standalone runtime PNG animations are no longer supported.

1. Lock one canonical identity, art style, body proportion, ground baseline, and solid key background. No row may change face, ears, markings, tail, materials, or camera.
2. A new atlas uses `spriteVersionNumber: 2` and `assetScale: 2`: 3072×4576, 8 columns × 11 rows, and 384×416 cells. The old 1536×2288 form is rejected; never upscale old cells as an HD source.
3. Generate left and right gait rows independently. Mirror only for a truly symmetric pet and explicit user approval. Gait loops must close on contact phase and must never use reverse playback. Each gait start contains at least four ordered authored poses; the loop continues at the next contact pose and publishes all eight distinct poses in cyclic order. Keep that order identical across walk/jog/run timing tiers so runtime tier changes preserve phase instead of snapping the legs back to frame zero. Do not add a second procedural whole-body bob to an already articulated gait row.
4. Rows 9–10 contain all 16 directions: 0° up, 90° screen-right, 180° down, and 270° screen-left at 22.5° steps. Approve the four cardinals before synthesizing both coherent direction rows.
5. Keep paws, lower torso, and baseline stable during look motion. Eyes lead, muzzle/head/neck follow, and ears, cheek fur, and ruff lag subtly. Never rotate the whole sprite to fake a head turn.
6. `spriteAtlas.animations` declares per-frame timing, loop, motion, and short blend fraction. `bindings` maps the 27 standard semantic IDs and may use `frameIndices`, `rightAnimation`, and `frameDurationScale`. Never hardcode a pet-specific path in Swift.
   Treat atlas cells as authored key poses, not as a finished low-frame-rate movie. Calm gestures normally use 0.55–0.72 temporal blending and semantic durations from the Creator contract; jumping, locomotion, sneezing, and tail chasing normally use 0.08–0.32. Validate animated previews, not only the atlas. Match adjacent alpha height, center, and ground ports; if runtime registration would exceed 12%, regenerate the row instead of hiding it with a longer dissolve.
7. `actions` may publish any number of localized cute actions. The current creator-Skill action registry is `2026-08-19.1`, including `gesture.drowsy` for the standing/sitting low-head pose. Titles, autonomous eligibility, and resulting posture belong to the pack; the image-mode menu reads them automatically and video mode disables them. Actions require anticipation, a readable hold, and recovery; a single fast pass through sparse key poses is not acceptable. Adding or retiming an action also requires updating the contract, Skill, and validator under `Sources/Furball2D/CreatorSkill/`.
8. Cursor gaze advances one adjacent direction at a time, using roughly 0.15 seconds of initial stability and a 0.085–0.12-second adjacent cooldown. Before locomotion, take the shortest route to the matching 90° or 270° profile. Do not change look cells during movement.
9. Direction cells take over only after recent pointer movement. After roughly 2.4 seconds of pointer stillness, return to the full idle row so one static gaze cannot permanently hide breathing and blinking. Briefly return through the idle port before a front-facing posture action such as sitting.
10. Cursor following and free roam retain one two-dimensional target, gait hysteresis, and horizontal/vertical bounds. A sprite gait with real start frames does not need a video first-paw delay, but retains the roughly 0.07-second image-mode acceleration ramp.
11. Declare `capabilities.imageMode=true`. An image-only pack sets `videoMode=false` and omits `clips`, automatically forcing and disabling the top-level video toggle. The sprite-atlas bindings must cover all 27 standard semantic slots.
12. Declare `pet.bodySize` from 1 through 100. A medium dog uses 60; this relative physical size is applied before the independent 60%–140% display scale. A sleeping row must become genuinely horizontal before it closes the eyes. A standing low-head pose is `gesture.drowsy` or sniffing, never `sleep.idle`. Autonomous `sleep.idle` holds only canonical closed-eye frame `[5]`; one continuous eight-second sub-pixel procedural sine provides breathing. Never cycle atlas cells during sleep.
13. Every sprite atlas declares `stateModel: furball-image-state-v1` and uses the shared row-5 stages and posture bindings from `Docs/PET_PACK_STANDARD.md`; no pet profile may redefine sleep. The creator produces Realistic 2D only. This contract is image-only. Do not apply its frame map to MP4 clips.
14. Before delivery, pass `Scripts/validate-pet-pack.swift`, Codex v2 structure/alpha validation, per-row previews, 16-direction semantics and continuity review, 60%/100%/140% in-app checks, and `Scripts/package-app.sh`. Review metric warnings at normal display size; never silence them by relaxing a threshold. Inspect the exact `stand.idle` entry cell through a real appearance switch. If it is soft, rebuild the complete idle row from the native identity master; never sharpen one cell or upscale a legacy 192×208 frame.

## 2. First steps after receiving new footage

If the task replaces the complete animal rather than adding one action, read `Docs/PET_PACK_STANDARD.md` first. Dogs and cats use the same 27 semantic action slots. Never add pet-specific hardcoded file paths to Swift; paths, loop properties, capabilities, and identity belong in the Pet Pack `manifest.json`. Image, video, and dual-mode packs must all pass `Scripts/validate-pet-pack.swift`; never package a validation failure.

Preserve the original video. Do not immediately overwrite `Sources/Furball2D/Assets/Pets/Nina/Clips`. Archive sources under `Assets/Pets/Nina/UserProvided/SourceVideos/<view>/<action>.mp4`, then complete these checks:

View directories use lowercase kebab-case, such as `left-profile`, `right-profile`, `front`, and `three-quarter-left`. If the view changes during the clip, use a directional name such as `three-quarter-to-front`. Action filenames also use kebab-case, such as `stand-idle.mp4` and `stand-to-sit.mp4`. Exports go under the matching `Sources/Furball2D/Assets/Pets/Nina/Clips/<view>/` directory; never mix views in one folder.

- Use `ffprobe` to record resolution, frame rate, duration, color format, and whether frame rate is constant.
- Generate a contact sheet at 0.25–0.5-second intervals and inspect the complete action timeline.
- Verify identity continuity using ears, facial markings, tail length, body proportions, and coat colors.
- Check whether the camera is fixed and identify zoom, pan, crop, or ground-height drift.
- Check whether lighting, white balance, or green-screen color changes over time.
- Locate watermarks, generator marks, and dirty edges. Re-measure `delogo` coordinates for every new video; never copy old coordinates blindly.

Create a segmentation table before processing:

| Output action | Source | Start | End | Entry pose port | Exit pose port | Loop strategy | Scale correction |
|---|---|---:|---:|---|---|---|---|
| `stand-idle` | Source A | Measure | Measure | Stand | Stand | True loop or low-motion ping-pong | Measure |
| `stand-to-sit` | Source A | Measure | Measure | Stand | Sit | One-shot | Measure |
| `sit-idle` | Source A | Measure | Measure | Sit | Sit | True loop or low-motion ping-pong | Measure |
| `sit-to-lie` | Source A | Measure | Measure | Sit | Lie | One-shot | Measure |
| `lie-idle` | Source A | Measure | Measure | Lie | Lie | True loop or low-motion ping-pong | Measure |
| `lie-to-sleep` | Source A | Measure | Measure | Lie | Sleep | One-shot | Measure |
| `sleep-idle` | Source A | Measure | Measure | Sleep | Sleep | Low-motion breathing loop | Measure |
| `sleep-to-stand` | Source A | Measure | Measure | Sleep | Stand | One-shot | Measure |

When one continuous video contains a complete state chain, prefer adjacent actions cut from that same source. Keep two to four stable pose frames at boundaries, but do not replay the same obvious movement in both an idle and a transition.

## 3. Selecting action ports

Every clip has an entry port and an exit port. Adjacent ports must at least match in:

- Facing direction.
- Paw/ground contact state.
- Ground baseline.
- Subject height and head size.
- Head, tail, and front-paw position.
- Lighting and coat color.

Prefer cut points with low velocity and a stable pose. Do not cut during a raised paw, fast head turn, tail sweep, or falling body.

If a continuous source contains “eight stable standing frames → beginning of sit,” end `stand-idle` in that stable region and begin `stand-to-sit` near the same standing pose. A short crossfade then has compatible ports to blend.

## 4. Normalizing subject size and ground anchors

After keying, measure at least the first, middle, and last frame of every clip:

- Alpha bounds `xMin/yMin/xMax/yMax`.
- Subject height and width.
- Alpha-weighted center.
- Lowest paw or body contact y-coordinate.

Do not compare canvas sizes alone. Two 1280×720 videos can still contain pets at different scales or positions.

Recommended workflow:

1. Detect subject scale and position at the original green-screen resolution.
2. Select a stable reference pose, such as a clean `stand-idle` frame.
3. Apply smoothed per-frame correction to clips with camera zoom or subject drift.
4. Anchor vertical scale correction at the feet, not at the center of the image.
5. Interpolate correction values with smoothstep so the correction does not introduce a velocity discontinuity.
6. Apply keying, despill, and the final 1280×720 output only after scale and placement are solved.

Define a clear “port tuple” for each stable posture instead of recording only one scale percentage:

```text
port = (subject height, alpha-weighted center x, ground y)
```

Normalize both the outgoing last frame and incoming first frame to the same port. A “stand → gait loop → stand” source needs at least four measurements: standing entry, loop entry, loop exit, and standing exit. Treat start / loop / stop independently:

- `start` moves from the standard standing port to the loop-entry port with smoothstep correction.
- `loop` must finish at the same transformed height, center, and ground anchor where it begins. Correction may vary gently within one cycle, but the transformed last frame must return seamlessly to the first.
- `stop` moves continuously from the loop-exit port back to the standard standing port.

Never apply one fixed scale to a complete locomotion video. An AI source can change size and drift within the same shot; a fixed value such as 93% can align one frame while leaving the entry, exit, or loop seam wrong.

When correction requires both enlargement and reduction, transform on a larger transparent work canvas and crop back to the 1280×720 standard canvas. This prevents `pad` from clipping scale factors above 1. Compute scale around canvas center, then compensate vertical position against the ground port.

The current `sleep-to-stand` source enlarges the subject by roughly 6% near the end. The build script corrects it with dynamic scale and foot anchoring. New footage must be measured independently; never reuse this 6% value or its offsets.

Avoid non-uniform scaling. It may make bounding-box numbers agree while deforming a realistic animal. If separate videos contain different tail length, head shape, or markings, report an AI-source consistency problem and request a new generation rather than stretching the body.

### 4.1 Color normalization

Normalize separate generation batches to one explicit reference after keying. The current reference is `stand-idle` / `left-profile`. Measure opaque black, tan, and white fur separately instead of using a whole-frame average; transparent background and posture-dependent area make whole-frame averages misleading.

- All start / loop / stop clips cut from one locomotion source must share one color curve. Never auto-white-balance each segment independently.
- Individual image views may use separate monotonic PCHIP curves, but every curve must target the same black/tan/white reference anchors.
- Apply grading after chromakey / despill without changing alpha. Never include the green background in white-balance statistics.
- Extract representative source frames, verify them with `Scripts/audit-png-color.swift`, and record accepted anchors in the build script. Do not auto-grade every runtime frame; that creates breathing color drift during motion.
- Composite all representative outputs over the same middle-gray background before delivery. Matching numbers do not replace checking pink whites, blue blacks, or oversaturated tan fur.

## 5. Keying and transparent-video output

The current starting point in `Scripts/build-assets.sh` is:

```text
chromakey=0x3f985b:0.075:0.025
despill=green:mix=0.30:expand=0.05
unsharp=5:5:0.25:3:3:0
scale=960:540:flags=lanczos+accurate_rnd
format=bgra
```

Re-sample green-screen color for every new video. Inspect fur edges over dark gray, pure black, and white backgrounds:

- Visible green outline: increase despill carefully; do not immediately expand chromakey similarity substantially.
- White fur disappears or becomes transparent: reduce chromakey similarity or softness.
- Black fur develops a gray fringe: verify straight versus premultiplied alpha handling.
- Flickering edge: first inspect compression noise and frame-to-frame exposure changes, then tune the key.
- Watermark region: use `delogo` only after measuring coordinates for the new resolution.

Output requirements:

```text
1280×720
120 fps
HEVC VideoToolbox with Alpha
-alpha_quality 0.95
-q:v 75
-tag:v hvc1
No audio track
```

Do not return to 640×360. The default display area is about 520 points wide; 640×360 is visibly enlarged on a Retina display and loses fur and eye detail.

## 6. Correct idle and gait loops

### 6.1 Truly periodic actions

Walk, run, and tail-wag loops have explicit phases. The first and last frame must use the same leg and the same contact phase. Never reverse a walking clip; reversed gait dynamics look physically wrong.

If no valid in-place gait loop exists, do not slide a static standing pose across the desktop. The app should remain standing instead of moving without foot motion.

### 6.2 Low-motion idles

Standing breathing, seated observation, lying, and sleep can use endpoint-deduplicated forward/reverse loops:

```text
forward:  0, 1, 2, ... N
reverse:  N-1, N-2, ... 1
loop:     0, 1, 2, ...
```

Remove duplicated endpoint frames at both the turn and the loop seam. Convert the result to a consistent 120 fps only after constructing the sequence; motion-interpolate low-frame-rate chroma footage instead of merely duplicating frames with `fps`.

Ping-pong is appropriate only for low-amplitude, weakly directional motion. A clear head turn, raised paw, roll, or walk will reveal reversal; find a more stable interval or construct a true closed loop instead.

### 6.3 Sleep

The user prefers the pet to sleep quietly when untouched. Never loop an entire sleep video containing tail sweeps, posture changes, or head lifts.

Find a roughly 0.5–1.0-second lowest-motion window containing only subtle breathing. If needed, slow it by about 1.5–2.5×, then build an endpoint-deduplicated ping-pong loop. The current asset uses a 0.55-second window slowed 2.5× for a final loop of roughly 2.7 seconds at 120 fps.

## 7. Runtime transition rules

`PetRenderer.swift` uses two independent decoder lanes:

1. Keep displaying the outgoing action.
2. Start decoding the incoming lane.
3. Begin fading only after the incoming lane has produced a real first frame; never fade toward an empty transparent frame.
4. Freeze the outgoing lane when the fade begins so both clips do not move simultaneously and create wobble.
5. Convert each lane to premultiplied alpha before blending.
6. Use a fifth-order smootherstep weight over about 0.14 seconds, about 17 samples on a 120 Hz presentation path. Its first and second derivatives are zero at both endpoints, reducing subtle opacity jolts compared with cubic smoothstep.
7. Keep clip-end callbacks and fade completion as separate lifecycles.

Do not switch walk, jog, and run from a single speed sample. Require a requested speed tier to remain stable for roughly 0.15–0.25 seconds and retain threshold hysteresis. Stop and fresh start may respond immediately. This short confirmation period prevents repeated crossfades when cursor speed oscillates near a threshold.

On a fresh transition from standing into locomotion, first recut the `start` clip near the first visible weight shift, then use a short `translationDelay` to align desktop translation with the paws. Current walk, jog, and run delays are about 0.12, 0.07, and 0.10 seconds, with velocity ramps of roughly 0.18, 0.13, and 0.10 seconds. Re-measure after every recut: avoid both planted-paw sliding and a long cursor-response pause.

Keep most crossfades within 0.10–0.16 seconds. Above about 0.20–0.25 seconds, realistic footage commonly shows double eyes, heads, paws, or tails. If a short fade remains obvious, repair the offline ports instead of lengthening the dissolve.

## 8. Required frame-by-frame QA

Every asset replacement requires more than launching the app for a few seconds.

### 8.1 Loop seams

Compare the last visible frame with the first frame of every idle or gait loop:

- Foot/contact displacement should ideally be no more than 1–2 pixels.
- Alpha-weighted center displacement should ideally be no more than 2 pixels.
- Subject-height change should be below 2%.
- Premultiplied RGB mean absolute difference should ideally be below 1; low-motion footage should generally remain below 2.

Current repaired reference values:

```text
stand-idle seam MAE ≈ 0.69
sit-idle seam MAE   ≈ 0.58
lie-idle seam MAE   ≈ 0.69
sleep-idle seam MAE ≈ 0.48
```

Current locomotion normalization results as of 2026-08-14:

```text
stand-idle → walk/jog/run start: subject-height difference ≈ 0–0.2%, ground difference 0–2 px
walk-loop seam: height difference ≈ 0.3%, center difference ≈ 0.3 px, ground difference 0 px
jog-loop seam: height difference ≈ 0%, center difference ≈ 0.2 px, ground difference 1 px
run-loop seam: height difference ≈ 0.3%, center difference ≈ 0.3 px, ground difference 0 px
sit-to-lie → lie-idle: subject-height difference reduced from ≈ 13.5% to ≈ 0.3%
```

These values document the current assets; they are not transform parameters to copy to future footage. Measure every new source independently.

The MAE figures are references, not universal hard limits. Any new source substantially above 2 requires visual inspection.

### 8.2 Action ports

For every adjacent pair, compare “outgoing last frame → incoming first frame”:

- Ground y difference should ideally be no more than 2 pixels.
- Same-posture subject-height difference should ideally be below 3%.
- Alpha center displacement should ideally be no more than 5 pixels.
- Identity, tail length, coat color, and body proportions must not change suddenly.

Composite endpoint frames over a middle-gray background and inspect them side by side. Similar alpha bounds do not prove the character shape is actually consistent.

### 8.3 On-device checks

- Inspect at 60%, 100%, and 140% display sizes.
- Inspect green/black fringes and alpha flicker over both dark and light desktops.
- Play every idle loop for at least three full cycles.
- Exercise the complete autonomous chain: sleep → wake → stand → sit → lie → sleep.
- Check for empty transparent frames, a still-moving outgoing action, double images, and sudden scale changes during transitions.
- Watch for sustained memory growth and confirm the old player lane is released after each fade.

`FURBALL_FAST_BEHAVIOR=1` may accelerate state-machine testing, but always launch once at normal speed before delivery.

## 9. Files to update with the project

After processing a new action, review all of these:

- `Scripts/build-assets.sh`: sources, cut points, loop construction, and correction parameters.
- `Assets/README.md`: view directories, legacy mappings, alternate footage, and duplicate records.
- `Sources/Furball2D/Assets/Pets/<PetName>/manifest.json`: canvas, frame rate, view, filenames, sources, and loop flags.
- `Sources/Furball2D/PetClip.swift`: action IDs, filenames, and resulting postures.
- `Sources/Furball2D/PetController.swift`: only legal posture paths may exist in the state graph.
- `README.md`: asset requirements and user-visible behavior.

Then run:

```bash
./Scripts/build-assets.sh
swift build
./Scripts/package-app.sh
```

`Scripts/package-app.sh` signs the app from a clean `/tmp` staging directory, then outputs:

```text
dist/Furball.app
dist/Furball.zip
```

Desktop File Provider may attach FinderInfo to a local app copy. Prefer the ZIP for transfer or strict signature validation, and run `codesign --verify --deep --strict` against the app extracted from that ZIP.

## 10. Explicitly forbidden shortcuts

- Do not apply one longer crossfade duration to every transition.
- Do not mark a full video with obvious movement as `loop: true`.
- Do not slide a static standing pose across the desktop as a substitute for walking.
- Do not upscale an old low-resolution transparent clip to 1280×720.
- Do not compare canvas sizes alone; measure subject bounds and the ground anchor.
- Do not use arbitrary non-uniform scaling merely to align bounding boxes.
- Do not chromakey at runtime; green-screen processing is an offline step.
- Do not copy old green colors, watermark coordinates, 6% scale values, or trim times onto new footage.
- Do not deliver without real on-device loop testing.

If source videos contain different pets, severely incompatible pose ports, or obvious generation deformation, report those limitations clearly and identify which entry/exit poses require regeneration. Request a correctly ported source instead of hiding the problem with a long dissolve.
