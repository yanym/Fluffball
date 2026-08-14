# Fluffball

[中文](#中文) · [English](#english) · [素材目录说明 / Asset catalog](Assets/README.md) · [AI 视频参考图 / AI video references](Assets/SourceImagesForAIVideo/README.md) · [Agent 规范 / Agent guide](AGENTS.md)

## 中文

Fluffball 是一个仅面向 Apple Silicon、macOS 14 及以上版本的写实视频桌面宠物项目。当前 macOS 应用产品名仍为 **Furball2D**，使用透明 `NSPanel`、AVFoundation/VideoToolbox 与 Metal，在桌面上播放带 Alpha 的宠物动作视频。

### 功能

- 狗狗会睡觉、醒来、站立、坐下和趴下，并在无人互动时自行休息。
- 根据姿态随机显示可爱对话；气泡会按宠物大小缩放、跟随动作，并依据视频 Alpha 轮廓自动避开身体。
- 菜单中的“语言 / Language”可即时切换简体中文或 English，并记住选择。
- 宠物大小支持 60%–140% 无级调节。
- 透明区域自动穿透鼠标，也可开启完全穿透。
- 通过五阶淡化曲线、主体高度/中心/脚底三重端口对齐和无缝待机循环改善动作衔接。
- 狗狗会使用真实走路、慢跑和快跑素材在桌面移动；开启“跟随鼠标”后会依据距离与鼠标速度自动换挡。

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

### 素材结构

```text
Assets/
├── SourceImagesForAIVideo/          # 图生视频用的身份、姿态与视角参考图
│   ├── originals/
│   └── generation-ready/
└── SourceVideos/                    # 原始绿幕视频，按视角与动作命名
    ├── left-profile/
    ├── three-quarter-to-front/
    └── archive/exact-duplicates/

Sources/Furball2D/Assets/
├── Clips/left-profile/              # 导出的 HEVC with Alpha 视频
└── manifest.json                    # 动作、视角、源文件与循环属性
```

主动作链统一使用 `left-profile` 视角。素材预处理输出为 960×540、24 fps、HEVC with Alpha。站立、坐姿和趴卧待机使用首尾去重的正放/倒放循环；睡眠只截取低动作呼吸窗口；过渡和移动片段会在透明工作画布上平滑校正主体尺度、Alpha 中心与脚底锚点。

完整旧文件名映射、备用素材与重复文件说明见 [Assets/README.md](Assets/README.md)。生成新动作时优先使用 [generation-ready 参考图说明](Assets/SourceImagesForAIVideo/README.md)，后续 Agent 在替换视频前必须阅读 [AGENTS.md](AGENTS.md)。

### 交互

- 单击狗狗：说一句话并进入下一合法动作。
- 拖拽狗狗：移动桌宠。
- 右键狗狗或点击菜单栏爪印：打开设置。
- “宠物大小”：连续调节 60%–140%。
- “语言 / Language”：选择简体中文或 English。
- “现在去睡觉”：立即走完合法姿态链并睡觉。
- “跟随鼠标（按速度走 / 跑）”：让狗狗沿桌面追随鼠标，近距离走路、中距离慢跑、远距离或快速移动时快跑。
- “柔和动作过渡（MVP）”：启用或关闭短 Crossfade，方便 A/B 对比。

无人互动约 12 秒后，狗狗会依次坐下、趴下并睡觉；睡一段时间后会偶尔自己醒来观察四周，然后再次休息。

### 移动素材

走路、慢跑和快跑原片分别保存为 `stand-to-walk-to-stand.mp4`、`stand-to-slow-run-to-stand.mp4` 和 `stand-to-fast-run-to-stand.mp4`。构建脚本会从每段原片导出起步、相位闭合循环和停步三部分，并让三段连接处落在同一尺度、中心和脚底基线上；方向性步态不会倒放。运行时速度档位需要短暂稳定后才切换，避免鼠标速度在阈值附近造成频繁转场。

---

## English

Fluffball is a realistic, video-based desktop pet project for Apple Silicon Macs running macOS 14 or later. The current macOS app product is still named **Furball2D**. It renders HEVC-with-alpha pet animations in a transparent `NSPanel` using AVFoundation/VideoToolbox and Metal.

### Features

- Natural sleep, wake, stand, sit, and lie-down behavior, including autonomous rest when the pet is idle.
- Posture-aware cute dialogue; the speech bubble scales with the pet, follows its motion, and avoids the live video alpha silhouette.
- Runtime Simplified Chinese or English selection under “语言 / Language”, persisted between launches.
- Continuous pet sizing from 60% to 140%.
- Alpha-aware mouse click-through, with an optional full pass-through mode.
- Smoother action changes using a fifth-order fade curve, subject-height/center/ground port alignment, and seamless idle loops.
- Real walk, jog, and run footage moves the pet across the desktop. Cursor-follow mode selects a gait from cursor speed and distance.

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

### Asset layout

```text
Assets/
├── SourceImagesForAIVideo/          # Identity, posture, and view references for image-to-video generation
│   ├── originals/
│   └── generation-ready/
└── SourceVideos/                    # Original green-screen videos, named by view and action
    ├── left-profile/
    ├── three-quarter-to-front/
    └── archive/exact-duplicates/

Sources/Furball2D/Assets/
├── Clips/left-profile/              # Exported HEVC-with-alpha runtime clips
└── manifest.json                    # Action, view, source, and loop metadata
```

The main action chain uses a consistent `left-profile` view. Preprocessed assets are 960×540 at 24 fps in HEVC with Alpha. Stand, sit, and lie idles use endpoint-deduplicated forward/reverse loops. Sleep uses only a low-motion breathing window. Transition and locomotion clips are smoothly corrected on a transparent work canvas for subject scale, alpha center, and ground anchor.

See [Assets/README.md](Assets/README.md) for legacy filename mappings, alternate footage, and duplicate records. When generating new actions, start with the [generation-ready reference guide](Assets/SourceImagesForAIVideo/README.md). Any Agent replacing video assets must first read [AGENTS.md](AGENTS.md).

### Interaction

- Click the dog: say a line and advance to the next legal action.
- Drag the dog: reposition the desktop pet.
- Right-click the dog or click the menu-bar paw: open settings.
- “Pet Size”: continuously adjust the pet from 60% to 140%.
- “语言 / Language”: choose Simplified Chinese or English.
- “Sleep Now”: traverse the legal posture chain and go to sleep.
- “Follow Cursor (Walk / Run)”: follow the cursor horizontally, walking nearby, jogging at medium demand, and running when far away or when the cursor moves quickly.
- “Soft Action Transitions (MVP)”: enable or disable the short crossfade for A/B comparison.

After roughly 12 seconds without interaction, the dog sits, lies down, and sleeps. After resting, it occasionally wakes up, looks around, and later settles down again.

### Locomotion footage

The walk, jog, and run sources are stored as `stand-to-walk-to-stand.mp4`, `stand-to-slow-run-to-stand.mp4`, and `stand-to-fast-run-to-stand.mp4`. The build script exports start, phase-closed loop, and stop segments from each source and aligns every junction to the same scale, center, and ground baseline. Directional gaits are never reversed. At runtime, a requested speed tier must remain stable briefly before switching, which prevents repeated transitions near a cursor-speed threshold.
