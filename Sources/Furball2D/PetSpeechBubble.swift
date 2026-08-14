import AppKit

@MainActor
final class PetSpeechBubble {
    private static let bubbleSize = NSSize(width: 232, height: 82)

    private let panel: NSPanel
    private let content: SpeechBubbleView
    private var animationGeneration = 0

    var isVisible: Bool { panel.isVisible }

    init() {
        let frame = NSRect(origin: .zero, size: Self.bubbleSize)
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

    func show(message: String, near petFrame: NSRect, in visibleFrame: NSRect, level: NSWindow.Level) {
        animationGeneration += 1
        content.message = message
        panel.level = levelAbovePet(level)
        reposition(near: petFrame, in: visibleFrame)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func reposition(near petFrame: NSRect, in visibleFrame: NSRect) {
        let preferred = NSPoint(
            x: petFrame.midX - Self.bubbleSize.width / 2,
            y: petFrame.maxY - 7
        )
        let origin = NSPoint(
            x: min(visibleFrame.maxX - Self.bubbleSize.width - 4, max(visibleFrame.minX + 4, preferred.x)),
            y: min(visibleFrame.maxY - Self.bubbleSize.height - 4, max(visibleFrame.minY + 4, preferred.y))
        )
        panel.setFrameOrigin(origin)
    }

    func setLevel(_ level: NSWindow.Level) {
        panel.level = levelAbovePet(level)
    }

    func hide(animated: Bool = true) {
        guard panel.isVisible else { return }
        animationGeneration += 1
        let generation = animationGeneration

        guard animated else {
            panel.alphaValue = 0
            panel.orderOut(nil)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.animationGeneration == generation else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    private func levelAbovePet(_ petLevel: NSWindow.Level) -> NSWindow.Level {
        NSWindow.Level(rawValue: petLevel.rawValue + 1)
    }
}

@MainActor
private final class SpeechBubbleView: NSView {
    private let label = NSTextField(wrappingLabelWithString: "")

    var message: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        label.frame = NSRect(x: 18, y: 25, width: frameRect.width - 36, height: 43)
        label.alignment = .center
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = NSColor(calibratedRed: 0.24, green: 0.18, blue: 0.30, alpha: 1)
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bodyRect = NSRect(x: 5, y: 17, width: bounds.width - 10, height: bounds.height - 22)
        let bubblePath = NSBezierPath(roundedRect: bodyRect, xRadius: 18, yRadius: 18)
        bubblePath.move(to: NSPoint(x: bounds.midX - 13, y: bodyRect.minY + 1))
        bubblePath.line(to: NSPoint(x: bounds.midX, y: 4))
        bubblePath.line(to: NSPoint(x: bounds.midX + 14, y: bodyRect.minY + 1))
        bubblePath.close()

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
        shadow.shadowBlurRadius = 9
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.set()
        NSColor.white.withAlphaComponent(0.96).setFill()
        bubblePath.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor(calibratedRed: 0.86, green: 0.55, blue: 0.84, alpha: 0.95).setStroke()
        bubblePath.lineWidth = 1.6
        bubblePath.stroke()

        let heart = "♥" as NSString
        heart.draw(
            at: NSPoint(x: bodyRect.maxX - 25, y: bodyRect.maxY - 22),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: NSColor(calibratedRed: 0.94, green: 0.36, blue: 0.55, alpha: 1)
            ]
        )
    }
}
