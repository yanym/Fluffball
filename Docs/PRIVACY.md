# Furball2D Privacy / 隐私说明

[中文](#中文) · [English](#english)

## 中文

Furball2D 1.0 默认完全离线运行：

- 不包含账号、广告、分析、遥测或崩溃上传 SDK。
- 不发送鼠标位置、桌面内容、宠物照片或宠物包。
- 宠物设置、性格、当前状态和最多 48 小时的短期记忆保存在 macOS `UserDefaults`；可在宠物档案中清除记忆。
- 用户导入的宠物包保存在 `~/Library/Application Support/Furball2D/Pets/`。
- “导出创建请求”只在用户选择的本地目录创建照片副本、`REQUEST.json` 和创建 Skill，不上传任何内容。
- 用户明确确认“用 Codex 一键生成并导入”后，App 会启动本机已登录的 Codex CLI，并把所选照片副本交给其图片模型；App 不读取或保存 Codex 账号、Token 或 API Key。数据处理、套餐和用量限制由用户的 Codex 服务及其隐私政策负责。
- 一键创建的临时请求和日志位于 `~/Library/Application Support/Furball2D/CreationJobs/`；成功导入后自动删除，失败或用户取消时保留，便于查看日志和重试。

## English

Furball2D 1.0 runs locally by default:

- No account, advertising, analytics, telemetry, or crash-upload SDK is included.
- Cursor positions, desktop content, pet photos, and pet packs are never transmitted by the app.
- Pet preferences, personality, current state, and short-term memories retained for up to 48 hours are stored in macOS `UserDefaults`; memories can be cleared from the pet profile.
- Imported pet packs are stored under `~/Library/Application Support/Furball2D/Pets/`.
- Export Creation Request only copies photos, `REQUEST.json`, and the creator Skill into a local folder selected by the user and uploads nothing.
- After the user explicitly confirms Build & Import with Codex, the app launches the signed-in local Codex CLI and provides copies of the selected photos to its image model. The app never reads or stores Codex account data, tokens, or API keys. Data handling, plan terms, and usage limits are governed by the user’s Codex service and privacy policy.
- Temporary one-click requests and logs live under `~/Library/Application Support/Furball2D/CreationJobs/`. Successful imports remove them automatically; failed or cancelled jobs remain locally for logs and retrying.
