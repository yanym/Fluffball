# Furball 视频素材目录

[中文](#furball-视频素材目录) · [English](#fluffball-video-asset-catalog)

所有原始视频按 `视角/动作` 组织，目录与文件名统一使用小写英文和 kebab-case。运行时使用的透明导出视频也保持相同的视角层级，避免未来加入正面、右侧面或背面动作时混用。

`SourceImagesForAIVideo/` 是另一类资产：它保存生成 AI 视频时使用的狗狗身份、姿态和视角参考图，不会进入应用包。具体目录和选图规则见 [SourceImagesForAIVideo/README.md](SourceImagesForAIVideo/README.md)。

`ImageTurnMVP/normalized/` 保存 9 张 960×540 透明 PNG，按主体高度、边界框中心和脚底基线对齐。`Scripts/build-image-turn-mvp.sh` 不调用任何 AI 视频模型：它会合成一次性演示 `look-around-images.mov`，并为运行时多角度转头导出 `Clips/image-views/` 下的 9 个单视角循环。目录名保留 `MVP` 仅为兼容现有构建路径，菜单中的功能已经作为正式功能提供。

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

`Sources/Furball2D/Assets/Clips/image-views/` 另含从 `left-profile.mov` 到 `right-profile.mov` 的 9 个角度，其中 `front-near-profile-*` 和 `front-near-center-*` 是新增中间视角。每个文件都是由对应透明 PNG 导出的 1 秒、24 fps 单视角循环；运行时只逐级切换相邻视角，并在进入视频动作前逐级抵达匹配朝向的左或右侧面端口。右向待机、过渡、睡眠和步态由左侧面动作视频在运行时镜像得到。

首次从站立进入走路、慢跑或快跑时，运行时分别等待约 0.32、0.16 和 0.32 秒再开始桌面位移，并使用平滑加速接入目标速度。这些时间来自起步片段接触表中的第一处明确步态，而不是从菜单点击时刻立即平移。

这些导出文件可以由 `Scripts/build-assets.sh` 完整重建。移动素材按各自绿幕颜色抠像，并对 start / loop / stop 的首末帧分别归一化主体高度、Alpha 中心和脚底基线；循环段使用相同落脚相位且不倒放。校正通过 1600×900 透明工作画布平滑完成，最后裁回标准画布，不会使用固定缩放值硬套整条原片。切点、端口参数、循环策略和画布参数记录在脚本与 `Sources/Furball2D/Assets/manifest.json` 中。

## 新素材命名规则

```text
Assets/SourceVideos/<view>/<action>.mp4
Sources/Furball2D/Assets/Clips/<view>/<action>.mov
```

建议视角名：`left-profile`、`right-profile`、`front`、`rear`、`three-quarter-left`、`three-quarter-right`。如果动作过程中视角发生改变，使用 `three-quarter-to-front` 这类方向明确的目录名。

---

# Fluffball Video Asset Catalog

All original videos are organized by `view/action`. Directory and file names use lowercase English and kebab-case. Transparent runtime exports retain the same view hierarchy so future front, right-profile, or rear actions cannot be mixed accidentally.

`SourceImagesForAIVideo/` is a separate asset class. It contains dog identity, posture, and view references used to generate AI videos and is not included in the app bundle. See [SourceImagesForAIVideo/README.md](SourceImagesForAIVideo/README.md) for its layout and image-selection rules.

`ImageTurnMVP/normalized/` contains nine transparent 960×540 PNGs aligned by subject height, bounding-box center, and ground baseline. Without invoking any AI video model, `Scripts/build-image-turn-mvp.sh` composes the one-shot `look-around-images.mov` demo and exports nine single-view loops under `Clips/image-views/` for runtime multi-angle turning. The `MVP` directory name remains only for build-path compatibility; the menu now presents this as a regular feature.

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

`Sources/Furball2D/Assets/Clips/image-views/` additionally contains nine angles from `left-profile.mov` through `right-profile.mov`; the `front-near-profile-*` and `front-near-center-*` files are the added intermediate views. Each is a one-second, 24 fps loop exported from its matching transparent PNG. At runtime the app changes only to an adjacent view and reaches the left- or right-profile port matching the next video action. Right-facing idle, transition, sleep, and gait footage is produced by mirroring the left-profile clips at runtime.

On a fresh transition from standing to walking, jogging, or running, runtime translation waits approximately 0.32, 0.16, or 0.32 seconds respectively, then ramps smoothly to the target speed. These offsets come from the first clear gait motion in each start-clip contact sheet rather than translating immediately when the menu action occurs.

`Scripts/build-assets.sh` can rebuild every export. Each locomotion source is keyed using its sampled green-screen color. The first and last frames of every start / loop / stop segment are independently normalized for subject height, alpha center, and ground baseline. Loop segments use matching footfall phases and are never reversed. Corrections are applied smoothly on a 1600×900 transparent work canvas before cropping back to the standard canvas; the pipeline does not apply one fixed scale to an entire source. Cut points, port parameters, loop strategies, and canvas metadata are recorded in the script and `Sources/Furball2D/Assets/manifest.json`.

## Naming new assets

```text
Assets/SourceVideos/<view>/<action>.mp4
Sources/Furball2D/Assets/Clips/<view>/<action>.mov
```

Recommended view names include `left-profile`, `right-profile`, `front`, `rear`, `three-quarter-left`, and `three-quarter-right`. If the view changes during an action, use a directional name such as `three-quarter-to-front`.
