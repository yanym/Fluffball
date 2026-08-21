#!/usr/bin/env swift

import AVFoundation
import CoreImage
import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: export-alpha-preview <input.mov> <output.png>\n".utf8))
    exit(1)
}

let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
var tracks = asset.tracks(withMediaType: .video)
if tracks.isEmpty {
    Thread.sleep(forTimeInterval: 0.15)
    tracks = asset.tracks(withMediaType: .video)
}
guard let track = tracks.first else { exit(2) }
guard let reader = try? AVAssetReader(asset: asset) else { exit(3) }
let output = AVAssetReaderTrackOutput(
    track: track,
    outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
)
reader.add(output)
guard reader.startReading() else { exit(4) }
let target = max(0, CMTimeGetSeconds(asset.duration) * 0.5)
var chosen: CVPixelBuffer?
while let sample = output.copyNextSampleBuffer() {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
    chosen = pixelBuffer
    if CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)) >= target { break }
}
guard let chosen else { exit(5) }
let image = CIImage(cvPixelBuffer: chosen)
let context = CIContext(options: [.useSoftwareRenderer: false])
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
do {
    try context.writePNGRepresentation(
        of: image,
        to: URL(fileURLWithPath: CommandLine.arguments[2]),
        format: .RGBA8,
        colorSpace: colorSpace
    )
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(6)
}
