import AppKit
import QuartzCore

@MainActor
final class DesktopTreat {
    private let panel: NSPanel
    private let view: TreatView

    var isVisible: Bool { panel.isVisible }

    init() {
        let frame = NSRect(x: 0, y: 0, width: 52, height: 52)
        panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        view = TreatView(frame: frame)
        panel.contentView = view
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.alphaValue = 0
    }

    func show(at point: NSPoint, level: NSWindow.Level, in visibleFrame: NSRect) -> NSPoint {
        let size = panel.frame.size
        let origin = NSPoint(
            x: min(visibleFrame.maxX - size.width, max(visibleFrame.minX, point.x - size.width / 2)),
            y: min(visibleFrame.maxY - size.height, max(visibleFrame.minY, point.y - size.height / 2))
        )
        panel.level = NSWindow.Level(rawValue: level.rawValue + 1)
        panel.setFrameOrigin(origin)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        view.startAnimation()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1, 0.3, 1)
            panel.animator().alphaValue = 1
        }
        return NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
    }

    func hide() {
        guard panel.isVisible else { return }
        view.stopAnimation()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 0
        } completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        }
    }
}

private final class TreatView: NSView {
    private let emoji = NSTextField(labelWithString: "🦴")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        emoji.alignment = .center
        emoji.font = .systemFont(ofSize: 27)
        emoji.frame = bounds
        emoji.autoresizingMask = [.width, .height]
        addSubview(emoji)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let circle = bounds.insetBy(dx: 5, dy: 5)
        let path = NSBezierPath(ovalIn: circle)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.set()
        NSColor.controlBackgroundColor.withAlphaComponent(0.92).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.75).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    func startAnimation() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let bounce = CABasicAnimation(keyPath: "transform.translation.y")
        bounce.fromValue = -1
        bounce.toValue = 4
        bounce.duration = 0.55
        bounce.autoreverses = true
        bounce.repeatCount = .infinity
        bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(bounce, forKey: "treat-bounce")
    }

    func stopAnimation() {
        layer?.removeAnimation(forKey: "treat-bounce")
    }
}
