import AppKit
import ImageIO

enum PetPackLibraryError: LocalizedError {
    case invalidPack(String)
    case petAlreadyExists(String)
    case bundledPetConflict(String)
    case missingCreatorSkill
    case operationFailed(String)
    case readOnlyRuntime

    var errorDescription: String? {
        switch self {
        case .invalidPack(let reason): "The pet pack failed validation: \(reason)"
        case .petAlreadyExists(let name): "\(name) is already in the library."
        case .bundledPetConflict(let id): "The imported ID (\(id)) conflicts with a built-in pet."
        case .missingCreatorSkill: "The pet creator Skill is missing from the app bundle."
        case .operationFailed(let reason): "The operation failed: \(reason)"
        case .readOnlyRuntime: "Furball runs in read-only safety mode and cannot create, change, move, or delete files or folders."
        }
    }
}

struct ValidatedPetPack {
    let id: String
    let name: String
    let species: String
    let assetVersion: Int
    let appearanceCount: Int
    let supportsVideo: Bool
}

final class CodexPetCreationJob: @unchecked Sendable {
    let process: Process
    let workingDirectory: URL
    let expectedPackURL: URL
    let logURL: URL
    let logHandle: FileHandle

    init(
        process: Process,
        workingDirectory: URL,
        expectedPackURL: URL,
        logURL: URL,
        logHandle: FileHandle
    ) {
        self.process = process
        self.workingDirectory = workingDirectory
        self.expectedPackURL = expectedPackURL
        self.logURL = logURL
        self.logHandle = logHandle
    }
}

enum PetPackLibraryManager {
    private static let requiredSemanticIDs: Set<String> = [
        "stand.idle", "stand.look.images",
        "stand.facing.left-profile", "stand.facing.front-near-profile-left",
        "stand.facing.front-three-quarter-left", "stand.facing.front-near-center-left",
        "stand.facing.front", "stand.facing.front-near-center-right",
        "stand.facing.front-three-quarter-right", "stand.facing.front-near-profile-right",
        "stand.facing.right-profile",
        "stand.to.sit", "sit.idle", "sit.to.lie", "lie.idle", "lie.to.sleep",
        "sleep.idle", "sleep.to.stand",
        "walk.start", "walk.loop", "walk.stop",
        "slow-run.start", "slow-run.loop", "slow-run.stop",
        "fast-run.start", "fast-run.loop", "fast-run.stop"
    ]
    private static let requiredLoopingIDs: Set<String> = [
        "stand.idle", "sit.idle", "lie.idle", "sleep.idle",
        "walk.loop", "slow-run.loop", "fast-run.loop",
        "stand.facing.left-profile", "stand.facing.front-near-profile-left",
        "stand.facing.front-three-quarter-left", "stand.facing.front-near-center-left",
        "stand.facing.front", "stand.facing.front-near-center-right",
        "stand.facing.front-three-quarter-right", "stand.facing.front-near-profile-right",
        "stand.facing.right-profile"
    ]

    static func validatePack(at rootURL: URL) throws -> ValidatedPetPack {
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw PetPackLibraryError.invalidPack("Choose a .furballpet folder")
        }
        try validateTreeSafety(at: root)

        let manifestURL = root.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PetPackLibraryError.invalidPack("Missing or invalid manifest.json")
        }
        guard (json["petPackVersion"] as? Int) == 2 else {
            throw PetPackLibraryError.invalidPack("petPackVersion must be 2")
        }
        guard let pet = json["pet"] as? [String: Any],
              let id = pet["id"] as? String,
              id.range(of: "^[a-z0-9][a-z0-9-]{1,63}$", options: .regularExpression) != nil,
              let name = pet["name"] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PetPackLibraryError.invalidPack("Invalid pet.id or pet.name")
        }
        let species = (pet["species"] as? String) ?? "other"
        guard ["dog", "cat", "other"].contains(species) else {
            throw PetPackLibraryError.invalidPack("pet.species must be dog, cat, or other")
        }
        let assetVersion = max(1, (pet["assetVersion"] as? Int) ?? 1)
        guard let capabilities = json["capabilities"] as? [String: Any] else {
            throw PetPackLibraryError.invalidPack("Missing capabilities")
        }
        let imageMode = capabilities["imageMode"] as? Bool ?? false
        let videoMode = capabilities["videoMode"] as? Bool ?? false
        guard imageMode || videoMode else {
            throw PetPackLibraryError.invalidPack("Enable at least one visual mode")
        }

        var semanticLoops: [String: Bool] = [:]
        var atlasFiles = Set<String>()
        if let atlas = json["spriteAtlas"] as? [String: Any] {
            try inspectAtlas(atlas, root: root, semanticLoops: &semanticLoops, atlasFiles: &atlasFiles)
        }
        let appearances = json["appearances"] as? [[String: Any]] ?? []
        for appearance in appearances where (appearance["kind"] as? String) == "sprite-atlas" {
            if let atlas = appearance["spriteAtlas"] as? [String: Any] {
                try inspectAtlas(atlas, root: root, semanticLoops: &semanticLoops, atlasFiles: &atlasFiles)
            } else if let atlasPath = appearance["atlasFile"] as? String {
                atlasFiles.insert(atlasPath)
            }
        }
        for atlasPath in atlasFiles {
            try validateAtlasImage(try safeFile(atlasPath, under: root))
        }

        if imageMode {
            guard !atlasFiles.isEmpty else {
                throw PetPackLibraryError.invalidPack("Image mode requires a sprite-atlas v2 WebP")
            }
            let missing = requiredSemanticIDs.subtracting(semanticLoops.keys)
            guard missing.isEmpty else {
                throw PetPackLibraryError.invalidPack(
                    "Missing required actions: \(missing.sorted().joined(separator: ", "))"
                )
            }
            for id in requiredSemanticIDs {
                guard semanticLoops[id] == requiredLoopingIDs.contains(id) else {
                    throw PetPackLibraryError.invalidPack("Invalid loop semantics for \(id)")
                }
            }
        }
        if videoMode {
            guard let clips = json["clips"] as? [[String: Any]], !clips.isEmpty else {
                throw PetPackLibraryError.invalidPack("videoMode=true requires clips")
            }
            for clip in clips {
                guard let path = clip["file"] as? String else { continue }
                _ = try safeFile(path, under: root)
            }
        }

        let appearanceCount = max(appearances.count, (imageMode ? 1 : 0) + (videoMode ? 1 : 0))
        return ValidatedPetPack(
            id: id,
            name: name,
            species: species,
            assetVersion: assetVersion,
            appearanceCount: appearanceCount,
            supportsVideo: videoMode
        )
    }

    @discardableResult
    static func installPack(from sourceURL: URL, replacingExisting: Bool = false) throws -> ValidatedPetPack {
        throw PetPackLibraryError.readOnlyRuntime
    }

    static func exportPet(_ pet: PetLibraryPet, to destinationDirectory: URL) throws -> URL {
        throw PetPackLibraryError.readOnlyRuntime
    }

    static func removePet(_ pet: PetLibraryPet) throws {
        throw PetPackLibraryError.readOnlyRuntime
    }

    static func exportCreatorSkill(to destinationDirectory: URL) throws -> URL {
        throw PetPackLibraryError.readOnlyRuntime
    }

    static func makeCreationRequest(
        name: String,
        species: String,
        styles: [String],
        photos: [URL],
        in destinationDirectory: URL
    ) throws -> URL {
        throw PetPackLibraryError.readOnlyRuntime
    }

    static var codexExecutableURL: URL? {
        if let override = ProcessInfo.processInfo.environment["FURBALL_CODEX_EXECUTABLE"],
           FileManager.default.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map(URL.init(fileURLWithPath:))
    }

    static func startCodexCreation(
        name: String,
        species: String,
        styles: [String],
        photos: [URL]
    ) throws -> CodexPetCreationJob {
        throw PetPackLibraryError.readOnlyRuntime
    }

    static func finishCodexCreation(_ job: CodexPetCreationJob) throws -> ValidatedPetPack {
        throw PetPackLibraryError.readOnlyRuntime
    }

    private static func inspectAtlas(
        _ atlas: [String: Any],
        root: URL,
        semanticLoops: inout [String: Bool],
        atlasFiles: inout Set<String>
    ) throws {
        guard (atlas["spriteVersionNumber"] as? Int) == 2,
              let file = atlas["file"] as? String else {
            throw PetPackLibraryError.invalidPack("spriteAtlas must be v2 and declare file")
        }
        guard let layout = atlas["layout"] as? [String: Any],
              layout["columns"] as? Int == 8,
              layout["rows"] as? Int == 11,
              atlas["assetScale"] as? Int == 2,
              layout["cellWidth"] as? Int == 384,
              layout["cellHeight"] as? Int == 416 else {
            throw PetPackLibraryError.invalidPack("v2 atlases must be 8×11 with native 384×416 cells at assetScale 2")
        }
        atlasFiles.insert(file)
        guard let animations = atlas["animations"] as? [[String: Any]], !animations.isEmpty else {
            throw PetPackLibraryError.invalidPack("spriteAtlas.animations cannot be empty")
        }
        var animationLoops: [String: Bool] = [:]
        for animation in animations {
            guard let id = animation["id"] as? String,
                  let row = animation["rowIndex"] as? Int, (0..<11).contains(row),
                  let count = animation["frameCount"] as? Int, (1...8).contains(count),
                  let durations = animation["frameDurations"] as? [Double],
                  durations.count == count, durations.allSatisfy({ $0 > 0 }),
                  let loops = animation["loop"] as? Bool else {
                throw PetPackLibraryError.invalidPack("Invalid sprite animation row, frame count, or timing")
            }
            animationLoops[id] = loops
        }
        guard let bindings = atlas["bindings"] as? [[String: Any]] else {
            throw PetPackLibraryError.invalidPack("spriteAtlas.bindings cannot be empty")
        }
        for binding in bindings {
            guard let id = binding["id"] as? String,
                  let animation = binding["animation"] as? String,
                  let inheritedLoop = animationLoops[animation] else {
                throw PetPackLibraryError.invalidPack("A sprite binding references a missing animation")
            }
            semanticLoops[id] = binding["loop"] as? Bool ?? inheritedLoop
        }
        guard let directions = atlas["lookDirections"] as? [[String: Any]], directions.count == 16,
              Set(directions.compactMap { $0["degrees"] as? Double }) == Set((0..<16).map { Double($0) * 22.5 }),
              directions.allSatisfy({ direction in
                  guard let row = direction["rowIndex"] as? Int,
                        let column = direction["columnIndex"] as? Int else { return false }
                  return (0..<11).contains(row) && (0..<8).contains(column)
              }) else {
            throw PetPackLibraryError.invalidPack("A v2 atlas must declare all 16 directions")
        }
        for id in [
            "stand.facing.left-profile", "stand.facing.front-near-profile-left",
            "stand.facing.front-three-quarter-left", "stand.facing.front-near-center-left",
            "stand.facing.front", "stand.facing.front-near-center-right",
            "stand.facing.front-three-quarter-right", "stand.facing.front-near-profile-right",
            "stand.facing.right-profile"
        ] { semanticLoops[id] = true }
        _ = try safeFile(file, under: root)
    }

    private static func validateAtlasImage(_ url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == 3072, image.height == 4576 else {
            throw PetPackLibraryError.invalidPack("\(url.lastPathComponent) must be a 3072×4576 WebP")
        }
        let alpha = image.alphaInfo
        guard alpha != .none && alpha != .noneSkipFirst && alpha != .noneSkipLast else {
            throw PetPackLibraryError.invalidPack("\(url.lastPathComponent) has no alpha channel")
        }
    }

    private static func safeFile(_ relativePath: String, under root: URL) throws -> URL {
        guard !relativePath.hasPrefix("/"), !relativePath.contains("\\") else {
            throw PetPackLibraryError.invalidPack("Unsafe path: \(relativePath)")
        }
        let file = root.appendingPathComponent(relativePath).standardizedFileURL.resolvingSymlinksInPath()
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard file.path.hasPrefix(rootPrefix), FileManager.default.fileExists(atPath: file.path) else {
            throw PetPackLibraryError.invalidPack("Missing asset or path escapes the pack: \(relativePath)")
        }
        return file
    }

    private static func validateTreeSafety(at root: URL) throws {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { throw PetPackLibraryError.invalidPack("Could not read the pet pack") }
        var fileCount = 0
        var totalBytes: Int64 = 0
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true else {
                throw PetPackLibraryError.invalidPack("Symbolic links are not allowed: \(file.lastPathComponent)")
            }
            if values.isRegularFile == true {
                fileCount += 1
                totalBytes += Int64(values.fileSize ?? 0)
            }
            guard fileCount <= 2_000, totalBytes <= 800 * 1_024 * 1_024 else {
                throw PetPackLibraryError.invalidPack("Pet pack exceeds 2,000 files or 800 MB")
            }
        }
    }

    private static func creatorSkillURL() -> URL? {
        if let bundled = Bundle.module.url(forResource: "CreatorSkill", withExtension: nil) {
            return bundled
        }
        return Bundle.main.resourceURL?.appendingPathComponent("CreatorSkill", isDirectory: true)
    }
}
