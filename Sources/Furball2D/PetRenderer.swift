import AppKit
@preconcurrency import AVFoundation
@preconcurrency import CoreVideo
@preconcurrency import MetalKit
import QuartzCore

/// One independent decoder/player lane. Every channel filters end notifications
/// to its own AVPlayerItems, so two live channels cannot trigger each other.
private final class PetVideoChannel: @unchecked Sendable {
    let id = UUID()
    let clip: PetClip
    let player = AVQueuePlayer()
    var onClipFinished: (() -> Void)?

    private var videoOutputs: [ObjectIdentifier: AVPlayerItemVideoOutput] = [:]
    private var lastPixelBuffer: CVPixelBuffer?
    private var endObserver: NSObjectProtocol?
    private var loopTimeObserver: Any?
    private var invalidated = false

    init(clip: PetClip) throws {
        self.clip = clip
        player.actionAtItemEnd = .advance
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false

        let first = try makeItem()
        player.insert(first, after: nil)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let item = notification.object as? AVPlayerItem else { return }
            let itemID = ObjectIdentifier(item)
            let ownedItem = self.videoOutputs.removeValue(forKey: itemID) != nil
            let isInvalidated = self.invalidated
            guard ownedItem, !isInvalidated else { return }

            if self.clip.loops {
                DispatchQueue.main.async { [weak self] in
                    self?.ensureLoopContinuesAfterEnd()
                }
            } else {
                self.onClipFinished?()
            }
        }

        if clip.loops {
            loopTimeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                queue: .main
            ) { [weak self] time in
                self?.primeNextLoopItem(currentTime: time)
            }
        }
    }

    deinit { invalidate() }

    func start() {
        player.playImmediately(atRate: 1)
    }

    func pause() {
        player.pause()
    }

    func updatePixelBuffer(hostTime: CFTimeInterval) -> (buffer: CVPixelBuffer?, isNew: Bool) {
        guard let item = player.currentItem else { return (latestPixelBuffer(), false) }
        let output = videoOutputs[ObjectIdentifier(item)]
        guard let output else { return (latestPixelBuffer(), false) }

        let itemTime = output.itemTime(forHostTime: hostTime)
        guard output.hasNewPixelBuffer(forItemTime: itemTime),
              let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) else {
            return (latestPixelBuffer(), false)
        }

        lastPixelBuffer = buffer
        return (buffer, true)
    }

    func latestPixelBuffer() -> CVPixelBuffer? {
        lastPixelBuffer
    }

    func invalidate() {
        guard !invalidated else { return }
        invalidated = true
        let observer = endObserver
        let timeObserver = loopTimeObserver
        endObserver = nil
        loopTimeObserver = nil
        videoOutputs.removeAll()
        lastPixelBuffer = nil

        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        player.pause()
        player.removeAllItems()
    }

    private func makeItem() throws -> AVPlayerItem {
        let item = AVPlayerItem(url: try clip.url)
        let attributes: [String: any Sendable] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
        output.suppressesPlayerRendering = true
        item.add(output)
        videoOutputs[ObjectIdentifier(item)] = output
        return item
    }

    private func primeNextLoopItem(currentTime: CMTime) {
        guard !invalidated, clip.loops, player.items().count == 1,
              let currentItem = player.currentItem else { return }
        let duration = currentItem.duration.seconds
        let elapsed = currentTime.seconds
        guard duration.isFinite, elapsed.isFinite, duration - elapsed <= 0.85 else { return }

        do {
            let next = try makeItem()
            player.insert(next, after: player.items().last)
        } catch {
            NSLog("Furball2D loop prequeue failed: %@", error.localizedDescription)
        }
    }

    private func ensureLoopContinuesAfterEnd() {
        guard !invalidated, clip.loops else { return }
        if player.items().isEmpty {
            do {
                player.insert(try makeItem(), after: nil)
            } catch {
                NSLog("Furball2D loop recovery failed: %@", error.localizedDescription)
                return
            }
        }
        if player.rate == 0 { player.playImmediately(atRate: 1) }
    }
}

private final class SubmittedFrameResources: @unchecked Sendable {
    let textureA: CVMetalTexture
    let textureB: CVMetalTexture
    let bufferA: CVPixelBuffer?
    let bufferB: CVPixelBuffer?

    init(textureA: CVMetalTexture, textureB: CVMetalTexture, bufferA: CVPixelBuffer?, bufferB: CVPixelBuffer?) {
        self.textureA = textureA
        self.textureB = textureB
        self.bufferA = bufferA
        self.bufferB = bufferB
    }
}

@MainActor
final class PetRenderer: NSObject, MTKViewDelegate {
    let view: PetMetalView

    var crossfadeEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "crossfadeEnabled") == nil { return true }
            return UserDefaults.standard.bool(forKey: "crossfadeEnabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "crossfadeEnabled") }
    }

    private struct CrossfadeState {
        let secondaryID: UUID
        let startTime: CFTimeInterval
        let duration: TimeInterval
    }

    private struct FragmentUniforms {
        var blendWeight: Float
        var hasTextureA: UInt32
        var hasTextureB: UInt32
    }

    private let channelLock = NSLock()
    private var primaryChannel: PetVideoChannel?
    private var secondaryChannel: PetVideoChannel?
    private var crossfadeState: CrossfadeState?
    private var pendingFadeDuration: TimeInterval = 0.14
    private var currentBlendWeight: Float = 0

    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let samplerState: MTLSamplerState
    private var textureCache: CVMetalTextureCache?
    private var isMirrored = false

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    struct FragmentUniforms {
        float blendWeight;
        uint hasTextureA;
        uint hasTextureB;
    };

    vertex VertexOut petVertex(const device float4 *vertices [[buffer(0)]], uint id [[vertex_id]]) {
        VertexOut out;
        float4 value = vertices[id];
        out.position = float4(value.xy, 0.0, 1.0);
        out.uv = value.zw;
        return out;
    }

    fragment float4 petFragment(VertexOut in [[stage_in]],
                                texture2d<float> textureA [[texture(0)]],
                                texture2d<float> textureB [[texture(1)]],
                                sampler videoSampler [[sampler(0)]],
                                constant FragmentUniforms &uniforms [[buffer(0)]]) {
        float4 colorA = uniforms.hasTextureA != 0 ? textureA.sample(videoSampler, in.uv) : float4(0.0);
        float4 colorB = uniforms.hasTextureB != 0 ? textureB.sample(videoSampler, in.uv) : float4(0.0);

        // HEVC Alpha is delivered as straight RGBA. Convert each lane to
        // premultiplied alpha before interpolation; mixing straight RGBA first
        // creates dark fringes and color cross-terms when silhouettes differ.
        colorA.rgb *= colorA.a;
        colorB.rgb *= colorB.a;
        float weight = clamp(uniforms.blendWeight, 0.0f, 1.0f);
        return mix(colorA, colorB, weight);
    }
    """

    init(frame: NSRect) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw PetAppError.metalUnavailable
        }

        view = PetMetalView(frame: frame, device: device)
        guard let commandQueue = device.makeCommandQueue() else {
            throw PetAppError.rendererSetup(AppLanguage.stored.commandQueueFailure)
        }
        self.commandQueue = commandQueue

        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            guard let vertexFunction = library.makeFunction(name: "petVertex"),
                  let fragmentFunction = library.makeFunction(name: "petFragment") else {
                throw PetAppError.rendererSetup(AppLanguage.stored.shaderFunctionsMissing)
            }

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw PetAppError.rendererSetup(error.localizedDescription)
        }

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .notMipmapped
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let samplerState = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw PetAppError.rendererSetup(AppLanguage.stored.samplerFailure)
        }
        self.samplerState = samplerState

        let cacheResult = CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        guard cacheResult == kCVReturnSuccess else {
            throw PetAppError.rendererSetup(AppLanguage.stored.textureCacheFailure(cacheResult))
        }

        super.init()

        view.delegate = self
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 60
        view.layer?.isOpaque = false
        view.wantsLayer = true
    }

    deinit {
        channelLock.lock()
        let channels = [primaryChannel, secondaryChannel].compactMap { $0 }
        primaryChannel = nil
        secondaryChannel = nil
        channelLock.unlock()
        channels.forEach { $0.invalidate() }
    }

    /// `completion` is strictly the clip-end callback. It is intentionally not
    /// tied to the fade completion, otherwise a 3–6 second transition clip would
    /// be truncated after the first 0.14 seconds.
    func play(_ clip: PetClip, fadeDuration: TimeInterval = 0.14, completion: (() -> Void)? = nil) throws {
        let channel = try PetVideoChannel(clip: clip)
        channel.onClipFinished = {
            DispatchQueue.main.async { completion?() }
        }
        channel.start()

        channelLock.lock()
        if primaryChannel == nil {
            primaryChannel = channel
            currentBlendWeight = 0
            channelLock.unlock()
            return
        }

        let discardedSecondary = secondaryChannel
        secondaryChannel = channel
        crossfadeState = nil
        pendingFadeDuration = crossfadeEnabled ? max(0, fadeDuration) : 0
        currentBlendWeight = 0
        channelLock.unlock()
        discardedSecondary?.invalidate()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        channelLock.lock()
        let primary = primaryChannel
        let secondary = secondaryChannel
        var fade = crossfadeState
        let requestedDuration = pendingFadeDuration
        channelLock.unlock()

        let primaryFrame: (buffer: CVPixelBuffer?, isNew: Bool) =
            primary?.updatePixelBuffer(hostTime: now) ?? (buffer: nil, isNew: false)
        let secondaryFrame: (buffer: CVPixelBuffer?, isNew: Bool) =
            secondary?.updatePixelBuffer(hostTime: now) ?? (buffer: nil, isNew: false)

        var blendWeight: Float = 0
        var fadeIsActive = false
        var oldPrimaryToRelease: PetVideoChannel?

        if let secondary, secondaryFrame.buffer != nil {
            if fade == nil {
                // Hold the outgoing pose once the incoming lane has its first frame.
                // Letting both clips keep moving during the short overlap creates a
                // subtle double-motion wobble even when their boundary poses match.
                primary?.pause()
                let newState = CrossfadeState(
                    secondaryID: secondary.id,
                    startTime: now,
                    duration: requestedDuration
                )
                channelLock.lock()
                if secondaryChannel?.id == secondary.id {
                    crossfadeState = newState
                    fade = newState
                }
                channelLock.unlock()
            }

            if let fade, fade.secondaryID == secondary.id {
                let linearProgress: Float
                if fade.duration <= 0 {
                    linearProgress = 1
                } else {
                    linearProgress = Float(min(1, max(0, (now - fade.startTime) / fade.duration)))
                }
                // Smoothstep avoids visible velocity discontinuities at both ends.
                blendWeight = linearProgress * linearProgress * (3 - 2 * linearProgress)
                fadeIsActive = linearProgress < 1

                if linearProgress >= 1 {
                    channelLock.lock()
                    if secondaryChannel?.id == secondary.id {
                        oldPrimaryToRelease = primaryChannel
                        primaryChannel = secondary
                        secondaryChannel = nil
                        crossfadeState = nil
                        currentBlendWeight = 0
                    }
                    channelLock.unlock()
                } else {
                    channelLock.lock()
                    currentBlendWeight = blendWeight
                    channelLock.unlock()
                }
            }
        }

        let shouldRender = primaryFrame.isNew || secondaryFrame.isNew || fadeIsActive || oldPrimaryToRelease != nil
        guard shouldRender else { return }

        let bufferA = primaryFrame.buffer
        let bufferB = secondaryFrame.buffer
        let fallbackBuffer = bufferA ?? bufferB
        guard let fallbackBuffer,
              let textureCache,
              let renderPass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        guard let textureAResult = makeTexture(from: bufferA ?? fallbackBuffer, cache: textureCache) else { return }
        // Outside the 0.14 s fade there is only one decoder lane. Reuse its
        // texture binding instead of creating a duplicate CVMetalTexture.
        let textureBResult: (cvTexture: CVMetalTexture, texture: MTLTexture)
        if let bufferB {
            guard let secondTexture = makeTexture(from: bufferB, cache: textureCache) else { return }
            textureBResult = secondTexture
        } else {
            textureBResult = textureAResult
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return }

        let leftU: Float = isMirrored ? 1 : 0
        let rightU: Float = isMirrored ? 0 : 1
        var vertices: [Float] = [
            -1, -1, leftU,  1,
             1, -1, rightU, 1,
            -1,  1, leftU,  0,
             1,  1, rightU, 0
        ]
        var uniforms = FragmentUniforms(
            blendWeight: bufferA == nil ? 1 : blendWeight,
            hasTextureA: bufferA == nil ? 0 : 1,
            hasTextureB: bufferB == nil ? 0 : 1
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(&vertices, length: MemoryLayout<Float>.stride * vertices.count, index: 0)
        encoder.setFragmentTexture(textureAResult.texture, index: 0)
        encoder.setFragmentTexture(textureBResult.texture, index: 1)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FragmentUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        let submittedResources = SubmittedFrameResources(
            textureA: textureAResult.cvTexture,
            textureB: textureBResult.cvTexture,
            bufferA: bufferA,
            bufferB: bufferB
        )
        commandBuffer.addCompletedHandler { [submittedResources] _ in
            _ = submittedResources
        }
        commandBuffer.commit()

        if let oldPrimaryToRelease {
            DispatchQueue.main.async { oldPrimaryToRelease.invalidate() }
        }
    }

    /// During a fade the hit area uses a weighted union, preventing the mouse
    /// from falling through between two slightly different silhouettes.
    func alpha(at point: NSPoint) -> Float? {
        channelLock.lock()
        let primaryBuffer = primaryChannel?.latestPixelBuffer()
        let secondaryBuffer = secondaryChannel?.latestPixelBuffer()
        let weight = currentBlendWeight
        channelLock.unlock()

        let alphaA = primaryBuffer.flatMap { sampleAlpha(in: $0, at: point) } ?? 0
        let alphaB = secondaryBuffer.flatMap { sampleAlpha(in: $0, at: point) } ?? 0
        guard primaryBuffer != nil || secondaryBuffer != nil else { return nil }
        return max(alphaA * (1 - weight), alphaB * weight)
    }

    /// Returns the pet's current non-transparent silhouette in view coordinates.
    /// Sampling both decoder lanes keeps placement stable during a crossfade.
    func visibleContentRect(alphaThreshold: UInt8 = 18) -> NSRect? {
        channelLock.lock()
        let buffers = [
            primaryChannel?.latestPixelBuffer(),
            secondaryChannel?.latestPixelBuffer()
        ].compactMap { $0 }
        channelLock.unlock()

        let rects = buffers.compactMap { visibleRect(in: $0, alphaThreshold: alphaThreshold) }
        guard var result = rects.first else { return nil }
        for rect in rects.dropFirst() {
            result = result.union(rect)
        }
        return result.insetBy(dx: -4, dy: -4).intersection(view.bounds)
    }

    func setMirrored(_ mirrored: Bool) {
        isMirrored = mirrored
    }

    private func makeTexture(
        from pixelBuffer: CVPixelBuffer,
        cache: CVMetalTextureCache
    ) -> (cvTexture: CVMetalTexture, texture: MTLTexture)? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            cache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        guard result == kCVReturnSuccess,
              let cvTexture,
              let texture = CVMetalTextureGetTexture(cvTexture) else { return nil }
        return (cvTexture, texture)
    }

    private func sampleAlpha(in buffer: CVPixelBuffer, at point: NSPoint) -> Float? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let rawNormalizedX = max(0, min(1, point.x / max(1, view.bounds.width)))
        let normalizedX = isMirrored ? 1 - rawNormalizedX : rawNormalizedX
        let normalizedY = max(0, min(1, point.y / max(1, view.bounds.height)))
        let centerX = min(width - 1, max(0, Int(normalizedX * CGFloat(width))))
        let centerY = min(height - 1, max(0, Int((1 - normalizedY) * CGFloat(height))))
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var maximum: UInt8 = 0

        for y in max(0, centerY - 2)...min(height - 1, centerY + 2) {
            for x in max(0, centerX - 2)...min(width - 1, centerX + 2) {
                maximum = max(maximum, bytes[y * rowBytes + x * 4 + 3])
            }
        }
        return Float(maximum) / 255
    }

    private func visibleRect(in buffer: CVPixelBuffer, alphaThreshold: UInt8) -> NSRect? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let sampleStep = max(2, min(width, height) / 150)
        var minimumX = width
        var maximumX = -1
        var minimumY = height
        var maximumY = -1

        for y in Swift.stride(from: 0, to: height, by: sampleStep) {
            let row = y * rowBytes
            for x in Swift.stride(from: 0, to: width, by: sampleStep) {
                if bytes[row + x * 4 + 3] >= alphaThreshold {
                    minimumX = min(minimumX, x)
                    maximumX = max(maximumX, x)
                    minimumY = min(minimumY, y)
                    maximumY = max(maximumY, y)
                }
            }
        }

        guard maximumX >= minimumX, maximumY >= minimumY else { return nil }
        minimumX = max(0, minimumX - sampleStep)
        maximumX = min(width - 1, maximumX + sampleStep)
        minimumY = max(0, minimumY - sampleStep)
        maximumY = min(height - 1, maximumY + sampleStep)

        if isMirrored {
            let mirroredMinimumX = width - 1 - maximumX
            maximumX = width - 1 - minimumX
            minimumX = mirroredMinimumX
        }

        let scaleX = view.bounds.width / CGFloat(width)
        let scaleY = view.bounds.height / CGFloat(height)
        return NSRect(
            x: CGFloat(minimumX) * scaleX,
            y: CGFloat(height - 1 - maximumY) * scaleY,
            width: CGFloat(maximumX - minimumX + 1) * scaleX,
            height: CGFloat(maximumY - minimumY + 1) * scaleY
        )
    }
}
