import AppKit
import ImageIO

enum PetPackLibraryError: LocalizedError {
    case invalidPack(String)
    case petAlreadyExists(String)
    case bundledPetConflict(String)
    case missingCreatorSkill
    case missingLiveMotionSkill
    case operationFailed(String)
    case readOnlyRuntime

    var errorDescription: String? {
        switch self {
        case .invalidPack(let reason): "The pet pack failed validation: \(reason)"
        case .petAlreadyExists(let name): "\(name) is already in the library."
        case .bundledPetConflict(let id): "The imported ID (\(id)) conflicts with a built-in pet."
        case .missingCreatorSkill: "The pet creator Skill is missing from the app bundle."
        case .missingLiveMotionSkill: "The Live Motion creator Skill is missing from the app bundle."
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
    let bodySize: Int
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
        let bodySize = (pet["bodySize"] as? Int) ?? 60
        guard (1...100).contains(bodySize) else {
            throw PetPackLibraryError.invalidPack("pet.bodySize must be an integer from 1 through 100")
        }
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
            let nativeFacing = (json["videoNativeFacing"] as? String) ?? "left"
            guard ["left", "right"].contains(nativeFacing) else {
                throw PetPackLibraryError.invalidPack("videoNativeFacing must be left or right")
            }
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
            bodySize: bodySize,
            appearanceCount: appearanceCount,
            supportsVideo: videoMode
        )
    }

    @discardableResult
    static func installPack(from sourceURL: URL, replacingExisting: Bool = false) throws -> ValidatedPetPack {
        let summary = try validatePack(at: sourceURL)
        if let bundled = PetAssetCatalog.availablePets.first(where: { $0.id == summary.id && $0.isBundled }) {
            throw PetPackLibraryError.bundledPetConflict(bundled.id)
        }

        let fileManager = FileManager.default
        let library = PetAssetCatalog.userPetPacksDirectory
        try fileManager.createDirectory(at: library, withIntermediateDirectories: true)
        let target = library.appendingPathComponent("\(summary.id).furballpet", isDirectory: true)
        try RuntimeSafetyPolicy.requireManagedPetLibraryURL(target)
        if fileManager.fileExists(atPath: target.path), !replacingExisting {
            throw PetPackLibraryError.petAlreadyExists(summary.name)
        }

        let staging = library.appendingPathComponent(".incoming-\(UUID().uuidString)", isDirectory: true)
        try RuntimeSafetyPolicy.requireManagedPetLibraryURL(staging)
        do {
            try fileManager.copyItem(at: sourceURL, to: staging)
            _ = try validatePack(at: staging)
            if fileManager.fileExists(atPath: target.path) {
                _ = try fileManager.replaceItemAt(target, withItemAt: staging)
            } else {
                try fileManager.moveItem(at: staging, to: target)
            }
        } catch {
            try? fileManager.removeItem(at: staging)
            if let libraryError = error as? PetPackLibraryError { throw libraryError }
            throw PetPackLibraryError.operationFailed(error.localizedDescription)
        }
        PetAssetCatalog.reload()
        return summary
    }

    static func exportPet(_ pet: PetLibraryPet, to destinationDirectory: URL) throws -> URL {
        throw PetPackLibraryError.readOnlyRuntime
    }

    static func removePet(_ pet: PetLibraryPet) throws {
        throw PetPackLibraryError.readOnlyRuntime
    }

    static func exportCreatorSkill(to destinationDirectory: URL) throws -> URL {
        guard let source = creatorSkillURL() else { throw PetPackLibraryError.missingCreatorSkill }
        let destination = destinationDirectory.appendingPathComponent("furball-pet-creator", isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw PetPackLibraryError.operationFailed("furball-pet-creator already exists")
        }
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            throw PetPackLibraryError.operationFailed(error.localizedDescription)
        }
    }

    static func exportLiveMotionSkill(to destinationDirectory: URL) throws -> URL {
        guard let source = liveMotionSkillURL() else { throw PetPackLibraryError.missingLiveMotionSkill }
        let destination = destinationDirectory.appendingPathComponent("furball-live-motion-creator", isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw PetPackLibraryError.operationFailed("furball-live-motion-creator already exists")
        }
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            throw PetPackLibraryError.operationFailed(error.localizedDescription)
        }
    }

    static func makeCreationRequest(
        name: String,
        species: String,
        bodySize: Int,
        styles: [String],
        photos: [URL],
        in destinationDirectory: URL
    ) throws -> URL {
        let slug = name.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let baseID = slug.isEmpty ? "my-pet" : slug
        let id = PetAssetCatalog.availablePets.contains(where: { $0.id == baseID })
            ? "\(baseID)-\(UUID().uuidString.prefix(6).lowercased())"
            : baseID
        let root = destinationDirectory.appendingPathComponent("\(id)-creation-request", isDirectory: true)
        guard !FileManager.default.fileExists(atPath: root.path) else {
            throw PetPackLibraryError.operationFailed("\(root.lastPathComponent) already exists")
        }
        let photosRoot = root.appendingPathComponent("ReferencePhotos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosRoot, withIntermediateDirectories: true)
        for (index, photo) in photos.enumerated() {
            let ext = photo.pathExtension.isEmpty ? "jpg" : photo.pathExtension.lowercased()
            try FileManager.default.copyItem(
                at: photo,
                to: photosRoot.appendingPathComponent(String(format: "%02d-reference.%@", index + 1, ext))
            )
        }
        let request: [String: Any] = [
            "requestVersion": 1,
            "pet": ["id": id, "name": name, "species": species, "bodySize": min(100, max(1, bodySize))],
            "styles": ["realistic-2d"],
            "videoGeneration": false,
            "referencePhotoCount": photos.count,
            "expectedOutput": "\(id).furballpet",
            "instructions": [
                "Use the bundled furball-pet-creator Skill.",
                "Generate and validate one Realistic 2D image appearance.",
                "Return one import-ready .furballpet folder."
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: request, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent("REQUEST.json"), options: .atomic)
        if let skill = creatorSkillURL() {
            try FileManager.default.copyItem(at: skill, to: root.appendingPathComponent("furball-pet-creator"))
        }
        return root
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
        bodySize: Int,
        styles: [String],
        photos: [URL]
    ) throws -> CodexPetCreationJob {
        guard let codexExecutableURL else {
            throw PetPackLibraryError.operationFailed(
                "Codex CLI was not found. Install and sign in to Codex, or export a creation request instead."
            )
        }
        let jobsRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Furball2D/CreationJobs", isDirectory: true)
        try FileManager.default.createDirectory(at: jobsRoot, withIntermediateDirectories: true)
        let jobRoot = jobsRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: jobRoot, withIntermediateDirectories: true)
        var didStart = false
        defer {
            if !didStart { try? FileManager.default.removeItem(at: jobRoot) }
        }
        let requestRoot = try makeCreationRequest(
            name: name,
            species: species,
            bodySize: bodySize,
            styles: styles,
            photos: photos,
            in: jobRoot
        )
        guard let requestData = try? Data(contentsOf: requestRoot.appendingPathComponent("REQUEST.json")),
              let request = try? JSONSerialization.jsonObject(with: requestData) as? [String: Any],
              let expectedOutput = request["expectedOutput"] as? String else {
            throw PetPackLibraryError.operationFailed("Could not read the generated REQUEST.json")
        }

        let referencePhotos = try FileManager.default.contentsOfDirectory(
            at: requestRoot.appendingPathComponent("ReferencePhotos", isDirectory: true),
            includingPropertiesForKeys: nil
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        let logURL = requestRoot.appendingPathComponent("codex-generation.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)
        let process = Process()
        process.executableURL = codexExecutableURL
        process.currentDirectoryURL = requestRoot
        var arguments = [
            "exec",
            "--skip-git-repo-check",
            "--ephemeral",
            "--sandbox", "workspace-write",
            "--ask-for-approval", "never",
            "--cd", requestRoot.path
        ]
        for photo in referencePhotos {
            arguments.append(contentsOf: ["--image", photo.path])
        }
        arguments.append(
            "Read REQUEST.json and the complete furball-pet-creator/SKILL.md, then execute that Skill. "
            + "Create the import-ready \(expectedOutput) inside this working directory. "
            + "Use image generation only, preserve the photographed pet's identity, run every bundled validator, "
            + "and do not stop until the final Pet Pack passes validation."
        )
        process.arguments = arguments
        process.standardOutput = logHandle
        process.standardError = logHandle
        do {
            try process.run()
            didStart = true
        } catch {
            try? logHandle.close()
            throw PetPackLibraryError.operationFailed(error.localizedDescription)
        }
        return CodexPetCreationJob(
            process: process,
            workingDirectory: requestRoot,
            expectedPackURL: requestRoot.appendingPathComponent(expectedOutput, isDirectory: true),
            logURL: logURL,
            logHandle: logHandle
        )
    }

    static func finishCodexCreation(_ job: CodexPetCreationJob) throws -> ValidatedPetPack {
        try? job.logHandle.close()
        guard job.process.terminationStatus == 0 else {
            throw PetPackLibraryError.operationFailed(
                "Codex exited with status \(job.process.terminationStatus). See \(job.logURL.lastPathComponent)."
            )
        }
        _ = try validatePack(at: job.expectedPackURL)
        let summary: ValidatedPetPack
        do {
            summary = try installPack(from: job.expectedPackURL)
        } catch PetPackLibraryError.petAlreadyExists {
            summary = try installPack(from: job.expectedPackURL, replacingExisting: true)
        }
        removeCompletedCreationJob(job)
        return summary
    }

    private static func removeCompletedCreationJob(_ job: CodexPetCreationJob) {
        let jobRoot = job.workingDirectory.deletingLastPathComponent().standardizedFileURL
        let jobsRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Furball2D/CreationJobs", isDirectory: true)
            .standardizedFileURL.path + "/"
        if jobRoot.path.hasPrefix(jobsRoot) {
            try? FileManager.default.removeItem(at: jobRoot)
        }
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
        guard atlas["stateModel"] as? String == PetImageStateModel.identifier else {
            throw PetPackLibraryError.invalidPack(
                "Every 2D appearance must use stateModel \(PetImageStateModel.identifier)"
            )
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
        let stateBindings = bindings.compactMap { binding -> PetImageStateModel.Binding? in
            guard let id = binding["id"] as? String,
                  let animation = binding["animation"] as? String else { return nil }
            return PetImageStateModel.Binding(
                id: id,
                animation: animation,
                frameIndices: binding["frameIndices"] as? [Int],
                loops: binding["loop"] as? Bool,
                motion: binding["motion"] as? String
            )
        }
        guard stateBindings.count == bindings.count,
              PetImageStateModel.validates(stateBindings) else {
            throw PetPackLibraryError.invalidPack(
                "2D posture bindings do not match \(PetImageStateModel.identifier)"
            )
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

        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: image.height * bytesPerRow)
        pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }

        func silhouette(row: Int, column: Int) throws -> (width: Int, height: Int) {
            let cellWidth = 384
            let cellHeight = 416
            let originX = column * cellWidth
            let originY = row * cellHeight
            var minX = cellWidth
            var minY = cellHeight
            var maxX = -1
            var maxY = -1
            for y in 0..<cellHeight {
                let rowOffset = (originY + y) * bytesPerRow
                for x in 0..<cellWidth where pixels[rowOffset + (originX + x) * 4 + 3] > 18 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
            guard maxX >= minX, maxY >= minY else {
                throw PetPackLibraryError.invalidPack("Empty shared-state cell [\(row),\(column)]")
            }
            return (maxX - minX + 1, maxY - minY + 1)
        }

        let standing = try silhouette(row: 0, column: 0)
        for column in [2, 3] {
            let lying = try silhouette(row: 5, column: column)
            guard Double(lying.height) <= Double(standing.height) * 0.75,
                  Double(lying.width) / Double(lying.height) >= 1.30 else {
                throw PetPackLibraryError.invalidPack(
                    "lie.idle must be a horizontal body pose (failed[\(column)])"
                )
            }
        }
        for column in [5, 6, 7] {
            let sleeping = try silhouette(row: 5, column: column)
            guard Double(sleeping.height) <= Double(standing.height) * 0.62,
                  Double(sleeping.width) / Double(sleeping.height) >= 1.50 else {
                throw PetPackLibraryError.invalidPack(
                    "sleep.idle must be a horizontal body pose (failed[\(column)])"
                )
            }
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

    private static func liveMotionSkillURL() -> URL? {
        if let bundled = Bundle.module.url(forResource: "VideoCreatorSkill", withExtension: nil) {
            return bundled
        }
        return Bundle.main.resourceURL?.appendingPathComponent("VideoCreatorSkill", isDirectory: true)
    }
}
