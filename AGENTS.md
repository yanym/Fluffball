# Furball Agent README：连续宠物动作视频处理规范

[中文](#furball-agent-readme连续宠物动作视频处理规范) · [English](#fluffball-agent-guide-processing-continuous-pet-action-video)

本文件给后续接手 Furball2D 的 Agent 使用。当用户提供一段或多段连续宠物动作视频时，必须先按照这里的流程分析、切分、归一化和验收，再替换应用素材。目标不是“能播放”，而是让桌宠在循环、换动作和改变显示尺寸时仍然自然、稳定、清晰。

## 1. 最重要的原则

1. 先匹配动作端口，再考虑 Crossfade。交叉淡化只能柔化已经接近的两帧，不能修复不同大小、不同落脚点、不同朝向或不同姿势的狗。
2. 不要根据文件名猜动作。必须观看整段视频并建立时间轴，确认每段的真实语义、稳定区间和动作方向。
3. 始终从用户提供的原始视频重新处理，不要放大已经抠像、压缩过的旧 `.mov`。
4. 所有视频动作必须使用同一个画布、帧率、主体尺度和地面锚点。当前运行时标准是 1280×720、120 fps、HEVC with Alpha；24 fps 原片必须在绿幕抠像前做双向运动补偿插帧，禁止用重复帧伪装高帧率。
5. “待机视频”不等于“可循环视频”。首尾姿态不一致时，直接循环一定会每隔几秒跳一下。
6. 质量问题优先在离线素材层修复。不要把运行时 Crossfade 拉长来掩盖坏切点，写实宠物会出现双头、双爪和毛发重影。

## 1.1 使用身份参考图生成新视频

如果任务包含生成新的 AI 宠物动作视频，先阅读 `Assets/SourceImagesForAIVideo/README.md`。优先从 `generation-ready/<pose>/<view>.png` 选择与目标动作相同姿态和视角的参考图，并用正面图锁定脸型与花纹。`originals/` 只用于身份核对和来源追溯，不能被新生成结果覆盖。

同一段动作通常使用 2–4 张参考图。除非镜头明确要求转身，不要混用相反侧视角。输出必须继承参考图中的同一只狗、固定视角、固定主体大小与地面基线；任何换脸、毛色变化、尾巴长度改变或左右花纹翻转都视为生成失败。

## 1.2 只用图片制作动作

当用户明确不要 AI 生成视频时，优先制作 Codex 兼容的 Pet Pack v2 图集图片模式。若环境提供 `$hatch-pet`，必须按该 Skill 生成、注册和验收；否则严格遵守 `Docs/PET_PACK_STANDARD.md`。旧 `Scripts/build-image-assets.sh` 与 `Images/` 仅是 PNG 兼容路径，不再是新宠物的首选。

1. 先锁定同一只宠物的标准身份、画风、身体比例、脚底基线和纯色抠像背景。不得在不同动作行改变脸、耳朵、花纹、尾巴、材质或镜头。
2. 新图集使用 `spriteVersionNumber: 2` 与 `assetScale: 2`：3072×4576、8 列×11 行、每格 384×416。1536×2288 / 192×208 仅用于兼容旧包，不得把旧小格放大冒充高清源。
3. 左右步态应分别生成。只有宠物完全左右对称且用户明确接受时才可镜像；步态首尾必须闭合相位，不能用倒放制作跑步。
4. 最后两行必须提供完整 16 方向：0° 为上、90° 为屏幕右、180° 为下、270° 为屏幕左，每 22.5° 一格。四个主方向先单独批准，再生成两条连续方向行。
5. 视线动作保持脚、下躯干和基线稳定；眼睛先动，口鼻和头颈随后，耳朵、面颊毛与胸毛轻微滞后。不得旋转整个 sprite 冒充转头。
6. `manifest.json` 的 `spriteAtlas.animations` 声明逐帧时长、循环、motion 和短溶解比例；`bindings` 将 27 个标准语义 ID 映射到图集动作。可用 `frameIndices`、`rightAnimation` 和 `frameDurationScale` 复用动作，不得在 Swift 中写某只宠物的路径。
7. `actions` 可发布任意数量的双语可爱动作。当前创建 Skill 的动作注册表版本为 `2026-08-17.2`，内置动作包括 wave、jump、failed、waiting、working、review、play-bow、head-tilt、sniff 和 high-five。标题、是否自动触发和结果姿态属于素材包；图片模式菜单自动读取，视频模式自动置灰。增加动作时必须同时更新 `Sources/Furball2D/CreatorSkill/` 的合同、Skill 和验证器。
8. 运行时看向鼠标时每次只走一个相邻方向，首次稳定约 0.15 秒，相邻冷却约 0.085–0.12 秒。进入走跑前沿最短路径抵达匹配的 90° 或 270° 侧面；移动期间不切换视线格。
9. 方向格只在鼠标最近发生移动时接管画面；鼠标静止约 2.4 秒后必须回到完整 idle 行，不能让单张方向格永久遮住呼吸和眨眼。进入坐下等正面动作前先短暂回到 idle 端口。
10. 鼠标跟随和自由漫游继续使用二维目标、速度迟滞和横纵边界。图集有真实起步帧时桌面位移无需等待视频的首个抬爪时间，但保留约 0.07 秒平滑加速。
11. `capabilities.imageMode=true`；纯图片包设 `videoMode=false` 并省略 `clips`，顶层视频开关会自动关闭并置灰。纯图集包可省略 `imageAnimations`，但图集绑定与 PNG 描述的并集必须覆盖全部 27 个标准语义槽位。
12. 交付前必须通过 `Scripts/validate-pet-pack.swift`、Codex v2 图集结构/Alpha 验收、逐行动画预览、16 方向语义与连续性检查、60%/100%/140% 实机测试和 `Scripts/package-app.sh`。指标警告必须结合正常尺寸的可见循环审阅，不得直接放宽阈值。

## 2. 接收新素材后的第一步

如果任务是替换整只宠物，而不是只新增一段动作，必须先阅读 `Docs/PET_PACK_STANDARD.md`。狗和猫使用同一组 27 个语义动作槽位。不得在 Swift 中为某只宠物新增硬编码文件路径；路径、循环属性、能力和宠物身份必须写入 Pet Pack `manifest.json`。图片、视频或双模式整包都必须通过 `Scripts/validate-pet-pack.swift`，验收未通过时不得打包。

保留原始视频，不要立刻覆盖 `Sources/Furball2D/Assets/Clips`。原片先按 `Assets/SourceVideos/<view>/<action>.mp4` 归档，再完成以下检查：

视角目录使用小写 kebab-case，例如 `left-profile`、`right-profile`、`front`、`three-quarter-left`。如果视频本身发生视角变化，使用 `three-quarter-to-front` 这类带方向的名称。动作文件也使用 kebab-case，例如 `stand-idle.mp4`、`stand-to-sit.mp4`。导出视频必须落到对应的 `Sources/Furball2D/Assets/Clips/<view>/`，不能把不同视角的动作混放在同一层。

- 用 `ffprobe` 记录分辨率、帧率、时长、颜色格式和是否为恒定帧率。
- 生成每 0.25–0.5 秒一张的缩略图或接触表，观看完整动作时间轴。
- 检查是否为同一只宠物：耳朵、脸部花纹、尾巴长度、身体比例和毛色必须连续。
- 检查机位是否固定，是否存在推近、拉远、横移、画面裁切或地面高度漂移。
- 检查光照、白平衡和绿幕颜色是否随时间变化。
- 找出水印、生成器标记和边缘脏点的位置。`delogo` 坐标必须按新视频重新测量，不能照抄旧素材的坐标。

建议先建立一张切分表：

| 输出动作 | 源视频 | 开始时间 | 结束时间 | 起始姿态端口 | 结束姿态端口 | 循环策略 | 尺度校正 |
|---|---|---:|---:|---|---|---|---|
| `stand-idle` | 原片 A | 待测 | 待测 | 站立 | 站立 | 真循环或低动作往返 | 待测 |
| `stand-to-sit` | 原片 A | 待测 | 待测 | 站立 | 坐姿 | 单次播放 | 待测 |
| `sit-idle` | 原片 A | 待测 | 待测 | 坐姿 | 坐姿 | 真循环或低动作往返 | 待测 |
| `sit-to-lie` | 原片 A | 待测 | 待测 | 坐姿 | 趴卧 | 单次播放 | 待测 |
| `lie-idle` | 原片 A | 待测 | 待测 | 趴卧 | 趴卧 | 真循环或低动作往返 | 待测 |
| `lie-to-sleep` | 原片 A | 待测 | 待测 | 趴卧 | 睡眠 | 单次播放 | 待测 |
| `sleep-idle` | 原片 A | 待测 | 待测 | 睡眠 | 睡眠 | 低动作呼吸循环 | 待测 |
| `sleep-to-stand` | 原片 A | 待测 | 待测 | 睡眠 | 站立 | 单次播放 | 待测 |

如果一条连续视频已经包含完整状态链，应尽量从同一条视频中切出相邻动作。保留 2–4 帧的姿态稳定区，但不要让待机动作和过渡动作重复播放同一段明显运动。

## 3. 动作端口应该怎样选

每个片段都有“进入端口”和“离开端口”。相邻片段的端口至少要满足：

- 朝向一致。
- 四肢接触地面的状态一致。
- 脚底基线一致。
- 主体高度和头部大小接近。
- 头、尾、前爪的位置没有突然跳变。
- 光照和毛色没有明显改变。

切点优先放在速度较低、姿态稳定的位置。不要切在抬爪、甩头、尾巴快速扫动或身体正在下落的中间帧。

连续视频中如果存在“站立稳定 8 帧 → 开始坐下”，`stand-idle` 应结束在稳定区，`stand-to-sit` 应从同一个稳定姿态附近开始。这样短 Crossfade 才能正常工作。

## 4. 主体大小与脚底锚点归一化

抠像后至少在每个片段的首帧、中间帧和末帧测量：

- Alpha 边界框 `xMin/yMin/xMax/yMax`。
- 主体高度与宽度。
- Alpha 加权中心点。
- 最低脚掌或身体接地点的 y 坐标。

不要只看画布大小。相同的 1280×720 视频里，狗仍然可能放大、缩小或漂移。

推荐流程：

1. 先在原始绿幕分辨率上检测主体尺度和位置。
2. 选定标准姿态作为参考，例如 `stand-idle` 的稳定帧。
3. 对存在镜头推近或主体漂移的片段做逐帧平滑校正。
4. 缩放时以脚底为锚点，不要以画面中心为锚点。
5. 使用 smoothstep 让校正量从片段开头平滑变化到结尾，避免校正本身产生速度突变。
6. 完成位置与尺度校正后再抠像、去绿边和输出 1280×720。

为每一种稳定姿态建立明确的“端口三元组”，不要只记录一个缩放百分比：

```text
port = (主体高度, Alpha 加权中心 x, 脚底 y)
```

相邻片段的旧末帧和新首帧都要归一到同一个端口。对于“站立 → 步态循环 →
站立”这类长原片，至少要建立站立入口、循环入口、循环出口、站立出口四个测量点，
并分别处理 start / loop / stop：

- `start` 从标准站立端口用 smoothstep 过渡到循环入口。
- `loop` 的首尾必须校正到相同高度、中心和脚底；允许校正量在一轮内缓慢变化，
  但变换后的末帧必须能无跳点回到首帧。
- `stop` 从循环出口连续过渡到标准站立端口。

不要把一个固定缩放值套到整条移动视频。AI 视频常在同一条原片里同时发生主体缩放和
画面漂移，固定 93% 之类的处理只能碰巧对齐某一帧，仍会在入口、出口或循环缝跳动。

需要同时支持放大和缩小时，可先在更大的透明工作画布上执行等比缩放与位移，再裁回
标准画布。当前构建脚本使用 1600×900 工作画布，直接裁回并输出 1280×720；
这样缩放大于 1 时不会被 `pad` 截断。缩放必须围绕画布中心计算，纵向位移再以脚底
端口补偿，不能直接围绕主体边界框中心缩放。

当前 `sleep-to-stand` 就有原片末端约放大 6% 的问题，构建脚本使用动态缩放和脚底锚定修正。新素材必须重新测量，不能复用这个 6% 数字或现有偏移量。

不要轻易使用非等比缩放。它虽然能让边界框数字吻合，但会让写实宠物身体变形。如果不同视频中的尾巴长度、头型或花纹发生改变，应明确告诉用户这是 AI 源素材一致性问题；优先请求重新生成，而不是强行拉伸。

### 4.1 色彩归一化

同一只宠物的不同生成批次必须在抠像后统一到一个明确参考。当前参考是 `stand-idle` / `left-profile`，分别测量不透明区域中的黑毛、棕毛和白毛，而不是用整帧平均色；透明背景或不同姿势所占面积会让整帧平均值失真。

- 同一条移动原片拆出的 start / loop / stop 必须共用同一条色彩曲线，不能逐段自动白平衡。
- 不同图片视角可以使用各自的单调 PCHIP 曲线，但都必须落到同一组黑/棕/白参考锚点。
- 色彩处理放在 chromakey / despill 之后，Alpha 通道保持不变；不要让绿色背景参与白平衡统计。
- 先对源片抽取代表帧，用 `Scripts/audit-png-color.swift` 复测，再把确定的锚点写进构建脚本。不要在运行时按帧自动校色，否则毛色会随动作呼吸式漂移。
- 交付前把所有动作代表帧合成到同一中灰背景并排观看。数值接近仍需检查白毛是否偏粉、黑毛是否发蓝以及棕毛是否过饱和。

## 5. 抠像与透明视频输出

当前构建脚本位于 `Scripts/build-assets.sh`，现有参数只能作为起点：

```text
chromakey=0x3f985b:0.075:0.025
despill=green:mix=0.30:expand=0.05
unsharp=5:5:0.25:3:3:0
scale=960:540:flags=lanczos+accurate_rnd
format=bgra
```

处理新视频时应重新采样绿幕颜色，并在深灰、纯黑、纯白三种背景上检查毛发边缘：

- 绿色轮廓明显：适度增加 despill，不要直接大幅扩大 chromakey 相似度。
- 白毛被吃掉或边缘透明：降低 chromakey 相似度或 softness。
- 黑毛边缘发灰：检查 straight/premultiplied Alpha 是否混用。
- 边缘闪烁：先检查绿幕压缩噪声和每帧曝光变化，再微调 key 参数。
- 水印区域：仅在确认坐标后使用 `delogo`，新分辨率必须重新计算位置。

输出要求：

```text
1280×720
120 fps
HEVC VideoToolbox with Alpha
-alpha_quality 0.95
-q:v 75
-tag:v hvc1
无音轨
```

不要再输出 640×360。应用默认显示区域约 520 pt，640×360 在 Retina 屏幕上会被明显放大，毛发和眼睛细节不足。

## 6. 待机循环的正确做法

### 6.1 真正的周期动作

走路、跑步、摇尾等有明确相位的动作，首帧和末帧必须是同一只脚、同一触地相位。不要对走路使用倒放，否则步态动力学会不自然。

如果没有合格的原地步态循环，不要让静止站姿在桌面上滑行。当前应用会在缺少 `Assets/SourceVideos/left-profile/walk-idle.mp4` 时保持站立观察。

### 6.2 低动作待机

站立呼吸、坐姿观察、趴卧和睡眠可以使用首尾去重的正放/倒放循环：

```text
forward:  0, 1, 2, ... N
reverse:  N-1, N-2, ... 1
loop:     0, 1, 2, ...
```

必须删除转折点和循环点的重复端帧，否则会在两端多停一帧。最终统一为 120 fps；低帧率源先在绿幕阶段做运动补偿，不能只用 `fps` 复制帧。

往返循环只适用于幅度小、方向性不强的动作。如果宠物明显转头、抬爪、翻身或走动，倒放会被看出来，应寻找更稳定的窗口或制作真实闭环。

### 6.3 睡眠

用户偏好是“没操作时安静睡觉”，不能把包含甩尾、换姿势或抬头的整段睡眠视频直接循环。

推荐从连续睡眠视频中寻找约 0.5–1.0 秒的最低动作窗口，只保留细微胸腹呼吸；必要时放慢约 1.5–2.5 倍，再制作首尾去重的往返循环。当前素材使用 0.55 秒窗口、放慢 2.5 倍，最终约 2.7 秒、120 fps。

## 7. 运行时转场规则

`PetRenderer.swift` 当前使用双解码通道：

1. 旧动作继续显示。
2. 新通道开始解码。
3. 等新通道真正拿到第一帧后再开始淡化，不能对透明空帧淡入。
4. 淡化开始时冻结旧通道，避免两段动作同时运动产生晃影。
5. 每个通道先转换为预乘 Alpha，再进行混合。
6. 使用五阶 smootherstep 权重，默认约 0.14 秒；在 120 Hz 显示链路中约覆盖 17 个采样点。五阶曲线在两端的
   一阶和二阶导数都为零，比三阶 smoothstep 更不容易出现轻微的透明度顿挫。
7. 动作播放完成回调与淡化完成必须是两个独立生命周期。

走路、慢跑、快跑之间不要只靠单帧速度阈值立即切换。速度档位至少稳定约 0.15–0.25
秒后再切换，并保留原有阈值迟滞；停止和重新起步可以立即响应。这个短暂确认时间能
避免鼠标速度在阈值附近波动时反复 Crossfade。

首次从站立进入移动时，先把 `start` 片段切到第一处可见重心变化附近，再用短 `translationDelay` 对齐脚步。当前走路、慢跑、快跑延迟分别约为 0.12、0.07、0.10 秒，速度渐入分别约为 0.18、0.13、0.10 秒。若重新切分起步素材，必须重新测量这些值，既不能让站立帧滑行，也不能用过长等待制造鼠标延迟。

通常将 Crossfade 控制在 0.10–0.16 秒。超过约 0.20–0.25 秒时，写实宠物很容易出现双眼、双头、双爪和两条尾巴。若短淡化仍然明显，返回离线素材修端口，不要继续加长。

## 8. 必须完成的逐帧 QA

每次替换素材后，不要只启动应用看几秒。至少执行以下检查。

### 8.1 循环缝

比较每个待机片段的最后可见帧与第一帧：

- 脚底或接地点位移最好不超过 1–2 像素。
- Alpha 加权中心点位移最好不超过 2 像素。
- 主体高度变化最好小于 2%。
- 预乘 RGB 平均绝对差异理想值小于 1，低动作素材应尽量不超过 2。

当前修复后的参考值：

```text
stand-idle seam MAE ≈ 0.69
sit-idle seam MAE   ≈ 0.58
lie-idle seam MAE   ≈ 0.69
sleep-idle seam MAE ≈ 0.48
```

当前移动素材归一化后的几何参考值（2026-08-14）为：

```text
stand-idle → walk/slow-run/fast-run start：主体高度差约 0–0.2%，脚底差 0–2 px
walk-loop seam：高度差约 0.3%，中心差约 0.3 px，脚底差 0 px
slow-run-loop seam：高度差约 0%，中心差约 0.2 px，脚底差 1 px
fast-run-loop seam：高度差约 0.3%，中心差约 0.3 px，脚底差 0 px
sit-to-lie → lie-idle：主体高度差由约 13.5% 降至约 0.3%
```

这些是当前素材的验收结果，不是下一批视频可以照抄的变换参数。新素材必须重新测量。

这些数值不是通用硬门槛，但如果新素材明显高于 2，必须肉眼检查跳点。

### 8.2 动作端口

对每一组相邻动作比较“旧片段末帧 → 新片段首帧”：

- 脚底 y 坐标差尽量不超过 2 像素。
- 同姿态主体高度差尽量小于 3%。
- Alpha 中心点位移尽量小于 5 像素。
- 不能出现突然换脸、尾巴变长、毛色改变或身体比例改变。

必须把端点帧合成到中灰背景上并并排查看。Alpha 边界框数字接近不代表造型真的一致。

### 8.3 实机检查

- 在 60%、100%、140% 三种显示尺寸下观看。
- 分别在深色和浅色桌面背景上检查绿边、黑边和透明闪烁。
- 每个待机循环至少播放 3 轮。
- 自动行为至少完整跑过：睡眠 → 起身 → 站立 → 坐下 → 趴下 → 睡眠。
- 检查切换时是否出现透明空帧、旧动作继续移动、双影或突然缩放。
- 观察内存是否持续增长，并确认双通道在淡化结束后释放旧播放器。

可以使用 `FURBALL_FAST_BEHAVIOR=1` 加速行为状态机测试，但最终还要以正常速度启动一次。

## 9. 更新工程时不要漏掉

新动作处理完成后，需要同步检查：

- `Scripts/build-assets.sh`：源文件、切点、循环方式、校正参数。
- `Assets/README.md`：视角目录、旧文件名映射、备用素材和重复素材记录。
- `Sources/Furball2D/Assets/manifest.json`：画布、帧率、视角、文件名、源文件和循环标记。
- `Sources/Furball2D/PetClip.swift`：动作 ID、文件名、结果姿态。
- `Sources/Furball2D/PetController.swift`：状态图中只能走合法姿态路径。
- `README.md`：素材要求和用户可见行为。

完成后运行：

```bash
./Scripts/build-assets.sh
swift build
./Scripts/package-app.sh
```

`Scripts/package-app.sh` 会在 `/tmp` 中完成签名，再输出：

```text
dist/Furball2D.app
dist/Furball2D.zip
```

桌面目录可能被 File Provider 自动写入 FinderInfo，因此需要传输或严格复验签名时优先使用 ZIP。对 ZIP 解包后的 `.app` 执行 `codesign --verify --deep --strict`。

## 10. 明确禁止的快捷做法

- 不要只给所有转场统一加长 Crossfade。
- 不要把有明显动作的整段视频直接标记为 `loop: true`。
- 不要用静止站姿代替走路并让窗口横向滑动。
- 不要把旧的低清透明视频放大成 1280×720。
- 不要只比较画布尺寸，必须测主体边界框和脚底锚点。
- 不要为了对齐边界框而随意做非等比拉伸。
- 不要在运行时实时 chromakey；绿幕处理必须离线完成。
- 不要在新素材上照抄旧素材的绿幕颜色、水印坐标、6% 缩放或 trim 时间。
- 不要在没有实机循环测试的情况下交付。

如果源视频本身不是同一只宠物、姿态端口差异太大或生成过程中发生明显变形，应清楚报告素材限制，并说明需要重新生成哪些起止姿态。宁可请求一段端口正确的新视频，也不要用长溶解把问题藏起来。

---

# Fluffball Agent Guide: Processing Continuous Pet Action Video

This file is mandatory guidance for any Agent working on Fluffball/Furball2D. When a user provides one or more continuous pet-action videos, analyze, segment, normalize, and validate them with this workflow before replacing app assets. The goal is not merely successful playback. The desktop pet must remain natural, stable, and sharp across loops, action changes, and display sizes.

## 1. Core principles

1. Match action ports before considering a crossfade. A crossfade can soften two already similar frames; it cannot fix different subject sizes, foot positions, directions, or postures.
2. Never infer action semantics from filenames. Watch the full video, build a timeline, and verify every stable interval and movement direction.
3. Always rebuild from the user-provided original video. Never enlarge an older keyed or compressed `.mov`.
4. Every video action must use the same canvas, frame rate, subject scale, and ground anchor. The runtime standard is 1280×720 at 120 fps HEVC with Alpha. Bidirectionally motion-interpolate 24 fps sources before keying; duplicated frames do not qualify as high frame rate.
5. An “idle video” is not automatically loopable. If the first and last poses differ, a direct loop will jump every few seconds.
6. Fix quality problems in offline assets first. Do not hide bad cut points with a long runtime crossfade; realistic pets develop double heads, paws, and fur trails.

## 1.1 Identity references for new AI videos

If the task includes generating a new AI pet-action video, first read `Assets/SourceImagesForAIVideo/README.md`. Prefer references under `generation-ready/<pose>/<view>.png` that match the target posture and view, and use the front view to lock face shape and markings. `originals/` exists only for identity verification and provenance and must not be overwritten by generated results.

A typical action uses two to four references. Do not mix opposite profile views unless the shot explicitly turns around. The output must preserve the same dog, fixed view, stable subject size, and stable ground baseline. Face replacement, coat changes, tail-length changes, or flipped left/right markings are generation failures.

## 1.2 Building actions from images only

When the user explicitly rejects AI-generated video, prefer a Codex-compatible Pet Pack v2 sprite-atlas image mode. If `$hatch-pet` is available, follow that Skill for generation, registration, and QA; otherwise follow `Docs/PET_PACK_STANDARD.md` exactly. The old `Scripts/build-image-assets.sh` and `Images/` tree are PNG compatibility paths, not the preferred starting point for a new pet.

1. Lock one canonical identity, art style, body proportion, ground baseline, and solid key background. No row may change face, ears, markings, tail, materials, or camera.
2. A new atlas uses `spriteVersionNumber: 2` and `assetScale: 2`: 3072×4576, 8 columns × 11 rows, and 384×416 cells. The 1536×2288 / 192×208 form is legacy-only; never upscale old runtime cells as an HD source.
3. Generate left and right gait rows independently. Mirror only for a truly symmetric pet and explicit user approval. Gait loops must close on contact phase and must never use reverse playback.
4. Rows 9–10 contain all 16 directions: 0° up, 90° screen-right, 180° down, and 270° screen-left at 22.5° steps. Approve the four cardinals before synthesizing both coherent direction rows.
5. Keep paws, lower torso, and baseline stable during look motion. Eyes lead, muzzle/head/neck follow, and ears, cheek fur, and ruff lag subtly. Never rotate the whole sprite to fake a head turn.
6. `spriteAtlas.animations` declares per-frame timing, loop, motion, and short blend fraction. `bindings` maps the 27 standard semantic IDs and may use `frameIndices`, `rightAnimation`, and `frameDurationScale`. Never hardcode a pet-specific path in Swift.
7. `actions` may publish any number of localized cute actions. The current creator-Skill action registry is `2026-08-17.2`, covering wave, jump, failed, waiting, working, review, play-bow, head-tilt, sniff, and high-five. Titles, autonomous eligibility, and resulting posture belong to the pack; the image-mode menu reads them automatically and video mode disables them. Adding an action also requires updating the contract, Skill, and validator under `Sources/Furball2D/CreatorSkill/`.
8. Cursor gaze advances one adjacent direction at a time, using roughly 0.15 seconds of initial stability and a 0.085–0.12-second adjacent cooldown. Before locomotion, take the shortest route to the matching 90° or 270° profile. Do not change look cells during movement.
9. Direction cells take over only after recent pointer movement. After roughly 2.4 seconds of pointer stillness, return to the full idle row so one static gaze cannot permanently hide breathing and blinking. Briefly return through the idle port before a front-facing posture action such as sitting.
10. Cursor following and free roam retain one two-dimensional target, gait hysteresis, and horizontal/vertical bounds. A sprite gait with real start frames does not need a video first-paw delay, but retains the roughly 0.07-second image-mode acceleration ramp.
11. Declare `capabilities.imageMode=true`. An image-only pack sets `videoMode=false` and omits `clips`, automatically forcing and disabling the top-level video toggle. A pure-atlas pack may omit `imageAnimations`, but the union of atlas bindings and PNG descriptors must cover all 27 standard semantic slots.
12. Before delivery, pass `Scripts/validate-pet-pack.swift`, Codex v2 structure/alpha validation, per-row previews, 16-direction semantics and continuity review, 60%/100%/140% in-app checks, and `Scripts/package-app.sh`. Review metric warnings at normal display size; never silence them by relaxing a threshold.

## 2. First steps after receiving new footage

If the task replaces the complete animal rather than adding one action, read `Docs/PET_PACK_STANDARD.md` first. Dogs and cats use the same 27 semantic action slots. Never add pet-specific hardcoded file paths to Swift; paths, loop properties, capabilities, and identity belong in the Pet Pack `manifest.json`. Image, video, and dual-mode packs must all pass `Scripts/validate-pet-pack.swift`; never package a validation failure.

Preserve the original video. Do not immediately overwrite `Sources/Furball2D/Assets/Clips`. Archive sources under `Assets/SourceVideos/<view>/<action>.mp4`, then complete these checks:

View directories use lowercase kebab-case, such as `left-profile`, `right-profile`, `front`, and `three-quarter-left`. If the view changes during the clip, use a directional name such as `three-quarter-to-front`. Action filenames also use kebab-case, such as `stand-idle.mp4` and `stand-to-sit.mp4`. Exports go under the matching `Sources/Furball2D/Assets/Clips/<view>/` directory; never mix views in one folder.

- Use `ffprobe` to record resolution, frame rate, duration, color format, and whether frame rate is constant.
- Generate a contact sheet at 0.25–0.5-second intervals and inspect the complete action timeline.
- Verify identity continuity using ears, facial markings, tail length, body proportions, and coat colors.
- Check whether the camera is fixed and identify zoom, pan, crop, or ground-height drift.
- Check whether lighting, white balance, or green-screen color changes over time.
- Locate watermarks, generator marks, and dirty edges. Re-measure `delogo` coordinates for every new video; never copy old coordinates blindly.

Create a segmentation table before processing:

| Output action | Source | Start | End | Entry pose port | Exit pose port | Loop strategy | Scale correction |
|---|---|---:|---:|---|---|---|---|
| `stand-idle` | Source A | Measure | Measure | Stand | Stand | True loop or low-motion ping-pong | Measure |
| `stand-to-sit` | Source A | Measure | Measure | Stand | Sit | One-shot | Measure |
| `sit-idle` | Source A | Measure | Measure | Sit | Sit | True loop or low-motion ping-pong | Measure |
| `sit-to-lie` | Source A | Measure | Measure | Sit | Lie | One-shot | Measure |
| `lie-idle` | Source A | Measure | Measure | Lie | Lie | True loop or low-motion ping-pong | Measure |
| `lie-to-sleep` | Source A | Measure | Measure | Lie | Sleep | One-shot | Measure |
| `sleep-idle` | Source A | Measure | Measure | Sleep | Sleep | Low-motion breathing loop | Measure |
| `sleep-to-stand` | Source A | Measure | Measure | Sleep | Stand | One-shot | Measure |

When one continuous video contains a complete state chain, prefer adjacent actions cut from that same source. Keep two to four stable pose frames at boundaries, but do not replay the same obvious movement in both an idle and a transition.

## 3. Selecting action ports

Every clip has an entry port and an exit port. Adjacent ports must at least match in:

- Facing direction.
- Paw/ground contact state.
- Ground baseline.
- Subject height and head size.
- Head, tail, and front-paw position.
- Lighting and coat color.

Prefer cut points with low velocity and a stable pose. Do not cut during a raised paw, fast head turn, tail sweep, or falling body.

If a continuous source contains “eight stable standing frames → beginning of sit,” end `stand-idle` in that stable region and begin `stand-to-sit` near the same standing pose. A short crossfade then has compatible ports to blend.

## 4. Normalizing subject size and ground anchors

After keying, measure at least the first, middle, and last frame of every clip:

- Alpha bounds `xMin/yMin/xMax/yMax`.
- Subject height and width.
- Alpha-weighted center.
- Lowest paw or body contact y-coordinate.

Do not compare canvas sizes alone. Two 1280×720 videos can still contain pets at different scales or positions.

Recommended workflow:

1. Detect subject scale and position at the original green-screen resolution.
2. Select a stable reference pose, such as a clean `stand-idle` frame.
3. Apply smoothed per-frame correction to clips with camera zoom or subject drift.
4. Anchor vertical scale correction at the feet, not at the center of the image.
5. Interpolate correction values with smoothstep so the correction does not introduce a velocity discontinuity.
6. Apply keying, despill, and the final 1280×720 output only after scale and placement are solved.

Define a clear “port tuple” for each stable posture instead of recording only one scale percentage:

```text
port = (subject height, alpha-weighted center x, ground y)
```

Normalize both the outgoing last frame and incoming first frame to the same port. A “stand → gait loop → stand” source needs at least four measurements: standing entry, loop entry, loop exit, and standing exit. Treat start / loop / stop independently:

- `start` moves from the standard standing port to the loop-entry port with smoothstep correction.
- `loop` must finish at the same transformed height, center, and ground anchor where it begins. Correction may vary gently within one cycle, but the transformed last frame must return seamlessly to the first.
- `stop` moves continuously from the loop-exit port back to the standard standing port.

Never apply one fixed scale to a complete locomotion video. An AI source can change size and drift within the same shot; a fixed value such as 93% can align one frame while leaving the entry, exit, or loop seam wrong.

When correction requires both enlargement and reduction, transform on a larger transparent work canvas and crop back to the 1280×720 standard canvas. This prevents `pad` from clipping scale factors above 1. Compute scale around canvas center, then compensate vertical position against the ground port.

The current `sleep-to-stand` source enlarges the subject by roughly 6% near the end. The build script corrects it with dynamic scale and foot anchoring. New footage must be measured independently; never reuse this 6% value or its offsets.

Avoid non-uniform scaling. It may make bounding-box numbers agree while deforming a realistic animal. If separate videos contain different tail length, head shape, or markings, report an AI-source consistency problem and request a new generation rather than stretching the body.

### 4.1 Color normalization

Normalize separate generation batches to one explicit reference after keying. The current reference is `stand-idle` / `left-profile`. Measure opaque black, tan, and white fur separately instead of using a whole-frame average; transparent background and posture-dependent area make whole-frame averages misleading.

- All start / loop / stop clips cut from one locomotion source must share one color curve. Never auto-white-balance each segment independently.
- Individual image views may use separate monotonic PCHIP curves, but every curve must target the same black/tan/white reference anchors.
- Apply grading after chromakey / despill without changing alpha. Never include the green background in white-balance statistics.
- Extract representative source frames, verify them with `Scripts/audit-png-color.swift`, and record accepted anchors in the build script. Do not auto-grade every runtime frame; that creates breathing color drift during motion.
- Composite all representative outputs over the same middle-gray background before delivery. Matching numbers do not replace checking pink whites, blue blacks, or oversaturated tan fur.

## 5. Keying and transparent-video output

The current starting point in `Scripts/build-assets.sh` is:

```text
chromakey=0x3f985b:0.075:0.025
despill=green:mix=0.30:expand=0.05
unsharp=5:5:0.25:3:3:0
scale=960:540:flags=lanczos+accurate_rnd
format=bgra
```

Re-sample green-screen color for every new video. Inspect fur edges over dark gray, pure black, and white backgrounds:

- Visible green outline: increase despill carefully; do not immediately expand chromakey similarity substantially.
- White fur disappears or becomes transparent: reduce chromakey similarity or softness.
- Black fur develops a gray fringe: verify straight versus premultiplied alpha handling.
- Flickering edge: first inspect compression noise and frame-to-frame exposure changes, then tune the key.
- Watermark region: use `delogo` only after measuring coordinates for the new resolution.

Output requirements:

```text
1280×720
120 fps
HEVC VideoToolbox with Alpha
-alpha_quality 0.95
-q:v 75
-tag:v hvc1
No audio track
```

Do not return to 640×360. The default display area is about 520 points wide; 640×360 is visibly enlarged on a Retina display and loses fur and eye detail.

## 6. Correct idle and gait loops

### 6.1 Truly periodic actions

Walk, run, and tail-wag loops have explicit phases. The first and last frame must use the same leg and the same contact phase. Never reverse a walking clip; reversed gait dynamics look physically wrong.

If no valid in-place gait loop exists, do not slide a static standing pose across the desktop. The app should remain standing instead of moving without foot motion.

### 6.2 Low-motion idles

Standing breathing, seated observation, lying, and sleep can use endpoint-deduplicated forward/reverse loops:

```text
forward:  0, 1, 2, ... N
reverse:  N-1, N-2, ... 1
loop:     0, 1, 2, ...
```

Remove duplicated endpoint frames at both the turn and the loop seam. Convert the result to a consistent 120 fps only after constructing the sequence; motion-interpolate low-frame-rate chroma footage instead of merely duplicating frames with `fps`.

Ping-pong is appropriate only for low-amplitude, weakly directional motion. A clear head turn, raised paw, roll, or walk will reveal reversal; find a more stable interval or construct a true closed loop instead.

### 6.3 Sleep

The user prefers the pet to sleep quietly when untouched. Never loop an entire sleep video containing tail sweeps, posture changes, or head lifts.

Find a roughly 0.5–1.0-second lowest-motion window containing only subtle breathing. If needed, slow it by about 1.5–2.5×, then build an endpoint-deduplicated ping-pong loop. The current asset uses a 0.55-second window slowed 2.5× for a final loop of roughly 2.7 seconds at 120 fps.

## 7. Runtime transition rules

`PetRenderer.swift` uses two independent decoder lanes:

1. Keep displaying the outgoing action.
2. Start decoding the incoming lane.
3. Begin fading only after the incoming lane has produced a real first frame; never fade toward an empty transparent frame.
4. Freeze the outgoing lane when the fade begins so both clips do not move simultaneously and create wobble.
5. Convert each lane to premultiplied alpha before blending.
6. Use a fifth-order smootherstep weight over about 0.14 seconds, about 17 samples on a 120 Hz presentation path. Its first and second derivatives are zero at both endpoints, reducing subtle opacity jolts compared with cubic smoothstep.
7. Keep clip-end callbacks and fade completion as separate lifecycles.

Do not switch walk, jog, and run from a single speed sample. Require a requested speed tier to remain stable for roughly 0.15–0.25 seconds and retain threshold hysteresis. Stop and fresh start may respond immediately. This short confirmation period prevents repeated crossfades when cursor speed oscillates near a threshold.

On a fresh transition from standing into locomotion, first recut the `start` clip near the first visible weight shift, then use a short `translationDelay` to align desktop translation with the paws. Current walk, jog, and run delays are about 0.12, 0.07, and 0.10 seconds, with velocity ramps of roughly 0.18, 0.13, and 0.10 seconds. Re-measure after every recut: avoid both planted-paw sliding and a long cursor-response pause.

Keep most crossfades within 0.10–0.16 seconds. Above about 0.20–0.25 seconds, realistic footage commonly shows double eyes, heads, paws, or tails. If a short fade remains obvious, repair the offline ports instead of lengthening the dissolve.

## 8. Required frame-by-frame QA

Every asset replacement requires more than launching the app for a few seconds.

### 8.1 Loop seams

Compare the last visible frame with the first frame of every idle or gait loop:

- Foot/contact displacement should ideally be no more than 1–2 pixels.
- Alpha-weighted center displacement should ideally be no more than 2 pixels.
- Subject-height change should be below 2%.
- Premultiplied RGB mean absolute difference should ideally be below 1; low-motion footage should generally remain below 2.

Current repaired reference values:

```text
stand-idle seam MAE ≈ 0.69
sit-idle seam MAE   ≈ 0.58
lie-idle seam MAE   ≈ 0.69
sleep-idle seam MAE ≈ 0.48
```

Current locomotion normalization results as of 2026-08-14:

```text
stand-idle → walk/jog/run start: subject-height difference ≈ 0–0.2%, ground difference 0–2 px
walk-loop seam: height difference ≈ 0.3%, center difference ≈ 0.3 px, ground difference 0 px
jog-loop seam: height difference ≈ 0%, center difference ≈ 0.2 px, ground difference 1 px
run-loop seam: height difference ≈ 0.3%, center difference ≈ 0.3 px, ground difference 0 px
sit-to-lie → lie-idle: subject-height difference reduced from ≈ 13.5% to ≈ 0.3%
```

These values document the current assets; they are not transform parameters to copy to future footage. Measure every new source independently.

The MAE figures are references, not universal hard limits. Any new source substantially above 2 requires visual inspection.

### 8.2 Action ports

For every adjacent pair, compare “outgoing last frame → incoming first frame”:

- Ground y difference should ideally be no more than 2 pixels.
- Same-posture subject-height difference should ideally be below 3%.
- Alpha center displacement should ideally be no more than 5 pixels.
- Identity, tail length, coat color, and body proportions must not change suddenly.

Composite endpoint frames over a middle-gray background and inspect them side by side. Similar alpha bounds do not prove the character shape is actually consistent.

### 8.3 On-device checks

- Inspect at 60%, 100%, and 140% display sizes.
- Inspect green/black fringes and alpha flicker over both dark and light desktops.
- Play every idle loop for at least three full cycles.
- Exercise the complete autonomous chain: sleep → wake → stand → sit → lie → sleep.
- Check for empty transparent frames, a still-moving outgoing action, double images, and sudden scale changes during transitions.
- Watch for sustained memory growth and confirm the old player lane is released after each fade.

`FURBALL_FAST_BEHAVIOR=1` may accelerate state-machine testing, but always launch once at normal speed before delivery.

## 9. Files to update with the project

After processing a new action, review all of these:

- `Scripts/build-assets.sh`: sources, cut points, loop construction, and correction parameters.
- `Assets/README.md`: view directories, legacy mappings, alternate footage, and duplicate records.
- `Sources/Furball2D/Assets/manifest.json`: canvas, frame rate, view, filenames, sources, and loop flags.
- `Sources/Furball2D/PetClip.swift`: action IDs, filenames, and resulting postures.
- `Sources/Furball2D/PetController.swift`: only legal posture paths may exist in the state graph.
- `README.md`: asset requirements and user-visible behavior.

Then run:

```bash
./Scripts/build-assets.sh
swift build
./Scripts/package-app.sh
```

`Scripts/package-app.sh` signs the app from a clean `/tmp` staging directory, then outputs:

```text
dist/Furball2D.app
dist/Furball2D.zip
```

Desktop File Provider may attach FinderInfo to a local app copy. Prefer the ZIP for transfer or strict signature validation, and run `codesign --verify --deep --strict` against the app extracted from that ZIP.

## 10. Explicitly forbidden shortcuts

- Do not apply one longer crossfade duration to every transition.
- Do not mark a full video with obvious movement as `loop: true`.
- Do not slide a static standing pose across the desktop as a substitute for walking.
- Do not upscale an old low-resolution transparent clip to 1280×720.
- Do not compare canvas sizes alone; measure subject bounds and the ground anchor.
- Do not use arbitrary non-uniform scaling merely to align bounding boxes.
- Do not chromakey at runtime; green-screen processing is an offline step.
- Do not copy old green colors, watermark coordinates, 6% scale values, or trim times onto new footage.
- Do not deliver without real on-device loop testing.

If source videos contain different pets, severely incompatible pose ports, or obvious generation deformation, report those limitations clearly and identify which entry/exit poses require regeneration. Request a correctly ported source instead of hiding the problem with a long dissolve.
