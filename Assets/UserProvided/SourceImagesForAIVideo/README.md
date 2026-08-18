# AI Video Generation Reference Images

This directory preserves the Furball dog's user-provided identity, body proportions, coat colors, postures, and view references. These files are not runtime assets and are not bundled into `Furball2D.app`. Generated and standardized derivatives live separately under `Assets/Generated/`.

## Directory layout

```text
Assets/
├── UserProvided/SourceImagesForAIVideo/originals/  # Immutable user inputs
│   ├── stand/
│   ├── sit/
│   ├── lie/
│   └── sleep/
└── Generated/AIReferenceImages/generation-ready/   # Prepared model inputs
    ├── stand/
    ├── sit/
    ├── lie/
    └── sleep/
```

Images under `Assets/Generated/AIReferenceImages/generation-ready/` are standardized to 1440×1080 on a green background and provide a more complete posture and left/right view set. Prefer that collection for new generations. Use `originals/` to verify the dog's real identity details and trace provenance; do not overwrite or delete it.

Files matching `Assets/Generated/AIReferenceImages/generation-ready/stand/*-imagegen.png` are green-screen still keyframes generated on 2026-08-14 for the image-only turn prototype. The suffix distinguishes them from the user's earlier references. Their aligned derivatives under `Assets/Generated/ImageTurn/normalized/` are 960×540 with a 450 px subject height, center x≈500, and ground y=504.

Some PNG files contain C2PA Content Credentials that record generation and processing provenance. The repository preserves this authenticity metadata. Inspection found no GPS, camera-device, or personal-author fields.

## Naming convention

The directory name describes the posture. The filename describes the direction visible to the camera:

- `front.png`: front view.
- `left-profile.png`: standard left profile, with the dog's head facing screen-left.
- `right-profile.png`: standard right profile, with the dog's head facing screen-right.
- `rear.png`: direct rear view.
- `front-three-quarter-left.png`: left-front three-quarter view.
- `front-three-quarter-right.png`: right-front three-quarter view.
- `rear-three-quarter-left.png`: left-rear three-quarter view.
- `rear-three-quarter-right.png`: right-rear three-quarter view.

Continue to use this pattern for new files:

```text
<collection>/<pose>/<view>.png
```

Do not reintroduce ambiguous names such as `std`, `1.png`, or `stand_left_v2_final.png`.

## Selecting images for video generation

1. Use `Assets/Generated/AIReferenceImages/generation-ready/stand/front.png` as the primary identity reference for face shape, eyes, nose, ear placement, and chest markings.
2. Add posture and view references that match the target action. For a left-profile “sit → lie” clip, prefer `sit/left-profile.png` and `lie/left-profile.png`.
3. Add one standing side or rear view when the model needs extra guidance for tail length, back markings, or body proportions. Two to four reference images are usually enough.
4. Unless the action explicitly turns around, do not mix left- and right-profile references in one generation. Doing so often flips markings or changes ear placement mid-clip.
5. Every generated video must keep the same dog, fixed camera, fixed canvas, stable subject scale, stable ground baseline, and a solid green background.
6. Process every generated result through the inspection, segmentation, normalization, keying, and QA workflow in the root [AGENTS.md](../../../AGENTS.md). Never overwrite runtime assets directly with an unchecked generation.

## Legacy filename mapping

Legacy `<pose>_<view>.png` files were reorganized as `<collection>/<pose>/<view>.png`. Examples:

| Legacy path | Current path |
|---|---|
| `stand_front.png` | `originals/stand/front.png` |
| `stand_left.png` | `originals/stand/left-profile.png` |
| `stand_back_left.png` | `originals/stand/rear-three-quarter-left.png` |
| `sleep_right.png` | `originals/sleep/right-profile.png` |
| `std/sit_left.png` | `Assets/Generated/AIReferenceImages/generation-ready/sit/left-profile.png` |
| `std/lie_right.png` | `Assets/Generated/AIReferenceImages/generation-ready/lie/right-profile.png` |

The complete collection contains 14 `originals` and 24 `generation-ready` images. `generation-ready/lie/left-profile.png` and `right-profile.png` have no same-named original counterpart, so they remain independent generation-ready references.
