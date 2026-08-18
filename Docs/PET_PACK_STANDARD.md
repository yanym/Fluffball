# Furball Pet Pack v2 / Furball 宠物素材包 v2

[中文](#中文) · [English](#english)

## 中文

### 目标

Pet Pack 把“这是哪只动物”“有哪些素材表示”和“应用如何行为”分开。用户只提供身份照片并确认标准身份板；图片与可选视频的生成、抠像、颜色、尺寸、脚底锚点、循环和验收由离线生产工具处理。应用只读取统一动作 ID，因此狗、猫或其他四足宠物不需要各写一套 Swift 状态机，也不必为了加入应用而先购买整套 AI 视频。

### 用户最小输入

1. 6–12 张清晰原始照片：正面、左/右侧面、左/右 3/4，以及一张能看清全身比例和尾巴的照片。
2. 宠物名称与种类：`dog`、`cat` 或 `other`。
3. 用户确认一张“标准身份板”，检查脸型、耳朵、花纹、毛色、尾巴和体型。身份板未通过前不批量生成姿态图；只有用户选择高级视频模式时才进入视频阶段。

绿幕不应该是用户必须理解的输入。生成器可以输出固定绿幕、纯色背景或原生 Alpha；只要生产适配器能生成同一组透明标准片段，应用层无需知道上游模型。

### 标准生产流程

1. **输入质检**：检测清晰度、遮挡、视角覆盖、过度滤镜和多只动物。
2. **身份建模**：保留原图，生成统一的正面/侧面/花纹身份板，并记录毛色锚点。
3. **标准视角与姿态**：生成 9 个站立视角，以及 stand / sit / lie / sleep 稳定姿态。所有结果使用同一相机、主体尺度和地面基线。
4. **图片包先交付**：将站、坐、趴、睡和视角图离线抠像并归一到透明 PNG；程序化运动参数在清单中按语义声明。到这里已能形成完整可用的低成本宠物。
5. **可选视频增强**：只有用户选择时才调用视频模型。不同提供商使用同一进入姿态、主动作和离开姿态约定。
6. **自动编译**：图片执行 Alpha、去色边、尺度/脚底归一；视频额外执行时间切分、逐帧跟踪、起步延迟检测和循环相位搜索。
7. **自动验收与重试**：身份相似度、突变、端口偏差、循环缝、透明边缘或颜色超标时拒收；生成型问题回到上游重试，不用长 Crossfade 隐藏。
8. **导出**：只有通过验收的运行时素材才进入 `.furballpet` 包。

### Pet Pack v2 运行时合同

- `capabilities.imageMode` 与 `capabilities.videoMode` 明确声明可用表示，至少一个为 `true`。
- 每种已启用的表示都必须覆盖同一组 27 个语义槽位：17 个姿态/移动动作、9 个站立视角和 1 个完整转身演示。
- 图片表示可以由 `imageAnimations`、`spriteAtlas` 或两者混合组成；同一语义 ID 同时存在时图集绑定优先，旧 PNG 作为兼容回退。
- 独立图片规格：960×540 RGBA PNG，必须已有透明背景，禁止运行时 chromakey。`imageAnimations` 为语义 ID 声明 `files`、可选 `rightFiles`、循环属性、时长和程序化 `motion`。
- Furball 生产图集使用 v2 语义布局的 2× 扩展：透明无损 WebP、3072×4576、8 列×11 行、每格 384×416、`spriteVersionNumber: 2`、`assetScale: 2`。1536×2288 / 192×208 仅用于兼容旧包，不再作为新素材默认值。`animations` 声明行、有效帧数、逐帧时长、循环和短溶解比例；`bindings` 将任意语义 ID 映射到动画。
- `lookDirections` 必须完整声明从 0° 起每 22.5° 一个的 16 个方向。0° 为上、90° 为屏幕右、180° 为下、270° 为屏幕左；运行时沿相邻格最短路径切换。
- `actions` 可将图集绑定发布为双语菜单动作，并可声明是否允许自动行为使用。动作标题、帧时长、菜单数量和语义映射均属于素材包，不在 Swift 中按某只宠物硬编码。
- 视频规格：1280×720、60 fps、HEVC with Alpha、`hvc1`、无音轨；24 fps 原片先做双向运动补偿插帧，再抠像和归一化。`clips` 为每个语义 ID 声明相对路径与循环属性。
- `appearances` 可以为同一宠物声明一个视频外观与多个图片图集外观；默认项由 `isDefault` 指定。应用只显示实际存在的外观，视频混合设置仅在视频外观中出现。
- 统一姿态端口：`stand`、`sit`、`lie`、`sleep`。
- 统一跟踪端口：主体高度、Alpha 加权中心 x 和接地 y。
- 统一色彩端口：黑毛、棕毛和浅色毛锚点，背景不参与统计。
- 行为层只依赖 `manifest.json` 中的标准 ID，不依赖文件名、动物种类或生成提供商。

```text
MyPet.furballpet/
├── manifest.json
├── Sprites/MyPet/spritesheet.webp   # 推荐的 Codex v2 图片表示
├── Images/                          # 独立 PNG 回退，可选
│   ├── stand/
│   ├── sit/
│   ├── lie/
│   └── sleep/
└── Clips/                           # videoMode=true 时必需
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

- 应用会按标准动作 ID 从 `manifest.json` 解析图集动画、PNG 动画和视频片段，并在一个行为状态机下切换渲染器。
- 图集只解码一次，单元格按需铺到统一 16:9 小画布并缓存为 Metal 纹理；支持可变逐帧时长、每动作短溶解比例、真实左右步态行和程序化 motion 的混合。
- 图片模式具备同画风的站、坐、趴、闭眼睡眠、醒来、真实相位走跑、十类可爱动作和 16 方向视线跟随；右向优先使用真实 `rightAnimation`，缺失时才镜像。
- `FURBALL_PET_PACK=/absolute/path/MyPet.furballpet` 可在不重新编译的情况下运行一个外部包，适合制作和测试工具。
- App 内“宠物素材库”会验证、安装、切换、导出和可恢复地移除 `.furballpet`；Finder 双击宠物包也会进入相同验证路径。用户包安装在 `~/Library/Application Support/Furball2D/Pets/`。
- 每个宠物 ID 拥有独立的本地性格、动态状态与短期记忆；这些用户数据不写回或污染可分享的 `.furballpet`。
- “创建 2D 宠物”接受 6–12 张照片、宠物名称/种类和目标风格，输出照片、`REQUEST.json`、双语 Skill、动作注册表与独立验证器。当前明确不生成视频。
- 同一宠物可拥有真实连续动画、可爱 2D 和写实 2D；Nina 是包含三种外观的内置参考包。
- `Scripts/validate-pet-pack.swift <pack>` 会按能力解析 PNG 与图集绑定的并集，检查 27 个语义动作、路径安全、循环语义、图集结构/Alpha/方向、PNG 尺寸/Alpha，以及视频分辨率、帧率、编码、音轨和透明像素。纯图集包不必伪造 PNG 或空视频。

当前版本已经完成普通用户可操作的图片包导入、导出、切换和创建请求工作流。生成阶段仍由用户选择的图片模型执行：随请求导出的 Skill 强制身份板、两种风格、16 方向、睡眠 flow、透明图集和 QA 合同，结果返回后可直接导入。未来若加入托管模型调用，应复用同一请求与验证合同，而不是另建不兼容格式。

---

## English

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
4. **Ship images first:** key and normalize stand, sit, lie, sleep, and view images as transparent PNGs, then declare semantic procedural motion. This already forms a complete low-cost pet.
5. **Optional video enhancement:** call a video provider only when selected. Every provider follows the same entry-pose, action, and exit-pose contract.
6. **Automated compilation:** images receive alpha, despill, scale, and ground normalization; video additionally receives segmentation, per-frame tracking, translation-delay detection, and loop-phase search.
7. **Automated QA and retry:** reject identity changes, discontinuities, bad ports, loop seams, alpha edges, and color outliers. Regenerate failed sources instead of hiding them with long fades.
8. **Export:** only validated runtime assets enter a `.furballpet` package.

### Pet Pack v2 runtime contract

- `capabilities.imageMode` and `capabilities.videoMode` declare available representations; at least one is true.
- Every enabled representation covers the same 27 semantic slots: 17 posture/locomotion actions, nine standing views, and one complete look-around demonstration.
- An image representation may use `imageAnimations`, `spriteAtlas`, or a hybrid. When both resolve the same semantic ID, the atlas binding wins and the standalone PNG remains a compatibility fallback.
- Standalone images are transparent 960×540 RGBA PNGs with no runtime chroma key. Each `imageAnimations` entry declares `files`, optional `rightFiles`, looping, duration, and procedural `motion`.
- Furball's production atlas is the 2× extension of the v2 semantic layout: transparent lossless WebP at 3072×4576, 8 columns × 11 rows, 384×416 cells, `spriteVersionNumber: 2`, and `assetScale: 2`. The 1536×2288 / 192×208 form remains a legacy import path, not the default for new assets.
- `lookDirections` contains all 16 directions from 0° in 22.5° steps. Zero is up, 90° is screen-right, 180° is down, and 270° is screen-left. Runtime transitions along the shortest adjacent-cell path.
- `actions` exposes atlas bindings as localized menu actions and may opt individual actions into autonomous behavior. Titles, timing, action count, and semantic mapping belong to the pack rather than pet-specific Swift code.
- Video assets are 1280×720 at 60 fps, HEVC with Alpha, `hvc1`, and no audio. Motion-compensate lower-frame-rate sources before keying. Each `clips` entry declares a relative file and loop behavior.
- `appearances` may declare one video appearance and multiple sprite-atlas appearances for one pet, with exactly one `isDefault`. The app exposes only available appearances, and video-blending controls appear only for a video appearance.
- Four posture ports: stand, sit, lie, and sleep.
- Geometry ports use subject height, alpha-weighted center x, and ground y.
- Color ports use black, tan, and light-fur anchors without background pixels.
- Runtime behavior depends on semantic IDs in `manifest.json`, not filenames, species, or generation provider.

```text
MyPet.furballpet/
├── manifest.json
├── Sprites/MyPet/spritesheet.webp   # Recommended Codex v2 image representation
├── Images/                          # Optional standalone-PNG fallback
└── Clips/                           # Required only when videoMode=true
```

Source photos, chroma footage, and generation logs stay in a private source project rather than the user-facing `.furballpet` runtime package.

### Implemented foundation

- Runtime resolves atlas animations, PNG animation descriptors, and video clips by semantic ID under one behavior state machine.
- The atlas decodes once; requested cells are placed on a shared 16:9 render canvas and cached as Metal textures. Variable frame durations, per-animation blend fractions, true left/right gait rows, and procedural motion can coexist.
- Image mode now provides one-style stand, sit, lie, closed-eye sleep, wake, phased locomotion, ten cute actions, and 16-direction gaze. Right-facing art prefers `rightAnimation` and mirrors only as a fallback.
- `FURBALL_PET_PACK=/absolute/path/MyPet.furballpet` runs an unpacked external pack without recompilation for production and QA workflows.
- Pet Library validates, installs, switches, exports, and recoverably removes `.furballpet` packages. Finder-opened packages use the same validation path. User packs live under `~/Library/Application Support/Furball2D/Pets/`.
- Each pet ID has separate local personality, dynamic state, and short-term memory data; this user state never mutates or contaminates a shareable `.furballpet`.
- Create 2D Pet accepts 6–12 photos, name/species, and requested styles, then exports the photos, `REQUEST.json`, bilingual Skill, action registry, and standalone validator. It explicitly does not generate video.
- One pet may expose Live Motion, Cute 2D, and Realistic 2D; Nina is the built-in three-appearance reference pack.
- `Scripts/validate-pet-pack.swift <pack>` resolves the union of PNG descriptors and atlas bindings, then validates all 27 semantic actions, safe paths, loop semantics, atlas structure/alpha/directions, PNG dimensions/alpha, and video canvas, frame rate, codec, audio absence, and decoded transparency. A pure-atlas pack does not need placeholder PNGs or empty videos.

The current release includes the consumer image-pack import, export, switching, and creation-request workflow. Generation still runs in the user’s chosen image-capable model: the exported Skill enforces an identity board, both styles, 16 directions, the sleep flow, transparent atlases, and QA contract, after which the result imports directly. A future hosted provider should reuse this request and validation contract rather than introduce an incompatible format.
