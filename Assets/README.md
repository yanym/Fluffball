# Furball 视频素材目录

所有原始视频按 `视角/动作` 组织，目录与文件名统一使用小写英文和 kebab-case。运行时使用的透明导出视频也保持相同的视角层级，避免未来加入正面、右侧面或背面动作时混用。

`SourceImagesForAIVideo/` 是另一类资产：它保存生成 AI 视频时使用的狗狗身份、姿态和视角参考图，不会进入应用包。具体目录和选图规则见 [SourceImagesForAIVideo/README.md](SourceImagesForAIVideo/README.md)。

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

`Sources/Furball2D/Assets/Clips/left-profile/` 包含应用实际播放的 17 段 HEVC with Alpha 视频：

| 文件 | 类型 | 来源 |
|---|---|---|
| `stand-idle.mov` | 无缝待机循环 | `stand-idle.mp4` |
| `stand-to-sit.mov` | 单次过渡 | `stand-to-sit.mp4` |
| `sit-idle.mov` | 无缝待机循环 | `sit-to-lie.mp4` 的稳定开头 |
| `sit-to-lie.mov` | 单次过渡 | `sit-to-lie.mp4` |
| `lie-idle.mov` | 无缝待机循环 | `lie-to-sleep.mp4` 的稳定开头 |
| `lie-to-sleep.mov` | 单次过渡 | `lie-to-sleep.mp4` |
| `sleep-idle.mov` | 低动作呼吸循环 | `sleep-idle.mp4` 的 0.55 秒稳定窗口 |
| `sleep-to-stand.mov` | 单次过渡并校正尺度 | `sleep-to-stand.mp4` |
| `walk-start/loop/stop.mov` | 走路起步、相位闭合循环、停步 | `stand-to-walk-to-stand.mp4` |
| `slow-run-start/loop/stop.mov` | 慢跑起步、相位闭合循环、停步 | `stand-to-slow-run-to-stand.mp4` |
| `fast-run-start/loop/stop.mov` | 快跑起步、相位闭合循环、停步 | `stand-to-fast-run-to-stand.mp4` |

这些导出文件可以由 `Scripts/build-assets.sh` 完整重建。移动素材按各自绿幕颜色抠像，统一缩放至现有站姿尺度；循环段使用相同落脚相位且不倒放。切点、循环策略和画布参数记录在脚本与 `Sources/Furball2D/Assets/manifest.json` 中。

## 新素材命名规则

```text
Assets/SourceVideos/<view>/<action>.mp4
Sources/Furball2D/Assets/Clips/<view>/<action>.mov
```

建议视角名：`left-profile`、`right-profile`、`front`、`rear`、`three-quarter-left`、`three-quarter-right`。如果动作过程中视角发生改变，使用 `three-quarter-to-front` 这类方向明确的目录名。
