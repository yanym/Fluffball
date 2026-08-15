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

    let petPackVersion: Int
    let pet: Pet
    let canvas: Canvas
    let capabilities: Capabilities?
    let imageCanvas: ImageCanvas?
    let imageAnimations: [ImageAnimation]?
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
        try fail("\(url.lastPathComponent)：无法读取 PNG")
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

private func safeAssetURL(_ relativePath: String, rootURL: URL) throws -> URL {
    guard !relativePath.hasPrefix("/") else { try fail("素材路径必须是 Pet Pack 内的相对路径") }
    let url = rootURL.appendingPathComponent(relativePath).standardizedFileURL
    let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
    guard url.path.hasPrefix(rootPrefix), FileManager.default.fileExists(atPath: url.path) else {
        try fail("找不到或越界的素材路径 \(relativePath)")
    }
    return url
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
    guard manifest.canvas.width == 960, manifest.canvas.height == 540,
          abs(manifest.canvas.fps - 24) < 0.01 else {
        try fail("Pet Pack 运行时画布必须为 960×540、24 fps")
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
        guard manifest.petPackVersion >= 2, let imageCanvas = manifest.imageCanvas else {
            try fail("图片模式需要 petPackVersion 2 和 imageCanvas")
        }
        guard imageCanvas.width == 960, imageCanvas.height == 540, !imageCanvas.runtimeKeying else {
            try fail("图片模式必须使用 960×540 透明 PNG，并关闭运行时抠像")
        }
        var imagesByID: [String: Manifest.ImageAnimation] = [:]
        for animation in manifest.imageAnimations ?? [] {
            guard imagesByID[animation.id] == nil else { try fail("重复图片动作 ID：\(animation.id)") }
            imagesByID[animation.id] = animation
        }
        let missing = requiredClipIDs.subtracting(imagesByID.keys)
        guard missing.isEmpty else { try fail("图片模式缺少标准动作：\(missing.sorted().joined(separator: ", "))") }

        var validatedPaths = Set<String>()
        let supportedMotions: Set<String> = [
            "idle", "sleep", "transition", "look", "walk", "slow-run", "fast-run", "settle"
        ]
        for id in requiredClipIDs.sorted() {
            guard let animation = imagesByID[id] else { continue }
            guard animation.loop == loopingClipIDs.contains(id) else {
                try fail("\(id)：图片 loop 标记不符合标准动作语义")
            }
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
            for path in animation.files + (animation.rightFiles ?? []) where validatedPaths.insert(path).inserted {
                guard path.hasSuffix(".png") else { try fail("\(id)：图片必须是 PNG") }
                let url = try safeAssetURL(path, rootURL: rootURL)
                try validateImage(url, width: imageCanvas.width, height: imageCanvas.height)
            }
            print("✓ image \(id)  \(animation.files.count) frame(s)")
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
