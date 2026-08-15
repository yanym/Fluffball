# Furball Pet Pack v1 / Furball 宠物素材包 v1

[中文](#中文) · [English](#english)

## 中文

### 目标

Pet Pack 把“这是哪只动物”与“应用如何行为”完全分开。用户只提供身份照片并确认一次标准身份板；后续的视角生成、动作生成、抠像、颜色、尺寸、脚底锚点、循环和验收由离线生产工具处理。应用只读取统一的动作 ID，因此狗、猫或其他四足宠物不需要各写一套 Swift 状态机。

### 用户最小输入

1. 6–12 张清晰原始照片：正面、左/右侧面、左/右 3/4，以及一张能看清全身比例和尾巴的照片。
2. 宠物名称与种类：`dog`、`cat` 或 `other`。
3. 用户只需确认一张“标准身份板”，检查脸型、耳朵、花纹、毛色、尾巴和体型。身份板未通过前不进入视频阶段，避免将错误放大到几十段动作。

绿幕不应该是用户必须理解的输入。生成器可以输出固定绿幕、纯色背景或原生 Alpha；只要生产适配器能生成同一组透明标准片段，应用层无需知道上游模型。

### 标准生产流程

1. **输入质检**：检测清晰度、遮挡、视角覆盖、过度滤镜和多只动物。
2. **身份建模**：保留原图，生成统一的正面/侧面/花纹身份板，并记录毛色锚点。
3. **标准视角与姿态**：生成 9 个站立视角，以及 stand / sit / lie / sleep 稳定姿态。所有结果使用同一相机、主体尺度和地面基线。
4. **动作生成适配器**：不同 AI 提供商使用同一组输入/输出约定。每次生成必须包含标准进入姿态、主动作和标准离开姿态。
5. **自动编译**：进行时间切分、Alpha 抠像、去色边、逐帧跟踪、尺度/中心/脚底归一、毛色匹配、起步延迟检测和循环相位搜索。
6. **自动验收与重试**：身份相似度、突变、端口偏差、循环缝、透明边缘或颜色超标时拒收；生成型问题回到上游重试，不用长 Crossfade 隐藏。
7. **导出**：只有通过验收的运行时素材才进入 `.furballpet` 包。

### Pet Pack v1 运行时合同

- 统一规格：960×540、24 fps、HEVC with Alpha、`hvc1`、无音轨。
- 统一动作语义：17 个姿态/移动片段、9 个站立视角循环和 1 个完整转身演示，共 27 个必需槽位。
- 统一姿态端口：`stand`、`sit`、`lie`、`sleep`。
- 统一跟踪端口：主体高度、Alpha 加权中心 x 和接地 y。
- 统一色彩端口：黑毛、棕毛和浅色毛锚点，背景不参与统计。
- 行为层只依赖 `manifest.json` 中的标准 ID，不依赖文件名、动物种类或生成提供商。

```text
MyPet.furballpet/
├── manifest.json
└── Clips/
    ├── left-profile/
    │   ├── stand-idle.mov
    │   ├── walk-start.mov
    │   └── ...
    └── image-views/
        ├── left-profile.mov
        └── ...
```

开发源图、绿幕视频和生成记录应保留在独立的源素材工程中，不放入给普通用户的 `.furballpet` 包。

### 当前已落地的部分

- 应用现在会按标准动作 ID 从 `manifest.json` 解析实际文件路径和循环属性。
- `FURBALL_PET_PACK=/absolute/path/MyPet.furballpet` 可在不重新编译的情况下运行一个外部包，适合制作和测试工具。
- `Scripts/validate-pet-pack.swift <pack>` 会检查清单、27 个必需动作、路径安全、循环语义、分辨率、帧率、编码、音轨和透明像素。

这是通用宠物的底层合同，但还不是完整的普通用户生产器。下一阶段是在 App 中加入 Pet Pack 导入/切换菜单，并将身份板生成、AI 提供商适配器、自动重试和 QA 报告组成独立制作向导。在视频 AI 仍会偶发换脸或改变花纹的情况下，“身份板一次确认”不应被取消。

---

## English

### Goal

A Pet Pack separates animal identity from application behavior. The user supplies identity photos and approves one canonical identity board. View generation, motion generation, keying, color, scale, ground anchoring, loops, and validation belong to an offline production tool. The app consumes semantic action IDs, so dogs, cats, and other quadrupeds share one Swift behavior graph.

### Minimum user input

1. Six to twelve clear originals covering front, both profiles, both three-quarter views, and one full-body image that shows proportions and tail.
2. A pet name and `dog`, `cat`, or `other` species metadata.
3. One approval of a canonical identity board covering face, ears, markings, coat, tail, and proportions. Motion generation does not begin before this gate passes.

Green screen is an implementation detail, not a user requirement. A provider may emit fixed chroma, a clean solid background, or native alpha. Provider adapters must converge on the same transparent runtime clips.

### Standard production flow

1. **Intake QA:** score sharpness, occlusion, view coverage, heavy filters, and multiple animals.
2. **Identity model:** preserve originals, build a canonical front/profile/marking board, and record coat-color anchors.
3. **Canonical views and postures:** produce nine standing views plus stable stand, sit, lie, and sleep ports with one camera, scale, and ground baseline.
4. **Motion provider adapters:** every provider follows the same entry-pose, action, and exit-pose contract.
5. **Automated compilation:** segment time, extract alpha, despill, track, normalize scale/center/ground, match coat color, detect translation delay, and search loop phase.
6. **Automated QA and retry:** reject identity changes, discontinuities, bad ports, loop seams, alpha edges, and color outliers. Regenerate failed sources instead of hiding them with long fades.
7. **Export:** only validated runtime clips enter a `.furballpet` package.

### Pet Pack v1 runtime contract

- 960×540, 24 fps, HEVC with Alpha, `hvc1`, and no audio.
- Twenty-seven required semantic slots: 17 posture/locomotion clips, nine standing-view loops, and one complete look-around demonstration.
- Four posture ports: stand, sit, lie, and sleep.
- Geometry ports use subject height, alpha-weighted center x, and ground y.
- Color ports use black, tan, and light-fur anchors without background pixels.
- Runtime behavior depends on semantic IDs in `manifest.json`, not filenames, species, or generation provider.

Source photos, chroma footage, and generation logs stay in a private source project rather than the user-facing `.furballpet` runtime package.

### Implemented foundation

- Runtime now resolves file paths and loop properties by semantic ID from `manifest.json`.
- `FURBALL_PET_PACK=/absolute/path/MyPet.furballpet` runs an unpacked external pack without recompilation for production and QA workflows.
- `Scripts/validate-pet-pack.swift <pack>` validates the manifest, all 27 required actions, safe relative paths, loop semantics, canvas, frame rate, codec, audio absence, and decoded transparency.

This establishes the universal runtime contract, not yet the complete consumer production experience. The next phase is an in-app Pet Pack importer/switcher and a separate production wizard combining identity-board generation, provider adapters, automated retries, and a visual QA report. While video models can still change faces or markings, the single identity-board approval remains a necessary quality gate.
