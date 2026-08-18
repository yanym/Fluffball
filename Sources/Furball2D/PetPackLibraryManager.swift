import AppKit
import ImageIO

enum PetPackLibraryError: LocalizedError {
    case invalidPack(String)
    case petAlreadyExists(String)
    case bundledPetConflict(String)
    case missingCreatorSkill
    case operationFailed(String)

    var errorDescription: String? {
        switch (AppLanguage.stored, self) {
        case (.simplifiedChinese, .invalidPack(let reason)): "宠物包未通过验证：\(reason)"
        case (.english, .invalidPack(let reason)): "The pet pack failed validation: \(reason)"
        case (.simplifiedChinese, .petAlreadyExists(let name)): "素材库里已经有 \(name)。"
        case (.english, .petAlreadyExists(let name)): "\(name) is already in the library."
        case (.simplifiedChinese, .bundledPetConflict(let id)): "导入包的 ID（\(id)）与内置宠物冲突。"
        case (.english, .bundledPetConflict(let id)): "The imported ID (\(id)) conflicts with a built-in pet."
        case (.simplifiedChinese, .missingCreatorSkill): "安装包中找不到宠物创建 Skill。"
        case (.english, .missingCreatorSkill): "The pet creator Skill is missing from the app bundle."
        case (.simplifiedChinese, .operationFailed(let reason)): "操作失败：\(reason)"
        case (.english, .operationFailed(let reason)): "The operation failed: \(reason)"
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
            throw PetPackLibraryError.invalidPack("请选择一个 .furballpet 文件夹 / Choose a .furballpet folder")
        }
        try validateTreeSafety(at: root)

        let manifestURL = root.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PetPackLibraryError.invalidPack("manifest.json 缺失或格式无效 / missing or invalid manifest.json")
        }
        guard (json["petPackVersion"] as? Int) == 2 else {
            throw PetPackLibraryError.invalidPack("petPackVersion 必须为 2 / must be 2")
        }
        guard let pet = json["pet"] as? [String: Any],
              let id = pet["id"] as? String,
              id.range(of: "^[a-z0-9][a-z0-9-]{1,63}$", options: .regularExpression) != nil,
              let name = pet["name"] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PetPackLibraryError.invalidPack("pet.id 或 pet.name 无效 / invalid pet.id or pet.name")
        }
        let species = (pet["species"] as? String) ?? "other"
        guard ["dog", "cat", "other"].contains(species) else {
            throw PetPackLibraryError.invalidPack("pet.species 必须是 dog、cat 或 other")
        }
        let assetVersion = max(1, (pet["assetVersion"] as? Int) ?? 1)
        guard let capabilities = json["capabilities"] as? [String: Any] else {
            throw PetPackLibraryError.invalidPack("缺少 capabilities / missing capabilities")
        }
        let imageMode = capabilities["imageMode"] as? Bool ?? false
        let videoMode = capabilities["videoMode"] as? Bool ?? false
        guard imageMode || videoMode else {
            throw PetPackLibraryError.invalidPack("至少启用一种视觉模式 / enable at least one visual mode")
        }

        var semanticLoops: [String: Bool] = [:]
        if let images = json["imageAnimations"] as? [[String: Any]] {
            for animation in images {
                guard let semanticID = animation["id"] as? String,
                      let files = animation["files"] as? [String], !files.isEmpty else { continue }
                for path in files + ((animation["rightFiles"] as? [String]) ?? []) {
                    _ = try safeFile(path, under: root)
                }
                semanticLoops[semanticID] = animation["loop"] as? Bool ?? false
            }
        }

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
            guard !atlasFiles.isEmpty || !semanticLoops.isEmpty else {
                throw PetPackLibraryError.invalidPack("图片模式没有图集或 PNG 动画 / no image assets")
            }
            let missing = requiredSemanticIDs.subtracting(semanticLoops.keys)
            guard missing.isEmpty else {
                throw PetPackLibraryError.invalidPack(
                    "缺少标准动作：\(missing.sorted().joined(separator: ", "))"
                )
            }
            for id in requiredSemanticIDs {
                guard semanticLoops[id] == requiredLoopingIDs.contains(id) else {
                    throw PetPackLibraryError.invalidPack("\(id) 的 loop 语义不正确 / invalid loop semantics")
                }
            }
        }
        if videoMode {
            guard let clips = json["clips"] as? [[String: Any]], !clips.isEmpty else {
                throw PetPackLibraryError.invalidPack("videoMode=true 但没有 clips")
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
        let summary = try validatePack(at: sourceURL)
        if let bundled = PetAssetCatalog.availablePets.first(where: { $0.id == summary.id && $0.isBundled }) {
            throw PetPackLibraryError.bundledPetConflict(bundled.id)
        }

        let fileManager = FileManager.default
        let library = PetAssetCatalog.userPetPacksDirectory
        try fileManager.createDirectory(at: library, withIntermediateDirectories: true)
        let target = library.appendingPathComponent("\(summary.id).furballpet", isDirectory: true)
        if fileManager.fileExists(atPath: target.path), !replacingExisting {
            throw PetPackLibraryError.petAlreadyExists(summary.name)
        }

        let staging = library.appendingPathComponent(".incoming-\(UUID().uuidString)", isDirectory: true)
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
        let fileManager = FileManager.default
        let safeName = pet.name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let exportName = safeName.isEmpty ? pet.id : safeName
        let destination = destinationDirectory.appendingPathComponent("\(exportName).furballpet", isDirectory: true)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw PetPackLibraryError.operationFailed("\(destination.lastPathComponent) already exists")
        }
        do {
            try fileManager.copyItem(at: pet.rootURL, to: destination)
            _ = try validatePack(at: destination)
            return destination
        } catch {
            try? fileManager.removeItem(at: destination)
            if let libraryError = error as? PetPackLibraryError { throw libraryError }
            throw PetPackLibraryError.operationFailed(error.localizedDescription)
        }
    }

    static func removePet(_ pet: PetLibraryPet) throws {
        guard !pet.isBundled else {
            throw PetPackLibraryError.operationFailed("Built-in pets cannot be removed")
        }
        let root = pet.rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let library = PetAssetCatalog.userPetPacksDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let prefix = library.path.hasSuffix("/") ? library.path : library.path + "/"
        guard root.path.hasPrefix(prefix) else {
            throw PetPackLibraryError.operationFailed("Pet is outside the managed library")
        }
        do {
            var trashedURL: NSURL?
            try FileManager.default.trashItem(at: root, resultingItemURL: &trashedURL)
            PetAssetCatalog.reload()
        } catch {
            throw PetPackLibraryError.operationFailed(error.localizedDescription)
        }
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

    static func makeCreationRequest(
        name: String,
        species: String,
        styles: [String],
        photos: [URL],
        in destinationDirectory: URL
    ) throws -> URL {
        let slug = name.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let id = slug.isEmpty ? "my-pet-\(Int(Date().timeIntervalSince1970))" : slug
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
            "pet": ["id": id, "name": name, "species": species],
            "styles": styles,
            "videoGeneration": false,
            "referencePhotoCount": photos.count,
            "expectedOutput": "\(id).furballpet",
            "instructions": [
                "Use the bundled furball-pet-creator Skill.",
                "Generate and validate every requested image style.",
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

    private static func inspectAtlas(
        _ atlas: [String: Any],
        root: URL,
        semanticLoops: inout [String: Bool],
        atlasFiles: inout Set<String>
    ) throws {
        guard (atlas["spriteVersionNumber"] as? Int) == 2,
              let file = atlas["file"] as? String else {
            throw PetPackLibraryError.invalidPack("spriteAtlas 必须是 v2 并声明 file")
        }
        guard let layout = atlas["layout"] as? [String: Any],
              layout["columns"] as? Int == 8,
              layout["rows"] as? Int == 11,
              layout["cellWidth"] as? Int == 192,
              layout["cellHeight"] as? Int == 208 else {
            throw PetPackLibraryError.invalidPack("v2 图集必须是 8×11，每格 192×208")
        }
        atlasFiles.insert(file)
        guard let animations = atlas["animations"] as? [[String: Any]], !animations.isEmpty else {
            throw PetPackLibraryError.invalidPack("spriteAtlas.animations 不能为空")
        }
        var animationLoops: [String: Bool] = [:]
        for animation in animations {
            guard let id = animation["id"] as? String,
                  let row = animation["rowIndex"] as? Int, (0..<11).contains(row),
                  let count = animation["frameCount"] as? Int, (1...8).contains(count),
                  let durations = animation["frameDurations"] as? [Double],
                  durations.count == count, durations.allSatisfy({ $0 > 0 }),
                  let loops = animation["loop"] as? Bool else {
                throw PetPackLibraryError.invalidPack("sprite 动画行、帧数或时长无效")
            }
            animationLoops[id] = loops
        }
        guard let bindings = atlas["bindings"] as? [[String: Any]] else {
            throw PetPackLibraryError.invalidPack("spriteAtlas.bindings 不能为空")
        }
        for binding in bindings {
            guard let id = binding["id"] as? String,
                  let animation = binding["animation"] as? String,
                  let inheritedLoop = animationLoops[animation] else {
                throw PetPackLibraryError.invalidPack("sprite binding 引用了不存在的动画")
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
            throw PetPackLibraryError.invalidPack("v2 图集必须声明完整 16 方向")
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
              image.width == 1536, image.height == 2288 else {
            throw PetPackLibraryError.invalidPack("\(url.lastPathComponent) 必须是 1536×2288 WebP")
        }
        let alpha = image.alphaInfo
        guard alpha != .none && alpha != .noneSkipFirst && alpha != .noneSkipLast else {
            throw PetPackLibraryError.invalidPack("\(url.lastPathComponent) 没有透明通道")
        }
    }

    private static func safeFile(_ relativePath: String, under root: URL) throws -> URL {
        guard !relativePath.hasPrefix("/"), !relativePath.contains("\\") else {
            throw PetPackLibraryError.invalidPack("不安全路径：\(relativePath)")
        }
        let file = root.appendingPathComponent(relativePath).standardizedFileURL.resolvingSymlinksInPath()
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard file.path.hasPrefix(rootPrefix), FileManager.default.fileExists(atPath: file.path) else {
            throw PetPackLibraryError.invalidPack("缺少素材或路径越界：\(relativePath)")
        }
        return file
    }

    private static func validateTreeSafety(at root: URL) throws {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { throw PetPackLibraryError.invalidPack("无法读取宠物包") }
        var fileCount = 0
        var totalBytes: Int64 = 0
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true else {
                throw PetPackLibraryError.invalidPack("不允许符号链接：\(file.lastPathComponent)")
            }
            if values.isRegularFile == true {
                fileCount += 1
                totalBytes += Int64(values.fileSize ?? 0)
            }
            guard fileCount <= 2_000, totalBytes <= 800 * 1_024 * 1_024 else {
                throw PetPackLibraryError.invalidPack("宠物包过大（最多 2000 个文件 / 800 MB）")
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
