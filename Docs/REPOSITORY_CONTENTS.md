# Repository Contents

Repository name: `Furball`. Keep the repository private by default because it contains user-provided identity references and original pet footage.

### Included

- Swift sources and `Package.swift`
- Identity references and usage guidance under `Assets/Pets/Nina/UserProvided/SourceImagesForAIVideo/`
- Multi-view sources, normalized stills, and QA material under `Assets/Pets/Nina/Generated/ImageTurn/`
- `Assets/Pets/Nina/Generated/SpritePets/NinaRealistic/`, containing the retained Realistic 2D Codex v2 generation record, direction sheets, and continuity QA
- Archived source footage under `Assets/Pets/Nina/UserProvided/SourceVideos/`
- Nina's transparent 3072×4576, 8×11 2× Realistic 2D runtime atlas under `Sources/Furball2D/Assets/Pets/Nina/Sprites/Nina/realistic/`
- Twenty-seven transparent runtime video clips under `Sources/Furball2D/Assets/Pets/Nina/Clips/`
- Fortune's six immutable identity photos, grounded generation run, and native-HD QA under `Assets/Pets/Fortune/`
- Fortune's image-only 3072×4576 Realistic 2D runtime atlas under `Sources/Furball2D/Assets/Pets/Fortune/`
- One Pet Pack v2 `manifest.json` per named pet, declaring image/video capabilities, atlas animations/bindings, 16 directions, localized custom actions, and all 27 semantic actions
- Atlas-source preparation, video rebuilding, pack validation, and app packaging scripts
- The English Pet Pack v2 specification and Agent workflow guide, plus the bilingual project README
- The bundled English `furball-pet-creator` Skill, action registry, template, and standalone validator
- Asset provenance, naming, and directory guidance in `Assets/README.md`
- `Support/Info.plist` and the application icon

Sprite atlases and videos are parallel optional representations. Nina supports both modes and Fortune is image-only, so Fortune correctly omits `Clips/` while reusing the same behavior engine.

### Excluded

- `.build/`: reproducible local Swift build cache
- `dist/`: reproducible local application packages
- `.DS_Store` and Xcode user state

These exclusions are recorded in `.gitignore`. No current image or video exceeds GitHub's 100 MB single-file limit, so Git LFS is not required. The repository does not currently include an open-source license. Before making it public, select a license and confirm publication rights for originals, identity references, and AI-generated assets.
