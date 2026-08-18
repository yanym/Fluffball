# Repository Contents

Repository name: `Furball`. Keep the repository private by default because it contains user-provided identity references and original pet footage.

### Included

- Swift sources and `Package.swift`
- Identity references and usage guidance under `Assets/UserProvided/SourceImagesForAIVideo/`
- Multi-view sources, normalized stills, and QA material under `Assets/Generated/ImageTurn/`
- `Assets/Generated/SpritePets/Furball/` and `Assets/Generated/SpritePets/NinaRealistic/`, containing Cute/Realistic Codex v2 generation records, direction sheets, and continuity QA
- Archived source footage under `Assets/UserProvided/SourceVideos/`
- The two transparent 3072×4576, 8×11 2× runtime atlases under `Sources/Furball2D/Assets/Sprites/Nina/{cute,realistic}/`
- Twenty-seven transparent runtime video clips under `Sources/Furball2D/Assets/Clips/`
- The Pet Pack v2 `manifest.json`, declaring image/video capabilities, atlas animations/bindings, 16 directions, localized custom actions, and both sets of 27 semantic actions
- Atlas-source preparation, video rebuilding, pack validation, and app packaging scripts
- The English Pet Pack v2 specification and Agent workflow guide, plus the bilingual project README
- The bundled English `furball-pet-creator` Skill, action registry, template, and standalone validator
- Asset provenance, naming, and directory guidance in `Assets/README.md`
- `Support/Info.plist` and the application icon

Sprite atlases and videos are parallel optional representations. An image-only Pet Pack may omit `Clips/`; the current Furball example supports both modes, so its source footage and transparent exports remain in the repository.

### Excluded

- `.build/`: reproducible local Swift build cache
- `dist/`: reproducible local application packages
- `.DS_Store` and Xcode user state

These exclusions are recorded in `.gitignore`. No current image or video exceeds GitHub's 100 MB single-file limit, so Git LFS is not required. The repository does not currently include an open-source license. Before making it public, select a license and confirm publication rights for originals, identity references, and AI-generated assets.
