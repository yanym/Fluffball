# Furball2D Commercial Release / 商业发布

[中文](#中文) · [English](#english)

## 中文

当前工程已具备 1.0 产品结构：稳定 Bundle ID `com.fluffball.Furball2D`、三外观、多宠物素材库、`.furballpet` 文件类型、应用内导入/导出/创建请求、双语 UI、离线素材验证、无网络依赖以及本地可验证安装包。

### 本地预览包

```bash
./Scripts/package-app.sh
open dist/Furball2D.app
```

本地包使用 ad-hoc 签名。`dist/Furball2D.zip` 是传输和严格签名复验的权威产物。

### Developer ID 与公证

发布者需要自己的 Apple Developer Program 账号、Developer ID Application 证书和 `notarytool` keychain profile：

```bash
FURBALL_CODESIGN_IDENTITY="Developer ID Application: COMPANY (TEAMID)" \
FURBALL_NOTARY_PROFILE="fluffball-notary" \
./Scripts/package-app.sh
```

脚本会启用 Hardened Runtime、时间戳签名、提交 Apple 公证、staple 并重新生成 ZIP。发布前再次执行：

```bash
codesign --verify --deep --strict dist/Furball2D.app
spctl --assess --type execute --verbose=4 dist/Furball2D.app
xcrun stapler validate dist/Furball2D.app
```

### 必须由发布方确认

- Nina 原始照片、原视频、AI 生成图像和 App 图标的商业使用权。
- 产品名称、商标、网站、支持邮箱和最终隐私政策 URL。
- Developer ID 证书、公证凭据和是否进入 Mac App Store；Mac App Store 版本还需单独启用 Sandbox 并重新审查文件导入权限。
- 版本号、更新渠道、崩溃报告/分析工具；当前版本不包含遥测。

## English

The project now has a 1.0 product structure: stable bundle ID `com.fluffball.Furball2D`, three appearances, multi-pet library, `.furballpet` document type, in-app import/export/creation requests, bilingual UI, offline asset validation, no network dependency, and a locally verifiable package.

### Local preview

```bash
./Scripts/package-app.sh
open dist/Furball2D.app
```

Local packages are ad-hoc signed. `dist/Furball2D.zip` is authoritative for transfer and strict signature verification.

### Developer ID and notarization

The publisher needs an Apple Developer Program account, Developer ID Application certificate, and `notarytool` keychain profile:

```bash
FURBALL_CODESIGN_IDENTITY="Developer ID Application: COMPANY (TEAMID)" \
FURBALL_NOTARY_PROFILE="fluffball-notary" \
./Scripts/package-app.sh
```

The script enables Hardened Runtime and timestamp signing, submits notarization, staples the result, and rebuilds the ZIP. Before release, run:

```bash
codesign --verify --deep --strict dist/Furball2D.app
spctl --assess --type execute --verbose=4 dist/Furball2D.app
xcrun stapler validate dist/Furball2D.app
```

### Publisher-owned confirmations

- Commercial rights for Nina’s source photos/video, AI-generated art, and the app icon.
- Final product name, trademarks, website, support email, and hosted privacy-policy URL.
- Developer ID/notarization credentials and whether to ship through the Mac App Store. A Store build also requires Sandbox enablement and a separate file-access review.
- Version/update channel and any crash-reporting or analytics provider. This build contains no telemetry.

