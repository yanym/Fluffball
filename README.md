# Furball

一个仅面向 Apple Silicon、macOS 14 及以上版本的写实视频桌面宠物。应用产品名目前为 **Furball2D**，使用透明 `NSPanel`、AVFoundation/VideoToolbox 与 Metal，在桌面上播放带 Alpha 的宠物动作视频。

[English](#english) · [素材目录说明](Assets/README.md) · [AI 视频生成参考图](Assets/SourceImagesForAIVideo/README.md) · [Agent 素材处理规范](AGENTS.md)

## 功能

- 狗狗会睡觉、醒来、站立、坐下和趴下，并在无人互动时自行休息。
- 根据姿态随机显示可爱对话；点击狗狗或菜单中的“让它说句话”可立即触发。
- 菜单中的“语言 / Language”可即时切换简体中文或 English，并记住选择。
- 宠物大小支持 60%–140% 无级调节。
- 透明区域自动穿透鼠标，也可开启完全穿透。
- 通过短时双通道 Crossfade、端口对齐和无缝待机循环改善动作衔接。
- 如果加入合格的侧视步态循环，狗狗可以自动巡视桌面。

## 运行与构建

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

## 素材结构

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

主动作链统一使用 `left-profile` 视角。素材预处理输出为 960×540、24 fps、HEVC with Alpha。站立、坐姿和趴卧待机使用首尾去重的正放/倒放循环；睡眠只截取低动作呼吸窗口；睡醒起身片段会以脚底为锚点修正原片约 6% 的推近变化。

完整旧文件名映射、备用素材与重复文件说明见 [Assets/README.md](Assets/README.md)。生成新动作时优先使用 [generation-ready 参考图说明](Assets/SourceImagesForAIVideo/README.md)，后续 Agent 在替换视频前必须阅读 [AGENTS.md](AGENTS.md)。

## 交互

- 单击狗狗：说一句话并进入下一合法动作。
- 拖拽狗狗：移动桌宠。
- 右键狗狗或点击菜单栏爪印：打开设置。
- “宠物大小”：连续调节 60%–140%。
- “语言 / Language”：选择简体中文或 English。
- “现在去睡觉”：立即走完合法姿态链并睡觉。
- “柔和动作过渡（MVP）”：启用或关闭短 Crossfade，方便 A/B 对比。

无人互动约 12 秒后，狗狗会依次坐下、趴下并睡觉；睡一段时间后会偶尔自己醒来观察四周，然后再次休息。

### 可选走路素材

将侧视原地步态循环放到：

```text
Assets/SourceVideos/left-profile/walk-idle.mp4
```

然后重新运行构建和打包脚本。素材需要固定机位、纯绿背景、与现有狗尺度一致，且首尾为同一只脚的相同触地相位。不要使用静止站姿在桌面上滑行，也不要倒放有明确方向性的步态。

## English

Furball is a realistic video-based desktop pet for Apple Silicon Macs running macOS 14 or later. The current app product is named **Furball2D**. It renders HEVC-with-alpha pet clips in a transparent desktop window using AVFoundation, VideoToolbox, and Metal.

Highlights:

- Natural sleep, wake, stand, sit, and lie-down behavior.
- Posture-aware speech bubbles with both Chinese and English copy.
- Runtime language selection under “语言 / Language”, persisted across launches.
- Continuous 60%–140% size control and alpha-aware mouse hit testing.
- Short dual-channel crossfades and prepared seamless idle loops.
- Optional desktop patrol when a valid left-profile walking loop is provided.

Build and run:

```bash
./Scripts/build-assets.sh
./Scripts/package-app.sh
open dist/Furball2D.app
```

See [Assets/README.md](Assets/README.md) for the asset catalog, [the AI video reference guide](Assets/SourceImagesForAIVideo/README.md) for image-to-video inputs, and [AGENTS.md](AGENTS.md) for the mandatory video-processing workflow.
