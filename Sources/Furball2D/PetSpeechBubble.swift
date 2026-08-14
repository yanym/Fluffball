import AppKit
import QuartzCore

enum PetSpeechBubbleMood {
    case stand
    case sit
    case lie
    case sleep
    case active
}

@MainActor
final class PetSpeechBubble {
    private struct Placement {
        let id: Int
        let frame: NSRect
        let tailEdge: SpeechBubbleView.TailEdge
        let tailPosition: CGFloat
        let overlapArea: CGFloat
        let score: CGFloat
    }

    private let panel: NSPanel
    private let content: SpeechBubbleView
    private var animationGeneration = 0
    private var currentScale: CGFloat = 1
    private var targetFrame: NSRect?
    private var motionTimer: Timer?
    private var motionVelocity = CGVector.zero
    private var lastMotionTime: TimeInterval?
    private var lockedPlacementID: Int?
    private var lockedTailEdge: SpeechBubbleView.TailEdge?
    private var lastPlacementChangeTime: TimeInterval = 0

    var isVisible: Bool { panel.isVisible }

    init() {
        let frame = NSRect(x: 0, y: 0, width: 256, height: 96)
        panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        content = SpeechBubbleView(frame: frame)

        panel.contentView = content
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.alphaValue = 0
    }

    func show(
        message: String,
        avoiding petFrame: NSRect,
        in visibleFrame: NSRect,
        level: NSWindow.Level,
        petScale: CGFloat,
        mood: PetSpeechBubbleMood
    ) {
        animationGeneration += 1
        currentScale = displayScale(for: petScale)
        lockedPlacementID = nil
        lockedTailEdge = nil
        motionVelocity = .zero
        content.configure(message: message, scale: currentScale, mood: mood)
        panel.level = levelAbovePet(level)
        updateTarget(avoiding: petFrame, in: visibleFrame, immediately: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        startMotionLoop()
        content.playEntranceAnimation()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            panel.animator().alphaValue = 1
        }
    }

    func reposition(avoiding petFrame: NSRect, in visibleFrame: NSRect, petScale: CGFloat) {
        let newScale = displayScale(for: petScale)
        if abs(newScale - currentScale) > 0.005 {
            currentScale = newScale
            content.updateScale(newScale)
        }
        updateTarget(avoiding: petFrame, in: visibleFrame, immediately: false)
    }

    func updateAppearance(mood: PetSpeechBubbleMood) {
        guard panel.isVisible else { return }
        content.updateMood(mood)
    }

    func setLevel(_ level: NSWindow.Level) {
        panel.level = levelAbovePet(level)
    }

    func hide(animated: Bool = true) {
        guard panel.isVisible else { return }
        animationGeneration += 1
        let generation = animationGeneration
        stopMotionLoop()
        content.stopAnimations()

        guard animated else {
            panel.alphaValue = 0
            panel.orderOut(nil)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.animationGeneration == generation else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    private func updateTarget(avoiding petFrame: NSRect, in visibleFrame: NSRect, immediately: Bool) {
        let placement = bestPlacement(size: content.preferredSize, petFrame: petFrame, visibleFrame: visibleFrame)
        let edgeChanged = lockedTailEdge != placement.tailEdge
        content.updateTail(edge: placement.tailEdge, position: placement.tailPosition, immediately: immediately || edgeChanged)
        lockedTailEdge = placement.tailEdge
        targetFrame = placement.frame

        if immediately || !panel.isVisible {
            panel.setFrame(placement.frame, display: true)
            motionVelocity = .zero
        }
    }

    private func startMotionLoop() {
        motionTimer?.invalidate()
        motionTimer = nil
        lastMotionTime = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.advanceMotion()
            }
        }
        motionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopMotionLoop() {
        motionTimer?.invalidate()
        motionTimer = nil
        lastMotionTime = nil
        targetFrame = nil
        motionVelocity = .zero
    }

    private func advanceMotion() {
        guard panel.isVisible, let targetFrame else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let deltaTime = min(1.0 / 30.0, max(1.0 / 120.0, now - (lastMotionTime ?? now)))
        lastMotionTime = now

        let current = panel.frame
        let stiffness: CGFloat = 118
        let damping: CGFloat = 21.0
        let accelerationX = (targetFrame.minX - current.minX) * stiffness - motionVelocity.dx * damping
        let accelerationY = (targetFrame.minY - current.minY) * stiffness - motionVelocity.dy * damping
        motionVelocity.dx += accelerationX * deltaTime
        motionVelocity.dy += accelerationY * deltaTime

        var next = current
        next.origin.x += motionVelocity.dx * deltaTime
        next.origin.y += motionVelocity.dy * deltaTime
        let sizeResponse = min(1, deltaTime * 9)
        next.size.width += (targetFrame.width - current.width) * sizeResponse
        next.size.height += (targetFrame.height - current.height) * sizeResponse

        let positionDistance = hypot(targetFrame.minX - next.minX, targetFrame.minY - next.minY)
        let speed = hypot(motionVelocity.dx, motionVelocity.dy)
        if positionDistance < 0.15, speed < 0.6 {
            next.origin = targetFrame.origin
            motionVelocity = .zero
        }
        if abs(targetFrame.width - next.width) < 0.1 { next.size.width = targetFrame.width }
        if abs(targetFrame.height - next.height) < 0.1 { next.size.height = targetFrame.height }
        panel.setFrame(next, display: true)
    }

    private func bestPlacement(size: NSSize, petFrame: NSRect, visibleFrame: NSRect) -> Placement {
        let scale = currentScale
        let gap = 12 * scale
        let screen = visibleFrame.insetBy(dx: 10, dy: 10)
        let safePetFrame = petFrame.insetBy(dx: -8 * scale, dy: -6 * scale)
        let centeredX = petFrame.midX - size.width / 2
        let centeredY = petFrame.midY - size.height / 2

        let candidates: [(Int, NSPoint, SpeechBubbleView.TailEdge, CGFloat)] = [
            (0, NSPoint(x: centeredX, y: petFrame.maxY + gap), .bottom, 0),
            (1, NSPoint(x: petFrame.minX - size.width * 0.12, y: petFrame.maxY + gap), .bottom, 5),
            (2, NSPoint(x: petFrame.maxX - size.width * 0.88, y: petFrame.maxY + gap), .bottom, 5),
            (3, NSPoint(x: petFrame.minX - size.width - gap, y: centeredY), .right, 12),
            (4, NSPoint(x: petFrame.maxX + gap, y: centeredY), .left, 12),
            (5, NSPoint(x: centeredX, y: petFrame.minY - size.height - gap), .top, 24)
        ]

        let placements = candidates.map { id, origin, edge, preferencePenalty in
            let clampedOrigin = NSPoint(
                x: min(screen.maxX - size.width, max(screen.minX, origin.x)),
                y: min(screen.maxY - size.height, max(screen.minY, origin.y))
            )
            let frame = NSRect(origin: clampedOrigin, size: size)
            let overlap = frame.intersection(safePetFrame)
            let overlapArea = overlap.isNull ? 0 : overlap.width * overlap.height
            let clampingDistance = hypot(clampedOrigin.x - origin.x, clampedOrigin.y - origin.y)
            let tailPosition: CGFloat
            switch edge {
            case .top, .bottom:
                tailPosition = min(0.78, max(0.22, (petFrame.midX - frame.minX) / frame.width))
            case .left, .right:
                tailPosition = min(0.76, max(0.24, (petFrame.midY - frame.minY) / frame.height))
            }
            return Placement(
                id: id,
                frame: frame,
                tailEdge: edge,
                tailPosition: tailPosition,
                overlapArea: overlapArea,
                score: overlapArea * 100 + clampingDistance * 0.65 + preferencePenalty
            )
        }

        let best = placements.min(by: { $0.score < $1.score })!
        var chosen = best
        if let lockedPlacementID,
           let previous = placements.first(where: { $0.id == lockedPlacementID }),
           previous.overlapArea < 1,
           previous.score <= best.score + 90 {
            chosen = previous
        }

        if self.lockedPlacementID != chosen.id {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastPlacementChangeTime < 0.85,
               let lockedPlacementID,
               let previous = placements.first(where: { $0.id == lockedPlacementID }),
               previous.overlapArea < 1,
               previous.score <= best.score + 180 {
                chosen = previous
            } else {
                self.lockedPlacementID = chosen.id
                lastPlacementChangeTime = now
            }
        }
        return chosen
    }

    private func displayScale(for petScale: CGFloat) -> CGFloat {
        min(1.20, max(0.85, 0.92 + (petScale - 0.6) * 0.35))
    }

    private func levelAbovePet(_ petLevel: NSWindow.Level) -> NSWindow.Level {
        NSWindow.Level(rawValue: petLevel.rawValue + 1)
    }
}

@MainActor
private final class SpeechBubbleView: NSView {
    enum TailEdge: Equatable {
        case top
        case bottom
        case left
        case right
    }

    private struct Theme {
        let gradientTop: NSColor
        let gradientBottom: NSColor
        let glassBorderColor: NSColor
        let glowColor: NSColor
        let accentColor: NSColor
        let badgeBackground: NSColor
        let badgeTextColor: NSColor
        let textColor: NSColor
        let iconName: String
        let tagTitle: String
    }

    private let tagLabel = NSTextField(labelWithString: "")
    private let tagIcon = NSImageView()
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private var mood: PetSpeechBubbleMood = .stand
    private var displayScale: CGFloat = 1
    private(set) var tailEdge: TailEdge = .bottom
    private var tailPosition: CGFloat = 0.5

    var preferredSize: NSSize {
        let minTextW: CGFloat = 136 * displayScale
        let maxTextW: CGFloat = 230 * displayScale
        let contentW = min(maxTextW, max(minTextW, measuredMessageWidth + 4 * displayScale))
        let messageH = measuredMessageHeight(for: contentW)

        let horizontalPadding = 36 * displayScale
        let topBarHeight = 22 * displayScale
        let verticalSpacing = 7 * displayScale
        let bottomPadding = 32 * displayScale

        let totalW = contentW + horizontalPadding
        let totalH = max(86 * displayScale, topBarHeight + verticalSpacing + messageH + bottomPadding)
        return NSSize(width: totalW, height: totalH)
    }

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        // 标签栏图标
        tagIcon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(tagIcon)

        // 标签栏文字（Mood Tag）
        tagLabel.alignment = .left
        tagLabel.maximumNumberOfLines = 1
        tagLabel.drawsBackground = false
        addSubview(tagLabel)

        // 对话正文
        messageLabel.alignment = .left
        messageLabel.maximumNumberOfLines = 2
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.drawsBackground = false
        addSubview(messageLabel)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(message: String, scale: CGFloat, mood: PetSpeechBubbleMood) {
        messageLabel.stringValue = message
        displayScale = scale
        self.mood = mood
        applyTheme()
        needsLayout = true
        needsDisplay = true
    }

    func updateScale(_ scale: CGFloat) {
        displayScale = scale
        applyTheme()
        needsLayout = true
        needsDisplay = true
    }

    func updateMood(_ mood: PetSpeechBubbleMood) {
        guard self.mood != mood else { return }
        self.mood = mood
        applyTheme()
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.25
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer?.add(transition, forKey: "speech-theme-transition")
        }
        needsDisplay = true
    }

    func updateTail(edge: TailEdge, position: CGFloat, immediately: Bool) {
        if edge != tailEdge || immediately {
            tailEdge = edge
            tailPosition = position
            needsLayout = true
        } else {
            tailPosition += (position - tailPosition) * 0.20
        }
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let body = bodyRect

        let padX = 16 * displayScale
        let padTop = 13 * displayScale

        // 顶部小胶囊区域
        let iconSize = 13 * displayScale
        let tagIconY = body.maxY - padTop - iconSize
        tagIcon.frame = NSRect(
            x: body.minX + padX,
            y: tagIconY,
            width: iconSize,
            height: iconSize
        )

        let tagTextX = tagIcon.frame.maxX + 5 * displayScale
        let tagTextW = max(50, body.width - padX * 2 - iconSize - 8 * displayScale)
        tagLabel.frame = NSRect(
            x: tagTextX,
            y: tagIconY - 1.5 * displayScale,
            width: tagTextW,
            height: 16 * displayScale
        )

        // 下方消息内容
        let msgTop = tagLabel.frame.minY - 5 * displayScale
        let msgW = max(40, body.width - padX * 2)
        let msgH = max(20, msgTop - (body.minY + 11 * displayScale))
        messageLabel.frame = NSRect(
            x: body.minX + padX,
            y: body.minY + 11 * displayScale,
            width: msgW,
            height: msgH
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let theme = currentTheme(for: mood)
        let body = bodyRect
        let cornerRadius = min(body.height * 0.38, 20 * displayScale)

        // 1. 构建整体气泡路径（主体 + G2 水滴顺滑尾巴）
        let path = buildBubblePath(body: body, radius: cornerRadius)

        // 2. 绘制多层柔和环境光晕与阴影（Ambient Colored Glow + Drop Shadow）
        NSGraphicsContext.saveGraphicsState()

        // 外层色彩弥散柔光
        let glowShadow = NSShadow()
        glowShadow.shadowColor = theme.glowColor
        glowShadow.shadowBlurRadius = 18 * displayScale
        glowShadow.shadowOffset = NSSize(width: 0, height: -4 * displayScale)
        glowShadow.set()

        // 填充通透高雅渐变背景
        if let gradient = NSGradient(starting: theme.gradientTop, ending: theme.gradientBottom) {
            gradient.draw(in: path, angle: -90)
        }
        NSGraphicsContext.restoreGraphicsState()

        // 3. 绘制晶莹半透明内发光轮廓（1.0pt 玻璃微边缘）
        NSGraphicsContext.saveGraphicsState()
        theme.glassBorderColor.setStroke()
        path.lineWidth = 1.1 * displayScale
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // 4. 绘制气泡顶部镜面微高光线（Top Sheen），赋予果冻/玻璃通透感
        drawTopSheen(body: body, radius: cornerRadius)

        // 5. 绘制右下角精致小星芒 / 心动微光标
        drawSparkleDecoration(body: body, theme: theme)
    }

    func playEntranceAnimation() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer else { return }
        // 软萌果冻弹性弹出动画（Jelly Spring Animation）
        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [0.82, 1.06, 0.97, 1.015, 1.0]
        pop.keyTimes = [0, 0.42, 0.68, 0.86, 1.0]
        pop.duration = 0.46
        pop.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.9, 0.32, 1.2)
        layer.add(pop, forKey: "speech-pop")

        // 微微悬浮呼吸微动效（Subtle Bobbing）
        let float = CABasicAnimation(keyPath: "transform.translation.y")
        float.fromValue = 0.0
        float.toValue = 2.4 * displayScale
        float.duration = 1.8
        float.autoreverses = true
        float.repeatCount = .infinity
        float.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(float, forKey: "speech-float")
    }

    func stopAnimations() {
        layer?.removeAnimation(forKey: "speech-pop")
        layer?.removeAnimation(forKey: "speech-float")
        layer?.removeAnimation(forKey: "speech-theme-transition")
    }

    private var measuredMessageWidth: CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: messageLabel.font ?? NSFont.systemFont(ofSize: 14)]
        return ceil((messageLabel.stringValue as NSString).size(withAttributes: attributes).width)
    }

    private func measuredMessageHeight(for width: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: messageLabel.font ?? NSFont.systemFont(ofSize: 14)]
        let rect = (messageLabel.stringValue as NSString).boundingRect(
            with: NSSize(width: width, height: 1000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        return ceil(rect.height)
    }

    private var bodyRect: NSRect {
        let tail = 13 * displayScale
        let margin = 11 * displayScale
        var rect = bounds.insetBy(dx: margin, dy: margin)
        switch tailEdge {
        case .top: rect.size.height -= tail
        case .bottom:
            rect.origin.y += tail
            rect.size.height -= tail
        case .left:
            rect.origin.x += tail
            rect.size.width -= tail
        case .right: rect.size.width -= tail
        }
        return rect
    }

    private func buildBubblePath(body: NSRect, radius: CGFloat) -> NSBezierPath {
        let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
        let tailW = 18 * displayScale
        let tailH = 12 * displayScale

        switch tailEdge {
        case .bottom:
            let centerX = min(body.maxX - radius - tailW * 0.5, max(body.minX + radius + tailW * 0.5, body.minX + body.width * tailPosition))
            let tail = NSBezierPath()
            tail.move(to: NSPoint(x: centerX - tailW * 0.5, y: body.minY + 0.5))
            tail.curve(
                to: NSPoint(x: centerX, y: body.minY - tailH),
                controlPoint1: NSPoint(x: centerX - tailW * 0.22, y: body.minY - tailH * 0.25),
                controlPoint2: NSPoint(x: centerX - tailW * 0.08, y: body.minY - tailH * 0.85)
            )
            tail.curve(
                to: NSPoint(x: centerX + tailW * 0.5, y: body.minY + 0.5),
                controlPoint1: NSPoint(x: centerX + tailW * 0.08, y: body.minY - tailH * 0.85),
                controlPoint2: NSPoint(x: centerX + tailW * 0.22, y: body.minY - tailH * 0.25)
            )
            tail.close()
            path.append(tail)

        case .top:
            let centerX = min(body.maxX - radius - tailW * 0.5, max(body.minX + radius + tailW * 0.5, body.minX + body.width * tailPosition))
            let tail = NSBezierPath()
            tail.move(to: NSPoint(x: centerX - tailW * 0.5, y: body.maxY - 0.5))
            tail.curve(
                to: NSPoint(x: centerX, y: body.maxY + tailH),
                controlPoint1: NSPoint(x: centerX - tailW * 0.22, y: body.maxY + tailH * 0.25),
                controlPoint2: NSPoint(x: centerX - tailW * 0.08, y: body.maxY + tailH * 0.85)
            )
            tail.curve(
                to: NSPoint(x: centerX + tailW * 0.5, y: body.maxY - 0.5),
                controlPoint1: NSPoint(x: centerX + tailW * 0.08, y: body.maxY + tailH * 0.85),
                controlPoint2: NSPoint(x: centerX + tailW * 0.22, y: body.maxY + tailH * 0.25)
            )
            tail.close()
            path.append(tail)

        case .left:
            let centerY = min(body.maxY - radius - tailW * 0.5, max(body.minY + radius + tailW * 0.5, body.minY + body.height * tailPosition))
            let tail = NSBezierPath()
            tail.move(to: NSPoint(x: body.minX + 0.5, y: centerY - tailW * 0.5))
            tail.curve(
                to: NSPoint(x: body.minX - tailH, y: centerY),
                controlPoint1: NSPoint(x: body.minX - tailH * 0.25, y: centerY - tailW * 0.22),
                controlPoint2: NSPoint(x: body.minX - tailH * 0.85, y: centerY - tailW * 0.08)
            )
            tail.curve(
                to: NSPoint(x: body.minX + 0.5, y: centerY + tailW * 0.5),
                controlPoint1: NSPoint(x: body.minX - tailH * 0.85, y: centerY + tailW * 0.08),
                controlPoint2: NSPoint(x: body.minX - tailH * 0.25, y: centerY + tailW * 0.22)
            )
            tail.close()
            path.append(tail)

        case .right:
            let centerY = min(body.maxY - radius - tailW * 0.5, max(body.minY + radius + tailW * 0.5, body.minY + body.height * tailPosition))
            let tail = NSBezierPath()
            tail.move(to: NSPoint(x: body.maxX - 0.5, y: centerY - tailW * 0.5))
            tail.curve(
                to: NSPoint(x: body.maxX + tailH, y: centerY),
                controlPoint1: NSPoint(x: body.maxX + tailH * 0.25, y: centerY - tailW * 0.22),
                controlPoint2: NSPoint(x: body.maxX + tailH * 0.85, y: centerY - tailW * 0.08)
            )
            tail.curve(
                to: NSPoint(x: body.maxX - 0.5, y: centerY + tailW * 0.5),
                controlPoint1: NSPoint(x: body.maxX + tailH * 0.85, y: centerY + tailW * 0.08),
                controlPoint2: NSPoint(x: body.maxX + tailH * 0.25, y: centerY + tailW * 0.22)
            )
            tail.close()
            path.append(tail)
        }

        return path
    }

    private func drawTopSheen(body: NSRect, radius: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        let sheenRect = NSRect(
            x: body.minX + 4 * displayScale,
            y: body.maxY - 14 * displayScale,
            width: body.width - 8 * displayScale,
            height: 10 * displayScale
        )
        let sheenPath = NSBezierPath(roundedRect: sheenRect, xRadius: radius * 0.6, yRadius: radius * 0.6)

        let sheenGradient = NSGradient(
            starting: NSColor.white.withAlphaComponent(0.48),
            ending: NSColor.white.withAlphaComponent(0.02)
        )
        sheenGradient?.draw(in: sheenPath, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSparkleDecoration(body: NSRect, theme: Theme) {
        let center = NSPoint(x: body.maxX - 14 * displayScale, y: body.maxY - 13 * displayScale)
        let radius = 3.8 * displayScale
        let sparkle = NSBezierPath()
        sparkle.move(to: NSPoint(x: center.x, y: center.y + radius))
        sparkle.curve(
            to: NSPoint(x: center.x + radius, y: center.y),
            controlPoint1: NSPoint(x: center.x + radius * 0.15, y: center.y + radius * 0.15),
            controlPoint2: NSPoint(x: center.x + radius * 0.15, y: center.y + radius * 0.15)
        )
        sparkle.curve(
            to: NSPoint(x: center.x, y: center.y - radius),
            controlPoint1: NSPoint(x: center.x + radius * 0.15, y: center.y - radius * 0.15),
            controlPoint2: NSPoint(x: center.x + radius * 0.15, y: center.y - radius * 0.15)
        )
        sparkle.curve(
            to: NSPoint(x: center.x - radius, y: center.y),
            controlPoint1: NSPoint(x: center.x - radius * 0.15, y: center.y - radius * 0.15),
            controlPoint2: NSPoint(x: center.x - radius * 0.15, y: center.y - radius * 0.15)
        )
        sparkle.curve(
            to: NSPoint(x: center.x, y: center.y + radius),
            controlPoint1: NSPoint(x: center.x - radius * 0.15, y: center.y + radius * 0.15),
            controlPoint2: NSPoint(x: center.x - radius * 0.15, y: center.y + radius * 0.15)
        )
        sparkle.close()
        theme.accentColor.withAlphaComponent(0.70).setFill()
        sparkle.fill()

        let dot = NSBezierPath(ovalIn: NSRect(
            x: center.x - 7 * displayScale,
            y: center.y + 4 * displayScale,
            width: 2.2 * displayScale,
            height: 2.2 * displayScale
        ))
        theme.accentColor.withAlphaComponent(0.40).setFill()
        dot.fill()
    }

    private func applyTheme() {
        let theme = currentTheme(for: mood)

        // 1. 设置 Tag 标题与图标
        tagLabel.stringValue = theme.tagTitle
        let tagFontSize = 10.8 * displayScale
        let tagBaseFont = NSFont.systemFont(ofSize: tagFontSize, weight: .bold)
        tagLabel.font = tagBaseFont.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: tagFontSize) } ?? tagBaseFont
        tagLabel.textColor = theme.badgeTextColor

        let config = NSImage.SymbolConfiguration(pointSize: 11 * displayScale, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [theme.accentColor]))
        tagIcon.image = NSImage(systemSymbolName: theme.iconName, accessibilityDescription: nil)?.withSymbolConfiguration(config)

        // 2. 设置对话文字排版（现代高清晰圆体）
        let messageFontSize = 13.8 * displayScale
        let messageBaseFont = NSFont.systemFont(ofSize: messageFontSize, weight: .medium)
        let roundedFont = messageBaseFont.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: messageFontSize) } ?? messageBaseFont
        messageLabel.font = roundedFont
        messageLabel.textColor = theme.textColor
    }

    private func currentTheme(for mood: PetSpeechBubbleMood) -> Theme {
        let tagTitle = AppLanguage.stored.moodTitle(for: mood)
        switch mood {
        case .stand:
            return Theme(
                gradientTop: NSColor(calibratedRed: 0.99, green: 0.99, blue: 0.99, alpha: 0.96),
                gradientBottom: NSColor(calibratedRed: 1.00, green: 0.95, blue: 0.92, alpha: 0.96),
                glassBorderColor: NSColor(calibratedRed: 1.00, green: 0.82, blue: 0.76, alpha: 0.75),
                glowColor: NSColor(calibratedRed: 1.00, green: 0.55, blue: 0.38, alpha: 0.16),
                accentColor: NSColor(calibratedRed: 0.98, green: 0.44, blue: 0.30, alpha: 1),
                badgeBackground: NSColor(calibratedRed: 1.00, green: 0.92, blue: 0.88, alpha: 0.85),
                badgeTextColor: NSColor(calibratedRed: 0.82, green: 0.32, blue: 0.22, alpha: 1),
                textColor: NSColor(calibratedRed: 0.18, green: 0.14, blue: 0.13, alpha: 1),
                iconName: "pawprint.fill",
                tagTitle: tagTitle
            )
        case .sit:
            return Theme(
                gradientTop: NSColor(calibratedRed: 0.99, green: 0.99, blue: 0.99, alpha: 0.96),
                gradientBottom: NSColor(calibratedRed: 1.00, green: 0.94, blue: 0.97, alpha: 0.96),
                glassBorderColor: NSColor(calibratedRed: 0.98, green: 0.78, blue: 0.89, alpha: 0.75),
                glowColor: NSColor(calibratedRed: 0.96, green: 0.42, blue: 0.68, alpha: 0.16),
                accentColor: NSColor(calibratedRed: 0.94, green: 0.32, blue: 0.58, alpha: 1),
                badgeBackground: NSColor(calibratedRed: 0.99, green: 0.90, blue: 0.95, alpha: 0.85),
                badgeTextColor: NSColor(calibratedRed: 0.78, green: 0.22, blue: 0.48, alpha: 1),
                textColor: NSColor(calibratedRed: 0.19, green: 0.13, blue: 0.17, alpha: 1),
                iconName: "heart.fill",
                tagTitle: tagTitle
            )
        case .lie:
            return Theme(
                gradientTop: NSColor(calibratedRed: 0.99, green: 0.99, blue: 0.99, alpha: 0.96),
                gradientBottom: NSColor(calibratedRed: 0.93, green: 0.98, blue: 0.96, alpha: 0.96),
                glassBorderColor: NSColor(calibratedRed: 0.75, green: 0.92, blue: 0.86, alpha: 0.75),
                glowColor: NSColor(calibratedRed: 0.20, green: 0.68, blue: 0.54, alpha: 0.16),
                accentColor: NSColor(calibratedRed: 0.15, green: 0.62, blue: 0.48, alpha: 1),
                badgeBackground: NSColor(calibratedRed: 0.88, green: 0.96, blue: 0.93, alpha: 0.85),
                badgeTextColor: NSColor(calibratedRed: 0.12, green: 0.48, blue: 0.36, alpha: 1),
                textColor: NSColor(calibratedRed: 0.12, green: 0.18, blue: 0.16, alpha: 1),
                iconName: "leaf.fill",
                tagTitle: tagTitle
            )
        case .sleep:
            return Theme(
                gradientTop: NSColor(calibratedRed: 0.99, green: 0.99, blue: 1.00, alpha: 0.96),
                gradientBottom: NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.99, alpha: 0.96),
                glassBorderColor: NSColor(calibratedRed: 0.78, green: 0.82, blue: 0.96, alpha: 0.75),
                glowColor: NSColor(calibratedRed: 0.42, green: 0.48, blue: 0.88, alpha: 0.16),
                accentColor: NSColor(calibratedRed: 0.48, green: 0.46, blue: 0.88, alpha: 1),
                badgeBackground: NSColor(calibratedRed: 0.90, green: 0.91, blue: 0.98, alpha: 0.85),
                badgeTextColor: NSColor(calibratedRed: 0.35, green: 0.34, blue: 0.72, alpha: 1),
                textColor: NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.22, alpha: 1),
                iconName: "moon.stars.fill",
                tagTitle: tagTitle
            )
        case .active:
            return Theme(
                gradientTop: NSColor(calibratedRed: 1.00, green: 1.00, blue: 0.99, alpha: 0.96),
                gradientBottom: NSColor(calibratedRed: 1.00, green: 0.96, blue: 0.88, alpha: 0.96),
                glassBorderColor: NSColor(calibratedRed: 1.00, green: 0.86, blue: 0.65, alpha: 0.75),
                glowColor: NSColor(calibratedRed: 0.98, green: 0.64, blue: 0.15, alpha: 0.18),
                accentColor: NSColor(calibratedRed: 0.94, green: 0.55, blue: 0.08, alpha: 1),
                badgeBackground: NSColor(calibratedRed: 1.00, green: 0.94, blue: 0.82, alpha: 0.85),
                badgeTextColor: NSColor(calibratedRed: 0.76, green: 0.42, blue: 0.05, alpha: 1),
                textColor: NSColor(calibratedRed: 0.20, green: 0.16, blue: 0.10, alpha: 1),
                iconName: "sparkles",
                tagTitle: tagTitle
            )
        }
    }
}
