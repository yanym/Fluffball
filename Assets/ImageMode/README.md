# Furball 图片动画素材 / Furball Image Animation Assets

[中文](#中文) · [English](#english)

## 中文

这个目录保存图片模式的 QA 产物；应用实际读取的文件在 `Sources/Furball2D/Assets/Images/`。当前素材完全由静态图片组成，运行时不需要 AI 视频、绿幕或视频解码。

来源与构建：

- `stand/`：复制 `Assets/ImageTurnMVP/normalized/` 的 9 张透明视角图。
- `sit/`、`lie/`、`sleep/`：从 `Assets/SourceImagesForAIVideo/generation-ready/` 的姿态图离线抠像并归一到 960×540。
- `Scripts/build-image-assets.sh`：可重复构建上述 17 张运行时 PNG。
- `qa/contact-sheet.png`：检查身份、左右视角、主体尺度、脚底基线和透明边缘。

动作不是写在图片里，而是在 `manifest.json.imageAnimations` 中声明。`PetImageAnimator` 对单张图片加入克制的呼吸、睡眠起伏、弹性过渡和速度相关的移动节奏；多角度转头使用有序图片序列。可选 blink / wave 等额外帧只有在身份与端口验收通过后才能加入，缺少时必须自然降级，不得使用换脸或尺寸漂移的生成结果。

## English

This directory stores image-mode QA artifacts. Runtime files live under `Sources/Furball2D/Assets/Images/`. The current representation consists entirely of still images and needs no AI video, green screen, or video decoding at runtime.

Sources and build flow:

- `stand/`: copies the nine transparent normalized views under `Assets/ImageTurnMVP/normalized/`.
- `sit/`, `lie/`, and `sleep/`: keys the pose references under `Assets/SourceImagesForAIVideo/generation-ready/` and normalizes them to 960×540.
- `Scripts/build-image-assets.sh`: deterministically rebuilds all 17 runtime PNGs.
- `qa/contact-sheet.png`: reviews identity, left/right views, subject scale, ground baseline, and transparent edges.

Motion is declared in `manifest.json.imageAnimations`, not baked into the PNGs. `PetImageAnimator` adds restrained breathing, quiet sleep motion, springy transitions, and speed-specific locomotion rhythm to single images; ordered image sequences drive multi-angle looking. Optional blink or wave frames may be added only after identity and port QA. Missing optional frames must degrade gracefully rather than installing a generated result with identity or scale drift.
