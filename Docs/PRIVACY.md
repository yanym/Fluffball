# Furball2D Privacy

Furball2D 1.0 runs locally by default:

- No account, advertising, analytics, telemetry, or crash-upload SDK is included.
- Cursor positions, desktop content, pet photos, and pet packs are never transmitted by the app.
- Pet preferences, personality, current state, and short-term memories retained for up to 48 hours are stored in macOS `UserDefaults`; memories can be cleared from the pet profile.
- Desktop interaction is read-only: Furball cannot move, rename, trash, or delete Desktop items and contains no Finder automation. Explicit Pet Pack import, creation, and export are the only file-writing workflows.
- Desktop interaction reads only visible item names and system-provided icons. All carried items are app-owned visual proxies; the real Finder item and its position remain unchanged.
- User-invoked Pet Pack import validates the selected package before copying it into Furball's managed Application Support library. Create Pet may send the explicitly selected photos to a signed-in local Codex process; Furball stores no OpenAI account credential or API key.
- Developer QA screenshots and JSON reports are compiled out of release builds. They are available only in debug builds with explicit `FURBALL_*_QA` environment variables.
