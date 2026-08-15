#!/usr/bin/env swift

@preconcurrency import AVFoundation
import CoreVideo
import Foundation

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

    let petPackVersion: Int
    let pet: Pet
    let canvas: Canvas
    let clips: [Clip]
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

private func validate(packURL: URL) async throws {
    let rootURL = packURL.standardizedFileURL
    let manifestURL = rootURL.appendingPathComponent("manifest.json")
    guard let data = try? Data(contentsOf: manifestURL) else {
        try fail("找不到 manifest.json：\(manifestURL.path)")
    }
    let manifest = try JSONDecoder().decode(Manifest.self, from: data)

    guard manifest.petPackVersion == 1 else { try fail("当前只支持 petPackVersion 1") }
    guard !manifest.pet.id.isEmpty, !manifest.pet.name.isEmpty, manifest.pet.assetVersion > 0 else {
        try fail("pet.id、pet.name 和 pet.assetVersion 必须有效")
    }
    guard ["dog", "cat", "other"].contains(manifest.pet.species) else {
        try fail("pet.species 必须是 dog、cat 或 other")
    }
    guard manifest.canvas.width == 960, manifest.canvas.height == 540,
          abs(manifest.canvas.fps - 24) < 0.01 else {
        try fail("Pet Pack v1 运行时画布必须为 960×540、24 fps")
    }

    var clipsByID: [String: Manifest.Clip] = [:]
    for clip in manifest.clips {
        guard clipsByID[clip.id] == nil else { try fail("重复动作 ID：\(clip.id)") }
        clipsByID[clip.id] = clip
    }
    let missing = requiredClipIDs.subtracting(clipsByID.keys)
    guard missing.isEmpty else { try fail("缺少标准动作：\(missing.sorted().joined(separator: ", "))") }

    for id in requiredClipIDs.sorted() {
        guard let clip = clipsByID[id] else { continue }
        guard clip.loop == loopingClipIDs.contains(id) else {
            try fail("\(id)：loop 标记不符合标准动作语义")
        }
        guard clip.file.hasSuffix(".mov"), !clip.file.hasPrefix("/") else {
            try fail("\(id)：file 必须是 Pet Pack 内的相对 .mov 路径")
        }
        let url = rootURL.appendingPathComponent(clip.file).standardizedFileURL
        let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard url.path.hasPrefix(rootPrefix), FileManager.default.fileExists(atPath: url.path) else {
            try fail("\(id)：找不到或越界的素材路径 \(clip.file)")
        }
        try await validateVideo(url, canvas: manifest.canvas)
        print("✓ \(id)  \(clip.file)")
    }

    print("\nPet Pack 验证通过：\(manifest.pet.name) [\(manifest.pet.species)]，共 \(requiredClipIDs.count) 个标准动作槽位。")
}

let argument = CommandLine.arguments.dropFirst().first
    ?? "Sources/Furball2D/Assets"

do {
    try await validate(packURL: URL(fileURLWithPath: argument, isDirectory: true))
} catch {
    FileHandle.standardError.write(Data("Pet Pack 验证失败：\(error.localizedDescription)\n".utf8))
    exit(1)
}
