# Fortune Live Motion — Gemini Generation Guide

This guide creates the nine source videos needed to give Fortune a Live Motion appearance equivalent to Nina. Generate and download exactly one video per request. Do not combine multiple actions into one Gemini request, and do not ask Gemini to return multiple alternatives.

## Why Fortune uses screen-right as its native direction

Fortune's strongest full-body and sleeping references face screen-right. Her narrow white forehead blaze is asymmetric. Generate every source video with Fortune facing screen-right so Gemini does not invent an unverified opposite-side identity. Furball integration must declare Fortune's native video facing as `right` and mirror the video when Fortune travels left.

All accepted originals should eventually be archived under:

```text
Assets/Pets/Fortune/UserProvided/SourceVideos/right-profile/
```

The nine target filenames are:

```text
stand-idle.mp4
stand-to-sit.mp4
sit-to-lie.mp4
lie-to-sleep.mp4
sleep-idle.mp4
sleep-to-stand.mp4
stand-to-walk-to-stand.mp4
stand-to-slow-run-to-stand.mp4
stand-to-fast-run-to-stand.mp4
```

## Step 1: Create four generation-ready stills first

Do not drive all nine videos directly from the six room and outdoor photos. They have different backgrounds, camera angles, and apparent body scales. First use Gemini image generation to create four standardized 1280x720 reference stills. Each still must use the same camera, optical scale, lighting, chroma color, and ground baseline.

Save the accepted stills at these paths:

```text
Assets/Pets/Fortune/Generated/AIReferenceImages/generation-ready/stand/right-profile.png
Assets/Pets/Fortune/Generated/AIReferenceImages/generation-ready/sit/right-profile.png
Assets/Pets/Fortune/Generated/AIReferenceImages/generation-ready/lie/right-profile.png
Assets/Pets/Fortune/Generated/AIReferenceImages/generation-ready/sleep/right-profile.png
```

### Input images for the stand, sit, and lie stills

Upload these four files in this order:

1. `Assets/Pets/Fortune/Generated/SpritePet/run/references/canonical-base.png` — primary body, coat, and screen-right orientation reference.
2. `Assets/Pets/Fortune/UserProvided/ReferencePhotos/front-resting.jpg` — primary face and asymmetric forehead-blaze identity reference.
3. `Assets/Pets/Fortune/UserProvided/ReferencePhotos/front-three-quarter-right.jpg` — muzzle, ears, white chest, and natural expression reference.
4. `Assets/Pets/Fortune/UserProvided/ReferencePhotos/rear-three-quarter-awake.jpg` — black saddle, tan haunches, body length, and very short tail reference.

### Input images for the sleep still

Upload these four files in this order:

1. `Assets/Pets/Fortune/UserProvided/ReferencePhotos/right-profile-sleeping.jpg` — primary pose and screen-right orientation reference.
2. `Assets/Pets/Fortune/Generated/SpritePet/run/references/canonical-base.png` — standing optical scale, body proportions, and coat reference.
3. `Assets/Pets/Fortune/UserProvided/ReferencePhotos/front-resting.jpg` — face and blaze identity reference.
4. `Assets/Pets/Fortune/UserProvided/ReferencePhotos/belly-up-sleeping.jpg` — closed eyes, relaxed paws, underside colors, and natural sleep expression reference only; do not copy the belly-up pose.

### Common still-image prompt

For each still, paste this prompt and replace `[POSE]` with one of the pose instructions below.

```text
Create exactly one photorealistic studio reference image of Fortune, the same adult tricolor Pembroke Welsh Corgi shown in all uploaded references.

Identity is mandatory: compact long low body, short sturdy legs, large upright ears, dark almond-shaped eyes, warm tan head and haunches, deep black saddle with the same edge shape, white muzzle, chest, belly and lower legs, a narrow asymmetric white forehead blaze, and a naturally very short tail. No collar, clothing, toy, prop, extra fur marking, changed blaze, changed ear shape, or changed tail length.

Fortune is shown in a strict full-body side profile facing screen-right. Use a locked eye-level orthographic-looking studio camera with an approximately 85 mm lens. Create a 16:9 landscape image at 1280x720. Keep the full body inside frame with generous margins. Keep the body center near x=640 and the lowest contacting paw or body point near y=650. Use the same optical scale as the first uploaded reference; posture may change but head size and shoulder-to-rump length must not.

[POSE]

The background and floor are one perfectly flat, evenly lit chroma green color #3F985B. There is no horizon line, corner, floor texture, gradient, vignette, reflection, or visible cast shadow. Lighting on the dog is soft neutral daylight with crisp natural fur detail and no green color cast.

No text, logo, watermark, border, camera movement, scenery, furniture, grass, bed, blanket, or other animal. This image is a clean identity-locked source frame for desktop-pet animation.
```

Use these pose replacements:

- **Stand:** `Fortune stands neutrally on all four paws with weight evenly distributed, head level, mouth closed, ears naturally alert, and all four paws readable. Do not sit, crouch, step, or raise a paw.`
- **Sit:** `Fortune sits naturally like a corgi, hindquarters resting on the ground, front legs straight and planted, spine relaxed, head level, mouth closed, and ears naturally alert. Do not lie down or raise a paw.`
- **Lie:** `Fortune lies awake in a relaxed sphinx-like side-profile posture, chest and belly on the ground, front paws extended naturally toward screen-right, hind legs folded comfortably, head upright, eyes open, and ears relaxed but still upright.`
- **Sleep:** `Fortune lies fully on her side facing screen-right in the same natural horizontal sleeping posture as the primary sleeping photo. Her head rests on the ground, eyes are fully closed, paws are relaxed, ears are relaxed, and the short tail is still. Do not place her on her back.`

Reject a still if the full dog is cropped, the blaze or saddle changes, the tail grows, a cast shadow appears, the background is not flat, or the scale differs visibly from the stand reference.

## Step 2: Generate the nine videos

Start a fresh Gemini video conversation for every numbered request. Select landscape 16:9. Upload the listed images in the listed order. Paste the **Common video lock** followed by that video's **Action block**. Request one result only.

### Common video lock — paste this into every video request

```text
Create exactly one continuous 8-second photorealistic video, 16:9 landscape, 1280x720, 24 fps, with no audio. This is production source footage for a transparent macOS desktop pet, not a cinematic scene.

The dog is Fortune, the exact same adult tricolor Pembroke Welsh Corgi shown in the uploaded references. Preserve her identity in every frame: compact long low body, short sturdy legs, large upright ears, dark almond-shaped eyes, warm tan head and haunches, deep black saddle with the same edge shape, white muzzle, chest, belly and lower legs, narrow asymmetric white forehead blaze, and naturally very short tail. Never change her face, blaze, saddle, ears, body proportions, leg length, or tail length. No collar, clothing, props, toys, or other animals.

The first generation-ready image defines Fortune's optical scale, camera, screen-right orientation, and ground registration. Any original photo is identity evidence only and must not contribute its room, grass, bedding, furniture, perspective, or lighting.

Use a completely locked eye-level side-profile camera with an approximately 85 mm lens. Fortune faces screen-right for the entire video. No camera motion, pan, tilt, zoom, crop change, focus breathing, cut, dissolve, slow motion, or view change. Keep the entire dog visible with generous margins. Keep the body center near x=640 and the ground contact baseline near y=650. Head size, shoulder-to-rump length, body scale, and ground baseline remain visually constant in every frame.

The entire background and floor are one perfectly flat, evenly lit chroma green #3F985B. No horizon, corner, floor texture, gradient, vignette, reflection, visible cast shadow, green spill, scenery, text, logo, watermark, or border. Lighting on Fortune is soft neutral daylight with crisp high-resolution fur detail and stable color.

Motion must follow real corgi anatomy and physics. Keep paws attached to the legs, maintain four consistent limbs, preserve contact with the ground, and avoid foot sliding, floating, morphing, rubber limbs, duplicated paws, changing coat patterns, sudden vertical jumps, or sudden scale changes. Keep the head and torso stable unless the requested action requires them to move.
```

### 1. Stand idle

Upload:

1. `Assets/Pets/Fortune/Generated/AIReferenceImages/generation-ready/stand/right-profile.png`
2. `Assets/Pets/Fortune/UserProvided/ReferencePhotos/front-resting.jpg`
3. `Assets/Pets/Fortune/UserProvided/ReferencePhotos/front-three-quarter-right.jpg`

Action block:

```text
For all 8 seconds Fortune remains standing in the exact neutral pose of the first image. She performs only extremely subtle natural breathing and one gentle blink. The chest movement is barely visible and completes one slow breath over roughly 7 to 8 seconds. The paws remain planted, the short tail remains still, and the head does not turn. Hold an almost motionless clean neutral stand during the first 1.0 second and return to the same pose and registration during the final 1.0 second. The first and last visible poses must be nearly identical so a low-motion loop can be built offline.
```

Save as `stand-idle.mp4`.

### 2. Stand to sit

Upload:

1. `Assets/Pets/Fortune/Generated/AIReferenceImages/generation-ready/stand/right-profile.png`
2. `Assets/Pets/Fortune/Generated/AIReferenceImages/generation-ready/sit/right-profile.png`
3. `Assets/Pets/Fortune/UserProvided/ReferencePhotos/front-resting.jpg`
4. `Assets/Pets/Fortune/UserProvided/ReferencePhotos/rear-three-quarter-awake.jpg`

Action block:

```text
Fortune begins in the exact neutral standing port shown in the first image and holds it completely still from 0.0 to 1.2 seconds. From 1.2 to about 3.8 seconds she naturally shifts weight backward and lowers into the exact seated port shown in the second image. Her paws do not slide, her legs do not morph, and her body does not change scale. From 3.8 to 8.0 seconds she remains calmly seated with only minimal breathing. The final 1.5 seconds are a clean stable seated hold. Do not lie down, turn the head, lift a paw, wag dramatically, or stand again.
```

Save as `stand-to-sit.mp4`.

### 3. Sit to lie

Upload:

1. `Assets/Pets/Fortune/Generated/AIReferenceImages/generation-ready/sit/right-profile.png`
2. `Assets/Pets/Fortune/Generated/AIReferenceImages/generation-ready/lie/right-profile.png`
3. `Assets/Pets/Fortune/UserProvided/ReferencePhotos/front-three-quarter-right.jpg`
4. `Assets/Pets/Fortune/UserProvided/ReferencePhotos/front-resting.jpg`

Action block:

```text
Fortune begins in the exact seated port shown in the first image. From 0.0 to 2.2 seconds she remains seated and awake with only subtle breathing; this opening interval must be stable enough to become a seated idle loop. From 2.2 to about 5.0 seconds she naturally lowers her chest, folds her short legs, and settles into the exact awake lying port shown in the second image. Keep the front paws and ground baseline stable and preserve body scale. From 5.0 to 8.0 seconds she remains lying awake with head upright and eyes open. The final 1.5 seconds are a clean stable lying hold. Do not close the eyes, sleep, roll over, stand, or change camera view.
```

Save as `sit-to-lie.mp4`.

### 4. Lie to sleep

Upload:

1. `Assets/Pets/Fortune/Generated/AIReferenceImages/generation-ready/lie/right-profile.png`
2. `Assets/Pets/Fortune/Generated/AIReferenceImages/generation-ready/sleep/right-profile.png`
3. `Assets/Pets/Fortune/UserProvided/ReferencePhotos/right-profile-sleeping.jpg`
4. `Assets/Pets/Fortune/UserProvided/ReferencePhotos/front-resting.jpg`

Action block:

```text
Fortune begins in the exact awake lying port shown in the first image. From 0.0 to 2.5 seconds she remains awake and lying with only subtle breathing; this interval must be stable enough to become a lying idle loop. From 2.5 to about 5.2 seconds she slowly relaxes onto her side, gently lowers her head to the ground, relaxes her ears, and closes her eyes once. She ends in the exact horizontal sleeping port shown in the second image. From 5.2 to 8.0 seconds she sleeps quietly. The final 1.5 seconds contain no tail sweep, paw twitch, head lift, or posture change. Do not roll onto the back.
```

Save as `lie-to-sleep.mp4`.

### 5. Sleep idle

Upload:

1. `Assets/Pets/Fortune/Generated/AIReferenceImages/generation-ready/sleep/right-profile.png`
2. `Assets/Pets/Fortune/UserProvided/ReferencePhotos/right-profile-sleeping.jpg`
3. `Assets/Pets/Fortune/UserProvided/ReferencePhotos/front-resting.jpg`

Action block:

```text
For all 8 seconds Fortune remains in the exact side-sleeping pose shown in the first image. Her eyes remain fully closed. The only motion is one extremely slow, very small breathing cycle across roughly the full 8 seconds: the ribcage rises by only a few pixels and settles smoothly. The head, paws, ears, very short tail, ground contact, body center, and silhouette remain effectively still. No twitching, dreaming, tail movement, head lift, rolling, stretching, waking, or repeated rapid breathing. The first and last poses must be nearly identical.
```

Save as `sleep-idle.mp4`.

### 6. Sleep to stand

Upload:

1. `Assets/Pets/Fortune/Generated/AIReferenceImages/generation-ready/sleep/right-profile.png`
2. `Assets/Pets/Fortune/Generated/AIReferenceImages/generation-ready/stand/right-profile.png`
3. `Assets/Pets/Fortune/UserProvided/ReferencePhotos/right-profile-sleeping.jpg`
4. `Assets/Pets/Fortune/UserProvided/ReferencePhotos/front-resting.jpg`

Action block:

```text
Fortune begins in the exact sleeping port shown in the first image and remains asleep from 0.0 to 1.2 seconds. From 1.2 to 2.5 seconds she opens her eyes, raises her head naturally, and becomes alert. From 2.5 to about 6.4 seconds she rolls only as needed into a chest-down position, plants her paws, rises through a natural corgi crouch, and reaches the exact neutral standing port shown in the second image. Her feet stay registered to the same ground baseline and her body never enlarges, shrinks, floats, or jumps. From 6.4 to 8.0 seconds she holds a clean neutral stand with all four paws planted. Do not sit again, turn around, walk, or shake the body.
```

Save as `sleep-to-stand.mp4`.

### 7. Stand to walk to stand

Upload:

1. `Assets/Pets/Fortune/Generated/AIReferenceImages/generation-ready/stand/right-profile.png`
2. `Assets/Pets/Fortune/Generated/SpritePet/run/references/canonical-base.png`
3. `Assets/Pets/Fortune/UserProvided/ReferencePhotos/front-resting.jpg`
4. `Assets/Pets/Fortune/UserProvided/ReferencePhotos/rear-three-quarter-awake.jpg`

Action block:

```text
Fortune begins in the exact neutral standing port shown in the first image and holds it from 0.0 to 1.1 seconds. From 1.1 to 2.0 seconds she makes a visible natural weight shift and begins the first walking step. From 2.0 to 6.1 seconds she performs a relaxed, anatomically correct corgi walk cycle in place, facing screen-right. Her legs cycle as if traveling but her body center stays registered near x=640 because desktop translation will be applied at runtime. Include at least three complete evenly paced stride cycles and repeated matching paw-contact phases that can be cut into a seamless forward loop. The feet must articulate and plant; do not slide a rigid body. From 6.1 to 7.0 seconds she completes the current stride, decelerates naturally, and returns to the exact starting stand port. From 7.0 to 8.0 seconds she holds still. No treadmill, scenery, horizontal travel across frame, moonwalk, hopping, pacing, reverse playback, head turn, or tail growth.
```

Save as `stand-to-walk-to-stand.mp4`.

### 8. Stand to slow run to stand

Upload:

1. `Assets/Pets/Fortune/Generated/AIReferenceImages/generation-ready/stand/right-profile.png`
2. `Assets/Pets/Fortune/Generated/SpritePet/run/references/canonical-base.png`
3. `Assets/Pets/Fortune/UserProvided/ReferencePhotos/front-resting.jpg`
4. `Assets/Pets/Fortune/UserProvided/ReferencePhotos/rear-three-quarter-awake.jpg`

Action block:

```text
Fortune begins in the exact neutral standing port shown in the first image and holds it from 0.0 to 1.0 seconds. From 1.0 to 1.8 seconds she visibly shifts weight and accelerates into a gentle corgi jog. From 1.8 to 6.2 seconds she performs a physically natural slow-run or jog cycle in place, facing screen-right. Use a comfortable moderate cadence, clearly faster than walking but not frantic. Her body center stays registered near x=640 while the legs perform at least four complete evenly paced gait cycles with repeated matching paw-contact phases suitable for a forward loop. Show real paw lift and landing without sliding. From 6.2 to 7.1 seconds she finishes the current gait cycle, decelerates naturally, and returns to the exact starting stand port. From 7.1 to 8.0 seconds she holds still. No horizontal travel, gallop, bunny-hop, exaggerated vertical bounce, rubber legs, moonwalk, head turn, or camera movement.
```

Save as `stand-to-slow-run-to-stand.mp4`.

### 9. Stand to fast run to stand

Upload:

1. `Assets/Pets/Fortune/Generated/AIReferenceImages/generation-ready/stand/right-profile.png`
2. `Assets/Pets/Fortune/Generated/SpritePet/run/references/canonical-base.png`
3. `Assets/Pets/Fortune/UserProvided/ReferencePhotos/front-resting.jpg`
4. `Assets/Pets/Fortune/UserProvided/ReferencePhotos/rear-three-quarter-awake.jpg`

Action block:

```text
Fortune begins in the exact neutral standing port shown in the first image and holds it from 0.0 to 0.9 seconds. From 0.9 to 1.6 seconds she visibly shifts weight and accelerates into a fast but believable corgi run. From 1.6 to 6.3 seconds she performs a physically natural fast-run cycle in place, facing screen-right. The cadence is energetic but still readable: do not make the short legs vibrate or spin unrealistically. Her body center stays registered near x=640 while the legs perform at least five complete evenly paced gait cycles with repeated matching contact phases suitable for a forward-only loop. Allow only a small natural torso rise and fall. From 6.3 to 7.2 seconds she completes the current gait cycle, decelerates without foot sliding, and returns to the exact starting stand port. From 7.2 to 8.0 seconds she holds still. No horizontal travel, teleporting, frantic leg blur, duplicated paws, extreme gallop, bunny-hop, moonwalk, head turn, or camera movement.
```

Save as `stand-to-fast-run-to-stand.mp4`.

## Acceptance checklist after every generation

Reject and regenerate immediately if any item fails:

- Exactly one continuous video; no montage, cut, transition, or alternate take.
- Fortune remains the same dog and faces screen-right throughout.
- The asymmetric blaze, black saddle, white chest/legs, ears, and short tail do not change.
- Camera, crop, body scale, center, and ground baseline remain fixed.
- Entire body and all paws remain visible.
- Green background is flat and contains no horizon, shadow, texture, or objects.
- Entry and exit holds match the named generation-ready pose references.
- Locomotion includes clear start, repeatable forward gait cycles, and stop; the body does not slide rigidly.
- Sleep contains only tiny slow breathing and no posture changes.

Do not attempt to repair identity, scale, ground drift, broken paws, or bad gait with a longer runtime crossfade. Regenerate the source instead.

## What happens after the nine videos are returned

The source videos are not runtime assets. Furball must:

1. inspect every timeline and choose exact ports;
2. motion-interpolate the 24 fps source to 120 fps before keying;
3. normalize subject scale, alpha center, and ground anchor per frame;
4. chroma-key, despill, and color-match all batches to the accepted stand-idle reference;
5. split each locomotion source into start, forward loop, and stop;
6. export 1280x720 120 fps HEVC with Alpha;
7. add Fortune's native-facing metadata, Live Motion appearance, and clip manifest entries;
8. run pet-pack validation, Live Motion QA, behavior QA, packaging, signing, and notarization.

Do not generate a head-turn video for cursor gaze. A generative turn video tends to morph face markings and body scale. Fortune's cursor-facing system should be built from identity-locked still directions and bridged separately, as Nina's image-view system is.
