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
    private var holdsFirstFrame = false
    private var firstFrameIsReady = false

    init(clip: PetClip, prepareOnly: Bool = false) throws {
        self.clip = clip
        holdsFirstFrame = prepareOnly
        player.actionAtItemEnd = .advance
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false

        let first = try makeItem()
        first.preferredForwardBufferDuration = clip.loops ? 2.5 : 0.8
        player.insert(first, after: nil)
        // Short gait loops can end before the periodic observer gets enough
        // main-run-loop time while the window is moving. Queue the first repeat
        // up front so fast-run playback never has to recover from an empty queue.
        if clip.loops {
            let next = try makeItem()
            next.preferredForwardBufferDuration = 2.5
            player.insert(next, after: first)
        }
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
        // AVPlayerItemVideoOutput is pull-driven. Asking for media-data changes
        // before playback avoids a blank first frame when a menu-bar app is
        // launched in the background and MTKView's display link starts late.
        if let item = player.currentItem,
           let output = videoOutputs[ObjectIdentifier(item)] {
            output.requestNotificationOfMediaDataChange(withAdvanceInterval: 0.03)
        }
        player.playImmediately(atRate: 1)
    }

    func activatePreparedPlayback() {
        holdsFirstFrame = false
        player.playImmediately(atRate: 1)
    }

    func pause() {
        player.pause()
    }

    func updatePixelBuffer(hostTime: CFTimeInterval) -> (buffer: CVPixelBuffer?, isNew: Bool) {
        guard let item = player.currentItem else { return (latestPixelBuffer(), false) }
        let output = videoOutputs[ObjectIdentifier(item)]
        guard let output else { return (latestPixelBuffer(), false) }

        let hostItemTime = output.itemTime(forHostTime: hostTime)
        let playerItemTime = item.currentTime()
        for itemTime in [hostItemTime, playerItemTime] where itemTime.isValid {
            if output.hasNewPixelBuffer(forItemTime: itemTime),
               let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
                lastPixelBuffer = buffer
                if holdsFirstFrame, !firstFrameIsReady {
                    firstFrameIsReady = true
                    player.pause()
                }
                return (buffer, true)
            }
        }
        return (latestPixelBuffer(), false)
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
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]()
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
            next.preferredForwardBufferDuration = 2.5
            player.insert(next, after: player.items().last)
        } catch {
            NSLog("Furball loop prequeue failed: %@", error.localizedDescription)
        }
    }

    private func ensureLoopContinuesAfterEnd() {
        guard !invalidated, clip.loops else { return }
        if player.items().isEmpty {
            do {
                player.insert(try makeItem(), after: nil)
            } catch {
                NSLog("Furball loop recovery failed: %@", error.localizedDescription)
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

struct PetVideoFrameDiagnostics {
    let drawCallbacks: Int
    let freshVideoFrames: Int
    let maximumDrawGap: TimeInterval
    let averageDrawGap: TimeInterval

    var freshFrameRatio: Double {
        guard drawCallbacks > 0 else { return 0 }
        return Double(freshVideoFrames) / Double(drawCallbacks)
    }
}

@MainActor
final class PetRenderer: NSObject, MTKViewDelegate {
    let view: PetMetalView
    private(set) var visualMode: PetVisualMode

    var crossfadeEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "crossfadeEnabled") == nil { return true }
            return UserDefaults.standard.bool(forKey: "crossfadeEnabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "crossfadeEnabled") }
    }

    var isVideoTransitionActive: Bool {
        channelLock.lock()
        defer { channelLock.unlock() }
        return secondaryChannel != nil || crossfadeState != nil
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
        var texturesArePremultiplied: UInt32
        var textureBScale: Float
        var textureBSourceCenterX: Float
        var textureBSourceGroundY: Float
        var textureBTargetCenterX: Float
        var textureBTargetGroundY: Float
    }

    private struct PlayRequest {
        let clip: PetClip
        let fadeDuration: TimeInterval
        let completion: (() -> Void)?
    }

    private let channelLock = NSLock()
    private var primaryChannel: PetVideoChannel?
    private var secondaryChannel: PetVideoChannel?
    private var preparedChannel: PetVideoChannel?
    private var crossfadeState: CrossfadeState?
    private var pendingFadeDuration: TimeInterval = 0.14
    private var currentBlendWeight: Float = 0

    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let samplerState: MTLSamplerState
    private let imageAnimator: PetImageAnimator
    private var textureCache: CVMetalTextureCache?
    private var isMirrored = false
    private var lastPlayRequest: PlayRequest?
    private var lastDrawCallbackTime: CFTimeInterval = 0
    private var diagnosticsEnabled = false
    private var diagnosticDrawCallbacks = 0
    private var diagnosticFreshVideoFrames = 0
    private var diagnosticGapTotal: TimeInterval = 0
    private var diagnosticMaximumGap: TimeInterval = 0
    private var diagnosticLastDrawTime: CFTimeInterval?

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
        uint texturesArePremultiplied;
        float textureBScale;
        float textureBSourceCenterX;
        float textureBSourceGroundY;
        float textureBTargetCenterX;
        float textureBTargetGroundY;
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
        float scaleB = max(0.001f, uniforms.textureBScale);
        float2 sourceUVB = float2(
            uniforms.textureBSourceCenterX + (in.uv.x - uniforms.textureBTargetCenterX) / scaleB,
            uniforms.textureBSourceGroundY + (in.uv.y - uniforms.textureBTargetGroundY) / scaleB
        );
        bool sourceBIsValid = all(sourceUVB >= float2(0.0)) && all(sourceUVB <= float2(1.0));
        float4 colorB = uniforms.hasTextureB != 0 && sourceBIsValid
            ? textureB.sample(videoSampler, sourceUVB)
            : float4(0.0);

        // HEVC Alpha is delivered as straight RGBA. Convert each lane to
        // premultiplied alpha before interpolation; mixing straight RGBA first
        // creates dark fringes and color cross-terms when silhouettes differ.
        if (uniforms.texturesArePremultiplied == 0) {
            colorA.rgb *= colorA.a;
            colorB.rgb *= colorB.a;
        }
        float weight = clamp(uniforms.blendWeight, 0.0f, 1.0f);
        return mix(colorA, colorB, weight);
    }
    """

    init(frame: NSRect, visualMode: PetVisualMode = .video) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw PetAppError.metalUnavailable
        }

        self.visualMode = visualMode
        imageAnimator = PetImageAnimator(device: device)
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
        let displayFPS = NSScreen.main?.maximumFramesPerSecond ?? 60
        view.preferredFramesPerSecond = min(120, max(60, displayFPS))
        view.layer?.isOpaque = false
        view.wantsLayer = true
        if let metalLayer = view.layer as? CAMetalLayer {
            metalLayer.maximumDrawableCount = 3
            metalLayer.allowsNextDrawableTimeout = false
        }
    }

    deinit {
        channelLock.lock()
        let channels = [primaryChannel, secondaryChannel, preparedChannel].compactMap { $0 }
        primaryChannel = nil
        secondaryChannel = nil
        preparedChannel = nil
        channelLock.unlock()
        channels.forEach { $0.invalidate() }
    }

    /// `completion` is strictly the clip-end callback. It is intentionally not
    /// tied to the fade completion, otherwise a 3–6 second transition clip would
    /// be truncated after the first 0.14 seconds.
    func play(_ clip: PetClip, fadeDuration: TimeInterval = 0.14, completion: (() -> Void)? = nil) throws {
        lastPlayRequest = PlayRequest(clip: clip, fadeDuration: fadeDuration, completion: completion)
        switch visualMode {
        case .video:
            try playVideo(clip, fadeDuration: fadeDuration, completion: completion)
        case .images:
            try playImages(clip, fadeDuration: fadeDuration, completion: completion)
        }
    }

    /// Decode and hold the first frame of an upcoming video clip. Locomotion
    /// uses this while the start clip is still playing so the start→loop handoff
    /// never waits on a cold HEVC-with-alpha decoder.
    func prepareVideo(_ clip: PetClip) throws {
        guard visualMode == .video else { return }
        channelLock.lock()
        if preparedChannel?.clip.id == clip.id {
            channelLock.unlock()
            return
        }
        let discarded = preparedChannel
        preparedChannel = nil
        channelLock.unlock()
        discarded?.invalidate()

        let channel = try PetVideoChannel(clip: clip, prepareOnly: true)
        channel.start()
        channelLock.lock()
        preparedChannel = channel
        channelLock.unlock()
    }

    func beginVideoFrameDiagnostics() {
        diagnosticsEnabled = true
        diagnosticDrawCallbacks = 0
        diagnosticFreshVideoFrames = 0
        diagnosticGapTotal = 0
        diagnosticMaximumGap = 0
        diagnosticLastDrawTime = nil
    }

    func finishVideoFrameDiagnostics() -> PetVideoFrameDiagnostics {
        diagnosticsEnabled = false
        let measuredGaps = max(0, diagnosticDrawCallbacks - 1)
        return PetVideoFrameDiagnostics(
            drawCallbacks: diagnosticDrawCallbacks,
            freshVideoFrames: diagnosticFreshVideoFrames,
            maximumDrawGap: diagnosticMaximumGap,
            averageDrawGap: measuredGaps > 0 ? diagnosticGapTotal / Double(measuredGaps) : 0
        )
    }

    func playImageAnimation(
        _ animation: PetImageAnimation,
        fadeDuration: TimeInterval = 0.10,
        completion: (() -> Void)? = nil
    ) throws {
        clearVideoChannels()
        visualMode = .images
        try imageAnimator.play(
            animation,
            fadeDuration: crossfadeEnabled ? fadeDuration : 0,
            completion: completion
        )
    }

    func setVisualMode(
        _ mode: PetVisualMode,
        replaying replayClip: PetClip? = nil,
        forceReload: Bool = false
    ) throws {
        if forceReload {
            clearVideoChannels()
            imageAnimator.stop()
            visualMode = mode
            if let replayClip { try play(replayClip, fadeDuration: 0.045) }
            return
        }
        if visualMode == mode {
            if let replayClip {
                try play(replayClip)
            }
            return
        }
        visualMode = mode
        if let replayClip {
            try play(replayClip)
            return
        }
        guard let request = lastPlayRequest else { return }
        try play(request.clip, fadeDuration: request.fadeDuration, completion: request.completion)
    }

    private func playVideo(
        _ clip: PetClip,
        fadeDuration: TimeInterval,
        completion: (() -> Void)?
    ) throws {
        imageAnimator.stop()
        channelLock.lock()
        let prepared = preparedChannel
        preparedChannel = nil
        channelLock.unlock()

        let channel: PetVideoChannel
        if let prepared, prepared.clip.id == clip.id {
            channel = prepared
            channel.activatePreparedPlayback()
        } else {
            prepared?.invalidate()
            channel = try PetVideoChannel(clip: clip)
            channel.start()
        }
        channel.onClipFinished = {
            DispatchQueue.main.async { completion?() }
        }

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

    private func playImages(
        _ clip: PetClip,
        fadeDuration: TimeInterval,
        completion: (() -> Void)?
    ) throws {
        clearVideoChannels()
        try imageAnimator.play(
            clip.imageAnimation,
            fadeDuration: crossfadeEnabled ? fadeDuration : 0,
            completion: completion
        )
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        if diagnosticsEnabled {
            diagnosticDrawCallbacks += 1
            if let previous = diagnosticLastDrawTime {
                let gap = now - previous
                diagnosticGapTotal += gap
                diagnosticMaximumGap = max(diagnosticMaximumGap, gap)
            }
            diagnosticLastDrawTime = now
        }
        lastDrawCallbackTime = now
        if visualMode == .images {
            drawImage(in: view, at: now)
            return
        }

        channelLock.lock()
        let primary = primaryChannel
        let secondary = secondaryChannel
        let prepared = preparedChannel
        var fade = crossfadeState
        let requestedDuration = pendingFadeDuration
        channelLock.unlock()

        // Pull once per display callback until a prepared channel captures and
        // pauses on its first decoded frame. It never enters the render blend.
        _ = prepared?.updatePixelBuffer(hostTime: now)

        let primaryFrame: (buffer: CVPixelBuffer?, isNew: Bool) =
            primary?.updatePixelBuffer(hostTime: now) ?? (buffer: nil, isNew: false)
        let secondaryFrame: (buffer: CVPixelBuffer?, isNew: Bool) =
            secondary?.updatePixelBuffer(hostTime: now) ?? (buffer: nil, isNew: false)
        if diagnosticsEnabled, primaryFrame.isNew || secondaryFrame.isNew {
            diagnosticFreshVideoFrames += 1
        }

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
                // Smootherstep has zero first and second derivatives at both ends.
                // With aligned clip ports this removes the last subtle opacity jolt
                // without extending the overlap and creating double paws or tails.
                blendWeight = linearProgress * linearProgress * linearProgress
                    * (linearProgress * (linearProgress * 6 - 15) + 10)
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
            hasTextureB: bufferB == nil ? 0 : 1,
            texturesArePremultiplied: 0,
            textureBScale: 1,
            textureBSourceCenterX: 0.5,
            textureBSourceGroundY: 1,
            textureBTargetCenterX: 0.5,
            textureBTargetGroundY: 1
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
        if visualMode == .images {
            return imageAnimator.alpha(at: point, in: view.bounds)
        }

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

    /// MTKView normally drives itself from CVDisplayLink. Accessory/menu-bar
    /// apps can briefly have no active display link during login, Space changes,
    /// or a background LaunchServices launch. The controller already ticks for
    /// hit testing, so use that tick as a low-cost rendering watchdog instead of
    /// allowing the pet to remain permanently transparent.
    func ensureDisplayRefresh() {
        let now = CACurrentMediaTime()
        guard now - lastDrawCallbackTime > 0.10 else { return }
        view.draw()
    }

    /// Returns the pet's current non-transparent silhouette in view coordinates.
    /// Sampling both decoder lanes keeps placement stable during a crossfade.
    func visibleContentRect(alphaThreshold: UInt8 = 18) -> NSRect? {
        if visualMode == .images {
            return imageAnimator.visibleContentRect(in: view.bounds)?
                .insetBy(dx: -4, dy: -4)
                .intersection(view.bounds)
        }

        channelLock.lock()
        let primary = primaryChannel
        let secondary = secondaryChannel
        channelLock.unlock()
        var buffers = [primary?.latestPixelBuffer(), secondary?.latestPixelBuffer()].compactMap { $0 }
        if buffers.isEmpty {
            // Startup recovery may run before the first MTKView callback. Pull
            // only in that exceptional empty-cache case. Repeated silhouette
            // queries must never consume AVPlayerItemVideoOutput frames ahead
            // of the Metal display loop; doing so reduced visible motion to
            // roughly 20 fps while the panel was moving.
            let now = CACurrentMediaTime()
            buffers = [
                primary?.updatePixelBuffer(hostTime: now).buffer,
                secondary?.updatePixelBuffer(hostTime: now).buffer
            ].compactMap { $0 }
        }

        let rects = buffers.compactMap { visibleRect(in: $0, alphaThreshold: alphaThreshold) }
        guard var result = rects.first else { return nil }
        for rect in rects.dropFirst() {
            result = result.union(rect)
        }
        return result.insetBy(dx: -4, dy: -4).intersection(view.bounds)
    }

    func setMirrored(_ mirrored: Bool) {
        isMirrored = mirrored
        imageAnimator.setMirrored(mirrored)
    }

    private func drawImage(in view: MTKView, at now: CFTimeInterval) {
        guard let sample = imageAnimator.sample(at: now),
              let renderPass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return }

        var vertices = imageVertices(transform: sample.transform, mirrored: sample.isMirrored)
        var uniforms = FragmentUniforms(
            blendWeight: sample.blendWeight,
            hasTextureA: 1,
            hasTextureB: 1,
            texturesArePremultiplied: 1,
            textureBScale: sample.textureBScale,
            textureBSourceCenterX: sample.textureBSourceCenterX,
            textureBSourceGroundY: sample.textureBSourceGroundY,
            textureBTargetCenterX: sample.textureBTargetCenterX,
            textureBTargetGroundY: sample.textureBTargetGroundY
        )
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(&vertices, length: MemoryLayout<Float>.stride * vertices.count, index: 0)
        encoder.setFragmentTexture(sample.textureA, index: 0)
        encoder.setFragmentTexture(sample.textureB, index: 1)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FragmentUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func imageVertices(transform: PetImageTransform, mirrored: Bool) -> [Float] {
        let leftU: Float = mirrored ? 1 : 0
        let rightU: Float = mirrored ? 0 : 1
        let cosine = cos(transform.rotation)
        let sine = sin(transform.rotation)

        func point(_ x: Float, _ y: Float) -> (Float, Float) {
            let scaledX = x * transform.scaleX
            let scaledYFromBottom = (y + 1) * transform.scaleY
            let rotatedX = scaledX * cosine - scaledYFromBottom * sine
            let rotatedY = scaledX * sine + scaledYFromBottom * cosine - 1
            return (
                rotatedX + transform.translationX,
                rotatedY + transform.translationY
            )
        }

        let bottomLeft = point(-1, -1)
        let bottomRight = point(1, -1)
        let topLeft = point(-1, 1)
        let topRight = point(1, 1)
        return [
            bottomLeft.0, bottomLeft.1, leftU, 1,
            bottomRight.0, bottomRight.1, rightU, 1,
            topLeft.0, topLeft.1, leftU, 0,
            topRight.0, topRight.1, rightU, 0
        ]
    }

    private func clearVideoChannels() {
        channelLock.lock()
        let channels = [primaryChannel, secondaryChannel, preparedChannel].compactMap { $0 }
        primaryChannel = nil
        secondaryChannel = nil
        preparedChannel = nil
        crossfadeState = nil
        currentBlendWeight = 0
        channelLock.unlock()
        channels.forEach { $0.invalidate() }
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
