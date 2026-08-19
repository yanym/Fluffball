import AppKit
import QuartzCore

enum PetSpeechBubbleMood {
    case stand
    case sit
    case lie
    case sleep
    case active
}

enum PetSpeechBubbleStyle: String, CaseIterable {
    case cloud
    case candy
    case storybook
    case starlight

    var title: String {
        switch self {
        case .cloud: "Soft Cloud"
        case .candy: "Candy Pop"
        case .storybook: "Storybook"
        case .starlight: "Starlight"
        }
    }
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
        VisualQACapture.schedule(view: content, name: "speech-bubble")

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

    func setStyle(_ style: PetSpeechBubbleStyle) {
        content.updateStyle(style)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in
            guard let self, self.animationGeneration == generation else { return }
            self.panel.alphaValue = 0
            self.panel.orderOut(nil)
        }
    }

    private func updateTarget(avoiding petFrame: NSRect, in visibleFrame: NSRect, immediately: Bool) {
        let placement = bestPlacement(size: content.preferredSize, petFrame: petFrame, visibleFrame: visibleFrame)
        let edgeChanged = lockedTailEdge != placement.tailEdge
        content.updateTail(edge: placement.tailEdge, position: placement.tailPosition, immediately: immediately || edgeChanged)
        lockedTailEdge = placement.tailEdge
        if !immediately, let existing = targetFrame,
           hypot(existing.minX - placement.frame.minX, existing.minY - placement.frame.minY) < 2.2,
           abs(existing.width - placement.frame.width) < 0.8,
           abs(existing.height - placement.frame.height) < 0.8 {
            return
        }
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
        // Deliberately softer than the pet motion. The bubble should feel
        // attached, but it must not echo every one-frame silhouette change.
        // Critically damped enough to ignore silhouette noise while still
        // following a walking pet without the old 8 Hz staircase motion.
        let stiffness: CGFloat = 84
        let damping: CGFloat = 19
        let accelerationX = (targetFrame.minX - current.minX) * stiffness - motionVelocity.dx * damping
        let accelerationY = (targetFrame.minY - current.minY) * stiffness - motionVelocity.dy * damping
        motionVelocity.dx += accelerationX * deltaTime
        motionVelocity.dy += accelerationY * deltaTime

        var next = current
        next.origin.x += motionVelocity.dx * deltaTime
        next.origin.y += motionVelocity.dy * deltaTime
        let sizeResponse = min(1, deltaTime * 6.5)
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
        let accentColor: NSColor
        let badgeBackground: NSColor
        let textColor: NSColor
        let iconName: String
    }

    private let tagIcon = NSImageView()
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private var mood: PetSpeechBubbleMood = .stand
    private var style: PetSpeechBubbleStyle = .cloud
    private var displayScale: CGFloat = 1
    private(set) var tailEdge: TailEdge = .bottom
    private var tailPosition: CGFloat = 0.5

    var preferredSize: NSSize {
        // Measure against the message label's real usable width. The old sizing
        // measured against a wider virtual area and omitted the outer glow/tail
        // insets, so a line could wrap only after layout and lose its descenders
        // or final line at the panel edge.
        let minMessageWidth: CGFloat = 142 * displayScale
        let maxMessageWidth: CGFloat = 224 * displayScale
        let messageWidth = min(
            maxMessageWidth,
            max(minMessageWidth, measuredMessageWidth + 4 * displayScale)
        )
        let messageHeight = measuredMessageHeight(for: messageWidth)

        let outerMargins = 24 * displayScale
        let tailAllowance = 10 * displayScale
        // The icon, its gap, and the trailing inset consume 54 pt. Keeping this
        // exact reserve makes the layout width equal to the width used for text
        // measurement even when a left/right tail also consumes panel space.
        let messageHorizontalPadding = 54 * displayScale
        let contentVerticalReserve = 26 * displayScale
        let textBreathingRoom = 6 * displayScale

        // Reserve the tail in both axes. This keeps the panel size stable when
        // it moves from above the dog to either side and guarantees that the
        // message frame is never narrower than the width used for measurement.
        let totalW = messageWidth + outerMargins + tailAllowance + messageHorizontalPadding
        let totalH = max(
            82 * displayScale,
            messageHeight + outerMargins + tailAllowance + contentVerticalReserve + textBreathingRoom
        )
        return NSSize(width: totalW, height: totalH)
    }

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        // A single small mood mark is enough; the message remains the hero.
        tagIcon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(tagIcon)

        // Message body
        messageLabel.alignment = .left
        messageLabel.maximumNumberOfLines = 5
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

    func updateStyle(_ style: PetSpeechBubbleStyle) {
        guard self.style != style else { return }
        self.style = style
        applyTheme()
        let transition = CATransition()
        transition.type = .fade
        transition.duration = 0.18
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(transition, forKey: "speech-style-transition")
        needsDisplay = true
    }

    func updateTail(edge: TailEdge, position: CGFloat, immediately: Bool) {
        if edge != tailEdge || immediately {
            tailEdge = edge
            tailPosition = position
            needsLayout = true
        } else {
            tailPosition += (position - tailPosition) * 0.12
        }
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let body = bodyRect

        let padX = 15 * displayScale
        let iconSize = 14 * displayScale
        let tagIconY = body.midY - iconSize / 2
        tagIcon.frame = NSRect(
            x: body.minX + padX,
            y: tagIconY,
            width: iconSize,
            height: iconSize
        )

        let msgX = body.minX + 51 * displayScale
        let msgW = max(40, body.maxX - msgX - 17 * displayScale)
        let measuredHeight = measuredMessageHeight(for: msgW)
        let msgH = min(body.height - 16 * displayScale, max(20, measuredHeight + 3 * displayScale))
        messageLabel.frame = NSRect(
            x: msgX,
            y: body.midY - msgH / 2,
            width: msgW,
            height: msgH
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let theme = currentTheme(for: mood)
        let body = bodyRect
        let cornerRadius: CGFloat = switch style {
        case .cloud, .candy: min(body.height * 0.42, 24 * displayScale)
        case .storybook: min(body.height * 0.25, 15 * displayScale)
        case .starlight: min(body.height * 0.34, 20 * displayScale)
        }

        let path = buildBubblePath(body: body, radius: cornerRadius)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.19)
        shadow.shadowBlurRadius = 18 * displayScale
        shadow.shadowOffset = NSSize(width: 0, height: -5 * displayScale)
        shadow.set()
        let gradient = NSGradient(starting: theme.gradientTop, ending: theme.gradientBottom)
        gradient?.draw(in: path, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        NSColor.white.withAlphaComponent(0.72).setStroke()
        path.lineWidth = 1.25 * displayScale
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()

        let inner = NSBezierPath(roundedRect: body.insetBy(dx: 1.6 * displayScale, dy: 1.6 * displayScale), xRadius: cornerRadius - 1, yRadius: cornerRadius - 1)
        theme.accentColor.withAlphaComponent(0.12).setStroke()
        inner.lineWidth = 0.8 * displayScale
        inner.stroke()

        let badge = NSBezierPath(ovalIn: NSRect(
            x: body.minX + 10 * displayScale,
            y: body.midY - 15 * displayScale,
            width: 30 * displayScale,
            height: 30 * displayScale
        ))
        theme.badgeBackground.setFill()
        badge.fill()
        theme.accentColor.withAlphaComponent(0.22).setStroke()
        badge.lineWidth = 0.8 * displayScale
        badge.stroke()

        let accentPill = NSBezierPath(roundedRect: NSRect(
            x: body.minX + 18 * displayScale,
            y: body.maxY - 5.5 * displayScale,
            width: min(42 * displayScale, body.width * 0.18),
            height: 3 * displayScale
        ), xRadius: 1.5 * displayScale, yRadius: 1.5 * displayScale)
        theme.accentColor.withAlphaComponent(0.82).setFill()
        accentPill.fill()

        drawStyleDetails(in: body, theme: theme)
    }

    func playEntranceAnimation() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer else { return }
        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [0.94, 1.015, 1.0]
        pop.keyTimes = [0, 0.65, 1]
        pop.duration = 0.22
        pop.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(pop, forKey: "speech-pop")
    }

    func stopAnimations() {
        layer?.removeAnimation(forKey: "speech-pop")
        layer?.removeAnimation(forKey: "speech-theme-transition")
        layer?.removeAnimation(forKey: "speech-style-transition")
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
        let tail = 10 * displayScale
        let margin = 13 * displayScale
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
        let tailW = 15 * displayScale
        let tailH = 9 * displayScale

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

    private func applyTheme() {
        let theme = currentTheme(for: mood)

        let config = NSImage.SymbolConfiguration(pointSize: 12 * displayScale, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [theme.accentColor]))
        tagIcon.image = NSImage(systemSymbolName: theme.iconName, accessibilityDescription: nil)?.withSymbolConfiguration(config)

        let messageFontSize = 13.8 * displayScale
        let messageBaseFont = NSFont.systemFont(ofSize: messageFontSize, weight: .semibold)
        let roundedFont = messageBaseFont.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: messageFontSize) } ?? messageBaseFont
        messageLabel.font = roundedFont
        messageLabel.textColor = theme.textColor
    }

    private func currentTheme(for mood: PetSpeechBubbleMood) -> Theme {
        switch style {
        case .candy:
            return Theme(
                gradientTop: NSColor(calibratedRed: 1.00, green: 0.97, blue: 0.99, alpha: 0.99),
                gradientBottom: NSColor(calibratedRed: 1.00, green: 0.84, blue: 0.91, alpha: 0.98),
                accentColor: NSColor(calibratedRed: 0.96, green: 0.25, blue: 0.55, alpha: 1),
                badgeBackground: NSColor(calibratedRed: 1.00, green: 0.91, blue: 0.38, alpha: 0.94),
                textColor: NSColor(calibratedRed: 0.25, green: 0.10, blue: 0.18, alpha: 1),
                iconName: mood == .sleep ? "moon.stars.fill" : "heart.fill"
            )
        case .storybook:
            return Theme(
                gradientTop: NSColor(calibratedRed: 1.00, green: 0.98, blue: 0.90, alpha: 0.99),
                gradientBottom: NSColor(calibratedRed: 0.96, green: 0.88, blue: 0.72, alpha: 0.98),
                accentColor: NSColor(calibratedRed: 0.48, green: 0.28, blue: 0.16, alpha: 1),
                badgeBackground: NSColor(calibratedRed: 0.91, green: 0.73, blue: 0.42, alpha: 0.88),
                textColor: NSColor(calibratedRed: 0.22, green: 0.14, blue: 0.09, alpha: 1),
                iconName: mood == .sleep ? "moon.fill" : "book.closed.fill"
            )
        case .starlight:
            return Theme(
                gradientTop: NSColor(calibratedRed: 0.17, green: 0.18, blue: 0.34, alpha: 0.98),
                gradientBottom: NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.20, alpha: 0.98),
                accentColor: NSColor(calibratedRed: 0.72, green: 0.66, blue: 1.00, alpha: 1),
                badgeBackground: NSColor(calibratedRed: 0.33, green: 0.29, blue: 0.58, alpha: 0.92),
                textColor: NSColor(calibratedRed: 0.97, green: 0.96, blue: 1.00, alpha: 1),
                iconName: mood == .active ? "sparkles" : "moon.stars.fill"
            )
        case .cloud:
            break
        }
        switch mood {
        case .stand:
            return Theme(
                gradientTop: NSColor(calibratedRed: 1.00, green: 1.00, blue: 0.995, alpha: 0.98),
                gradientBottom: NSColor(calibratedRed: 1.00, green: 0.965, blue: 0.94, alpha: 0.97),
                accentColor: NSColor(calibratedRed: 0.96, green: 0.38, blue: 0.25, alpha: 1),
                badgeBackground: NSColor(calibratedRed: 1.00, green: 0.92, blue: 0.87, alpha: 0.94),
                textColor: NSColor(calibratedRed: 0.18, green: 0.14, blue: 0.13, alpha: 1),
                iconName: "pawprint.fill"
            )
        case .sit:
            return Theme(
                gradientTop: NSColor(calibratedRed: 1.00, green: 1.00, blue: 1.00, alpha: 0.98),
                gradientBottom: NSColor(calibratedRed: 1.00, green: 0.95, blue: 0.975, alpha: 0.97),
                accentColor: NSColor(calibratedRed: 0.94, green: 0.32, blue: 0.58, alpha: 1),
                badgeBackground: NSColor(calibratedRed: 0.99, green: 0.90, blue: 0.95, alpha: 0.85),
                textColor: NSColor(calibratedRed: 0.19, green: 0.13, blue: 0.17, alpha: 1),
                iconName: "heart.fill"
            )
        case .lie:
            return Theme(
                gradientTop: NSColor(calibratedRed: 0.995, green: 1.00, blue: 0.995, alpha: 0.98),
                gradientBottom: NSColor(calibratedRed: 0.93, green: 0.98, blue: 0.96, alpha: 0.97),
                accentColor: NSColor(calibratedRed: 0.15, green: 0.62, blue: 0.48, alpha: 1),
                badgeBackground: NSColor(calibratedRed: 0.88, green: 0.96, blue: 0.93, alpha: 0.85),
                textColor: NSColor(calibratedRed: 0.12, green: 0.18, blue: 0.16, alpha: 1),
                iconName: "leaf.fill"
            )
        case .sleep:
            return Theme(
                gradientTop: NSColor(calibratedRed: 0.99, green: 0.99, blue: 1.00, alpha: 0.98),
                gradientBottom: NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.99, alpha: 0.97),
                accentColor: NSColor(calibratedRed: 0.48, green: 0.46, blue: 0.88, alpha: 1),
                badgeBackground: NSColor(calibratedRed: 0.90, green: 0.91, blue: 0.98, alpha: 0.85),
                textColor: NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.22, alpha: 1),
                iconName: "moon.stars.fill"
            )
        case .active:
            return Theme(
                gradientTop: NSColor(calibratedRed: 1.00, green: 1.00, blue: 0.995, alpha: 0.98),
                gradientBottom: NSColor(calibratedRed: 1.00, green: 0.96, blue: 0.88, alpha: 0.97),
                accentColor: NSColor(calibratedRed: 0.94, green: 0.55, blue: 0.08, alpha: 1),
                badgeBackground: NSColor(calibratedRed: 1.00, green: 0.94, blue: 0.82, alpha: 0.85),
                textColor: NSColor(calibratedRed: 0.20, green: 0.16, blue: 0.10, alpha: 1),
                iconName: "sparkles"
            )
        }
    }

    private func drawStyleDetails(in body: NSRect, theme: Theme) {
        switch style {
        case .cloud:
            let shine = NSBezierPath(ovalIn: NSRect(
                x: body.maxX - 31 * displayScale,
                y: body.maxY - 14 * displayScale,
                width: 8 * displayScale,
                height: 3.5 * displayScale
            ))
            NSColor.white.withAlphaComponent(0.62).setFill()
            shine.fill()
        case .candy:
            for (index, alpha) in [0.75, 0.48, 0.28].enumerated() {
                let dot = NSBezierPath(ovalIn: NSRect(
                    x: body.maxX - CGFloat(20 + index * 9) * displayScale,
                    y: body.maxY - 10 * displayScale,
                    width: 4.5 * displayScale,
                    height: 4.5 * displayScale
                ))
                theme.accentColor.withAlphaComponent(alpha).setFill()
                dot.fill()
            }
        case .storybook:
            let stitch = NSBezierPath(roundedRect: body.insetBy(dx: 4 * displayScale, dy: 4 * displayScale), xRadius: 11 * displayScale, yRadius: 11 * displayScale)
            theme.accentColor.withAlphaComponent(0.20).setStroke()
            stitch.lineWidth = 1 * displayScale
            stitch.setLineDash([3 * displayScale, 3 * displayScale], count: 2, phase: 0)
            stitch.stroke()
        case .starlight:
            for point in [
                NSPoint(x: body.maxX - 22 * displayScale, y: body.maxY - 10 * displayScale),
                NSPoint(x: body.maxX - 35 * displayScale, y: body.minY + 11 * displayScale)
            ] {
                let star = NSBezierPath(ovalIn: NSRect(x: point.x, y: point.y, width: 3 * displayScale, height: 3 * displayScale))
                NSColor.white.withAlphaComponent(0.72).setFill()
                star.fill()
            }
        }
    }
}
