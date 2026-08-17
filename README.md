# Fluffball

[中文](#中文) · [English](#english) · [素材目录说明 / Asset catalog](Assets/README.md) · [AI 视频参考图 / AI video references](Assets/SourceImagesForAIVideo/README.md) · [Agent 规范 / Agent guide](AGENTS.md)

## 中文

Fluffball 是一个仅面向 Apple Silicon、macOS 14 及以上版本的双模式桌面宠物项目。当前 macOS 应用产品名仍为 **Furball2D**。同一套行为引擎既能通过 AVFoundation/VideoToolbox 播放带 Alpha 的写实视频，也能用 Codex 兼容的透明 WebP 图集、透明 PNG 回退素材和 Metal 运行，不再要求每只宠物都先生成昂贵的视频。

### 功能

- 狗狗会睡觉、醒来、站立、坐下和趴下，并在无人互动时自行休息。
- 根据姿态随机显示可爱对话；气泡会按宠物大小缩放、跟随动作，并依据当前图片或视频的 Alpha 轮廓自动避开身体。
- 菜单中的“语言 / Language”可即时切换简体中文或 English，并记住选择。
- 宠物大小支持 60%–140% 无级调节。
- 菜单顶层的“视频动画（更细腻）”可在视频与图片动画之间一键切换；双模式素材包默认开启视频，纯图片素材包会自动使用图片模式并将该开关置灰。
- 图片模式优先读取 8×11、每格 192×208 的 Codex v2 透明 WebP 图集，以可变逐帧时长播放真实步态、眨眼、挥爪、跳跃、期待、寻找、检查和委屈等动作；旧的 960×540 PNG 序列只作为兼容回退。运行时不抠像、不解码视频。
- 透明区域自动穿透鼠标，也可开启完全穿透。
- 通过五阶淡化曲线、主体高度/中心/脚底三重端口对齐和无缝待机循环改善动作衔接。
- 不同生成批次会在离线导出时统一到站立基准的黑毛、棕毛和白毛色彩锚点，避免走路、跑步或转向时突然变暖、变亮。
- 狗狗会使用真实走路、慢跑和快跑素材在桌面全方向移动；开启“追随鼠标”后会依据二维距离与鼠标速度自动换挡。
- “自由漫游”会在当前桌面的安全范围内随机选择二维目标，走到后停留片刻，再继续探索。
- 不依赖 AI 视频的视线跟随使用 16 个等距方向（每 22.5° 一格）；眼睛先动，头颈、耳朵和胸毛随后跟进，站立待机时会沿最短相邻路径看向鼠标，不跨方向瞬移。
- 图片模式的“可爱动作”子菜单由素材包声明；当前包含挥爪、开心跳、委屈、期待、认真寻找和仔细检查，后续宠物可以只改 `manifest.json` 添加或改名，无需修改 Swift。
- 鼠标移动时，图片宠物按相邻格逐步看向 16 个方向；鼠标静止约 2.4 秒后自动回到会呼吸、眨眼的动态待机。标记为 `autonomous` 的可爱动作会自然穿插在休息流程中，然后宠物继续坐下、睡觉或出门巡逻。
- 左侧面的动作视频可在运行时镜像为右侧动作，因此自主待机、摇尾巴、姿态过渡和睡眠都能保持选定的左右朝向。
- 运行时通过 Pet Pack 标准动作 ID 读取素材，文件路径和循环属性不再硬编码；同规格的狗狗或猫猫素材包可复用同一行为引擎。

### 运行与构建

要求：Apple Silicon、macOS 14+、Swift 6 Command Line Tools，以及支持 `hevc_videotoolbox` 的 FFmpeg 8。

```bash
./Scripts/build-assets.sh
./Scripts/package-app.sh
open dist/Furball2D.app
```

打包结果位于：

```text
dist/Furball2D.app
dist/Furball2D.zip
```

应用图标源文件保存在 `Support/AppIcon.png`。需要替换图标时，放入新的正方形图片并运行 `./Scripts/build-app-icon.sh`；打包脚本会将生成的多尺寸 `AppIcon.icns` 写入应用包。

当前安装包同时包含 27 段 960×540、24 fps 的 HEVC with Alpha 视频、一个 1536×2288 的无损透明 WebP 图集，以及 17 张兼容回退 PNG，因此可现场比较两种模式。纯图片 Pet Pack 可以完全省略 `Clips/`，体积会显著下降。图集只解码一次，运行时按单元格缓存纹理；当前快速行为压力测试约 106–119 MB RSS，没有持续增长。应用图标源图为用户提供的 800×800，`.icns` 包含 macOS 要求的 16–1024 px 层级。

通用宠物素材包的双模式合同、27 个语义槽位和当前实现边界记录在 [Pet Pack v2 规范](Docs/PET_PACK_STANDARD.md)。可用 `./Scripts/validate-pet-pack.swift Sources/Furball2D/Assets` 同时验收能力声明、PNG 画布/Alpha、视频格式和动作完整性。

### 素材结构

```text
Assets/
├── ImageTurnMVP/                    # 纯图片转身的 9 张对齐透明关键帧
├── ImageMode/qa/                    # 图片模式接触表与视觉验收产物
├── SpritePets/Furball/              # Codex v2 图集的生成记录与 QA
├── SourceImagesForAIVideo/          # 图生视频用的身份、姿态与视角参考图
│   ├── originals/
│   └── generation-ready/
└── SourceVideos/                    # 原始绿幕视频，按视角与动作命名
    ├── left-profile/
    ├── three-quarter-to-front/
    └── archive/exact-duplicates/

Sources/Furball2D/Assets/
├── Sprites/Furball/spritesheet.webp # 图片模式优先使用的 8×11 透明图集
├── Images/{stand,sit,lie,sleep}/    # 图片模式直接读取的透明 PNG
├── Clips/image-views/               # 9 个图片视角的 HEVC with Alpha 循环
├── Clips/left-profile/              # 导出的动作 HEVC with Alpha 视频
└── manifest.json                    # 能力、图片动作、视频动作与循环属性
```

源动作链统一使用 `left-profile` 视角，右向动作由运行时镜像得到。素材预处理输出为 960×540、24 fps、HEVC with Alpha。站立、坐姿和趴卧待机使用首尾去重的正放/倒放循环；睡眠只截取低动作呼吸窗口；过渡和移动片段会在透明工作画布上平滑校正主体尺度、Alpha 中心与脚底锚点。

完整旧文件名映射、备用素材与重复文件说明见 [Assets/README.md](Assets/README.md)。生成新动作时优先使用 [generation-ready 参考图说明](Assets/SourceImagesForAIVideo/README.md)，后续 Agent 在替换视频前必须阅读 [AGENTS.md](AGENTS.md)。

### 交互

- 单击狗狗：说一句话并进入下一合法动作。
- 拖拽狗狗：移动桌宠。
- 右键狗狗或点击菜单栏爪印：打开设置。
- “宠物大小”：连续调节 60%–140%。
- “视频动画（更细腻）”：有图片和视频两套素材时默认开启；关闭后立即切换到图集图片动画。只有一种模式时显示当前状态但不可切换。
- “可爱动作”：图片模式下显示素材包自带动作；视频模式、移动中或过渡中自动置灰。
- “语言 / Language”：选择简体中文或 English。
- “现在去睡觉”：立即走完合法姿态链并睡觉。
- “转过来看看我”：先站起，再用静态图片关键帧转向正面和右侧，最后回到侧面待机。
- “跟随鼠标看向 16 个方向”：站立待机时同时使用鼠标的横向和纵向位置，每次只走一个相邻方向；进入走跑动作前再沿最短路径抵达对应左右侧面端口。
- “追随鼠标（全方向走 / 跑）”：让狗狗沿二维方向追随鼠标，近距离走路、中距离慢跑、远距离或快速移动时快跑。
- “自由漫游（全桌面）”：持续在当前桌面内随机走动；与“追随鼠标”互斥，关闭后恢复原先的自动作息。
- “自动作息（睡觉 / 巡游）”：无人互动时自行睡觉、醒来和进行一次短巡游；自由漫游期间会暂时挂起。
- “柔和动作过渡”：启用或关闭短 Crossfade，方便比较动作边界。

无人互动约 12 秒后，狗狗会依次坐下、趴下并睡觉；睡一段时间后会偶尔自己醒来观察四周，然后再次休息。

### 图片动画模式

图片模式不是把 PNG 再编码成一秒视频。`PetImageAnimator` 支持两种帧源：Codex v2 图集单元格和旧版独立 PNG。图集由 `manifest.json` 声明行、帧数、每帧时长、循环、短溶解比例、左右真实步态、27 个语义绑定、16 个方向以及双语自定义动作。运行时一次解码 WebP，将使用到的格子铺到统一 16:9 小画布并缓存 Metal 纹理；真实走跑行不再叠加程序化 squash/stretch，桌面位移只保留 0.14 秒速度渐入。

当前图集遵循 Codex `spriteVersionNumber: 2` 合同：1536×2288、8 列×11 行、192×208 单元格；前 9 行是 idle / running-right / running-left / waving / jumping / failed / waiting / working / review，最后两行是 16 个视线方向。坐、趴、睡和醒通过同画风动作绑定完成，旧 PNG 只用于未绑定语义的兼容路径。素材包可以完全不带视频；如果只有图片表示，顶层视频开关会保持关闭并置灰。

### 移动素材

走路、慢跑和快跑原片分别保存为 `stand-to-walk-to-stand.mp4`、`stand-to-slow-run-to-stand.mp4` 和 `stand-to-fast-run-to-stand.mp4`。构建脚本会从每段原片导出起步、相位闭合循环和停步三部分，并让三段连接处落在同一尺度、中心和脚底基线上；方向性步态不会倒放。运行时速度档位需要短暂稳定后才切换。首次起步时，桌面位移会等待素材里的第一步真正开始，再用平滑曲线加速，避免站立帧在地面滑动。

---

## English

Fluffball is a dual-mode desktop pet for Apple Silicon Macs running macOS 14 or later. The current macOS app product is still named **Furball2D**. One behavior engine can render detailed HEVC-with-alpha footage through AVFoundation/VideoToolbox or run Codex-compatible transparent WebP atlases with transparent-PNG fallback through Metal, so every pet no longer needs an expensive generated-video set.

### Features

- Natural sleep, wake, stand, sit, and lie-down behavior, including autonomous rest when the pet is idle.
- Posture-aware cute dialogue; the speech bubble scales with the pet, follows its motion, and avoids the active image or video alpha silhouette.
- Runtime Simplified Chinese or English selection under “语言 / Language”, persisted between launches.
- Continuous pet sizing from 60% to 140%.
- A top-level “Video Animations (More Detailed)” switch changes between video and image animation. Dual-mode packs default to video; image-only packs force image mode and gray out the switch.
- Image mode prefers an 8×11 Codex v2 transparent WebP atlas with variable frame durations and real gait phases, blink, wave, jump, hopeful wait, search, review, and disappointed actions. Legacy 960×540 PNG sequences remain a compatibility fallback. There is no runtime keying or video decoding.
- Alpha-aware mouse click-through, with an optional full pass-through mode.
- Smoother action changes using a fifth-order fade curve, subject-height/center/ground port alignment, and seamless idle loops.
- Offline black/tan/white fur anchor matching keeps separate generation batches from becoming abruptly warmer or brighter during locomotion and view changes.
- Real walk, jog, and run footage moves the pet in any desktop direction. Cursor-follow mode selects a gait from two-dimensional distance and cursor speed.
- Free Roam chooses safe two-dimensional destinations across the current desktop, pauses briefly after each arrival, and then continues exploring.
- Cursor gaze uses 16 evenly spaced directions at 22.5° intervals. Eyes lead, then the head, neck, ears, and ruff follow; the idle pet walks the shortest adjacent-direction path instead of snapping across the circle.
- A manifest-driven “Cute Actions” submenu currently exposes Wave, Happy Jump, A Little Sad, Wait Hopefully, Search Carefully, and Inspect Closely. A custom pack can add or rename actions without changing Swift.
- While the pointer moves, the image pet steps through adjacent cells across 16 gaze directions. After roughly 2.4 seconds of stillness it returns to a breathing/blinking idle. Gestures marked `autonomous` naturally appear in the rest routine before the pet sits, sleeps, or later patrols.
- Runtime mirroring gives the left-profile footage a right-facing counterpart, so autonomous idles, tail wags, posture transitions, and sleep retain the selected side.
- Runtime resolves assets by Pet Pack semantic action IDs, so paths and loop behavior are no longer hardcoded. Conforming dog and cat packs can reuse one behavior engine.

### Build and run

Requirements: Apple Silicon, macOS 14 or later, Swift 6 Command Line Tools, and FFmpeg 8 with `hevc_videotoolbox` support.

```bash
./Scripts/build-assets.sh
./Scripts/package-app.sh
open dist/Furball2D.app
```

Packaged outputs are written to:

```text
dist/Furball2D.app
dist/Furball2D.zip
```

The app-icon source is stored at `Support/AppIcon.png`. To replace it, provide another square image and run `./Scripts/build-app-icon.sh`; the packaging script embeds the generated multi-resolution `AppIcon.icns` in the app bundle.

The current package includes 27 HEVC-with-alpha clips at 960×540/24 fps, one lossless 1536×2288 transparent WebP atlas, and 17 compatibility PNGs so both renderers can be compared. An image-only Pet Pack may omit `Clips/` entirely and is substantially smaller. The atlas decodes once and caches cells on demand; the fast behavior stress run stayed around 106–119 MB RSS without sustained growth. The user-provided app-icon source is 800×800, and the `.icns` contains macOS 16–1024 px representations.

See the [Pet Pack v2 specification](Docs/PET_PACK_STANDARD.md) for the dual-mode contract, 27 semantic slots, and current implementation boundaries. Run `./Scripts/validate-pet-pack.swift Sources/Furball2D/Assets` to validate capability declarations, PNG canvas/alpha, video format, and action completeness.

### Asset layout

```text
Assets/
├── ImageTurnMVP/                    # Nine aligned transparent keyframes for the image-only turn
├── ImageMode/qa/                    # Image-mode contact sheet and visual QA artifact
├── SpritePets/Furball/              # Codex v2 atlas generation and QA records
├── SourceImagesForAIVideo/          # Identity, posture, and view references for image-to-video generation
│   ├── originals/
│   └── generation-ready/
└── SourceVideos/                    # Original green-screen videos, named by view and action
    ├── left-profile/
    ├── three-quarter-to-front/
    └── archive/exact-duplicates/

Sources/Furball2D/Assets/
├── Sprites/Furball/spritesheet.webp # Preferred 8×11 transparent image-mode atlas
├── Images/{stand,sit,lie,sleep}/    # Transparent PNGs consumed directly by image mode
├── Clips/image-views/               # Nine HEVC-with-alpha image-view loops
├── Clips/left-profile/              # Exported HEVC-with-alpha action clips
└── manifest.json                    # Capabilities plus image/video action metadata
```

The source action chain uses a consistent `left-profile` view; right-facing actions are produced by runtime mirroring. Preprocessed assets are 960×540 at 24 fps in HEVC with Alpha. Stand, sit, and lie idles use endpoint-deduplicated forward/reverse loops. Sleep uses only a low-motion breathing window. Transition and locomotion clips are smoothly corrected on a transparent work canvas for subject scale, alpha center, and ground anchor.

See [Assets/README.md](Assets/README.md) for legacy filename mappings, alternate footage, and duplicate records. When generating new actions, start with the [generation-ready reference guide](Assets/SourceImagesForAIVideo/README.md). Any Agent replacing video assets must first read [AGENTS.md](AGENTS.md).

### Interaction

- Click the dog: say a line and advance to the next legal action.
- Drag the dog: reposition the desktop pet.
- Right-click the dog or click the menu-bar paw: open settings.
- “Pet Size”: continuously adjust the pet from 60% to 140%.
- “Video Animations (More Detailed)”: defaults on when both representations exist; turn it off to use sprite-atlas image animation. Packs with only one representation show the current state but cannot switch.
- “Cute Actions”: shows pack-provided image actions in image mode and disables itself in video mode, while moving, or during a transition.
- “语言 / Language”: choose Simplified Chinese or English.
- “Sleep Now”: traverse the legal posture chain and go to sleep.
- “Look at Me”: stand up, turn through the front and right-side image keyframes, then return to a profile idle.
- “Look Toward Cursor (16 Directions)”: use both cursor axes while standing idle and advance one neighboring direction at a time; before locomotion, take the shortest path to the matching left or right profile port.
- “Follow Cursor (Move in Any Direction)”: follow the cursor in two dimensions, walking nearby, jogging at medium demand, and running when far away or when the cursor moves quickly.
- “Free Roam (Across Desktop)”: continuously visit random destinations on the current desktop. It is mutually exclusive with cursor following; disabling it restores the previous daily routine.
- “Daily Routine (Sleep / Patrol)”: sleep, wake, and take a short outing while idle. This routine is suspended during Free Roam.
- “Smooth Action Transitions”: enable or disable the short crossfade to compare action boundaries.

After roughly 12 seconds without interaction, the dog sits, lies down, and sleeps. After resting, it occasionally wakes up, looks around, and later settles down again.

### Image animation mode

Image mode does not re-encode PNGs as one-second videos. `PetImageAnimator` accepts Codex v2 atlas cells and legacy standalone PNGs. `manifest.json` declares rows, frame counts, per-frame durations, loops, short blend fractions, true left/right gait rows, all 27 semantic bindings, 16 look directions, and localized custom actions. The runtime decodes the WebP once, places requested cells on a shared 16:9 render canvas, and caches Metal textures. Real gait rows no longer receive procedural squash/stretch; desktop translation retains only the 0.14-second image-mode acceleration ramp.

The built-in atlas follows the Codex `spriteVersionNumber: 2` contract: 1536×2288, 8 columns × 11 rows, and 192×208 cells. The first nine rows are idle, running-right, running-left, waving, jumping, failed, waiting, working, and review. The final two rows contain all 16 gaze directions. Sit, lie, sleep, and wake behavior are mapped to the same visual family; old PNGs remain only for unbound compatibility paths. An image-only pack can omit video entirely, in which case the top-level video switch stays off and disabled.

### Locomotion footage

The walk, jog, and run sources are stored as `stand-to-walk-to-stand.mp4`, `stand-to-slow-run-to-stand.mp4`, and `stand-to-fast-run-to-stand.mp4`. The build script exports start, phase-closed loop, and stop segments from each source and aligns every junction to the same scale, center, and ground baseline. Directional gaits are never reversed. At runtime, a requested speed tier must remain stable briefly before switching. On a fresh start, desktop translation waits for the first real step in the source and then accelerates along a smooth curve, preventing stationary frames from sliding across the floor.
