#!/usr/bin/env swift

@preconcurrency import AVFoundation
import CoreVideo
import Foundation
import ImageIO

private struct Manifest: Decodable {
    struct Pet: Decodable {
        let id: String
        let name: String
        let species: String
        let assetVersion: Int
    }

    struct Canvas: Decodable {
        let width: Int
        let height: Int
        let fps: Double
    }

    struct Clip: Decodable {
        let id: String
        let file: String
        let loop: Bool
    }

    struct Capabilities: Decodable {
        let imageMode: Bool
        let videoMode: Bool
    }

    struct ImageCanvas: Decodable {
        let width: Int
        let height: Int
        let runtimeKeying: Bool
    }

    struct ImageAnimation: Decodable {
        let id: String
        let files: [String]
        let rightFiles: [String]?
        let loop: Bool
        let motion: String
        let frameDuration: Double?
        let duration: Double?
    }

    struct SpriteAtlas: Decodable {
        struct Layout: Decodable {
            let columns: Int
            let rows: Int
            let cellWidth: Int
            let cellHeight: Int
        }

        struct Rendering: Decodable {
            let canvasWidth: Int
            let canvasHeight: Int
            let bottomPadding: Int?
        }

        struct Animation: Decodable {
            let id: String
            let rowIndex: Int
            let frameCount: Int
            let frameDurations: [Double]
            let loop: Bool
            let motion: String
            let frameBlendFraction: Double?
        }

        struct Binding: Decodable {
            let id: String
            let animation: String
            let rightAnimation: String?
            let frameIndices: [Int]?
            let rightFrameIndices: [Int]?
            let loop: Bool?
            let motion: String?
            let frameDurationScale: Double?
            let frameBlendFraction: Double?
        }

        struct LookDirection: Decodable {
            let degrees: Double
            let rowIndex: Int
            let columnIndex: Int
        }

        struct LocalizedTitle: Decodable {
            let zhHans: String
            let en: String

            private enum CodingKeys: String, CodingKey {
                case zhHans = "zh-Hans"
                case en
            }
        }

        struct Action: Decodable {
            let id: String
            let title: LocalizedTitle
            let resultingPosture: String?
            let autonomous: Bool?
        }

        let file: String
        let spriteVersionNumber: Int
        let layout: Layout
        let rendering: Rendering
        let animations: [Animation]
        let bindings: [Binding]
        let lookDirections: [LookDirection]?
        let actions: [Action]?
    }

    struct Appearance: Decodable {
        let id: String
        let kind: String
        let isDefault: Bool?
        let atlasFile: String?
        let spriteAtlas: SpriteAtlas?
    }

    let petPackVersion: Int
    let pet: Pet
    let canvas: Canvas
    let capabilities: Capabilities?
    let imageCanvas: ImageCanvas?
    let imageAnimations: [ImageAnimation]?
    let spriteAtlas: SpriteAtlas?
    let appearances: [Appearance]?
    let clips: [Clip]?
}

private enum ValidationError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): message
        }
    }
}

private let requiredClipIDs: Set<String> = [
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

private let loopingClipIDs: Set<String> = [
    "stand.idle", "sit.idle", "lie.idle", "sleep.idle",
    "walk.loop", "slow-run.loop", "fast-run.loop",
    "stand.facing.left-profile", "stand.facing.front-near-profile-left",
    "stand.facing.front-three-quarter-left", "stand.facing.front-near-center-left",
    "stand.facing.front", "stand.facing.front-near-center-right",
    "stand.facing.front-three-quarter-right", "stand.facing.front-near-profile-right",
    "stand.facing.right-profile"
]

private struct ValidatedSpriteAtlas {
    let loopsByID: [String: Bool]
}

private func fail(_ message: String) throws -> Never {
    throw ValidationError.failed(message)
}

private func codecName(_ description: CMFormatDescription) -> String {
    let code = CMFormatDescriptionGetMediaSubType(description)
    let bytes: [UInt8] = [
        UInt8((code >> 24) & 0xff), UInt8((code >> 16) & 0xff),
        UInt8((code >> 8) & 0xff), UInt8(code & 0xff)
    ]
    return String(bytes: bytes, encoding: .ascii) ?? "unknown"
}

private func containsTransparency(asset: AVAsset, track: AVAssetTrack) throws -> Bool {
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(
        track: track,
        outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    )
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { return false }
    reader.add(output)
    guard reader.startReading() else { return false }
    defer { reader.cancelReading() }

    for _ in 0..<8 {
        guard let sample = output.copyNextSampleBuffer(),
              let buffer = CMSampleBufferGetImageBuffer(sample) else { break }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { continue }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let stepX = max(1, width / 96)
        let stepY = max(1, height / 54)
        for y in stride(from: 0, to: height, by: stepY) {
            let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in stride(from: 0, to: width, by: stepX) where row[x * 4 + 3] < 250 {
                return true
            }
        }
    }
    return false
}

private func validateVideo(_ url: URL, canvas: Manifest.Canvas) async throws {
    let asset = AVURLAsset(url: url)
    let videoTracks = try await asset.loadTracks(withMediaType: .video)
    guard videoTracks.count == 1, let track = videoTracks.first else {
        try fail("\(url.lastPathComponent)：必须恰好包含一条视频轨")
    }
    guard try await asset.loadTracks(withMediaType: .audio).isEmpty else {
        try fail("\(url.lastPathComponent)：运行时素材不能包含音轨")
    }
    guard let description = try await track.load(.formatDescriptions).first else {
        try fail("\(url.lastPathComponent)：无法读取视频格式")
    }

    let dimensions = CMVideoFormatDescriptionGetDimensions(description)
    guard dimensions.width == Int32(canvas.width), dimensions.height == Int32(canvas.height) else {
        try fail("\(url.lastPathComponent)：画布为 \(dimensions.width)×\(dimensions.height)，期望 \(canvas.width)×\(canvas.height)")
    }
    let nominalFrameRate = try await track.load(.nominalFrameRate)
    guard abs(Double(nominalFrameRate) - canvas.fps) < 0.01 else {
        try fail("\(url.lastPathComponent)：帧率为 \(nominalFrameRate)，期望 \(canvas.fps)")
    }
    guard codecName(description) == "hvc1" else {
        try fail("\(url.lastPathComponent)：编码标签不是 hvc1")
    }
    guard try containsTransparency(asset: asset, track: track) else {
        try fail("\(url.lastPathComponent)：抽样帧中没有检测到透明像素")
    }
}

private func validateImage(_ url: URL, width: Int, height: Int) throws {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        try fail("\(url.lastPathComponent)：无法读取图片")
    }
    guard image.width == width, image.height == height else {
        try fail("\(url.lastPathComponent)：画布为 \(image.width)×\(image.height)，期望 \(width)×\(height)")
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
    var hasTransparentPixel = false
    var hasVisiblePixel = false
    for offset in stride(from: 3, to: pixels.count, by: 4) {
        hasTransparentPixel = hasTransparentPixel || pixels[offset] < 250
        hasVisiblePixel = hasVisiblePixel || pixels[offset] > 18
        if hasTransparentPixel && hasVisiblePixel { break }
    }
    guard hasTransparentPixel, hasVisiblePixel else {
        try fail("\(url.lastPathComponent)：必须同时包含透明背景与可见宠物像素")
    }
}

private func validateSpriteAtlas(
    _ atlas: Manifest.SpriteAtlas,
    rootURL: URL
) throws -> ValidatedSpriteAtlas {
    guard atlas.spriteVersionNumber == 2 else {
        try fail("spriteAtlas.spriteVersionNumber 必须为 2")
    }
    let layout = atlas.layout
    guard layout.columns == 8, layout.rows == 11,
          layout.cellWidth % 192 == 0, layout.cellHeight % 208 == 0,
          layout.cellWidth / 192 == layout.cellHeight / 208,
          (1...2).contains(layout.cellWidth / 192) else {
        try fail("v2 spriteAtlas 必须为 8×11 格，并使用 192×208（1×）或 384×416（2×）单元格")
    }
    guard atlas.rendering.canvasWidth > 0, atlas.rendering.canvasHeight > 0,
          (atlas.rendering.bottomPadding ?? 0) >= 0 else {
        try fail("spriteAtlas.rendering 必须声明有效的运行时画布与底部留白")
    }
    guard atlas.file.lowercased().hasSuffix(".webp") else {
        try fail("spriteAtlas.file 必须是透明 WebP")
    }
    let atlasURL = try safeAssetURL(atlas.file, rootURL: rootURL)
    try validateImage(
        atlasURL,
        width: layout.columns * layout.cellWidth,
        height: layout.rows * layout.cellHeight
    )

    let supportedMotions: Set<String> = [
        "none", "idle", "sleep", "transition", "look", "walk", "slow-run", "fast-run", "settle"
    ]
    var animationsByID: [String: Manifest.SpriteAtlas.Animation] = [:]
    for animation in atlas.animations {
        guard animationsByID[animation.id] == nil else {
            try fail("重复 sprite 动画 ID：\(animation.id)")
        }
        guard !animation.id.isEmpty,
              animation.rowIndex >= 0, animation.rowIndex < layout.rows,
              animation.frameCount > 0, animation.frameCount <= layout.columns,
              animation.frameDurations.count == animation.frameCount,
              animation.frameDurations.allSatisfy({ $0 > 0 }),
              supportedMotions.contains(animation.motion) else {
            try fail("\(animation.id)：sprite 动画行、帧数、时长或 motion 无效")
        }
        if let fraction = animation.frameBlendFraction, !(0...0.48).contains(fraction) {
            try fail("\(animation.id)：frameBlendFraction 必须在 0...0.48")
        }
        animationsByID[animation.id] = animation
    }

    func validateIndices(
        _ indices: [Int]?,
        animation: Manifest.SpriteAtlas.Animation,
        bindingID: String
    ) throws {
        guard let indices else { return }
        guard !indices.isEmpty,
              indices.allSatisfy({ $0 >= 0 && $0 < animation.frameCount }) else {
            try fail("\(bindingID)：frameIndices 超出 \(animation.id) 的有效帧范围")
        }
    }

    var loopsByID: [String: Bool] = [:]
    for binding in atlas.bindings {
        guard loopsByID[binding.id] == nil else {
            try fail("重复 sprite 语义绑定：\(binding.id)")
        }
        guard let animation = animationsByID[binding.animation] else {
            try fail("\(binding.id)：找不到 sprite 动画 \(binding.animation)")
        }
        try validateIndices(binding.frameIndices, animation: animation, bindingID: binding.id)
        if let rightAnimationID = binding.rightAnimation {
            guard let rightAnimation = animationsByID[rightAnimationID] else {
                try fail("\(binding.id)：找不到右向 sprite 动画 \(rightAnimationID)")
            }
            let leftFrameCount = binding.frameIndices?.count ?? animation.frameCount
            let rightFrameCount = binding.rightFrameIndices?.count
                ?? binding.frameIndices?.count
                ?? rightAnimation.frameCount
            guard rightFrameCount == leftFrameCount else {
                try fail("\(binding.id)：左右 sprite 动画的有效帧数必须一致")
            }
            try validateIndices(
                binding.rightFrameIndices ?? binding.frameIndices,
                animation: rightAnimation,
                bindingID: binding.id
            )
        } else if binding.rightFrameIndices != nil {
            try fail("\(binding.id)：rightFrameIndices 需要 rightAnimation")
        }
        if let scale = binding.frameDurationScale, scale <= 0 {
            try fail("\(binding.id)：frameDurationScale 必须大于 0")
        }
        if let motion = binding.motion, !supportedMotions.contains(motion) {
            try fail("\(binding.id)：motion 无效")
        }
        if let fraction = binding.frameBlendFraction, !(0...0.48).contains(fraction) {
            try fail("\(binding.id)：frameBlendFraction 必须在 0...0.48")
        }
        loopsByID[binding.id] = binding.loop ?? animation.loop
    }

    if let directions = atlas.lookDirections {
        let expected = Set((0..<16).map { Double($0) * 22.5 })
        let actual = Set(directions.map(\.degrees))
        guard directions.count == 16, actual == expected else {
            try fail("spriteAtlas.lookDirections 必须完整声明 0° 起每 22.5° 的 16 个方向")
        }
        for direction in directions {
            guard direction.rowIndex >= 0, direction.rowIndex < layout.rows,
                  direction.columnIndex >= 0, direction.columnIndex < layout.columns else {
                try fail("lookDirections \(direction.degrees)° 的单元格越界")
            }
        }
        // A complete 16-direction atlas is the higher-fidelity replacement for
        // the legacy nine standalone facing assets. Count the corresponding
        // semantic slots as covered so a pure v2 atlas needs no placeholder PNGs.
        for id in [
            "stand.facing.left-profile", "stand.facing.front-near-profile-left",
            "stand.facing.front-three-quarter-left", "stand.facing.front-near-center-left",
            "stand.facing.front", "stand.facing.front-near-center-right",
            "stand.facing.front-three-quarter-right", "stand.facing.front-near-profile-right",
            "stand.facing.right-profile"
        ] {
            loopsByID[id] = true
        }
    }

    var actionIDs = Set<String>()
    for action in atlas.actions ?? [] {
        guard actionIDs.insert(action.id).inserted else {
            try fail("重复 sprite action ID：\(action.id)")
        }
        guard loopsByID[action.id] != nil,
              !action.title.zhHans.isEmpty,
              !action.title.en.isEmpty,
              ["stand", "sit", "lie", "sleep"].contains(action.resultingPosture ?? "stand") else {
            try fail("sprite action \(action.id) 缺少绑定、双语标题或有效 resultingPosture")
        }
    }

    print("✓ sprite atlas  \(atlas.file)  [\(layout.columns)×\(layout.rows), v\(atlas.spriteVersionNumber)]")
    return ValidatedSpriteAtlas(loopsByID: loopsByID)
}

private func safeAssetURL(_ relativePath: String, rootURL: URL) throws -> URL {
    guard !relativePath.hasPrefix("/") else { try fail("素材路径必须是 Pet Pack 内的相对路径") }
    let url = rootURL.appendingPathComponent(relativePath).standardizedFileURL
    let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
    guard url.path.hasPrefix(rootPrefix), FileManager.default.fileExists(atPath: url.path) else {
        try fail("找不到或越界的素材路径 \(relativePath)")
    }
    return url
}

private func atlas(_ atlas: Manifest.SpriteAtlas, replacingFile file: String) -> Manifest.SpriteAtlas {
    Manifest.SpriteAtlas(
        file: file,
        spriteVersionNumber: atlas.spriteVersionNumber,
        layout: atlas.layout,
        rendering: atlas.rendering,
        animations: atlas.animations,
        bindings: atlas.bindings,
        lookDirections: atlas.lookDirections,
        actions: atlas.actions
    )
}

private func validate(packURL: URL) async throws {
    let rootURL = packURL.standardizedFileURL
    let manifestURL = rootURL.appendingPathComponent("manifest.json")
    guard let data = try? Data(contentsOf: manifestURL) else {
        try fail("找不到 manifest.json：\(manifestURL.path)")
    }
    let manifest = try JSONDecoder().decode(Manifest.self, from: data)

    guard [1, 2].contains(manifest.petPackVersion) else {
        try fail("当前只支持 petPackVersion 1 或 2")
    }
    guard !manifest.pet.id.isEmpty, !manifest.pet.name.isEmpty, manifest.pet.assetVersion > 0 else {
        try fail("pet.id、pet.name 和 pet.assetVersion 必须有效")
    }
    guard ["dog", "cat", "other"].contains(manifest.pet.species) else {
        try fail("pet.species 必须是 dog、cat 或 other")
    }
    guard manifest.canvas.width >= 960, manifest.canvas.height >= 540,
          manifest.canvas.width * 9 == manifest.canvas.height * 16,
          manifest.canvas.fps >= 24, manifest.canvas.fps <= 120 else {
        try fail("Pet Pack 视频画布必须为至少 960×540 的 16:9 画布，帧率为 24–120 fps")
    }


    let supportsImages = manifest.capabilities?.imageMode ?? false
    let supportsVideo = manifest.capabilities?.videoMode ?? true
    guard supportsImages || supportsVideo else { try fail("素材包至少要支持图片或视频模式之一") }

    var clipsByID: [String: Manifest.Clip] = [:]
    for clip in manifest.clips ?? [] {
        guard clipsByID[clip.id] == nil else { try fail("重复动作 ID：\(clip.id)") }
        clipsByID[clip.id] = clip
    }

    if supportsVideo {
        let missing = requiredClipIDs.subtracting(clipsByID.keys)
        guard missing.isEmpty else { try fail("视频模式缺少标准动作：\(missing.sorted().joined(separator: ", "))") }

        for id in requiredClipIDs.sorted() {
            guard let clip = clipsByID[id] else { continue }
            guard clip.loop == loopingClipIDs.contains(id) else {
                try fail("\(id)：视频 loop 标记不符合标准动作语义")
            }
            guard clip.file.hasSuffix(".mov") else {
                try fail("\(id)：file 必须是 Pet Pack 内的相对 .mov 路径")
            }
            let url = try safeAssetURL(clip.file, rootURL: rootURL)
            try await validateVideo(url, canvas: manifest.canvas)
            print("✓ video \(id)  \(clip.file)")
        }
    }

    if supportsImages {
        guard manifest.petPackVersion >= 2 else {
            try fail("图片模式需要 petPackVersion 2")
        }
        var imagesByID: [String: Manifest.ImageAnimation] = [:]
        for animation in manifest.imageAnimations ?? [] {
            guard imagesByID[animation.id] == nil else { try fail("重复图片动作 ID：\(animation.id)") }
            imagesByID[animation.id] = animation
        }
        var resolvedLoopsByID: [String: Bool] = [:]

        if !imagesByID.isEmpty {
            guard let imageCanvas = manifest.imageCanvas,
                  imageCanvas.width == 960,
                  imageCanvas.height == 540,
                  !imageCanvas.runtimeKeying else {
                try fail("传统图片序列必须声明 960×540 imageCanvas，并关闭运行时抠像")
            }
            var validatedPaths = Set<String>()
            let supportedMotions: Set<String> = [
                "none", "idle", "sleep", "transition", "look", "walk", "slow-run", "fast-run", "settle"
            ]
            for id in imagesByID.keys.sorted() {
                guard let animation = imagesByID[id] else { continue }
                guard supportedMotions.contains(animation.motion), !animation.files.isEmpty else {
                    try fail("\(id)：图片 motion 或 files 无效")
                }
                if let rightFiles = animation.rightFiles, rightFiles.count != animation.files.count {
                    try fail("\(id)：rightFiles 必须与 files 数量一致")
                }
                if let frameDuration = animation.frameDuration, frameDuration <= 0 {
                    try fail("\(id)：frameDuration 必须大于 0")
                }
                if !animation.loop, (animation.duration ?? 0) <= 0 {
                    try fail("\(id)：一次性图片动作必须声明 duration")
                }
                for path in animation.files + (animation.rightFiles ?? [])
                    where validatedPaths.insert(path).inserted {
                    guard path.lowercased().hasSuffix(".png") else {
                        try fail("\(id)：传统图片序列必须使用 PNG")
                    }
                    let url = try safeAssetURL(path, rootURL: rootURL)
                    try validateImage(url, width: imageCanvas.width, height: imageCanvas.height)
                }
                resolvedLoopsByID[id] = animation.loop
                print("✓ image \(id)  \(animation.files.count) frame(s)")
            }
        }

        if let atlas = manifest.spriteAtlas {
            let validatedAtlas = try validateSpriteAtlas(atlas, rootURL: rootURL)
            // Runtime sprite bindings intentionally override legacy PNG
            // descriptors that share the same semantic ID.
            for (id, loops) in validatedAtlas.loopsByID {
                resolvedLoopsByID[id] = loops
            }
        }

        if let appearances = manifest.appearances, !appearances.isEmpty {
            var ids = Set<String>()
            guard appearances.allSatisfy({ ids.insert($0.id).inserted }),
                  appearances.filter({ $0.isDefault == true }).count == 1 else {
                try fail("appearances 必须使用唯一 ID，且恰好一个 isDefault=true")
            }
            guard appearances.contains(where: { $0.kind == "sprite-atlas" }) else {
                try fail("imageMode=true 时 appearances 至少包含一个 sprite-atlas")
            }
            for appearance in appearances where appearance.kind == "sprite-atlas" {
                let descriptor: Manifest.SpriteAtlas
                if let explicit = appearance.spriteAtlas {
                    descriptor = explicit
                } else if let file = appearance.atlasFile, let base = manifest.spriteAtlas {
                    descriptor = atlas(base, replacingFile: file)
                } else {
                    try fail("appearance \(appearance.id) 缺少 spriteAtlas 或 atlasFile")
                }
                _ = try validateSpriteAtlas(descriptor, rootURL: rootURL)
            }
        }

        guard !resolvedLoopsByID.isEmpty else {
            try fail("图片模式至少需要 imageAnimations 或 spriteAtlas")
        }
        let missing = requiredClipIDs.subtracting(resolvedLoopsByID.keys)
        guard missing.isEmpty else {
            try fail("图片模式缺少标准动作：\(missing.sorted().joined(separator: ", "))")
        }
        for id in requiredClipIDs.sorted() {
            guard resolvedLoopsByID[id] == loopingClipIDs.contains(id) else {
                try fail("\(id)：图片 loop 标记不符合标准动作语义")
            }
        }
    }

    let modes = [supportsImages ? "image" : nil, supportsVideo ? "video" : nil]
        .compactMap { $0 }
        .joined(separator: "+")
    print("\nPet Pack 验证通过：\(manifest.pet.name) [\(manifest.pet.species)]，模式 \(modes)，共 \(requiredClipIDs.count) 个标准动作槽位。")
}

let argument = CommandLine.arguments.dropFirst().first
    ?? "Sources/Furball2D/Assets"

do {
    try await validate(packURL: URL(fileURLWithPath: argument, isDirectory: true))
} catch {
    FileHandle.standardError.write(Data("Pet Pack 验证失败：\(error.localizedDescription)\n".utf8))
    exit(1)
}
