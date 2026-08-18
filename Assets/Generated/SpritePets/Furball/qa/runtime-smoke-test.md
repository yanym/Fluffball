# Runtime Smoke Test

Date: 2026-08-17

## Image Mode

```bash
FURBALL_FAST_BEHAVIOR=1 .build/debug/Furball2D \
  -videoAnimationsEnabled.furball-demo-dog false
```

- Ran for more than 73 seconds through accelerated stand, sit, lie, sleep, wake, and patrol cycles without a crash or runtime error.
- RSS sampled at about 119 MB after 33 seconds and 106 MB after 73 seconds; no sustained growth was observed.
- The atlas was decoded once and cells were reused by the runtime frame cache.
- After the final gaze-idle and autonomous-gesture changes, an additional 18-second accelerated run completed without an error.

## Video Mode Regression

```bash
.build/debug/Furball2D -videoAnimationsEnabled.furball-demo-dog true
```

The existing video path launched and played without runtime errors. The image-atlas implementation does not replace or re-encode the existing video clips.
