# Furball Pet Pack v2

### Goal

A Pet Pack separates animal identity, available representations, and application behavior. The user supplies identity photos and approves one canonical identity board. Image and optional video generation, keying, color, scale, ground anchoring, loops, and validation belong to an offline production tool. The app consumes semantic action IDs, so dogs, cats, and other quadrupeds share one Swift behavior graph without requiring a full AI-video purchase first.

### Minimum user input

1. Six to twelve clear originals covering front, both profiles, both three-quarter views, and one full-body image that shows proportions and tail.
2. A pet name and `dog`, `cat`, or `other` species metadata.
3. One approval of a canonical identity board covering face, ears, markings, coat, tail, and proportions. Pose-image generation does not fan out before this gate passes; video starts only when the user opts into the enhanced mode.

Green screen is an implementation detail, not a user requirement. A provider may emit fixed chroma, a clean solid background, or native alpha. Provider adapters must converge on the same transparent runtime clips.

### Standard production flow

1. **Intake QA:** score sharpness, occlusion, view coverage, heavy filters, and multiple animals.
2. **Identity model:** preserve originals, build a canonical front/profile/marking board, and record coat-color anchors.
3. **Canonical views and postures:** produce nine standing views plus stable stand, sit, lie, and sleep ports with one camera, scale, and ground baseline.
4. **Ship images first:** assemble identity-locked action frames into one transparent 2× WebP sprite atlas with semantic bindings. This already forms a complete low-cost pet.
5. **Optional video enhancement:** call a video provider only when selected. Every provider follows the same entry-pose, action, and exit-pose contract.
6. **Automated compilation:** images receive alpha, despill, scale, and ground normalization; video additionally receives segmentation, per-frame tracking, translation-delay detection, and loop-phase search.
7. **Automated QA and retry:** reject identity changes, discontinuities, bad ports, loop seams, alpha edges, and color outliers. Regenerate failed sources instead of hiding them with long fades.
8. **Export:** only validated runtime assets enter a `.furballpet` package.

### Pet Pack v2 runtime contract

- `capabilities.imageMode` and `capabilities.videoMode` declare available representations; at least one is true.
- Every enabled representation covers the same 27 semantic slots: 17 posture/locomotion actions, nine standing views, and one complete look-around demonstration.
- An image representation uses one `spriteAtlas`; standalone PNG animation descriptors and hybrid fallback paths are not supported.
- Every image representation declares `spriteAtlas.stateModel: furball-image-state-v1`. This one contract fixes the standard rows and posture-stage bindings for every Realistic 2D pet. Continuous-video clips do not use it and retain independently measured video entry/exit ports.
- In that model, row 5 is always `0 stand`, `1 lowering`, `2–3 horizontal awake lie`, `4 head/eye close`, and `5–7 horizontal closed-eye sleep ports`. Autonomous sleep holds canonical frame 5 with no image switching: `sit.to.lie=[1,2,3]`, `lie.idle=[2,3,2]`, `lie.to.sleep=[2,3,4,5]`, `sleep.idle=[5]`, and `sleep.to.stand=[5,4,3,2,1,0]`. The renderer supplies one continuous eight-second, sub-pixel procedural breath. Cycling multiple sleep cells is forbidden because every transition becomes another visible body pulse.
- Furball's production atlas is transparent lossless WebP at 3072×4576, 8 columns × 11 rows, 384×416 cells, `spriteVersionNumber: 2`, and `assetScale: 2`. Generate every action row natively for the target clarity, keep registration enlargement at or below 1.25×, and include `QA/clarity.json`. The old 1536×2288 form is rejected.
- `lookDirections` contains all 16 directions from 0° in 22.5° steps. Zero is up, 90° is screen-right, 180° is down, and 270° is screen-left. Runtime transitions along the shortest adjacent-cell path.
- `actions` exposes atlas bindings as localized menu actions and may opt individual actions into autonomous behavior. Titles, timing, action count, and semantic mapping belong to the pack rather than pet-specific Swift code.
- Video assets are 1280×720 at 120 fps, HEVC with Alpha, `hvc1`, and no audio. Bidirectionally motion-interpolate lower-frame-rate sources while the chroma silhouette is still intact, then key and normalize; duplicated frames do not qualify. Each `clips` entry declares a relative file and loop behavior.
- `appearances` may declare one video appearance and multiple sprite-atlas appearances for one pet, with exactly one `isDefault`. The app exposes only available appearances, and video-blending controls appear only for a video appearance.
- Four posture ports: stand, sit, lie, and sleep.
- One `pet.bodySize` integer from 1–100. A medium dog uses 60; the app applies this relative physical size before the independent 60%–140% Display Scale setting.
- Geometry ports use subject height, alpha-weighted center x, and ground y.
- Color ports use black, tan, and light-fur anchors without background pixels.
- Runtime behavior depends on semantic IDs in `manifest.json`, not filenames, species, or generation provider.

```text
MyPet.furballpet/
├── manifest.json
├── Sprites/MyPet/spritesheet.webp   # Required when imageMode=true
└── Clips/                           # Required only when videoMode=true
```

Source photos, chroma footage, and generation logs stay in a private source project rather than the user-facing `.furballpet` runtime package.

### Implemented foundation

- Runtime resolves the same user-facing behavior intent through separate asset state layers: every sprite atlas uses the shared `furball-image-state-v1` ports, while MP4 clips keep their independent manifest-declared transitions and measured video ports.
- The atlas decodes once; requested cells are placed on a shared 16:9 render canvas and cached as Metal textures. Variable frame durations, per-animation blend fractions, true left/right gait rows, and procedural motion can coexist.
- Sparse atlas poses are keyframes rather than a low-frame-rate movie. The image renderer samples temporal in-betweens at display refresh rate, blends premultiplied alpha with smootherstep, and eases incoming cells onto the outgoing height/center/ground port before releasing the correction. Calm gestures generally blend through 55–72% of each keyframe; fast silhouette changes retain 8–32% blends. Source rows requiring more than 12% size registration must be regenerated.
- Image mode now provides one-style stand, sit, genuinely horizontal closed-eye sleep, wake, phased locomotion, cute actions, and 16-direction gaze. A standing low-head pose is drowsy/sniffing rather than sleep. Right-facing art prefers `rightAnimation` and mirrors only as a fallback.
- `FURBALL_PET_PACK=/absolute/path/MyPet.furballpet` runs an unpacked external pack without recompilation for production and QA workflows.
- Pet Library validates, installs, switches, exports, and recoverably removes `.furballpet` packages. Finder-opened packages use the same validation path. User packs live under `~/Library/Application Support/Furball2D/Pets/`.
- Each pet ID has separate local personality, dynamic state, and short-term memory data; this user state never mutates or contaminates a shareable `.furballpet`.
- Create 2D Pet accepts 6–12 photos, name/species, and requested styles. A signed-in local Codex CLI can execute image generation, full validation, and automatic import under the same contract, or the app can export photos, `REQUEST.json`, the English Creator Skill, action registry, and standalone validator for another model. It explicitly does not generate video.
- A pet may expose Live Motion and Realistic 2D. New image-only packs expose exactly one Realistic 2D appearance; Nina is the built-in dual-representation reference pack.
- `Scripts/validate-pet-pack.swift <pack>` validates all 27 atlas bindings, the shared image-state identifier and exact posture bindings, horizontal lie/sleep silhouettes, safe paths, loop semantics, atlas structure/alpha/directions, clarity metadata, and video canvas, frame rate, codec, audio absence, and decoded transparency. An image pack never needs placeholder PNGs or empty videos.

The shipping app validates imports before copying them into Furball's guarded Application Support pet library. Create 2D Pet and the bundled English Creator Skill are available through the Settings sidebar. These asset workflows remain isolated from Desktop interaction: they never move Finder icons or rename, trash, or delete Desktop items.
