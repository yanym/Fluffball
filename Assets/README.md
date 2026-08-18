# Furball 素材目录

[中文](#furball-视频素材目录) · [English](#fluffball-video-asset-catalog)

所有原始视频按 `视角/动作` 组织，目录与文件名统一使用小写英文和 kebab-case。运行时使用的透明导出视频也保持相同的视角层级，避免未来加入正面、右侧面或背面动作时混用。

`SourceImagesForAIVideo/` 是另一类资产：它保存生成 AI 视频时使用的狗狗身份、姿态和视角参考图，不会进入应用包。具体目录和选图规则见 [SourceImagesForAIVideo/README.md](SourceImagesForAIVideo/README.md)。

`ImageTurnMVP/normalized/` 保存 9 张 960×540 透明 PNG，按主体高度、边界框中心和脚底基线对齐。`Scripts/build-image-turn-mvp.sh` 不调用任何 AI 视频模型：它会合成一次性演示 `look-around-images.mov`，并为运行时多角度转头导出 `Clips/image-views/` 下的 9 个单视角循环。目录名保留 `MVP` 仅为兼容现有构建路径，菜单中的功能已经作为正式功能提供。

`Scripts/build-image-assets.sh` 会独立构建真正的图片运行时素材，不把 PNG 再编码成视频。输出位于 `Sources/Furball2D/Assets/Images/{stand,sit,lie,sleep}/`：站姿来自已归一化的 9 个视角，坐/趴/睡来自 `generation-ready/` 姿态图并离线抠像。`ImageMode/qa/contact-sheet.png` 是本次 17 张运行时图片的接触表。`manifest.json.imageAnimations` 再把同一组 27 个语义动作映射到这些图片与程序化 motion。

`SpritePets/Furball/` 保存原可爱 Codex v2 图片宠物的生成记录；`SpritePets/NinaRealistic/` 保存 Nina 写实 2D 的完整生成、接触表、方向连续性和 Alpha QA。运行时成品位于 `Sources/Furball2D/Assets/Sprites/Nina/{cute,realistic}/spritesheet.webp`。两张生产图集都是 3072×4576、8×11、384×416 单元格的 2× 高清图集，使用同一组动作绑定与 16 个视线方向，因此切换风格不会改变行为语义。

图集/PNG 图片表示与视频表示并列。`capabilities.imageMode` 和 `capabilities.videoMode` 决定素材包支持哪一种；纯图片包可以完全不带 `Clips/`。两者都存在时应用默认视频并允许用户切换。当前图集具有独立左右步态行和真实脚掌相位，不再用单张站姿的程序化弹跳冒充走跑。

## 原始视频映射

| 旧文件名 | 当前路径 | 视角与内容 | 状态 |
|---|---|---|---|
| `v2/1 2.MP4` | `SourceVideos/left-profile/sleep-to-stand.mp4` | 左侧面，趴卧起身至站立 | 主动作链 |
| `v2/1.mp4` | `SourceVideos/left-profile/stand-look-around-reference.mp4` | 左侧面站立并短暂看向镜头 | 备用参考，宠物外观与主链略有差异 |
| `v2/2 2.MP4` | `SourceVideos/left-profile/stand-to-sit.mp4` | 左侧面，站立至坐姿 | 主动作链 |
| `v2/2.mp4` | `SourceVideos/three-quarter-to-front/stand-to-sit.mp4` | 左前侧逐渐转向正面并坐下 | 备用视角，不参与当前主链 |
| `v2/3.MP4` | `SourceVideos/left-profile/stand-idle.mp4` | 左侧面站立待机 | 主动作链 |
| `v2/4.MP4` | `SourceVideos/left-profile/sit-to-lie.mp4` | 左侧面坐姿至趴卧；开头也用于坐姿待机 | 主动作链 |
| `v2/5.MP4` | `SourceVideos/left-profile/lie-to-sleep.mp4` | 左侧面趴卧至睡眠；开头也用于趴卧待机 | 主动作链 |
| `v2/6.MP4` | `SourceVideos/left-profile/sleep-idle.mp4` | 左侧面睡眠与轻微抬头 | 主动作链，仅截取低动作窗口 |
| `v2/Generated Video August 13, 2026 - 1_28AM.mp4` | `SourceVideos/archive/exact-duplicates/three-quarter-to-front-stand-to-sit.duplicate.mp4` | 与原 `v2/2.mp4` 完全相同 | 保留归档，不参与构建 |
| 用户新增走路视频 | `SourceVideos/left-profile/stand-to-walk-to-stand.mp4` | 左侧面，站立至走路再停下 | 移动动作链，拆为起步/循环/停步 |
| 用户新增慢跑视频 | `SourceVideos/left-profile/stand-to-slow-run-to-stand.mp4` | 左侧面，站立至慢跑再停下 | 移动动作链，拆为起步/循环/停步 |
| 用户新增快跑视频 | `SourceVideos/left-profile/stand-to-fast-run-to-stand.mp4` | 左侧面，站立至快跑再停下 | 移动动作链，拆为起步/循环/停步 |

归档重复文件与 `SourceVideos/three-quarter-to-front/stand-to-sit.mp4` 的 SHA-256 均为：

```text
906fb512fccd3f10b91053877d4263a9b545cd6bdb790af329f90dff4eb34535
```

## 导出视频

`Sources/Furball2D/Assets/Clips/left-profile/` 包含应用实际播放的 18 段 HEVC with Alpha 视频：

| 文件 | 类型 | 来源 |
|---|---|---|
| `stand-idle.mov` | 无缝待机循环 | `stand-idle.mp4` |
| `look-around-images.mov` | 纯图片多角度转身 | `Assets/ImageTurnMVP/normalized/` 的 9 张 PNG |
| `stand-to-sit.mov` | 单次过渡 | `stand-to-sit.mp4` |
| `sit-idle.mov` | 无缝待机循环 | `sit-to-lie.mp4` 的稳定开头 |
| `sit-to-lie.mov` | 单次过渡并校正坐姿/趴卧端口 | `sit-to-lie.mp4` |
| `lie-idle.mov` | 无缝待机循环 | `lie-to-sleep.mp4` 的稳定开头 |
| `lie-to-sleep.mov` | 单次过渡并校正趴卧/睡眠端口 | `lie-to-sleep.mp4` |
| `sleep-idle.mov` | 低动作呼吸循环 | `sleep-idle.mp4` 的 0.55 秒稳定窗口 |
| `sleep-to-stand.mov` | 单次过渡并校正尺度 | `sleep-to-stand.mp4` |
| `walk-start/loop/stop.mov` | 走路起步、相位闭合循环、停步 | `stand-to-walk-to-stand.mp4` |
| `slow-run-start/loop/stop.mov` | 慢跑起步、相位闭合循环、停步 | `stand-to-slow-run-to-stand.mp4` |
| `fast-run-start/loop/stop.mov` | 快跑起步、相位闭合循环、停步 | `stand-to-fast-run-to-stand.mp4` |

`Sources/Furball2D/Assets/Clips/image-views/` 另含从 `left-profile.mov` 到 `right-profile.mov` 的 9 个角度，其中 `front-near-profile-*` 和 `front-near-center-*` 是新增中间视角。每个文件都是由对应透明 PNG 导出的 1280×720、120 fps 单视角循环；运行时只逐级切换相邻视角，并在进入视频动作前逐级抵达匹配朝向的左或右侧面端口。右向待机、过渡、睡眠和步态由左侧面动作视频在运行时镜像得到。

起步片段已从第一处可见重心变化附近重新切入；首次从站立进入走路、慢跑或快跑时，运行时只分别等待约 0.12、0.07 和 0.10 秒，再用约 0.18、0.13 和 0.10 秒的平滑加速接入目标速度。这样既避免站立帧滑行，也减少鼠标追随的体感延迟。

这些导出文件可以由 `Scripts/build-assets.sh` 完整重建。移动素材按各自绿幕颜色抠像，并对 start / loop / stop 的首末帧分别归一化主体高度、Alpha 中心和脚底基线；循环段使用相同落脚相位且不倒放。校正通过 1600×900 透明工作画布平滑完成，最后裁回标准画布，不会使用固定缩放值硬套整条原片。移动素材还会按源视频共享单调色彩曲线，匹配 `stand-idle` 的黑毛、棕毛和白毛锚点；9 个图片视角也在导出时分别匹配同一参考。可用 `Scripts/audit-png-color.swift` 对透明 PNG 代表帧复测。切点、端口参数、循环策略、色彩参考和画布参数记录在脚本与 `Sources/Furball2D/Assets/manifest.json` 中。

## 新素材命名规则

```text
Assets/SourceVideos/<view>/<action>.mp4
Assets/SourceImagesForAIVideo/generation-ready/<pose>/<view>.png
Assets/SpritePets/<pet>/qa/<artifact>.png
Sources/Furball2D/Assets/Sprites/<pet>/spritesheet.webp
Sources/Furball2D/Assets/Images/<pose>/<view>.png
Sources/Furball2D/Assets/Clips/<view>/<action>.mov
```

建议视角名：`left-profile`、`right-profile`、`front`、`rear`、`three-quarter-left`、`three-quarter-right`。如果动作过程中视角发生改变，使用 `three-quarter-to-front` 这类方向明确的目录名。

---

# Fluffball Asset Catalog

All original videos are organized by `view/action`. Directory and file names use lowercase English and kebab-case. Transparent runtime exports retain the same view hierarchy so future front, right-profile, or rear actions cannot be mixed accidentally.

`SourceImagesForAIVideo/` is a separate asset class. It contains dog identity, posture, and view references used to generate AI videos and is not included in the app bundle. See [SourceImagesForAIVideo/README.md](SourceImagesForAIVideo/README.md) for its layout and image-selection rules.

`ImageTurnMVP/normalized/` contains nine transparent 960×540 PNGs aligned by subject height, bounding-box center, and ground baseline. Without invoking any AI video model, `Scripts/build-image-turn-mvp.sh` composes the one-shot `look-around-images.mov` demo and exports nine single-view loops under `Clips/image-views/` for runtime multi-angle turning. The `MVP` directory name remains only for build-path compatibility; the menu now presents this as a regular feature.

`Scripts/build-image-assets.sh` independently builds true image-runtime assets; it does not encode the PNGs back into video. Outputs live under `Sources/Furball2D/Assets/Images/{stand,sit,lie,sleep}/`. Standing views come from the normalized nine-angle set, while sit/lie/sleep sources under `generation-ready/` are keyed offline. `ImageMode/qa/contact-sheet.png` reviews the current 17 runtime images. `manifest.json.imageAnimations` maps the same 27 semantic actions to these images and procedural motion types.

`SpritePets/Furball/` preserves the original cute Codex v2 generation record. `SpritePets/NinaRealistic/` contains Nina Realistic 2D generation, contact sheets, direction-continuity review, and alpha QA. Runtime atlases live at `Sources/Furball2D/Assets/Sprites/Nina/{cute,realistic}/spritesheet.webp`. Both production atlases are 2× assets at 3072×4576 with 384×416 cells, using the same semantic bindings and 16 gaze directions so style changes never alter behavior semantics.

Atlas/PNG image representation and video representation are parallel. `capabilities.imageMode` and `capabilities.videoMode` declare what the pack supports; an image-only pack may omit `Clips/` completely. When both exist, the app defaults to video and lets the user switch. The current atlas has independent left/right gait rows with real footfall phases instead of moving a procedurally bouncing standing still.

## Original video mapping

| Legacy name | Current path | View and content | Status |
|---|---|---|---|
| `v2/1 2.MP4` | `SourceVideos/left-profile/sleep-to-stand.mp4` | Left profile, lying down to standing | Main action chain |
| `v2/1.mp4` | `SourceVideos/left-profile/stand-look-around-reference.mp4` | Left-profile stand with a brief look toward the camera | Alternate reference; appearance differs slightly from the main chain |
| `v2/2 2.MP4` | `SourceVideos/left-profile/stand-to-sit.mp4` | Left profile, standing to sitting | Main action chain |
| `v2/2.mp4` | `SourceVideos/three-quarter-to-front/stand-to-sit.mp4` | Left-front three-quarter view turning toward the camera and sitting | Alternate view; not used by the current main chain |
| `v2/3.MP4` | `SourceVideos/left-profile/stand-idle.mp4` | Left-profile standing idle | Main action chain |
| `v2/4.MP4` | `SourceVideos/left-profile/sit-to-lie.mp4` | Left profile, sitting to lying; the beginning also supplies the sit idle | Main action chain |
| `v2/5.MP4` | `SourceVideos/left-profile/lie-to-sleep.mp4` | Left profile, lying to sleeping; the beginning also supplies the lie idle | Main action chain |
| `v2/6.MP4` | `SourceVideos/left-profile/sleep-idle.mp4` | Left-profile sleep with a small head lift | Main action chain; only a low-motion window is used |
| `v2/Generated Video August 13, 2026 - 1_28AM.mp4` | `SourceVideos/archive/exact-duplicates/three-quarter-to-front-stand-to-sit.duplicate.mp4` | Byte-identical to the original `v2/2.mp4` | Archived only; excluded from builds |
| User-provided walk video | `SourceVideos/left-profile/stand-to-walk-to-stand.mp4` | Left profile, stand to walk to stand | Locomotion chain, split into start/loop/stop |
| User-provided jog video | `SourceVideos/left-profile/stand-to-slow-run-to-stand.mp4` | Left profile, stand to jog to stand | Locomotion chain, split into start/loop/stop |
| User-provided run video | `SourceVideos/left-profile/stand-to-fast-run-to-stand.mp4` | Left profile, stand to run to stand | Locomotion chain, split into start/loop/stop |

The archived duplicate and `SourceVideos/three-quarter-to-front/stand-to-sit.mp4` both have this SHA-256 digest:

```text
906fb512fccd3f10b91053877d4263a9b545cd6bdb790af329f90dff4eb34535
```

## Exported videos

`Sources/Furball2D/Assets/Clips/left-profile/` contains the 18 HEVC-with-alpha clips played by the app:

| File | Type | Source |
|---|---|---|
| `stand-idle.mov` | Seamless idle loop | `stand-idle.mp4` |
| `look-around-images.mov` | Image-only multi-angle turn | Nine PNGs under `Assets/ImageTurnMVP/normalized/` |
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

`Sources/Furball2D/Assets/Clips/image-views/` additionally contains nine angles from `left-profile.mov` through `right-profile.mov`; the `front-near-profile-*` and `front-near-center-*` files are the added intermediate views. Each is a 1280×720, 120 fps loop exported from its matching transparent PNG. At runtime the app changes only to an adjacent view and reaches the left- or right-profile port matching the next video action. Right-facing idle, transition, sleep, and gait footage is produced by mirroring the left-profile clips at runtime.

The start clips now begin near their first visible weight shift. On a fresh transition from standing to walking, jogging, or running, runtime translation waits only about 0.12, 0.07, or 0.10 seconds and ramps in over roughly 0.18, 0.13, or 0.10 seconds. This preserves planted-paw contact without making cursor response feel delayed.

`Scripts/build-assets.sh` can rebuild every export. Each locomotion source is keyed using its sampled green-screen color. The first and last frames of every start / loop / stop segment are independently normalized for subject height, alpha center, and ground baseline. Loop segments use matching footfall phases and are never reversed. Corrections are applied smoothly on a 1600×900 transparent work canvas before cropping back to the standard canvas; the pipeline does not apply one fixed scale to an entire source. Every locomotion source also shares one monotonic grading curve across start / loop / stop, matching the black, tan, and white fur anchors from `stand-idle`; all nine image views independently target the same reference during export. Use `Scripts/audit-png-color.swift` to re-audit representative transparent PNG frames. Cut points, port parameters, color references, loop strategies, and canvas metadata are recorded in the script and `Sources/Furball2D/Assets/manifest.json`.

## Naming new assets

```text
Assets/SourceVideos/<view>/<action>.mp4
Assets/SourceImagesForAIVideo/generation-ready/<pose>/<view>.png
Assets/SpritePets/<pet>/qa/<artifact>.png
Sources/Furball2D/Assets/Sprites/<pet>/spritesheet.webp
Sources/Furball2D/Assets/Images/<pose>/<view>.png
Sources/Furball2D/Assets/Clips/<view>/<action>.mov
```

Recommended view names include `left-profile`, `right-profile`, `front`, `rear`, `three-quarter-left`, and `three-quarter-right`. If the view changes during an action, use a directional name such as `three-quarter-to-front`.
