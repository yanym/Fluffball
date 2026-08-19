# Furball

[English](#english) · [中文](#中文) · [Asset catalog](Assets/README.md) · [AI video references](Assets/Pets/Nina/UserProvided/SourceImagesForAIVideo/README.md) · [Agent guide](AGENTS.md) · [Commercial release](Docs/COMMERCIAL_RELEASE.md) · [Privacy](Docs/PRIVACY.md)

## English

Furball is a multi-pet desktop companion for Apple Silicon Macs running macOS 14 or later. Nina ships with Live Motion and Realistic 2D; Fortune is the second bundled profile and ships with a photo-grounded Realistic 2D appearance. One behavior engine renders HEVC-with-alpha footage through AVFoundation/VideoToolbox or Codex-compatible transparent WebP atlases through Metal, so a new pet no longer needs an expensive generated-video set.

### Features

- Natural sleep, wake, stand, sit, and lie-down behavior, including autonomous rest when the pet is idle.
- Posture-aware cute dialogue; the speech bubble scales with the pet, follows its motion, and avoids the active image or video alpha silhouette.
- The app and bundled creation workflow use English throughout; this README remains bilingual.
- Each profile declares a relative body size from 1–100; the independent Display Scale setting ranges continuously from 60% to 140%.
- Settings uses a sidebar with General, Appearance, Behavior, Desktop Interaction, Group Play, Dialogue, Pet Library, and Create Pet. The menu-bar item keeps only immediate actions, and video blending is absent in image mode.
- Group Play can show any checked image-capable pets together. Each companion has an independent 60 Hz movement controller, slows to a real stop, reflects away from screen edges, and periodically approaches another pet for play bows, head tilts, waves, and happy dances.
- Pet Library selects bundled or imported profiles, validates `.furballpet` packages before installing them into Furball's managed Application Support library, and shows personality and memory state. Create Pet and the bundled English Creator Skill are available again.
- Image mode requires an 8×11, 2× Codex v2 transparent WebP atlas with variable frame durations and real gait phases, blink, wave, jump, hopeful wait, search, review, and disappointed actions. Standalone PNG animation fallback has been removed.
- Alpha-aware mouse click-through, with an optional full pass-through mode.
- Smoother action changes using a fifth-order fade curve, subject-height/center/ground port alignment, and seamless idle loops.
- Offline black/tan/white fur anchor matching keeps separate generation batches from becoming abruptly warmer or brighter during locomotion and view changes.
- Real walk, jog, and run footage moves the pet in any desktop direction. Cursor-follow mode selects a gait from two-dimensional distance and cursor speed.
- Free Roam chooses safe two-dimensional destinations across the current desktop, pauses briefly after each arrival, and then continues exploring.
- With Desktop Item Interaction enabled, an image pet can discover a Desktop item and perform a head tilt, sniff, paw tap, play bow, inspection, guard, or happy dance. Carrying uses an app-owned visual copy of the icon; the real item and Finder layout never move.
- Desktop interaction is strictly read-only and contains no Finder AppleScript. The only file-writing flows are explicit Pet Pack import/creation/export actions; installation is path-guarded to Furball's managed Application Support library. `Scripts/audit-runtime-safety.sh` is a mandatory packaging gate.
- Cursor gaze uses 16 evenly spaced directions at 22.5° intervals. Eyes lead, then the head, neck, ears, and ruff follow; the idle pet walks the shortest adjacent-direction path instead of snapping across the circle.
- A manifest-driven “Cute Actions” submenu exposes 16 actions, including Wave, Happy Jump, Head Tilt, Sniff, High Five, Stretch, Sneeze, Paw Tap, Happy Dance, Yawn, and Chase Tail. A custom pack can add or rename actions without changing Swift.
- Image pets respond to the pointer: a short hover produces a curious head tilt, a double-click gives a high five, and Toss a Treat makes the pet walk/run in two dimensions to the cursor and sniff the treat.
- Every Realistic 2D appearance uses the same `furball-image-state-v1` posture stages. Different pet profiles cannot remap sleep to a standing head dip; imported packs are rejected unless lie and sleep use horizontal silhouettes and the shared bindings. MP4 animation ports remain independent.
- The sleep flow explicitly separates awake horizontal lying, eye-close, one canonical closed-eye sleep cell, and full wake-up. Runtime adds only a continuous eight-second, sub-pixel breathing transform, so sleep never pulses through several atlas poses.
- The image pet waits until the pointer has settled for roughly 0.32 seconds, then steps deliberately through adjacent cells toward one of 16 gaze directions without translucent pose blending. After roughly 2.4 seconds it returns to breathing/blinking idle. Gestures marked `autonomous` naturally appear in the rest routine before the pet sits, sleeps, or later patrols.
- Runtime mirroring gives the left-profile footage a right-facing counterpart, so autonomous idles, tail wags, posture transitions, and sleep retain the selected side.
- Pet and appearance cards remain available during every action. A user selection immediately interrupts locomotion, gaze, a one-shot gesture, or autonomous behavior and starts the selected profile from its stable standing port.
- Live Motion head tracking uses five stable view anchors, a short intention dwell, and complete decoder fades instead of rapidly cycling through all nine generated views.
- Runtime resolves assets by Pet Pack semantic action IDs, so paths and loop behavior are no longer hardcoded. Conforming dog and cat packs can reuse one behavior engine.
- The menu-bar dropdown and Settings both include an update control. Furball checks the latest public GitHub Release, prompts only when its semantic version is newer, and opens the preferred DMG or ZIP download in the browser; it never installs an update silently.

### Build and run

Requirements: Apple Silicon, macOS 14 or later, Swift 6 Command Line Tools, and FFmpeg 8 with `hevc_videotoolbox` support.

```bash
./Scripts/build-assets.sh
./Scripts/package-app.sh
open dist/Furball.app
```

Packaged outputs are written to:

```text
dist/Furball.app
dist/Furball.zip
```

The app-icon source is stored at `Support/AppIcon.png`. To replace it, provide another square image and run `./Scripts/build-app-icon.sh`; the packaging script embeds the generated multi-resolution `AppIcon.icns` in the app bundle.

The current package includes Nina's 1280×720/120 fps HEVC-with-alpha video plus Nina's and Fortune's Realistic atlases. Every atlas is a 3072×4576 lossless transparent WebP built from native high-resolution action rows rather than enlarged runtime cells. Nina's phase-closed gait cycles are repeated inside roughly ten-second video items to avoid frequent AVQueuePlayer decoder handoffs during walking and running.

The distributable Pet Pack creation Skill ships inside the app and lives at [`Sources/Furball2D/CreatorSkill`](Sources/Furball2D/CreatorSkill). Create Pet can use a signed-in local Codex to generate and validate a 2D Pet Pack, or export the same request and Skill for another image-capable model.

See the [Pet Pack v2 specification](Docs/PET_PACK_STANDARD.md) for the dual-mode contract, 27 semantic slots, and current implementation boundaries. Run the validator once per folder under `Sources/Furball2D/Assets/Pets/`; `Scripts/package-app.sh` does this automatically.

### Asset layout

```text
Assets/
└── Pets/
    ├── Nina/{UserProvided,Generated}/
    └── Fortune/{UserProvided,Generated}/

Sources/Furball2D/Assets/
└── Pets/
    ├── Nina/{manifest.json,Clips,Sprites}/       # Image + Live Motion
    └── Fortune/{manifest.json,Sprites}/         # Image-only
```

The source action chain uses a consistent `left-profile` view; right-facing actions are produced by runtime mirroring. Preprocessed assets are 1280×720 at 120 fps in HEVC with Alpha. Stand, sit, and lie idles use endpoint-deduplicated forward/reverse loops. Sleep uses only a low-motion breathing window. Transition and locomotion clips are smoothly corrected on a transparent work canvas for subject scale, alpha center, and ground anchor.

See [Assets/README.md](Assets/README.md) for legacy filename mappings, alternate footage, and duplicate records. When generating new actions, start with the [generation-ready reference guide](Assets/Pets/Nina/UserProvided/SourceImagesForAIVideo/README.md). Any Agent replacing video assets must first read [AGENTS.md](AGENTS.md).

### Interaction

- Click the dog: say a line and advance to the next legal action.
- Drag the dog: reposition the desktop pet.
- Right-click the dog or click the menu-bar paw: open settings.
- “Display Scale”: continuously magnify the profile-defined body size from 60% to 140%.
- “Appearance”: choose the active pet directly on this page, then switch among the representations it supplies: Live Motion and Realistic 2D. Selecting a row in My Pets also activates that pet immediately; there is no second confirmation step.
- “Settings”: the sidebar directly manages General, Appearance, Behavior, Desktop Interaction, Group Play, Dialogue, Pet Library, and Create Pet. Display scale and window level live here instead of in the menu-bar item; video blending appears only for Live Motion.
- “Pet Library”: import a validated `.furballpet` package, select a pet, and inspect its profile.
- “Create Pet”: choose 6–12 photos and create one maintainable Realistic 2D pack through local Codex, or export the standardized request and bundled Creator Skill.
- “Group Play”: enable several checked pets at once. They roam independently, preserve each profile's body size, avoid overlap, stop when they arrive, turn away from walls, and meet for paired social actions.
- “Pet Profile”: each pet keeps adjustable Vitality, Curiosity, Affection, and Composure traits plus dynamic Energy, Wonder, and Bond. The three newest short-term memories are visible and can be cleared at any time.
- “Cute Actions”: shows pack-provided image actions in image mode and disables itself in video mode, while moving, or during a transition.
- “Sleep Now”: traverse the legal posture chain and go to sleep.
- “Look at Me”: stand up, turn through the front and right-side image keyframes, then return to a profile idle.
- “Look Toward Cursor (16 Directions)”: use both cursor axes while standing idle and advance one neighboring direction at a time; before locomotion, take the shortest path to the matching left or right profile port.
- “Follow Cursor (Move in Any Direction)”: follow the cursor in two dimensions, walking nearby, jogging at medium demand, and running when far away or when the cursor moves quickly.
- “Free Roam (Across Desktop)”: continuously visit random destinations on the current desktop. It is mutually exclusive with cursor following; disabling it restores the previous daily routine.
- “Inspect desktop items while roaming”: lets image pets visit Trash and Desktop items using read-only names and icon previews. Every interaction is visual; Furball never changes Finder or the item.
- “Daily Routine (Sleep / Patrol)”: sleep, wake, and take a short outing while idle. This routine is suspended during Free Roam.
- “Smooth Action Transitions”: enable or disable the short crossfade to compare action boundaries.
- “Toss a Treat by Cursor”: the image pet walks, jogs, or runs to the pointer and performs its sniff action on arrival.
- Hover and double-click: the image pet responds with a head tilt or high five.

After a personality-dependent idle period, the dog sits, lies down, and sleeps. Personality and current state influence sleep length, whether an outing favors play or exploration, and whether movement becomes a walk, jog, or run. Petting, high fives, treats, desktop exploration, appearance changes, and naps create up to 12 local short-term memories retained for no more than 48 hours.

### Image animation mode

Image mode reads only Codex v2 WebP atlas cells. `manifest.json` declares `stateModel: furball-image-state-v1`, standard rows, frame counts, per-frame durations, loops, short blend fractions, true left/right gait rows, all 27 semantic bindings, 16 look directions, and English custom actions. The state model fixes stand/sit/lie/sleep ports across every profile and appearance; MP4 clips remain separately declared. The runtime decodes each WebP once, places requested cells on a shared 16:9 render canvas, and caches Metal textures. Real gait rows do not receive procedural squash/stretch; desktop translation retains only an approximately 0.07-second image-mode acceleration ramp.

Both built-in image atlases use the v2 8×11 semantic layout at `assetScale: 2`: 3072×4576 with 384×416 cells. The final two rows contain all 16 gaze directions. Imports must use this current 2× format.

### Locomotion footage

The walk, jog, and run sources are stored as `stand-to-walk-to-stand.mp4`, `stand-to-slow-run-to-stand.mp4`, and `stand-to-fast-run-to-stand.mp4`. The build script exports start, phase-closed loop, and stop segments from each source and aligns every junction to the same scale, center, and ground baseline. Directional gaits are never reversed. At runtime, a requested speed tier must remain stable briefly before switching. On a fresh start, desktop translation waits for the first real step in the source and then accelerates along a smooth curve, preventing stationary frames from sliding across the floor.


---

## 中文

Furball 是一个仅面向 Apple Silicon、macOS 14 及以上版本的多宠物桌面伴侣。Nina 内置真实连续动画和写实 2D；Fortune 是第二个内置宠物 profile，带有基于真实照片制作的写实 2D 外观。同一行为引擎既能通过 AVFoundation/VideoToolbox 播放带 Alpha 的写实视频，也能用 Codex 兼容的透明 WebP 图集与 Metal 运行。

### 功能

- 狗狗会睡觉、醒来、站立、坐下和趴下，并在无人互动时自行休息。
- 根据姿态随机显示可爱对话；气泡会按宠物大小缩放、跟随动作，并依据当前图片或视频的 Alpha 轮廓自动避开身体。
- App、素材合同和内置创建流程统一使用英语；本 README 继续保留中英文说明。
- 每个宠物 profile 定义 1–100 的相对体型；独立的界面显示缩放支持 60%–140% 无级调节。
- “设置”窗口使用左侧栏直接提供通用、外观、行为、桌面互动、宠物群、对话、宠物素材库和创建宠物；顶栏菜单只保留即时动作入口，视频专用的柔和过渡不会出现在图片模式中。
- “宠物群”可让用户勾选任意支持图片模式的宠物一起出现。每只宠物独立进行 60 Hz 平滑移动，会在抵达目标后及时停下、在屏幕边缘反向，并定期会合做出邀请玩耍、歪头、挥爪和开心舞等互动。
- “宠物素材库”可导入通过验证的 `.furballpet` 素材包、切换宠物并展示性格和记忆；创建宠物和英文 Creator Skill 已恢复。
- 图片模式只读取 8×11、每格 384×416 的 2× 高清 v2 透明 WebP 图集，以可变逐帧时长播放真实步态、眨眼和 16 个菜单动作；旧版独立 PNG 回退已经删除。
- 透明区域自动穿透鼠标，也可开启完全穿透。
- 通过五阶淡化曲线、主体高度/中心/脚底三重端口对齐和无缝待机循环改善动作衔接。
- 不同生成批次会在离线导出时统一到站立基准的黑毛、棕毛和白毛色彩锚点，避免走路、跑步或转向时突然变暖、变亮。
- 狗狗会使用真实走路、慢跑和快跑素材在桌面全方向移动；开启“追随鼠标”后会依据二维距离与鼠标速度自动换挡。
- “自由漫游”会在当前桌面的安全范围内随机选择二维目标，走到后停留片刻，再继续探索。
- 图片宠物自由漫游时会偶尔观察废纸篓和桌面项目，并组合歪头、闻闻、爪爪轻碰、邀请玩耍、认真检查、守护和开心舞等动作。叼取使用 App 自己的图标视觉副本，真实项目与 Finder 排列始终不变。
- 桌面互动严格只读且不包含 Finder AppleScript。只有用户主动执行的宠物素材导入、创建和导出可以写入文件；安装目标被严格限制在 Furball 自己的 Application Support 素材库。打包前必须通过 `Scripts/audit-runtime-safety.sh`。
- 不依赖 AI 视频的视线跟随使用 16 个等距方向（每 22.5° 一格）；眼睛先动，头颈、耳朵和胸毛随后跟进，站立待机时会沿最短相邻路径看向鼠标，不跨方向瞬移。
- 图片模式的“可爱动作”子菜单由素材包声明；当前提供 16 种动作，包括挥爪、跳跳、歪头、闻闻、击掌、伸懒腰、喷嚏、爪爪敲敲、开心舞、哈欠和追尾巴等，后续宠物可以只改 `manifest.json` 添加或改名，无需修改 Swift。
- 图片宠物支持更多鼠标互动：悬停一会会好奇歪头，双击会击掌，菜单可在鼠标旁丢下一块零食，让宠物全方向走跑过去寻找。
- 所有写实 2D 外观统一使用 `furball-image-state-v1` 姿态模型。不同宠物不能再把睡眠映射成站立低头；不满足共享绑定及水平趴卧轮廓的导入包会被拒绝。MP4 动画端口继续独立管理。
- 睡眠 flow 将“醒着水平趴卧 → 闭眼 → 单张闭眼睡姿 → 完整醒来”拆成明确端口；运行时仅叠加八秒一周期、亚像素幅度的连续呼吸，不再轮播多张睡眠图片。
- 鼠标停止移动约 0.32 秒后，图片宠物才按相邻格逐步看向 16 个方向，并且不再混合两个姿势产生重影；静止约 2.4 秒后自动回到会呼吸、眨眼的动态待机。标记为 `autonomous` 的可爱动作会自然穿插在休息流程中，然后宠物继续坐下、睡觉或出门巡逻。
- 左侧面的动作视频可在运行时镜像为右侧动作，因此自主待机、摇尾巴、姿态过渡和睡眠都能保持选定的左右朝向。
- 任何动作中都可直接选择宠物或外观；用户选择会立即中断移动、转头、一次性动作或自动行为，并从新 profile 的稳定站立动作开始。
- Live Motion 的鼠标转头改为五个稳定视角锚点、短暂意图停留和完整解码淡化，不再高速轮换九个视角造成双脸闪烁。
- 运行时通过 Pet Pack 标准动作 ID 读取素材，文件路径和循环属性不再硬编码；同规格的狗狗或猫猫素材包可复用同一行为引擎。
- 顶栏下拉菜单和设置页都提供更新按钮；应用只在检测到更高版本的公开 GitHub Release 时提示，并由浏览器打开 DMG 或 ZIP，不会静默安装。

### 运行与构建

要求：Apple Silicon、macOS 14+、Swift 6 Command Line Tools，以及支持 `hevc_videotoolbox` 的 FFmpeg 8。

```bash
./Scripts/build-assets.sh
./Scripts/package-app.sh
open dist/Furball.app
```

打包结果位于：

```text
dist/Furball.app
dist/Furball.zip
```

应用图标源文件保存在 `Support/AppIcon.png`。需要替换图标时，放入新的正方形图片并运行 `./Scripts/build-app-icon.sh`；打包脚本会将生成的多尺寸 `AppIcon.icns` 写入应用包。

当前安装包包含 Nina 的 1280×720、120 fps HEVC with Alpha 视频，以及 Nina 与 Fortune 的两张 3072×4576 写实 2D 无损透明 WebP 高清图集。原始 24 fps 动作在抠像前使用双向运动补偿插帧；图集从完整高清动作行重新切格，不放大旧的 192×208 运行时格子。

Pet Pack 创建 Skill 随 App 发布，也保存在 [`Sources/Furball2D/CreatorSkill`](Sources/Furball2D/CreatorSkill)。创建宠物可以调用本机已登录的 Codex 生成并验证 2D 素材包，也可以导出相同请求和 Skill 给其他图片模型。

通用宠物素材包的多外观合同、27 个语义槽位和当前实现边界记录在 [Pet Pack v2 规范](Docs/PET_PACK_STANDARD.md)。验收时对 `Sources/Furball2D/Assets/Pets/` 下的每个宠物目录分别运行 validator；`Scripts/package-app.sh` 会自动完成。

### 素材结构

```text
Assets/
└── Pets/
    ├── Nina/{UserProvided,Generated}/
    └── Fortune/{UserProvided,Generated}/

Sources/Furball2D/Assets/
└── Pets/
    ├── Nina/{manifest.json,Clips,Sprites}/       # 图片 + 真实连续动画
    └── Fortune/{manifest.json,Sprites}/         # 仅图片
```

源动作链统一使用 `left-profile` 视角，右向动作由运行时镜像得到。素材预处理输出为 1280×720、120 fps、HEVC with Alpha。站立、坐姿和趴卧待机使用首尾去重的正放/倒放循环；睡眠只截取低动作呼吸窗口；过渡和移动片段会在透明工作画布上平滑校正主体尺度、Alpha 中心与脚底锚点。

完整旧文件名映射、备用素材与重复文件说明见 [Assets/README.md](Assets/README.md)。生成新动作时优先使用 [generation-ready 参考图说明](Assets/Pets/Nina/UserProvided/SourceImagesForAIVideo/README.md)，后续 Agent 在替换视频前必须阅读 [AGENTS.md](AGENTS.md)。

### 交互

- 单击狗狗：说一句话并进入下一合法动作。
- 拖拽狗狗：移动桌宠。
- 右键狗狗或点击菜单栏爪印：打开设置。
- “显示缩放”：在宠物 profile 定义的相对体型之上连续缩放 60%–140%。
- “外观”：可先在本页直接选择当前宠物，再切换素材包实际提供的真实连续动画与写实 2D；在“宠物素材库”点选一只宠物也会立即激活，不再需要第二次确认。
- “设置”：左侧栏直接管理通用、外观、行为、桌面互动、Group Play、对话、宠物素材库和创建宠物；显示缩放与始终置顶也只在这里设置，仅真实连续动画显示视频混合设置。
- “宠物素材库”：导入经过验证的 `.furballpet` 素材包、切换宠物并查看档案。
- “创建宠物”：选择 6–12 张照片，通过本机 Codex 创建一套便于长期维护的写实 2D 外观，也可导出标准请求和 Creator Skill。
- “宠物群”：勾选需要同时出现的宠物；它们会分别漫游、避让、停步、撞墙反向，并进行成对互动。
- “宠物档案”：每只宠物保存可调的活力、好奇心、亲人和沉稳性格，以及会随休息、移动和互动变化的精力、探索欲与亲密度。最近三条短期记忆可见并可随时清除。
- “可爱动作”：图片模式下显示素材包自带动作；视频模式、移动中或过渡中自动置灰。
- “现在去睡觉”：立即走完合法姿态链并睡觉。
- “转过来看看我”：先站起，再用静态图片关键帧转向正面和右侧，最后回到侧面待机。
- “跟随鼠标看向 16 个方向”：站立待机时同时使用鼠标的横向和纵向位置，每次只走一个相邻方向；进入走跑动作前再沿最短路径抵达对应左右侧面端口。
- “追随鼠标（全方向走 / 跑）”：让狗狗沿二维方向追随鼠标，近距离走路、中距离慢跑、远距离或快速移动时快跑。
- “自由漫游（全桌面）”：持续在当前桌面内随机走动；与“追随鼠标”互斥，关闭后恢复原先的自动作息。
- “桌面物品互动”：允许图片宠物读取项目名称与系统图标并表演多种动作；叼起的只是 App 内视觉副本，真实文件及其位置不会发生任何变化。
- “自动作息（睡觉 / 巡游）”：无人互动时自行睡觉、醒来和进行一次短巡游；自由漫游期间会暂时挂起。
- “柔和动作过渡”：启用或关闭短 Crossfade，方便比较动作边界。
- “在鼠标旁丢个零食”：图片宠物会走、慢跑或快跑到鼠标位置，找到后执行闻闻动作。
- 悬停与双击：图片宠物会歪头回应，双击会击掌。

无人互动一段时间后，狗狗会按自己的性格与精力依次坐下、趴下并睡觉；睡多久、醒来后偏向玩耍还是探索、移动时选择走路还是跑步，都由性格与此刻状态共同影响。摸摸、击掌、零食、桌面探索、换外观和睡觉会形成最多 12 条、保留不超过 48 小时的本地短期记忆。

### 图片动画模式

图片模式只读取 Codex v2 WebP 图集单元格。图集由 `manifest.json` 声明 `stateModel: furball-image-state-v1`、标准行、帧数、每帧时长、循环、短溶解比例、左右真实步态、27 个语义绑定、16 个方向以及英文自定义动作。该状态模型统一所有 profile 和外观的站立、坐下、趴卧与睡眠端口；MP4 clips 继续单独声明。运行时一次解码 WebP，将使用到的格子铺到统一 16:9 小画布并缓存 Metal 纹理；真实走跑行不再叠加程序化 squash/stretch，桌面位移只保留约 0.07 秒速度渐入。

可爱与写实图集使用 `spriteVersionNumber: 2`、`assetScale: 2` 的 8×11 语义布局：3072×4576、384×416 单元格；最后两行是完整 16 方向。导入包也必须使用这一最新版 2× 格式。

### 移动素材

走路、慢跑和快跑原片分别保存为 `stand-to-walk-to-stand.mp4`、`stand-to-slow-run-to-stand.mp4` 和 `stand-to-fast-run-to-stand.mp4`。构建脚本会从每段原片导出起步、相位闭合循环和停步三部分，并让三段连接处落在同一尺度、中心和脚底基线上；方向性步态不会倒放。运行时速度档位需要短暂稳定后才切换。首次起步时，桌面位移会等待素材里的第一步真正开始，再用平滑曲线加速，避免站立帧在地面滑动。
