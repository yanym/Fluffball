import AppKit
import ImageIO
import MetalKit
import QuartzCore

enum PetVisualMode {
    case images
    case video
}

struct PetImageTransform {
    var scaleX: Float = 1
    var scaleY: Float = 1
    var translationX: Float = 0
    var translationY: Float = 0
    var rotation: Float = 0
}

struct PetImageRenderSample {
    let textureA: MTLTexture
    let textureB: MTLTexture
    let blendWeight: Float
    let transform: PetImageTransform
    let isMirrored: Bool
}

@MainActor
final class PetImageAnimator {
    private final class Frame {
        let texture: MTLTexture
        let width: Int
        let height: Int
        let alpha: [UInt8]
        let visiblePixelRect: NSRect?

        init(texture: MTLTexture, width: Int, height: Int, alpha: [UInt8], visiblePixelRect: NSRect?) {
            self.texture = texture
            self.width = width
            self.height = height
            self.alpha = alpha
            self.visiblePixelRect = visiblePixelRect
        }

        func alpha(at point: NSPoint, in bounds: NSRect, mirrored: Bool) -> Float {
            guard bounds.width > 0, bounds.height > 0 else { return 0 }
            let rawX = max(0, min(1, point.x / bounds.width))
            let normalizedX = mirrored ? 1 - rawX : rawX
            let normalizedY = max(0, min(1, point.y / bounds.height))
            let centerX = min(width - 1, max(0, Int(normalizedX * CGFloat(width))))
            let centerY = min(height - 1, max(0, Int((1 - normalizedY) * CGFloat(height))))
            var maximum: UInt8 = 0
            for y in max(0, centerY - 2)...min(height - 1, centerY + 2) {
                for x in max(0, centerX - 2)...min(width - 1, centerX + 2) {
                    maximum = max(maximum, alpha[y * width + x])
                }
            }
            return Float(maximum) / 255
        }

        func visibleRect(in bounds: NSRect, mirrored: Bool) -> NSRect? {
            guard var rect = visiblePixelRect else { return nil }
            if mirrored {
                rect.origin.x = CGFloat(width) - rect.maxX
            }
            let scaleX = bounds.width / CGFloat(width)
            let scaleY = bounds.height / CGFloat(height)
            return NSRect(
                x: rect.minX * scaleX,
                y: CGFloat(height) * scaleY - rect.maxY * scaleY,
                width: rect.width * scaleX,
                height: rect.height * scaleY
            )
        }
    }

    private struct Playback {
        let animation: PetImageAnimation
        let leftFrames: [Frame]
        let rightFrames: [Frame]?
        let previousFrame: Frame?
        let previousMirrored: Bool
        let startTime: CFTimeInterval
        let fadeDuration: TimeInterval
    }

    private let device: MTLDevice
    private var frameCache: [PetImageFrameReference: Frame] = [:]
    private var sourceImageCache: [URL: CGImage] = [:]
    private var playback: Playback?
    private var completionTimer: Timer?
    private(set) var isMirrored = false

    init(device: MTLDevice) {
        self.device = device
    }

    deinit {
        completionTimer?.invalidate()
    }

    func play(
        _ animation: PetImageAnimation,
        fadeDuration: TimeInterval,
        completion: (() -> Void)?
    ) throws {
        let now = CACurrentMediaTime()
        let previous = currentFrame(at: now)
        let previousMirrored = effectiveMirroring(for: playback)
        let leftFrames = try animation.frames.map(loadFrame)
        let rightFrames = try animation.rightFrames.map { try $0.map(loadFrame) }

        completionTimer?.invalidate()
        playback = Playback(
            animation: animation,
            leftFrames: leftFrames,
            rightFrames: rightFrames,
            previousFrame: previous,
            previousMirrored: previousMirrored,
            startTime: now,
            fadeDuration: max(0, fadeDuration)
        )

        if !animation.loops, let completion {
            let timer = Timer(timeInterval: animation.duration, repeats: false) { _ in
                MainActor.assumeIsolated { completion() }
            }
            RunLoop.main.add(timer, forMode: .common)
            completionTimer = timer
        }
    }

    func stop() {
        completionTimer?.invalidate()
        completionTimer = nil
        playback = nil
    }

    func setMirrored(_ mirrored: Bool) {
        isMirrored = mirrored
    }

    func sample(at now: CFTimeInterval) -> PetImageRenderSample? {
        guard let playback else { return nil }
        let frames = selectedFrames(for: playback)
        guard !frames.isEmpty else { return nil }
        let elapsed = max(0, now - playback.startTime)
        let current = sequenceSample(frames: frames, playback: playback, elapsed: elapsed)
        let transform = motionTransform(for: playback.animation, elapsed: elapsed)

        if let previous = playback.previousFrame,
           playback.fadeDuration > 0,
           elapsed < playback.fadeDuration {
            let progress = Float(elapsed / playback.fadeDuration)
            return PetImageRenderSample(
                textureA: previous.texture,
                textureB: current.a.texture,
                blendWeight: smootherstep(progress),
                transform: transform,
                isMirrored: effectiveMirroring(for: playback)
            )
        }

        return PetImageRenderSample(
            textureA: current.a.texture,
            textureB: current.b.texture,
            blendWeight: current.weight,
            transform: transform,
            isMirrored: effectiveMirroring(for: playback)
        )
    }

    func alpha(at point: NSPoint, in bounds: NSRect) -> Float? {
        guard let playback, let frame = currentFrame(at: CACurrentMediaTime()) else { return nil }
        return frame.alpha(at: point, in: bounds, mirrored: effectiveMirroring(for: playback))
    }

    func visibleContentRect(in bounds: NSRect) -> NSRect? {
        guard let playback, let frame = currentFrame(at: CACurrentMediaTime()) else { return nil }
        var result = frame.visibleRect(in: bounds, mirrored: effectiveMirroring(for: playback))
        if CACurrentMediaTime() - playback.startTime < playback.fadeDuration,
           let previous = playback.previousFrame,
           let previousRect = previous.visibleRect(in: bounds, mirrored: playback.previousMirrored) {
            result = result?.union(previousRect) ?? previousRect
        }
        return result
    }

    private func selectedFrames(for playback: Playback) -> [Frame] {
        if isMirrored, let rightFrames = playback.rightFrames, !rightFrames.isEmpty {
            return rightFrames
        }
        return playback.leftFrames
    }

    private func effectiveMirroring(for playback: Playback?) -> Bool {
        guard let playback else { return isMirrored }
        return isMirrored && (playback.rightFrames?.isEmpty ?? true)
    }

    private func currentFrame(at now: CFTimeInterval) -> Frame? {
        guard let playback else { return nil }
        let frames = selectedFrames(for: playback)
        guard !frames.isEmpty else { return nil }
        let elapsed = max(0, now - playback.startTime)
        return sequenceSample(frames: frames, playback: playback, elapsed: elapsed).a
    }

    private func sequenceSample(
        frames: [Frame],
        playback: Playback,
        elapsed: TimeInterval
    ) -> (a: Frame, b: Frame, weight: Float) {
        guard frames.count > 1 else { return (frames[0], frames[0], 0) }
        let durations = playback.animation.frameDurations
        guard durations.count == frames.count else { return (frames[0], frames[0], 0) }
        let cycleDuration = playback.animation.cycleDuration
        let timelineTime: TimeInterval
        if playback.animation.loops {
            timelineTime = elapsed.truncatingRemainder(dividingBy: cycleDuration)
        } else {
            timelineTime = min(max(0, cycleDuration - 0.000_001), elapsed)
        }

        var index = frames.count - 1
        var frameStart: TimeInterval = 0
        for candidate in frames.indices {
            let frameEnd = frameStart + durations[candidate]
            if timelineTime < frameEnd {
                index = candidate
                break
            }
            frameStart = frameEnd
        }
        let nextIndex = playback.animation.loops
            ? (index + 1) % frames.count
            : min(frames.count - 1, index + 1)
        let localProgress = Float(
            min(1, max(0, (timelineTime - frameStart) / max(durations[index], 0.000_001)))
        )
        let blendFraction = Float(playback.animation.frameBlendFraction)
        guard blendFraction > 0, nextIndex != index else {
            return (frames[index], frames[index], 0)
        }
        let blendStart = 1 - blendFraction
        let shortFade = max(0, min(1, (localProgress - blendStart) / blendFraction))
        return (frames[index], frames[nextIndex], smootherstep(shortFade))
    }

    private func motionTransform(for animation: PetImageAnimation, elapsed: TimeInterval) -> PetImageTransform {
        let twoPi = Double.pi * 2
        let progress = Float(min(1, elapsed / max(animation.duration, 0.001)))
        switch animation.motion {
        case .none:
            return PetImageTransform()
        case .idle:
            let breath = Float(sin(elapsed * twoPi / 3.8))
            return PetImageTransform(
                scaleX: 1 - breath * 0.0025,
                scaleY: 1 + breath * 0.006,
                translationY: breath * 0.002
            )
        case .sleep:
            let breath = Float(sin(elapsed * twoPi / 4.8))
            return PetImageTransform(
                scaleX: 1 + breath * 0.0035,
                scaleY: 1 - breath * 0.002,
                translationY: breath * 0.001
            )
        case .transition:
            let arc = sin(Float.pi * progress)
            let settle = sin(Float.pi * 2 * progress) * (1 - progress)
            return PetImageTransform(
                scaleX: 1 + arc * 0.022,
                scaleY: 1 - arc * 0.014,
                translationY: arc * 0.028 + settle * 0.008
            )
        case .look:
            let curiosity = Float(sin(elapsed * twoPi / 1.7))
            return PetImageTransform(
                scaleX: 1 - curiosity * 0.002,
                scaleY: 1 + curiosity * 0.004,
                translationY: abs(curiosity) * 0.003
            )
        case .walk:
            return locomotionTransform(elapsed: elapsed, frequency: 2.15, lift: 0.014, squash: 0.010, tilt: 0.006)
        case .slowRun:
            return locomotionTransform(elapsed: elapsed, frequency: 3.15, lift: 0.022, squash: 0.016, tilt: 0.009)
        case .fastRun:
            return locomotionTransform(elapsed: elapsed, frequency: 4.45, lift: 0.031, squash: 0.021, tilt: 0.012)
        case .settle:
            let decay = 1 - progress
            let bounce = sin(Float.pi * 3 * progress) * decay
            return PetImageTransform(
                scaleX: 1 + abs(bounce) * 0.014,
                scaleY: 1 - abs(bounce) * 0.009,
                translationY: max(0, bounce) * 0.016
            )
        }
    }

    private func locomotionTransform(
        elapsed: TimeInterval,
        frequency: Double,
        lift: Float,
        squash: Float,
        tilt: Float
    ) -> PetImageTransform {
        let phase = Float(elapsed * Double.pi * 2 * frequency)
        let stride = sin(phase)
        let step = abs(stride)
        return PetImageTransform(
            scaleX: 1 + step * squash,
            scaleY: 1 - step * squash * 0.62,
            translationY: step * lift,
            rotation: stride * tilt
        )
    }

    private func smootherstep(_ value: Float) -> Float {
        let x = max(0, min(1, value))
        return x * x * x * (x * (x * 6 - 15) + 10)
    }

    private func loadFrame(from reference: PetImageFrameReference) throws -> Frame {
        if let cached = frameCache[reference] { return cached }
        let sourceImage = try sourceImage(at: reference.url)
        let image: CGImage
        if let crop = reference.crop {
            let cropRect = CGRect(x: crop.x, y: crop.y, width: crop.width, height: crop.height)
            guard crop.x >= 0, crop.y >= 0,
                  crop.x + crop.width <= sourceImage.width,
                  crop.y + crop.height <= sourceImage.height,
                  let cropped = sourceImage.cropping(to: cropRect) else {
                throw PetAppError.missingAsset("sprite cell in \(reference.url.lastPathComponent)")
            }
            image = cropped
        } else {
            image = sourceImage
        }

        let width = reference.renderCanvas?.width ?? image.width
        let height = reference.renderCanvas?.height ?? image.height
        let bytesPerRow = width * 4
        var rgba = [UInt8](repeating: 0, count: height * bytesPerRow)
        rgba.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return }
            if reference.renderCanvas != nil {
                let usableHeight = max(1, height - reference.bottomPadding)
                let scale = min(
                    1,
                    min(CGFloat(width) / CGFloat(image.width), CGFloat(usableHeight) / CGFloat(image.height))
                )
                let drawWidth = CGFloat(image.width) * scale
                let drawHeight = CGFloat(image.height) * scale
                context.draw(
                    image,
                    in: CGRect(
                        x: (CGFloat(width) - drawWidth) / 2,
                        y: CGFloat(reference.bottomPadding),
                        width: drawWidth,
                        height: drawHeight
                    )
                )
            } else {
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
        }

        var alpha = [UInt8](repeating: 0, count: width * height)
        var minimumX = width
        var minimumY = height
        var maximumX = -1
        var maximumY = -1
        for y in 0..<height {
            for x in 0..<width {
                let value = rgba[y * bytesPerRow + x * 4 + 3]
                alpha[y * width + x] = value
                if value >= 18 {
                    minimumX = min(minimumX, x)
                    minimumY = min(minimumY, y)
                    maximumX = max(maximumX, x)
                    maximumY = max(maximumY, y)
                }
            }
        }
        let visibleRect: NSRect? = maximumX >= minimumX && maximumY >= minimumY
            ? NSRect(x: minimumX, y: minimumY, width: maximumX - minimumX + 1, height: maximumY - minimumY + 1)
            : nil
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw PetAppError.rendererSetup("Could not create image texture")
        }
        rgba.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: baseAddress,
                bytesPerRow: bytesPerRow
            )
        }
        let frame = Frame(texture: texture, width: width, height: height, alpha: alpha, visiblePixelRect: visibleRect)
        frameCache[reference] = frame
        return frame
    }

    private func sourceImage(at url: URL) throws -> CGImage {
        if let cached = sourceImageCache[url] { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PetAppError.missingAsset(url.lastPathComponent)
        }
        sourceImageCache[url] = image
        return image
    }
}
