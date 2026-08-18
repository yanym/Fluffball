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
            let en: String
        }

        struct Action: Decodable {
            let id: String
            let title: LocalizedTitle
            let resultingPosture: String?
            let autonomous: Bool?
        }

        let file: String
        let spriteVersionNumber: Int
        let assetScale: Int?
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
        try fail("\(url.lastPathComponent): expected exactly one video track")
    }
    guard try await asset.loadTracks(withMediaType: .audio).isEmpty else {
        try fail("\(url.lastPathComponent): runtime assets must not contain audio")
    }
    guard let description = try await track.load(.formatDescriptions).first else {
        try fail("\(url.lastPathComponent): could not read the video format")
    }

    let dimensions = CMVideoFormatDescriptionGetDimensions(description)
    guard dimensions.width == Int32(canvas.width), dimensions.height == Int32(canvas.height) else {
        try fail("\(url.lastPathComponent): canvas is \(dimensions.width)×\(dimensions.height), expected \(canvas.width)×\(canvas.height)")
    }
    let nominalFrameRate = try await track.load(.nominalFrameRate)
    guard abs(Double(nominalFrameRate) - canvas.fps) < 0.01 else {
        try fail("\(url.lastPathComponent): frame rate is \(nominalFrameRate), expected \(canvas.fps)")
    }
    guard codecName(description) == "hvc1" else {
        try fail("\(url.lastPathComponent): codec tag is not hvc1")
    }
    guard try containsTransparency(asset: asset, track: track) else {
        try fail("\(url.lastPathComponent): sampled frames contain no transparent pixels")
    }
}

private func validateImage(_ url: URL, width: Int, height: Int) throws {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        try fail("\(url.lastPathComponent): could not read the image")
    }
    guard image.width == width, image.height == height else {
        try fail("\(url.lastPathComponent): canvas is \(image.width)×\(image.height), expected \(width)×\(height)")
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
        try fail("\(url.lastPathComponent): expected both transparent background and visible pet pixels")
    }
}

private func validateStableCellBaselines(
    _ url: URL,
    atlas: Manifest.SpriteAtlas
) throws {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        try fail("\(url.lastPathComponent): could not decode cells for ground-baseline QA")
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

    let layout = atlas.layout
    var stableCells: [(label: String, row: Int, column: Int)] = []
    for animation in atlas.animations where animation.id != "jumping" {
        for column in 0..<animation.frameCount {
            stableCells.append(("\(animation.id)[\(column)]", animation.rowIndex, column))
        }
    }
    for direction in atlas.lookDirections ?? [] {
        stableCells.append(("look[\(direction.degrees)]", direction.rowIndex, direction.columnIndex))
    }

    var baselines: [(label: String, value: Int)] = []
    for cell in stableCells {
        var bottom = -1
        let originX = cell.column * layout.cellWidth
        let originY = cell.row * layout.cellHeight
        for y in 0..<layout.cellHeight {
            let rowOffset = (originY + y) * bytesPerRow
            for x in 0..<layout.cellWidth {
                let alpha = pixels[rowOffset + (originX + x) * 4 + 3]
                if alpha > 18 { bottom = max(bottom, y) }
            }
        }
        guard bottom >= 0 else {
            try fail("\(url.lastPathComponent): \(cell.label) is empty")
        }
        baselines.append((cell.label, bottom))
    }
    guard let minimum = baselines.map(\.value).min(),
          let maximum = baselines.map(\.value).max() else {
        try fail("\(url.lastPathComponent): no stable cells were available for baseline QA")
    }
    guard maximum - minimum <= 2 else {
        let outliers = baselines
            .filter { $0.value != minimum }
            .prefix(8)
            .map { "\($0.label)=\($0.value)" }
            .joined(separator: ", ")
        try fail("\(url.lastPathComponent): planted-cell ground baseline drifts \(minimum)...\(maximum) px (\(outliers))")
    }
    print("✓ ground baseline  \(atlas.file)  [spread \(maximum - minimum) px]")
}

private func validateSpriteAtlas(
    _ atlas: Manifest.SpriteAtlas,
    rootURL: URL
) throws -> ValidatedSpriteAtlas {
    guard atlas.spriteVersionNumber == 2 else {
        try fail("spriteAtlas.spriteVersionNumber must be 2")
    }
    let layout = atlas.layout
    guard atlas.assetScale == 2,
          layout.columns == 8, layout.rows == 11,
          layout.cellWidth == 384, layout.cellHeight == 416 else {
        try fail("v2 spriteAtlas must use assetScale 2 with an 8×11 layout and native 384×416 cells")
    }
    guard atlas.rendering.canvasWidth > 0, atlas.rendering.canvasHeight > 0,
          (atlas.rendering.bottomPadding ?? 0) >= 0 else {
        try fail("spriteAtlas.rendering must declare a valid canvas and bottom padding")
    }
    guard atlas.file.lowercased().hasSuffix(".webp") else {
        try fail("spriteAtlas.file must be a transparent WebP")
    }
    let atlasURL = try safeAssetURL(atlas.file, rootURL: rootURL)
    try validateImage(
        atlasURL,
        width: layout.columns * layout.cellWidth,
        height: layout.rows * layout.cellHeight
    )
    try validateStableCellBaselines(atlasURL, atlas: atlas)

    let supportedMotions: Set<String> = [
        "none", "idle", "sleep", "transition", "look", "walk", "slow-run", "fast-run", "settle"
    ]
    var animationsByID: [String: Manifest.SpriteAtlas.Animation] = [:]
    for animation in atlas.animations {
        guard animationsByID[animation.id] == nil else {
            try fail("Duplicate sprite animation ID: \(animation.id)")
        }
        guard !animation.id.isEmpty,
              animation.rowIndex >= 0, animation.rowIndex < layout.rows,
              animation.frameCount > 0, animation.frameCount <= layout.columns,
              animation.frameDurations.count == animation.frameCount,
              animation.frameDurations.allSatisfy({ $0 > 0 }),
              supportedMotions.contains(animation.motion) else {
            try fail("\(animation.id): invalid sprite row, frame count, duration, or motion")
        }
        if let fraction = animation.frameBlendFraction, !(0...0.48).contains(fraction) {
            try fail("\(animation.id): frameBlendFraction must be in 0...0.48")
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
            try fail("\(bindingID): frameIndices exceed the valid range for \(animation.id)")
        }
    }

    var loopsByID: [String: Bool] = [:]
    for binding in atlas.bindings {
        guard loopsByID[binding.id] == nil else {
            try fail("Duplicate sprite semantic binding: \(binding.id)")
        }
        guard let animation = animationsByID[binding.animation] else {
            try fail("\(binding.id): missing sprite animation \(binding.animation)")
        }
        try validateIndices(binding.frameIndices, animation: animation, bindingID: binding.id)
        if let rightAnimationID = binding.rightAnimation {
            guard let rightAnimation = animationsByID[rightAnimationID] else {
                try fail("\(binding.id): missing right-facing sprite animation \(rightAnimationID)")
            }
            let leftFrameCount = binding.frameIndices?.count ?? animation.frameCount
            let rightFrameCount = binding.rightFrameIndices?.count
                ?? binding.frameIndices?.count
                ?? rightAnimation.frameCount
            guard rightFrameCount == leftFrameCount else {
                try fail("\(binding.id): left and right sprite animations must use equal frame counts")
            }
            try validateIndices(
                binding.rightFrameIndices ?? binding.frameIndices,
                animation: rightAnimation,
                bindingID: binding.id
            )
        } else if binding.rightFrameIndices != nil {
            try fail("\(binding.id): rightFrameIndices requires rightAnimation")
        }
        if let scale = binding.frameDurationScale, scale <= 0 {
            try fail("\(binding.id): frameDurationScale must be greater than zero")
        }
        if let motion = binding.motion, !supportedMotions.contains(motion) {
            try fail("\(binding.id): invalid motion")
        }
        if let fraction = binding.frameBlendFraction, !(0...0.48).contains(fraction) {
            try fail("\(binding.id): frameBlendFraction must be in 0...0.48")
        }
        loopsByID[binding.id] = binding.loop ?? animation.loop
    }

    if let directions = atlas.lookDirections {
        let expected = Set((0..<16).map { Double($0) * 22.5 })
        let actual = Set(directions.map(\.degrees))
        guard directions.count == 16, actual == expected else {
            try fail("spriteAtlas.lookDirections must declare all 16 directions from 0° in 22.5° steps")
        }
        for direction in directions {
            guard direction.rowIndex >= 0, direction.rowIndex < layout.rows,
                  direction.columnIndex >= 0, direction.columnIndex < layout.columns else {
                try fail("lookDirections \(direction.degrees)° references an out-of-range cell")
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
            try fail("Duplicate sprite action ID: \(action.id)")
        }
        guard loopsByID[action.id] != nil,
              !action.title.en.isEmpty,
              ["stand", "sit", "lie", "sleep"].contains(action.resultingPosture ?? "stand") else {
            try fail("Sprite action \(action.id) lacks a binding, English title, or valid resultingPosture")
        }
    }

    print("✓ sprite atlas  \(atlas.file)  [\(layout.columns)×\(layout.rows), v\(atlas.spriteVersionNumber)]")
    return ValidatedSpriteAtlas(loopsByID: loopsByID)
}

private func safeAssetURL(_ relativePath: String, rootURL: URL) throws -> URL {
    guard !relativePath.hasPrefix("/") else { try fail("Asset paths must be relative to the Pet Pack") }
    let url = rootURL.appendingPathComponent(relativePath).standardizedFileURL
    let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
    guard url.path.hasPrefix(rootPrefix), FileManager.default.fileExists(atPath: url.path) else {
        try fail("Missing or out-of-bounds asset path: \(relativePath)")
    }
    return url
}

private func atlas(_ atlas: Manifest.SpriteAtlas, replacingFile file: String) -> Manifest.SpriteAtlas {
    Manifest.SpriteAtlas(
        file: file,
        spriteVersionNumber: atlas.spriteVersionNumber,
        assetScale: atlas.assetScale,
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
        try fail("manifest.json not found: \(manifestURL.path)")
    }
    let manifest = try JSONDecoder().decode(Manifest.self, from: data)

    guard manifest.petPackVersion == 2 else {
        try fail("Only petPackVersion 2 is supported")
    }
    guard !manifest.pet.id.isEmpty, !manifest.pet.name.isEmpty, manifest.pet.assetVersion > 0 else {
        try fail("pet.id, pet.name, and pet.assetVersion must be valid")
    }
    guard ["dog", "cat", "other"].contains(manifest.pet.species) else {
        try fail("pet.species must be dog, cat, or other")
    }
    guard manifest.canvas.width >= 960, manifest.canvas.height >= 540,
          manifest.canvas.width * 9 == manifest.canvas.height * 16,
          manifest.canvas.fps >= 24, manifest.canvas.fps <= 120 else {
        try fail("The video canvas must be 16:9 at 960×540 or larger and 24–120 fps")
    }


    let supportsImages = manifest.capabilities?.imageMode ?? false
    let supportsVideo = manifest.capabilities?.videoMode ?? true
    guard supportsImages || supportsVideo else { try fail("A pack must support image or video mode") }

    var clipsByID: [String: Manifest.Clip] = [:]
    for clip in manifest.clips ?? [] {
        guard clipsByID[clip.id] == nil else { try fail("Duplicate clip ID: \(clip.id)") }
        clipsByID[clip.id] = clip
    }

    if supportsVideo {
        let missing = requiredClipIDs.subtracting(clipsByID.keys)
        guard missing.isEmpty else { try fail("Video mode is missing required actions: \(missing.sorted().joined(separator: ", "))") }

        for id in requiredClipIDs.sorted() {
            guard let clip = clipsByID[id] else { continue }
            guard clip.loop == loopingClipIDs.contains(id) else {
                try fail("\(id): video loop flag does not match semantic requirements")
            }
            guard clip.file.hasSuffix(".mov") else {
                try fail("\(id): file must be a relative .mov path inside the Pet Pack")
            }
            let url = try safeAssetURL(clip.file, rootURL: rootURL)
            try await validateVideo(url, canvas: manifest.canvas)
            print("✓ video \(id)  \(clip.file)")
        }
    }

    if supportsImages {
        guard manifest.petPackVersion >= 2 else {
            try fail("Image mode requires petPackVersion 2")
        }
        var resolvedLoopsByID: [String: Bool] = [:]

        if let atlas = manifest.spriteAtlas {
            let validatedAtlas = try validateSpriteAtlas(atlas, rootURL: rootURL)
            for (id, loops) in validatedAtlas.loopsByID {
                resolvedLoopsByID[id] = loops
            }
        }

        if let appearances = manifest.appearances, !appearances.isEmpty {
            var ids = Set<String>()
            guard appearances.allSatisfy({ ids.insert($0.id).inserted }),
                  appearances.filter({ $0.isDefault == true }).count == 1 else {
                try fail("Appearances need unique IDs and exactly one isDefault=true")
            }
            guard appearances.contains(where: { $0.kind == "sprite-atlas" }) else {
                try fail("imageMode=true requires at least one sprite-atlas appearance")
            }
            for appearance in appearances where appearance.kind == "sprite-atlas" {
                let descriptor: Manifest.SpriteAtlas
                if let explicit = appearance.spriteAtlas {
                    descriptor = explicit
                } else if let file = appearance.atlasFile, let base = manifest.spriteAtlas {
                    descriptor = atlas(base, replacingFile: file)
                } else {
                    try fail("Appearance \(appearance.id) lacks spriteAtlas or atlasFile")
                }
                _ = try validateSpriteAtlas(descriptor, rootURL: rootURL)
            }
        }

        guard !resolvedLoopsByID.isEmpty else {
            try fail("Image mode requires a sprite-atlas v2 WebP")
        }
        let missing = requiredClipIDs.subtracting(resolvedLoopsByID.keys)
        guard missing.isEmpty else {
            try fail("Image mode is missing required actions: \(missing.sorted().joined(separator: ", "))")
        }
        for id in requiredClipIDs.sorted() {
            guard resolvedLoopsByID[id] == loopingClipIDs.contains(id) else {
                try fail("\(id): image loop flag does not match semantic requirements")
            }
        }
    }

    let modes = [supportsImages ? "image" : nil, supportsVideo ? "video" : nil]
        .compactMap { $0 }
        .joined(separator: "+")
    print("\nPet Pack validated: \(manifest.pet.name) [\(manifest.pet.species)], modes \(modes), \(requiredClipIDs.count) semantic slots.")
}

let argument = CommandLine.arguments.dropFirst().first
    ?? "Sources/Furball2D/Assets"

do {
    try await validate(packURL: URL(fileURLWithPath: argument, isDirectory: true))
} catch {
    FileHandle.standardError.write(Data("Pet Pack validation failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
