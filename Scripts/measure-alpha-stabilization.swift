#!/usr/bin/env swift

import AVFoundation
import CoreVideo
import Foundation

struct Sample {
    let time: Double
    let centerX: Double
    let groundY: Double
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count >= 3 else {
    fail("usage: measure-alpha-stabilization <input.mov> <commands.txt> [--loop]")
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let isLoop = CommandLine.arguments.contains("--loop")
let asset = AVURLAsset(url: inputURL)
guard let track = asset.tracks(withMediaType: .video).first else { fail("No video track: \(inputURL.path)") }

let reader: AVAssetReader
do { reader = try AVAssetReader(asset: asset) } catch { fail("Cannot read \(inputURL.path): \(error)") }
let output = AVAssetReaderTrackOutput(
    track: track,
    outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
)
output.alwaysCopiesSampleData = false
guard reader.canAdd(output) else { fail("Cannot decode BGRA frames") }
reader.add(output)
guard reader.startReading() else { fail("Could not start frame reader") }

var samples: [Sample] = []
var decodedFrames = 0
let samplingStride = 4 // 30 measurements/second for a 120 fps master.

while let buffer = output.copyNextSampleBuffer() {
    defer { decodedFrames += 1 }
    guard decodedFrames % samplingStride == 0,
          let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { continue }
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { continue }
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let pointer = base.assumingMemoryBound(to: UInt8.self)
    var weight = 0.0
    var weightedX = 0.0
    var rowCounts = [Int](repeating: 0, count: height)
    for y in 0..<height {
        let row = pointer.advanced(by: y * bytesPerRow)
        for x in 0..<width {
            let alpha = Int(row[x * 4 + 3])
            guard alpha >= 24 else { continue }
            let normalized = Double(alpha) / 255.0
            weight += normalized
            weightedX += Double(x) * normalized
            if alpha >= 48 { rowCounts[y] += 1 }
        }
    }
    guard weight > 100 else { continue }
    let ground = rowCounts.enumerated().reversed().first(where: { $0.element >= 8 })?.offset ?? (height - 1)
    let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffer))
    samples.append(Sample(time: time, centerX: weightedX / weight, groundY: Double(ground)))
}

guard samples.count >= 3 else { fail("Not enough visible-alpha samples in \(inputURL.path)") }

func neighborhood(_ values: [Double], index: Int, radius: Int, circular: Bool) -> [Double] {
    (-radius...radius).compactMap { offset in
        let candidate = index + offset
        if circular {
            return values[(candidate % values.count + values.count) % values.count]
        }
        guard values.indices.contains(candidate) else { return nil }
        return values[candidate]
    }
}

func medianSmooth(_ values: [Double], radius: Int, circular: Bool) -> [Double] {
    values.indices.map { index in
        let sorted = neighborhood(values, index: index, radius: radius, circular: circular).sorted()
        return sorted[sorted.count / 2]
    }
}

func meanSmooth(_ values: [Double], radius: Int, circular: Bool) -> [Double] {
    values.indices.map { index in
        let window = neighborhood(values, index: index, radius: radius, circular: circular)
        return window.reduce(0, +) / Double(window.count)
    }
}

func rollingMaximum(_ values: [Double], radius: Int, circular: Bool) -> [Double] {
    values.indices.map { index in
        neighborhood(values, index: index, radius: radius, circular: circular).max() ?? values[index]
    }
}

let rawCenters = samples.map(\.centerX)
let rawGrounds = samples.map(\.groundY)
// Reject paw/tail outliers first, then remove only low-frequency camera/generation drift.
let centers = meanSmooth(medianSmooth(rawCenters, radius: 2, circular: isLoop), radius: 4, circular: isLoop)
// Gait frames can briefly lift every paw. A local ground envelope preserves the desktop baseline.
let grounds = meanSmooth(rollingMaximum(rawGrounds, radius: 3, circular: isLoop), radius: 3, circular: isLoop)
let targetCenterX = 640.0
let targetGroundY = 682.0
let padX = 360.0
let padY = 240.0

var commands = ""
for index in samples.indices {
    let dx = max(-220, min(220, targetCenterX - centers[index]))
    let dy = max(-120, min(120, targetGroundY - grounds[index]))
    commands += String(format: "%.6f crop@stabilize x %.3f;\n", samples[index].time, padX - dx)
    commands += String(format: "%.6f crop@stabilize y %.3f;\n", samples[index].time, padY - dy)
}

do {
    try commands.write(to: outputURL, atomically: true, encoding: .utf8)
} catch {
    fail("Cannot write commands: \(error)")
}

let centerRange = (rawCenters.max() ?? 0) - (rawCenters.min() ?? 0)
let groundRange = (rawGrounds.max() ?? 0) - (rawGrounds.min() ?? 0)
print(String(format: "alpha stabilization: %d samples, raw center range %.1f px, raw ground range %.1f px", samples.count, centerRange, groundRange))
