# Furball2D Privacy

Furball2D 1.0 runs locally by default:

- No account, advertising, analytics, telemetry, or crash-upload SDK is included.
- Cursor positions, desktop content, pet photos, and pet packs are never transmitted by the app.
- Pet preferences, personality, current state, and short-term memories retained for up to 48 hours are stored in macOS `UserDefaults`; memories can be cleared from the pet profile.
- The shipping app is read-only with respect to user files and folders. It cannot create, copy, move, rename, trash, or delete them and contains no Finder automation.
- Desktop interaction reads only visible item names and system-provided icons. All carried items are app-owned visual proxies; the real Finder item and its position remain unchanged.
- Runtime pet-pack import, export, deletion, creation requests, and local model launching are disabled. New bundled assets are produced only by the developer-side repository workflow.
- Developer QA screenshots and JSON reports are compiled out of release builds. They are available only in debug builds with explicit `FURBALL_*_QA` environment variables.
