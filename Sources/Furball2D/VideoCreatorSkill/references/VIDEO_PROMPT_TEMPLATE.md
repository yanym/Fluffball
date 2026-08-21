# One-video generation template

Send one request for one video. Attach two to four identity references that agree with the requested view.

```text
Create exactly one continuous 16:9 video of the same pet shown in the attached references.

IDENTITY LOCK: Preserve the exact face, ears, muzzle, eye color, coat colors and markings, body proportions, leg length, paws, tail length, and collar state. Do not redesign, beautify, age, recolor, or replace the pet. No extra animal, duplicated pet, extra limb, prop, person, text, logo, or watermark.

CAMERA AND STAGE: Full body visible throughout. Locked eye-level camera, no pan, zoom, crop, shake, focus change, or cut. The pet remains centered at constant scale on one stable ground baseline. Even neutral lighting. Use one clean solid [GREEN OR MAGENTA] chroma background with no texture, horizon, floor seam, cast shadow, or color change.

DIRECTION: Fixed [SCREEN-LEFT OR SCREEN-RIGHT] side profile for the entire video. Do not turn toward camera, turn around, reverse direction, or swap left/right coat markings.

ACTION: [INSERT ONE ACTION CLAUSE BELOW]. Natural anatomy, believable weight transfer, restrained head/tail motion, and no foot sliding. Hold the requested entry and exit ports for 0.4–0.7 seconds.

OUTPUT: 1280×720 or higher, 24 fps constant frame rate, 8–10 seconds, no audio. Produce only this one video.
```

Use exactly one action clause:

- `stand-idle`: Begin and end in the same relaxed four-paw standing pose. Only subtle breathing, one gentle blink, and minimal ear motion.
- `stand-to-sit`: Hold the canonical stand, naturally lower into a stable sit, then remain seated. Do not lie down or stand again.
- `sit-to-lie`: Begin in the canonical sit, naturally lower chest and forelegs into a relaxed awake horizontal lie, then hold.
- `lie-to-sleep`: Begin awake in the canonical lie, settle the head, close the eyes, and hold the same horizontal sleeping pose.
- `sleep-idle`: Remain in one horizontal closed-eye sleeping pose. Only extremely subtle slow breathing; no head lift, roll, paw sweep, or tail sweep.
- `sleep-to-stand`: Begin in the canonical horizontal sleep, wake, rise naturally through lie/sit, and finish in the canonical four-paw stand.
- `stand-to-walk-to-stand`: Hold stand, accelerate into a fixed-direction side-profile walk with several clean cyclic strides, decelerate, and finish in the same stand.
- `stand-to-slow-run-to-stand`: Hold stand, accelerate into a natural easy jog with several clean cyclic strides, decelerate, and finish in the same stand.
- `stand-to-fast-run-to-stand`: Hold stand, accelerate into a controlled fast run with several clean cyclic strides, decelerate, and finish in the same stand. Never turn around inside the shot.

Generation is rejected if the animal changes direction, drifts in scale, slides before the first weight shift, produces a second animal, morphs identity, or cannot supply a phase-closed gait interval.
