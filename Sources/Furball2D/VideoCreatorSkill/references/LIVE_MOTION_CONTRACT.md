# Furball Live Motion contract

## Inputs and generation set

Prefer six to twelve clear identity photos plus these nine independently generated or recorded videos:

1. `stand-idle.mp4`
2. `stand-to-sit.mp4`
3. `sit-to-lie.mp4`
4. `lie-to-sleep.mp4`
5. `sleep-idle.mp4`
6. `sleep-to-stand.mp4`
7. `stand-to-walk-to-stand.mp4`
8. `stand-to-slow-run-to-stand.mp4`
9. `stand-to-fast-run-to-stand.mp4`

Each generation request produces exactly one video. Ask for a locked camera, full body, fixed side profile, constant distance, constant subject size, stable ground line, even lighting, solid chroma background, no shadows crossing the body, no props, no text, no watermark, no extra animal, and the same entry and exit stand pose where applicable. State whether the native profile faces screen-left or screen-right and keep it identical across the complete set.

Use two to four compatible identity references: a clean side profile matching the target direction, a front or three-quarter face reference to lock facial markings, and an action/posture reference when available. Do not combine opposite side profiles in a fixed-direction shot. Preserve ears, muzzle, coat markings, body proportions, tail length, paws, and collar state.

## Source archive and inspection

Archive originals without recompression:

```text
Assets/Pets/<PetName>/UserProvided/SourceVideos/<left-profile|right-profile>/<action>.mp4
```

Run `ffprobe` for resolution, frame rate, duration, pixel format, color metadata, audio, and constant-frame-rate status. Generate a contact sheet at 0.25–0.5 second intervals and inspect the complete timeline at normal speed and frame by frame. Sample the actual chroma color per generation batch; green and magenta screens both vary.

Create a segmentation table with source, start/end times, entry/exit posture, facing, paw-contact phase, loop strategy, subject bounds, alpha center, ground coordinate, and correction curve. Reject or trim duplicate animals, direction turns, morphing faces, coat changes, added limbs, tail changes, dirty edges, generator marks, or camera zoom. Record any deliberate substitution, such as using a compatible jog source for a corrupted fast-run start or stop.

## Offline processing

- Rebuild only from original footage; never upscale an older transparent export.
- Interpolate 24 fps sources bidirectionally to real 120 fps motion before chromakey. A plain `fps=120` duplicate is invalid.
- Measure alpha bounds, alpha-weighted center, subject height, and ground contact throughout each retained segment at no less than 24 samples per second. Endpoint-only measurements cannot detect camera drift inside an action.
- Normalize on a larger transparent work canvas. Correct scale around the canvas center and vertical placement around the feet. Use smoothstep or smootherstep correction and make adjacent ports agree. Apply a median-filtered, low-frequency center correction plus a rolling ground envelope so camera/generation drift is removed without stabilizing away paw, tail, or breathing motion. Loops use circular smoothing and matching first/last correction.
- Grade keyed opaque black, tan, and white fur against one explicit reference. One locomotion source uses one fixed color curve for start, loop, and stop. Never grade each runtime frame independently. Also compare opaque-fur alpha across sources; strengthen a weak key with one fixed alpha curve per batch before encoding rather than compensating with runtime window opacity.
- Tune chromakey and despill per source. Preserve white fur and dark edges; inspect over black, white, and middle gray.
- Encode no audio at 1280×720, 120 fps, HEVC VideoToolbox with Alpha, `hvc1`, alpha quality at least 0.95, and high visual quality.

Low-motion idle and sleep may use endpoint-deduplicated ping-pong only when motion is subtle and weakly directional. Sleep uses the quietest 0.5–1.0 second breathing window, optionally slowed 1.5–2.5×; never loop a whole clip with head lifts or posture changes. Walk/run loops must be true cyclic gait loops with matching contact phase and must never reverse.

## Runtime contract

Publish the standard 27 semantic clip IDs: standing/look/facing, posture transitions/idles, and walk/jog/run start-loop-stop. Set `capabilities.videoMode=true`, add a `continuous-video` appearance, and declare `videoNativeFacing` as `left` or `right`. Clip paths, loop properties, native facing, sources, and capabilities belong in the pack manifest—not pet-specific Swift branches.

Runtime transitions use two decoder lanes. Decode a real incoming frame before fading, freeze the outgoing lane at fade start, blend premultiplied alpha, and use a roughly 0.10–0.16 second smootherstep fade. Longer dissolves create double heads and paws. Locomotion tier hysteresis is roughly 0.15–0.25 seconds; fresh start and stop remain immediate. Align translation delay and acceleration ramp to the first visible weight shift in each processed start clip.

## Acceptance criteria

- Loop seam: contact/ground displacement ideally 0–2 px, alpha-center displacement about 2 px, subject-height change under 2%, and low-motion premultiplied RGB MAE generally below 2.
- Adjacent action ports: ground difference ideally 0–2 px, same-posture height difference under 3%, alpha-center difference at most 5 px, and no identity/color change.
- Inspect every loop for three cycles at 60%, 100%, and 140% display scale over light and dark desktops.
- Exercise sleep → wake → stand → sit → lie → sleep and stand → start → sustained fast loop → stop → stand.
- Confirm no empty frames, frozen sliding, repeated fades, alpha fringe, drift, scale pop, memory growth, or stale decoder lane.
- Run the repository's Pet Pack validator, Live Motion QA, behavior QA, runtime safety audit, build, and package scripts.

Never hide bad source ports with a long crossfade, reverse a directional gait, slide a static pet, key at runtime, reuse another video's key color/crop/timing/correction, or ship without watching the processed result.
