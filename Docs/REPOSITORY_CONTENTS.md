# GitHub 仓库内容说明

仓库名：`Furball`。仓库默认设为 private，因为其中包含用户提供的狗狗身份参考图和原始视频。

## 纳入仓库

- Swift 源码与 `Package.swift`
- `Assets/SourceImagesForAIVideo/` 下的 30 张 AI 视频生成参考图及用途说明
- `Assets/SourceVideos/` 下的 9 段原始视频（包含 1 个明确标注的完全重复归档）
- `Sources/Furball2D/Assets/Clips/left-profile/` 下的 8 段透明导出视频
- 素材清单 `manifest.json`
- 素材重建与应用打包脚本
- 中英文 README
- 根目录 `AGENTS.md` 视频处理规范
- `Assets/README.md` 旧文件名映射与视角目录说明
- `Support/Info.plist`

## 不纳入仓库

- `.build/`：Swift 本地构建缓存，可重新生成
- `dist/`：本地打包产物，可重新生成
- `.DS_Store` 与 Xcode 用户状态

上述排除项已经写入 `.gitignore`。图片、源视频和透明导出视频均小于 GitHub 单文件 100 MB 限制，当前不需要 Git LFS。仓库目前不附带开源许可证；如果未来转为 public，应先明确选择许可证并确认原始与 AI 生成素材的公开授权范围。
