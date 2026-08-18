# GitHub 仓库内容说明 / Repository Contents

[中文](#中文) · [English](#english)

## 中文

仓库名：`Furball`。仓库默认设为 private，因为其中包含用户提供的狗狗身份参考图和原始视频。

### 纳入仓库

- Swift 源码与 `Package.swift`
- `Assets/SourceImagesForAIVideo/` 下的 AI 图片/视频生成身份参考图及用途说明
- `Assets/ImageTurnMVP/` 下的多视角源图、归一化图片和 QA 资料
- `Assets/ImageMode/qa/contact-sheet.png`：当前 17 张图片模式运行时素材的接触表
- `Assets/SpritePets/Furball/` 与 `Assets/SpritePets/NinaRealistic/`：可爱/写实 Codex v2 图集生成记录、方向检查表和连续性 QA
- `Assets/SourceVideos/` 下的原始视频归档
- `Sources/Furball2D/Assets/Images/` 下的 17 张 960×540 透明 PNG 运行时图片
- `Sources/Furball2D/Assets/Sprites/Nina/{cute,realistic}/spritesheet.webp`：两套 3072×4576、8×11 的 2× 高清透明图片动画图集
- `Sources/Furball2D/Assets/Clips/` 下的 27 段透明运行时视频
- Pet Pack v2 素材清单 `manifest.json`：声明图片/视频能力、图集动画/绑定、16 方向、自定义双语动作和两套 27 个语义动作
- 图片素材构建、视频素材重建、素材验收和应用打包脚本
- Pet Pack v2 双语规范、双语项目 README 和双语 Agent 工作规范
- 随 App 发布的双语 `furball-pet-creator` Skill、动作注册表、模板与独立验证器
- `Assets/README.md` 中的素材来源、命名和目录说明
- `Support/Info.plist` 与应用图标

图片与视频是并列的可选表示。纯图片 Pet Pack 可以不包含 `Clips/`；当前 Furball 示例包同时包含两种模式，因此仓库仍保留视频源文件与透明导出视频。

### 不纳入仓库

- `.build/`：Swift 本地构建缓存，可重新生成
- `dist/`：本地打包产物，可重新生成
- `.DS_Store` 与 Xcode 用户状态

上述排除项已经写入 `.gitignore`。当前单个图片与视频文件均低于 GitHub 100 MB 限制，不需要 Git LFS。仓库目前不附带开源许可证；如果未来转为 public，应先明确选择许可证，并确认原始素材、身份参考图与 AI 生成素材的公开授权范围。

## English

Repository name: `Furball`. Keep the repository private by default because it contains user-provided identity references and original pet footage.

### Included

- Swift sources and `Package.swift`
- Identity references and usage guidance under `Assets/SourceImagesForAIVideo/`
- Multi-view sources, normalized stills, and QA material under `Assets/ImageTurnMVP/`
- `Assets/ImageMode/qa/contact-sheet.png`, covering the current 17 image-runtime assets
- `Assets/SpritePets/Furball/` and `Assets/SpritePets/NinaRealistic/`, containing Cute/Realistic Codex v2 generation records, direction sheets, and continuity QA
- Archived source footage under `Assets/SourceVideos/`
- Seventeen transparent 960×540 runtime PNGs under `Sources/Furball2D/Assets/Images/`
- The two transparent 3072×4576, 8×11 2× runtime atlases under `Sources/Furball2D/Assets/Sprites/Nina/{cute,realistic}/`
- Twenty-seven transparent runtime video clips under `Sources/Furball2D/Assets/Clips/`
- The Pet Pack v2 `manifest.json`, declaring image/video capabilities, atlas animations/bindings, 16 directions, localized custom actions, and both sets of 27 semantic actions
- Image building, video rebuilding, pack validation, and app packaging scripts
- The bilingual Pet Pack v2 specification, project README, and Agent workflow guide
- The bundled bilingual `furball-pet-creator` Skill, action registry, template, and standalone validator
- Asset provenance, naming, and directory guidance in `Assets/README.md`
- `Support/Info.plist` and the application icon

Images and videos are parallel optional representations. An image-only Pet Pack may omit `Clips/`; the current Furball example supports both modes, so its source footage and transparent exports remain in the repository.

### Excluded

- `.build/`: reproducible local Swift build cache
- `dist/`: reproducible local application packages
- `.DS_Store` and Xcode user state

These exclusions are recorded in `.gitignore`. No current image or video exceeds GitHub's 100 MB single-file limit, so Git LFS is not required. The repository does not currently include an open-source license. Before making it public, select a license and confirm publication rights for originals, identity references, and AI-generated assets.
