# Furball2D Commercial Release

The project has a release-ready product structure: stable bundle ID `com.fluffball.Furball2D`, three appearances, multi-pet library, `.furballpet` document type, in-app import/export/creation requests, English UI, offline asset validation, no network dependency, and a locally verifiable package.

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
