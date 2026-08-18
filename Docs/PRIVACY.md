# Furball2D Privacy / 隐私说明

[中文](#中文) · [English](#english)

## 中文

Furball2D 1.0 默认完全离线运行：

- 不包含账号、广告、分析、遥测或崩溃上传 SDK。
- 不发送鼠标位置、桌面内容、宠物照片或宠物包。
- 宠物设置保存在 macOS `UserDefaults`。
- 用户导入的宠物包保存在 `~/Library/Application Support/Furball2D/Pets/`。
- “创建 2D 宠物”只在用户选择的本地目录创建照片副本、`REQUEST.json` 和创建 Skill；App 本身不上传照片，也不调用图片或视频模型。
- 当用户把创建请求交给 ChatGPT、Codex 或其他模型时，数据处理由用户选择的服务及其隐私政策负责。

## English

Furball2D 1.0 runs locally by default:

- No account, advertising, analytics, telemetry, or crash-upload SDK is included.
- Cursor positions, desktop content, pet photos, and pet packs are never transmitted by the app.
- Pet preferences are stored in macOS `UserDefaults`.
- Imported pet packs are stored under `~/Library/Application Support/Furball2D/Pets/`.
- Create 2D Pet only copies photos, `REQUEST.json`, and the creator Skill into a local folder chosen by the user. The app itself uploads nothing and calls no image or video model.
- If the user gives that creation request to ChatGPT, Codex, or another model, data handling is governed by the selected service and its privacy policy.

