import Foundation

private struct PetAssetManifest: Decodable {
    struct PetDescriptor: Decodable {
        let id: String
        let name: String?
        let species: String?
        let assetVersion: Int?
        let bodySize: Int?
    }

    struct CapabilitiesDescriptor: Decodable {
        let imageMode: Bool?
        let videoMode: Bool?
    }

    struct ClipDescriptor: Decodable {
        let id: String
        let file: String
        let loop: Bool
    }

    struct SpriteAtlasDescriptor: Decodable {
        struct LayoutDescriptor: Decodable {
            let columns: Int
            let rows: Int
            let cellWidth: Int
            let cellHeight: Int
        }

        struct RenderingDescriptor: Decodable {
            let canvasWidth: Int
            let canvasHeight: Int
            let bottomPadding: Int?
        }

        struct AnimationDescriptor: Decodable {
            let id: String
            let rowIndex: Int
            let frameCount: Int
            let frameDurations: [TimeInterval]
            let loop: Bool
            let motion: PetImageMotion
            let frameBlendFraction: Double?
        }

        struct BindingDescriptor: Decodable {
            let id: String
            let animation: String
            let rightAnimation: String?
            let frameIndices: [Int]?
            let rightFrameIndices: [Int]?
            let loop: Bool?
            let motion: PetImageMotion?
            let frameDurationScale: Double?
            let frameBlendFraction: Double?
        }

        struct LookDirectionDescriptor: Decodable {
            let degrees: Double
            let rowIndex: Int
            let columnIndex: Int
        }

        struct LocalizedTitleDescriptor: Decodable {
            let en: String
        }

        struct ActionDescriptor: Decodable {
            let id: String
            let title: LocalizedTitleDescriptor
            let resultingPosture: PetPosture?
            let autonomous: Bool?
        }

        let file: String
        let spriteVersionNumber: Int
        let stateModel: String?
        let layout: LayoutDescriptor
        let rendering: RenderingDescriptor
        let animations: [AnimationDescriptor]
        let bindings: [BindingDescriptor]
        let lookDirections: [LookDirectionDescriptor]?
        let actions: [ActionDescriptor]?
    }

    struct AppearanceDescriptor: Decodable {
        struct LocalizedText: Decodable {
            let en: String
        }

        let id: String
        let kind: PetAppearanceKind
        let title: LocalizedText
        let subtitle: LocalizedText
        let systemImage: String?
        let isDefault: Bool?
        let atlasFile: String?
        let spriteAtlas: SpriteAtlasDescriptor?
    }

    let pet: PetDescriptor?
    let capabilities: CapabilitiesDescriptor?
    let clips: [ClipDescriptor]?
    let spriteAtlas: SpriteAtlasDescriptor?
    let appearances: [AppearanceDescriptor]?
}

enum PetAppearanceKind: String, Decodable {
    case continuousVideo = "continuous-video"
    case spriteAtlas = "sprite-atlas"

    var visualMode: PetVisualMode {
        switch self {
        case .continuousVideo: .video
        case .spriteAtlas: .images
        }
    }
}

struct PetAppearanceOption: Equatable {
    let id: String
    let kind: PetAppearanceKind
    let title: String
    let subtitle: String
    let systemImage: String
    let isDefault: Bool

    func title(for language: AppLanguage) -> String { title }

    func subtitle(for language: AppLanguage) -> String { subtitle }
}

struct PetLibraryPet: Equatable {
    let id: String
    let name: String
    let species: String
    let assetVersion: Int
    let bodySize: Int
    let isBundled: Bool
    let rootURL: URL
    let appearances: [PetAppearanceOption]
}

enum PetImageMotion: String, Decodable {
    case none
    case idle
    case sleep
    case transition
    case look
    case gesture
    case walk
    case slowRun = "slow-run"
    case fastRun = "fast-run"
    case settle
}

struct PetPixelRect: Hashable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

struct PetPixelSize: Hashable {
    let width: Int
    let height: Int
}

struct PetImageFrameReference: Hashable {
    let url: URL
    let crop: PetPixelRect?
    let renderCanvas: PetPixelSize?
    let bottomPadding: Int

}

struct PetImageAnimation {
    let id: String
    let frames: [PetImageFrameReference]
    let rightFrames: [PetImageFrameReference]?
    let loops: Bool
    let motion: PetImageMotion
    let frameDurations: [TimeInterval]
    let duration: TimeInterval
    let frameBlendFraction: Double

    var cycleDuration: TimeInterval {
        max(1.0 / 60.0, frameDurations.reduce(0, +))
    }
}

struct PetImageAction {
    let id: String
    let title: String
    let resultingPosture: PetPosture
    let mayRunAutonomously: Bool

    func title(for language: AppLanguage) -> String { title }
}

struct PetLookDirection: Hashable, Sendable {
    static let count = 16
    static let stepDegrees = 360.0 / Double(count)

    let index: Int

    init(index: Int) {
        self.index = (index % Self.count + Self.count) % Self.count
    }

    init(vectorX: CGFloat, vectorY: CGFloat) {
        let clockwiseFromUp = atan2(Double(vectorX), Double(vectorY)) * 180 / .pi
        let normalized = clockwiseFromUp < 0 ? clockwiseFromUp + 360 : clockwiseFromUp
        self.init(index: Int((normalized / Self.stepDegrees).rounded()))
    }

    var degrees: Double { Double(index) * Self.stepDegrees }

    var assetKey: String {
        if degrees.rounded() == degrees {
            return String(format: "%03d", Int(degrees))
        }
        let whole = Int(degrees.rounded(.down))
        return String(format: "%03d.5", whole)
    }

    func stepped(toward target: PetLookDirection) -> PetLookDirection {
        guard target != self else { return self }
        let clockwiseDistance = (target.index - index + Self.count) % Self.count
        let delta = clockwiseDistance <= Self.count / 2 ? 1 : -1
        return PetLookDirection(index: index + delta)
    }

    static let up = PetLookDirection(index: 0)
    static let right = PetLookDirection(index: 4)
    static let down = PetLookDirection(index: 8)
    static let left = PetLookDirection(index: 12)
}

enum PetAssetCatalog {
    private struct ResolvedSpriteAtlas {
        let url: URL
        let descriptor: PetAssetManifest.SpriteAtlasDescriptor
        let animationsByID: [String: PetAssetManifest.SpriteAtlasDescriptor.AnimationDescriptor]
        let bindingsByID: [String: PetAssetManifest.SpriteAtlasDescriptor.BindingDescriptor]
        let lookDirectionsByKey: [String: PetAssetManifest.SpriteAtlasDescriptor.LookDirectionDescriptor]
        let actions: [PetImageAction]
    }

    private struct LoadedCatalog {
        let rootURL: URL
        let petID: String
        let petName: String
        let species: String
        let assetVersion: Int
        let bodySize: Int
        let isBundled: Bool
        let clipsByID: [String: PetAssetManifest.ClipDescriptor]
        let appearances: [(option: PetAppearanceOption, spriteAtlas: ResolvedSpriteAtlas?)]
    }

    private static func loadCatalog(at rootURL: URL) -> LoadedCatalog? {
            let manifestURL = rootURL.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(PetAssetManifest.self, from: data) else {
                return nil
            }

            var clipsByID: [String: PetAssetManifest.ClipDescriptor] = [:]
            for clip in manifest.clips ?? [] where clipsByID[clip.id] == nil {
                clipsByID[clip.id] = clip
            }
            func resolveAtlas(
                _ descriptor: PetAssetManifest.SpriteAtlasDescriptor
            ) -> ResolvedSpriteAtlas? {
                guard let url = try? existingAssetURL(descriptor.file, in: rootURL) else { return nil }
                guard descriptor.stateModel == PetImageStateModel.identifier else { return nil }
                var animationsByID: [String: PetAssetManifest.SpriteAtlasDescriptor.AnimationDescriptor] = [:]
                for animation in descriptor.animations where animationsByID[animation.id] == nil {
                    animationsByID[animation.id] = animation
                }
                var bindingsByID: [String: PetAssetManifest.SpriteAtlasDescriptor.BindingDescriptor] = [:]
                for binding in descriptor.bindings where bindingsByID[binding.id] == nil {
                    bindingsByID[binding.id] = binding
                }
                let stateBindings = descriptor.bindings.map {
                    PetImageStateModel.Binding(
                        id: $0.id,
                        animation: $0.animation,
                        frameIndices: $0.frameIndices,
                        loops: $0.loop,
                        motion: $0.motion?.rawValue
                    )
                }
                guard PetImageStateModel.validates(stateBindings) else { return nil }
                var lookDirectionsByKey: [String: PetAssetManifest.SpriteAtlasDescriptor.LookDirectionDescriptor] = [:]
                for direction in descriptor.lookDirections ?? [] {
                    let key = PetLookDirection(
                        index: Int((direction.degrees / PetLookDirection.stepDegrees).rounded())
                    ).assetKey
                    lookDirectionsByKey[key] = direction
                }
                let actions = (descriptor.actions ?? []).compactMap { action -> PetImageAction? in
                    guard bindingsByID[action.id] != nil else { return nil }
                    return PetImageAction(
                        id: action.id,
                        title: action.title.en,
                        resultingPosture: action.resultingPosture ?? .stand,
                        mayRunAutonomously: action.autonomous ?? false
                    )
                }
                return ResolvedSpriteAtlas(
                    url: url,
                    descriptor: descriptor,
                    animationsByID: animationsByID,
                    bindingsByID: bindingsByID,
                    lookDirectionsByKey: lookDirectionsByKey,
                    actions: actions
                )
            }

            var appearances: [(option: PetAppearanceOption, spriteAtlas: ResolvedSpriteAtlas?)] = []
            for descriptor in manifest.appearances ?? [] {
                var appearanceAtlasDescriptor = descriptor.spriteAtlas
                if appearanceAtlasDescriptor == nil,
                   let atlasFile = descriptor.atlasFile,
                   let base = manifest.spriteAtlas {
                    appearanceAtlasDescriptor = PetAssetManifest.SpriteAtlasDescriptor(
                        file: atlasFile,
                        spriteVersionNumber: base.spriteVersionNumber,
                        stateModel: base.stateModel,
                        layout: base.layout,
                        rendering: base.rendering,
                        animations: base.animations,
                        bindings: base.bindings,
                        lookDirections: base.lookDirections,
                        actions: base.actions
                    )
                }
                let atlas = appearanceAtlasDescriptor.flatMap(resolveAtlas)
                if descriptor.kind == .continuousVideo, clipsByID.isEmpty { continue }
                if descriptor.kind == .spriteAtlas, atlas == nil { continue }
                appearances.append((
                    PetAppearanceOption(
                        id: descriptor.id,
                        kind: descriptor.kind,
                        title: descriptor.title.en,
                        subtitle: descriptor.subtitle.en,
                        systemImage: descriptor.systemImage ?? "pawprint.fill",
                        isDefault: descriptor.isDefault ?? false
                    ),
                    atlas
                ))
            }

            if appearances.isEmpty {
                let legacyAtlas = manifest.spriteAtlas.flatMap(resolveAtlas)
                if manifest.capabilities?.videoMode ?? !clipsByID.isEmpty {
                    appearances.append((
                        PetAppearanceOption(
                            id: "continuous-video",
                            kind: .continuousVideo,
                            title: "Live Motion",
                            subtitle: "Detailed continuous video",
                            systemImage: "film.stack.fill",
                            isDefault: true
                        ),
                        nil
                    ))
                }
                if let legacyAtlas {
                    appearances.append((
                        PetAppearanceOption(
                            id: "realistic-2d",
                            kind: .spriteAtlas,
                            title: "Realistic 2D",
                            subtitle: "Natural image animation",
                            systemImage: "camera.macro",
                            isDefault: appearances.isEmpty
                        ),
                        legacyAtlas
                    ))
                }
            }

            return LoadedCatalog(
                rootURL: rootURL.standardizedFileURL,
                petID: manifest.pet?.id ?? "legacy-pet",
                petName: manifest.pet?.name ?? manifest.pet?.id ?? "Pet",
                species: manifest.pet?.species ?? "pet",
                assetVersion: manifest.pet?.assetVersion ?? 1,
                bodySize: min(100, max(1, manifest.pet?.bodySize ?? 60)),
                isBundled: isBundledAssetRoot(rootURL),
                clipsByID: clipsByID,
                appearances: appearances
            )
    }

    private static var loadedCatalogs: [LoadedCatalog] = loadCatalogs()
    /// User selections live in memory as well as UserDefaults. This makes a
    /// Settings click authoritative immediately, even if defaults propagation
    /// or a renderer refresh happens in the same run-loop turn.
    private static var explicitlySelectedPetID: String?
    private static var explicitlySelectedAppearanceByPet: [String: String] = [:]

    private static var loaded: LoadedCatalog? {
        guard !loadedCatalogs.isEmpty else { return nil }
        // An explicit in-app choice must always win. Environment overrides are
        // launch defaults for QA and previews, not a lock that can make the UI
        // appear broken.
        if let selectedID = explicitlySelectedPetID,
           let selected = loadedCatalogs.first(where: { $0.petID == selectedID }) {
            return selected
        }
        if let forcedID = ProcessInfo.processInfo.environment["FURBALL_PET_ID"],
           let forced = loadedCatalogs.first(where: { $0.petID == forcedID }) {
            return forced
        }
        if let selectedID = UserDefaults.standard.string(forKey: "selectedPetID"),
           let selected = loadedCatalogs.first(where: { $0.petID == selectedID }) {
            return selected
        }
        return loadedCatalogs.first(where: { $0.isBundled }) ?? loadedCatalogs[0]
    }

    private static var selectedAppearance: (option: PetAppearanceOption, spriteAtlas: ResolvedSpriteAtlas?)? {
        guard let loaded, !loaded.appearances.isEmpty else { return nil }
        if let selectedID = explicitlySelectedAppearanceByPet[loaded.petID],
           let selected = loaded.appearances.first(where: { $0.option.id == selectedID }) {
            return selected
        }
        if let forcedID = ProcessInfo.processInfo.environment["FURBALL_APPEARANCE"],
           let forced = loaded.appearances.first(where: { $0.option.id == forcedID }) {
            return forced
        }
        let preferenceKey = "selectedAppearance.\(loaded.petID)"
        if let selectedID = UserDefaults.standard.string(forKey: preferenceKey),
           let selected = loaded.appearances.first(where: { $0.option.id == selectedID }) {
            return selected
        }

        // Preserve the user's previous image/video choice during migration to
        // the richer three-appearance selector.
        let legacyKey = "videoAnimationsEnabled.\(loaded.petID)"
        if UserDefaults.standard.object(forKey: legacyKey) != nil,
           !UserDefaults.standard.bool(forKey: legacyKey),
           let image = loaded.appearances.first(where: { $0.option.kind == .spriteAtlas }) {
            return image
        }
        return loaded.appearances.first(where: { $0.option.isDefault }) ?? loaded.appearances[0]
    }

    static var supportsDirectionalLook: Bool {
        selectedAppearance?.spriteAtlas?.lookDirectionsByKey.count == PetLookDirection.count
    }

    static var availableAppearances: [PetAppearanceOption] {
        loaded?.appearances.map(\.option) ?? []
    }

    static var activeAppearance: PetAppearanceOption {
        selectedAppearance?.option ?? PetAppearanceOption(
            id: "continuous-video",
            kind: .continuousVideo,
            title: "Live Motion",
            subtitle: "Detailed continuous video",
            systemImage: "film.stack.fill",
            isDefault: true
        )
    }

    static var availablePets: [PetLibraryPet] {
        loadedCatalogs.map {
            PetLibraryPet(
                id: $0.petID,
                name: $0.petName,
                species: $0.species,
                assetVersion: $0.assetVersion,
                bodySize: $0.bodySize,
                isBundled: $0.isBundled,
                rootURL: $0.rootURL,
                appearances: $0.appearances.map(\.option)
            )
        }
    }

    static var activePet: PetLibraryPet? {
        guard let loaded else { return nil }
        return PetLibraryPet(
            id: loaded.petID,
            name: loaded.petName,
            species: loaded.species,
            assetVersion: loaded.assetVersion,
            bodySize: loaded.bodySize,
            isBundled: loaded.isBundled,
            rootURL: loaded.rootURL,
            appearances: loaded.appearances.map(\.option)
        )
    }

    @discardableResult
    static func selectPet(id: String) -> Bool {
        guard loadedCatalogs.contains(where: { $0.petID == id }) else { return false }
        explicitlySelectedPetID = id
        UserDefaults.standard.set(id, forKey: "selectedPetID")
        UserDefaults.standard.synchronize()
        return true
    }

    static func reload() {
        loadedCatalogs = loadCatalogs()
    }

    @discardableResult
    static func selectAppearance(id: String) -> Bool {
        guard let loaded,
              let selection = loaded.appearances.first(where: { $0.option.id == id }) else { return false }
        explicitlySelectedAppearanceByPet[loaded.petID] = id
        UserDefaults.standard.set(id, forKey: "selectedAppearance.\(loaded.petID)")
        if selection.option.kind == .spriteAtlas {
            UserDefaults.standard.set(id, forKey: "lastImageAppearance.\(loaded.petID)")
        }
        UserDefaults.standard.synchronize()
        return true
    }

    static var petID: String { loaded?.petID ?? "legacy-pet" }
    static var petName: String { loaded?.petName ?? "Pet" }
    static var bodySize: Int { loaded?.bodySize ?? 60 }
    static var intrinsicBodyScale: CGFloat { CGFloat(bodySize) / 60.0 }
    static var imageActions: [PetImageAction] { selectedAppearance?.spriteAtlas?.actions ?? [] }

    static func loops(for id: String, fallback: Bool) -> Bool {
        loaded?.clipsByID[id]?.loop ?? fallback
    }

    static func url(for id: String, fallbackFileName: String) throws -> URL {
        if let loaded {
            let relativePath = loaded.clipsByID[id]?.file ?? "Clips/\(fallbackFileName).mov"
            let candidate = try safeAssetURL(relativePath, in: loaded.rootURL)
            guard FileManager.default.fileExists(atPath: candidate.path) else {
                throw PetAppError.missingAsset(relativePath)
            }
            return candidate
        }

        let relativePath = "Assets/Clips/\(fallbackFileName).mov"
        for candidate in legacyAssetCandidates(relativePath: relativePath)
            where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        throw PetAppError.missingAsset("\(fallbackFileName).mov")
    }

    static func imageAnimation(for id: String) throws -> PetImageAnimation {
        guard loaded != nil else {
            throw PetAppError.missingAsset("image animation: \(id)")
        }

        if let atlas = selectedAppearance?.spriteAtlas {
            if let binding = atlas.bindingsByID[id] {
                return try spriteAnimation(for: binding, in: atlas)
            }
            let directionPrefix = "stand.look.direction."
            if id.hasPrefix(directionPrefix) {
                let key = String(id.dropFirst(directionPrefix.count))
                return try lookAnimation(for: key, in: atlas, id: id)
            }
        }

        throw PetAppError.missingAsset("sprite-atlas animation: \(id)")
    }

    /// Resolves an image animation for a specific pet without changing the
    /// user's active pet or appearance. Group Play uses this path so each
    /// companion owns an independent atlas instead of racing the global picker.
    static func groupImageAnimation(petID: String, id: String) throws -> PetImageAnimation {
        guard let catalog = loadedCatalogs.first(where: { $0.petID == petID }) else {
            throw PetAppError.missingAsset("pet: \(petID)")
        }
        let preference = UserDefaults.standard.string(forKey: "lastImageAppearance.\(petID)")
            ?? explicitlySelectedAppearanceByPet[petID]
            ?? UserDefaults.standard.string(forKey: "selectedAppearance.\(petID)")
        let preferredAtlas = preference.flatMap { selectedID in
            catalog.appearances.first(where: {
                $0.option.id == selectedID && $0.spriteAtlas != nil
            })?.spriteAtlas
        }
        guard let atlas = preferredAtlas
                ?? catalog.appearances.first(where: { $0.option.id == "realistic-2d" && $0.spriteAtlas != nil })?.spriteAtlas
                ?? catalog.appearances.first(where: { $0.spriteAtlas != nil })?.spriteAtlas,
              let binding = atlas.bindingsByID[id] else {
            throw PetAppError.missingAsset("group sprite animation: \(petID)/\(id)")
        }
        return try spriteAnimation(for: binding, in: atlas)
    }

    static var imageCapablePetIDs: Set<String> {
        Set(loadedCatalogs.compactMap { catalog in
            catalog.appearances.contains(where: { $0.spriteAtlas != nil }) ? catalog.petID : nil
        })
    }

    private static func spriteAnimation(
        for binding: PetAssetManifest.SpriteAtlasDescriptor.BindingDescriptor,
        in atlas: ResolvedSpriteAtlas
    ) throws -> PetImageAnimation {
        guard let animation = atlas.animationsByID[binding.animation] else {
            throw PetAppError.missingAsset("sprite animation: \(binding.animation)")
        }
        let leftIndices = binding.frameIndices ?? Array(0..<animation.frameCount)
        let leftFrames = try spriteFrames(indices: leftIndices, animation: animation, atlas: atlas)
        let rightFrames: [PetImageFrameReference]?
        if let rightAnimationID = binding.rightAnimation {
            guard let rightAnimation = atlas.animationsByID[rightAnimationID] else {
                throw PetAppError.missingAsset("sprite animation: \(rightAnimationID)")
            }
            let rightIndices = binding.rightFrameIndices ?? binding.frameIndices ?? Array(0..<rightAnimation.frameCount)
            guard rightIndices.count == leftIndices.count else {
                throw PetAppError.missingAsset("sprite frame count: \(binding.id) right animation")
            }
            rightFrames = try spriteFrames(indices: rightIndices, animation: rightAnimation, atlas: atlas)
        } else {
            rightFrames = nil
        }

        let scale = max(0.05, binding.frameDurationScale ?? 1)
        let durations = try leftIndices.map { index -> TimeInterval in
            guard animation.frameDurations.indices.contains(index) else {
                throw PetAppError.missingAsset("sprite frame duration: \(animation.id)[\(index)]")
            }
            return max(1.0 / 120.0, animation.frameDurations[index] * scale)
        }
        let loops = binding.loop ?? animation.loop
        return PetImageAnimation(
            id: binding.id,
            frames: leftFrames,
            rightFrames: rightFrames,
            loops: loops,
            motion: binding.motion ?? animation.motion,
            frameDurations: durations,
            duration: max(1.0 / 60.0, durations.reduce(0, +)),
            frameBlendFraction: max(
                0,
                min(0.82, binding.frameBlendFraction ?? animation.frameBlendFraction ?? 0)
            )
        )
    }

    private static func spriteFrames(
        indices: [Int],
        animation: PetAssetManifest.SpriteAtlasDescriptor.AnimationDescriptor,
        atlas: ResolvedSpriteAtlas
    ) throws -> [PetImageFrameReference] {
        let layout = atlas.descriptor.layout
        guard animation.rowIndex >= 0, animation.rowIndex < layout.rows else {
            throw PetAppError.missingAsset("sprite row: \(animation.rowIndex)")
        }
        return try indices.map { index in
            guard index >= 0, index < animation.frameCount, index < layout.columns else {
                throw PetAppError.missingAsset("sprite frame: \(animation.id)[\(index)]")
            }
            return spriteFrame(row: animation.rowIndex, column: index, atlas: atlas)
        }
    }

    private static func lookAnimation(
        for key: String,
        in atlas: ResolvedSpriteAtlas,
        id: String
    ) throws -> PetImageAnimation {
        guard let direction = atlas.lookDirectionsByKey[key] else {
            throw PetAppError.missingAsset("look direction: \(key)")
        }
        return PetImageAnimation(
            id: id,
            frames: [spriteFrame(row: direction.rowIndex, column: direction.columnIndex, atlas: atlas)],
            rightFrames: nil,
            loops: true,
            motion: .none,
            frameDurations: [1],
            duration: 1,
            frameBlendFraction: 0
        )
    }

    private static func spriteFrame(
        row: Int,
        column: Int,
        atlas: ResolvedSpriteAtlas
    ) -> PetImageFrameReference {
        let layout = atlas.descriptor.layout
        let rendering = atlas.descriptor.rendering
        return PetImageFrameReference(
            url: atlas.url,
            crop: PetPixelRect(
                x: column * layout.cellWidth,
                y: row * layout.cellHeight,
                width: layout.cellWidth,
                height: layout.cellHeight
            ),
            renderCanvas: PetPixelSize(width: rendering.canvasWidth, height: rendering.canvasHeight),
            bottomPadding: max(0, rendering.bottomPadding ?? 0)
        )
    }

    private static func existingAssetURL(_ relativePath: String, in rootURL: URL) throws -> URL {
        let candidate = try safeAssetURL(relativePath, in: rootURL)
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            throw PetAppError.missingAsset(relativePath)
        }
        return candidate
    }

    private static func safeAssetURL(_ relativePath: String, in rootURL: URL) throws -> URL {
        guard !relativePath.hasPrefix("/") else {
            throw PetAppError.missingAsset(relativePath)
        }
        let candidate = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard candidate.path.hasPrefix(rootPrefix) else {
            throw PetAppError.missingAsset(relativePath)
        }
        return candidate
    }

    static var userPetPacksDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("Furball2D", isDirectory: true)
            .appendingPathComponent("Pets", isDirectory: true)
    }

    private static func loadCatalogs() -> [LoadedCatalog] {
        var seenPaths = Set<String>()
        var seenPetIDs = Set<String>()
        var result: [LoadedCatalog] = []
        for root in candidateAssetRoots() {
            let canonical = root.standardizedFileURL.resolvingSymlinksInPath()
            guard seenPaths.insert(canonical.path).inserted,
                  let catalog = loadCatalog(at: canonical),
                  seenPetIDs.insert(catalog.petID).inserted else { continue }
            result.append(catalog)
        }
        return result
    }

    private static func isBundledAssetRoot(_ rootURL: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let bundlePath = Bundle.main.bundleURL.standardizedFileURL.path
        return rootPath == bundlePath || rootPath.hasPrefix(bundlePath + "/")
    }

    private static func candidateAssetRoots() -> [URL] {
        var roots: [URL] = []

        // Production tooling and future pet-picker UI can point to an unpacked
        // `.furballpet` directory without recompiling the application.
        if let override = ProcessInfo.processInfo.environment["FURBALL_PET_PACK"], !override.isEmpty {
            roots.append(URL(fileURLWithPath: override, isDirectory: true))
        }

        if let installed = try? FileManager.default.contentsOfDirectory(
            at: userPetPacksDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            roots.append(contentsOf: installed.sorted { $0.lastPathComponent < $1.lastPathComponent })
        }

        var bundledAssetContainers: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            bundledAssetContainers.append(resourceURL.appendingPathComponent("Assets", isDirectory: true))
        }
        bundledAssetContainers.append(
            Bundle.main.bundleURL
                .appendingPathComponent("Furball_Furball.bundle", isDirectory: true)
                .appendingPathComponent("Assets", isDirectory: true)
        )
        if let executableURL = Bundle.main.executableURL {
            bundledAssetContainers.append(
                executableURL.deletingLastPathComponent()
                    .appendingPathComponent("Furball_Furball.bundle", isDirectory: true)
                    .appendingPathComponent("Assets", isDirectory: true)
            )
        }
        for container in bundledAssetContainers {
            let petsDirectory = container.appendingPathComponent("Pets", isDirectory: true)
            if let petRoots = try? FileManager.default.contentsOfDirectory(
                at: petsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                roots.append(contentsOf: petRoots.sorted {
                    let lhsPriority = $0.lastPathComponent == "Nina" ? 0 : 1
                    let rhsPriority = $1.lastPathComponent == "Nina" ? 0 : 1
                    return lhsPriority == rhsPriority
                        ? $0.lastPathComponent < $1.lastPathComponent
                        : lhsPriority < rhsPriority
                })
            }
            // Keep legacy single-pack bundles loadable during migration.
            roots.append(container)
        }
        return roots
    }

    private static func legacyAssetCandidates(relativePath: String) -> [URL] {
        [
            Bundle.main.resourceURL?.appendingPathComponent(relativePath),
            Bundle.main.bundleURL
                .appendingPathComponent("Furball_Furball.bundle")
                .appendingPathComponent(relativePath),
            Bundle.main.executableURL?.deletingLastPathComponent()
                .appendingPathComponent("Furball_Furball.bundle")
                .appendingPathComponent(relativePath)
        ].compactMap { $0 }
    }
}

enum PetPosture: String, Decodable {
    case stand
    case sit
    case lie
    case sleep
}

enum PetFacingView: Int, CaseIterable, Sendable {
    case leftProfile
    case frontNearProfileLeft
    case frontThreeQuarterLeft
    case frontNearCenterLeft
    case front
    case frontNearCenterRight
    case frontThreeQuarterRight
    case frontNearProfileRight
    case rightProfile

    var assetName: String {
        switch self {
        case .leftProfile: "left-profile"
        case .frontNearProfileLeft: "front-near-profile-left"
        case .frontThreeQuarterLeft: "front-three-quarter-left"
        case .frontNearCenterLeft: "front-near-center-left"
        case .front: "front"
        case .frontNearCenterRight: "front-near-center-right"
        case .frontThreeQuarterRight: "front-three-quarter-right"
        case .frontNearProfileRight: "front-near-profile-right"
        case .rightProfile: "right-profile"
        }
    }

    func stepped(toward target: PetFacingView) -> PetFacingView {
        guard target != self else { return self }
        let nextRawValue = rawValue + (target.rawValue > rawValue ? 1 : -1)
        return PetFacingView(rawValue: nextRawValue) ?? target
    }
}

struct PetClip {
    let id: String
    let fallbackFileName: String
    let fallbackLoops: Bool
    let resultingPosture: PetPosture

    var loops: Bool { PetAssetCatalog.loops(for: id, fallback: fallbackLoops) }

    var url: URL {
        get throws {
            try PetAssetCatalog.url(for: id, fallbackFileName: fallbackFileName)
        }
    }

    var isAvailable: Bool { (try? url) != nil }
    var imageAnimation: PetImageAnimation { get throws { try PetAssetCatalog.imageAnimation(for: id) } }
    var isImageAvailable: Bool { (try? imageAnimation) != nil }
}

struct PetMotionClipSet {
    let start: PetClip
    let loop: PetClip
    let stop: PetClip
}

enum PetClips {
    private static let viewDirectory = "left-profile"

    static let standIdle = clip("stand-idle", loops: true, posture: .stand)
    static let sitIdle = clip("sit-idle", loops: true, posture: .sit)
    static let lieIdle = clip("lie-idle", loops: true, posture: .lie)
    static let sleepIdle = clip("sleep-idle", loops: true, posture: .sleep)
    static let walk = motion("walk")
    static let slowRun = motion("slow-run")
    static let fastRun = motion("fast-run")
    static let walkIdle = walk.loop
    static let lookAroundImages = clip("look-around-images", loops: false, posture: .stand)
    static let sleepToStand = clip("sleep-to-stand", loops: false, posture: .stand)
    static let sitDown = clip("stand-to-sit", loops: false, posture: .sit)
    static let sitToLie = clip("sit-to-lie", loops: false, posture: .lie)
    static let lieToSleep = clip("lie-to-sleep", loops: false, posture: .sleep)

    static func imageFacing(_ view: PetFacingView) -> PetClip {
        PetClip(
            id: "stand.facing.\(view.assetName)",
            fallbackFileName: "image-views/\(view.assetName)",
            fallbackLoops: true,
            resultingPosture: .stand
        )
    }

    static func lookDirection(_ direction: PetLookDirection) -> PetClip {
        PetClip(
            id: "stand.look.direction.\(direction.assetKey)",
            fallbackFileName: "sprite-look/\(direction.assetKey)",
            fallbackLoops: true,
            resultingPosture: .stand
        )
    }

    static func imageAction(_ action: PetImageAction) -> PetClip {
        PetClip(
            id: action.id,
            fallbackFileName: "sprite-actions/\(action.id)",
            fallbackLoops: false,
            resultingPosture: action.resultingPosture
        )
    }

    static func idle(for posture: PetPosture) -> PetClip {
        switch posture {
        case .stand: standIdle
        case .sit: sitIdle
        case .lie: lieIdle
        case .sleep: sleepIdle
        }
    }

    private static func clip(_ name: String, loops: Bool, posture: PetPosture) -> PetClip {
        PetClip(
            id: semanticID(for: name),
            fallbackFileName: "\(viewDirectory)/\(name)",
            fallbackLoops: loops,
            resultingPosture: posture
        )
    }

    private static func semanticID(for name: String) -> String {
        switch name {
        case "stand-idle": "stand.idle"
        case "look-around-images": "stand.look.images"
        case "stand-to-sit": "stand.to.sit"
        case "sit-idle": "sit.idle"
        case "sit-to-lie": "sit.to.lie"
        case "lie-idle": "lie.idle"
        case "lie-to-sleep": "lie.to.sleep"
        case "sleep-idle": "sleep.idle"
        case "sleep-to-stand": "sleep.to.stand"
        case "walk-start": "walk.start"
        case "walk-loop": "walk.loop"
        case "walk-stop": "walk.stop"
        case "slow-run-start": "slow-run.start"
        case "slow-run-loop": "slow-run.loop"
        case "slow-run-stop": "slow-run.stop"
        case "fast-run-start": "fast-run.start"
        case "fast-run-loop": "fast-run.loop"
        case "fast-run-stop": "fast-run.stop"
        default: name.replacingOccurrences(of: "-", with: ".")
        }
    }

    private static func motion(_ name: String) -> PetMotionClipSet {
        PetMotionClipSet(
            start: clip("\(name)-start", loops: false, posture: .stand),
            loop: clip("\(name)-loop", loops: true, posture: .stand),
            stop: clip("\(name)-stop", loops: false, posture: .stand)
        )
    }
}

enum PetAppError: LocalizedError {
    case missingAsset(String)
    case metalUnavailable
    case rendererSetup(String)

    var errorDescription: String? {
        AppLanguage.stored.errorDescription(for: self)
    }
}
