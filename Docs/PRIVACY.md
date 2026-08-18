# Furball2D Privacy

Furball2D 1.0 runs locally by default:

- No account, advertising, analytics, telemetry, or crash-upload SDK is included.
- Cursor positions, desktop content, pet photos, and pet packs are never transmitted by the app.
- Pet preferences, personality, current state, and short-term memories retained for up to 48 hours are stored in macOS `UserDefaults`; memories can be cleared from the pet profile.
- Imported pet packs are stored under `~/Library/Application Support/Furball2D/Pets/`.
- Export Creation Request only copies photos, `REQUEST.json`, and the creator Skill into a local folder selected by the user and uploads nothing.
- After the user explicitly confirms Build & Import with Codex, the app launches the signed-in local Codex CLI and provides copies of the selected photos to its image model. The app never reads or stores Codex account data, tokens, or API keys. Data handling, plan terms, and usage limits are governed by the user’s Codex service and privacy policy.
- Temporary one-click requests and logs live under `~/Library/Application Support/Furball2D/CreationJobs/`. Successful imports remove them automatically; failed or cancelled jobs remain locally for logs and retrying.
