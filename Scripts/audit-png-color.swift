#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO

private struct ColorBucket {
    var red = 0.0
    var green = 0.0
    var blue = 0.0
    var luminance = 0.0
    var count = 0

    mutating func add(red: Double, green: Double, blue: Double) {
        self.red += red
        self.green += green
        self.blue += blue
        luminance += 0.2126 * red + 0.7152 * green + 0.0722 * blue
        count += 1
    }

    var description: String {
        guard count > 0 else { return "none" }
        return String(
            format: "RGB %.1f %.1f %.1f | Y %.1f | n=%d",
            red / Double(count),
            green / Double(count),
            blue / Double(count),
            luminance / Double(count),
            count
        )
    }
}

private func audit(path: String) throws {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let source = CGImageSourceCreateWithURL(url, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw NSError(domain: "FurballColorAudit", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "无法读取 PNG：\(path)"
        ])
    }

    let width = image.width
    let height = image.height
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    pixels.withUnsafeMutableBytes { bytes in
        let context = CGContext(
            data: bytes.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    var visible = ColorBucket()
    var whiteFur = ColorBucket()
    var blackFur = ColorBucket()
    var tanFur = ColorBucket()

    for offset in stride(from: 0, to: pixels.count, by: 4) {
        guard pixels[offset + 3] >= 240 else { continue }
        let red = Double(pixels[offset])
        let green = Double(pixels[offset + 1])
        let blue = Double(pixels[offset + 2])
        let maximum = max(red, max(green, blue))
        let minimum = min(red, min(green, blue))
        let saturation = maximum > 0 ? (maximum - minimum) / maximum : 0

        visible.add(red: red, green: green, blue: blue)
        if maximum >= 155, minimum >= 95, saturation <= 0.34 {
            whiteFur.add(red: red, green: green, blue: blue)
        }
        if maximum >= 18, maximum <= 92, saturation <= 0.48 {
            blackFur.add(red: red, green: green, blue: blue)
        }
        if red >= 65, red > green * 1.12, green > blue * 0.82, red > blue * 1.18 {
            tanFur.add(red: red, green: green, blue: blue)
        }
    }

    print("\n\(URL(fileURLWithPath: path).lastPathComponent)")
    print("  visible  \(visible.description)")
    print("  white    \(whiteFur.description)")
    print("  black    \(blackFur.description)")
    print("  tan      \(tanFur.description)")
}

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("用法：audit-png-color.swift <png> [png ...]\n".utf8))
    exit(2)
}

do {
    for path in CommandLine.arguments.dropFirst() {
        try audit(path: path)
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
