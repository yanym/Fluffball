import Foundation

private struct PetAssetManifest: Decodable {
    struct ClipDescriptor: Decodable {
        let id: String
        let file: String
        let loop: Bool
    }

    let clips: [ClipDescriptor]
}

private enum PetAssetCatalog {
    private struct LoadedCatalog {
        let rootURL: URL
        let clipsByID: [String: PetAssetManifest.ClipDescriptor]
    }

    private static let loaded: LoadedCatalog? = {
        for rootURL in candidateAssetRoots() {
            let manifestURL = rootURL.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(PetAssetManifest.self, from: data) else {
                continue
            }
            var clipsByID: [String: PetAssetManifest.ClipDescriptor] = [:]
            for clip in manifest.clips where clipsByID[clip.id] == nil {
                clipsByID[clip.id] = clip
            }
            return LoadedCatalog(rootURL: rootURL.standardizedFileURL, clipsByID: clipsByID)
        }
        return nil
    }()

    static func loops(for id: String, fallback: Bool) -> Bool {
        loaded?.clipsByID[id]?.loop ?? fallback
    }

    static func url(for id: String, fallbackFileName: String) throws -> URL {
        if let loaded {
            let relativePath = loaded.clipsByID[id]?.file ?? "Clips/\(fallbackFileName).mov"
            let candidate = loaded.rootURL.appendingPathComponent(relativePath).standardizedFileURL
            let rootPrefix = loaded.rootURL.path.hasSuffix("/")
                ? loaded.rootURL.path
                : loaded.rootURL.path + "/"
            guard candidate.path.hasPrefix(rootPrefix),
                  FileManager.default.fileExists(atPath: candidate.path) else {
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

    private static func candidateAssetRoots() -> [URL] {
        var roots: [URL] = []

        // Production tooling and future pet-picker UI can point to an unpacked
        // `.furballpet` directory without recompiling the application.
        if let override = ProcessInfo.processInfo.environment["FURBALL_PET_PACK"], !override.isEmpty {
            roots.append(URL(fileURLWithPath: override, isDirectory: true))
        }

        if let resourceURL = Bundle.main.resourceURL {
            roots.append(resourceURL.appendingPathComponent("Assets", isDirectory: true))
        }
        roots.append(
            Bundle.main.bundleURL
                .appendingPathComponent("Furball2D_Furball2D.bundle", isDirectory: true)
                .appendingPathComponent("Assets", isDirectory: true)
        )
        if let executableURL = Bundle.main.executableURL {
            roots.append(
                executableURL.deletingLastPathComponent()
                    .appendingPathComponent("Furball2D_Furball2D.bundle", isDirectory: true)
                    .appendingPathComponent("Assets", isDirectory: true)
            )
        }
        return roots
    }

    private static func legacyAssetCandidates(relativePath: String) -> [URL] {
        [
            Bundle.main.resourceURL?.appendingPathComponent(relativePath),
            Bundle.main.bundleURL
                .appendingPathComponent("Furball2D_Furball2D.bundle")
                .appendingPathComponent(relativePath),
            Bundle.main.executableURL?.deletingLastPathComponent()
                .appendingPathComponent("Furball2D_Furball2D.bundle")
                .appendingPathComponent(relativePath)
        ].compactMap { $0 }
    }
}

enum PetPosture {
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
