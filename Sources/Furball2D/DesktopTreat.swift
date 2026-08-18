import AppKit
import QuartzCore

@MainActor
final class DesktopTreat {
    private let panel: NSPanel
    private let view: TreatView
    private var animationGeneration = 0

    var isVisible: Bool { panel.isVisible }

    init() {
        let frame = NSRect(x: 0, y: 0, width: 56, height: 48)
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
        animationGeneration += 1
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
        VisualQACapture.schedule(view: view, name: "desktop-treat")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1, 0.3, 1)
            panel.animator().alphaValue = 1
        }
        return NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
    }

    func hide() {
        guard panel.isVisible else { return }
        animationGeneration += 1
        let generation = animationGeneration
        view.stopAnimation()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.animationGeneration == generation else { return }
                self.panel.orderOut(nil)
            }
        }
        // AppKit occasionally skips an animator completion for a nonactivating
        // accessory panel during rapid window-level changes. Keep a guarded
        // fallback so the treat can never remain as an invisible live window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self, self.animationGeneration == generation else { return }
            self.panel.alphaValue = 0
            self.panel.orderOut(nil)
        }
    }
}

private final class TreatView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let transform = NSAffineTransform()
        transform.translateX(by: bounds.midX, yBy: bounds.midY)
        transform.rotate(byDegrees: -9)
        transform.translateX(by: -bounds.midX, yBy: -bounds.midY)
        transform.concat()

        let shadowPath = NSBezierPath(ovalIn: NSRect(x: 9, y: 7, width: 39, height: 11))
        NSColor.black.withAlphaComponent(0.13).setFill()
        shadowPath.fill()

        let bone = NSBezierPath()
        bone.move(to: NSPoint(x: 16, y: 18))
        bone.curve(to: NSPoint(x: 11, y: 20), controlPoint1: NSPoint(x: 14, y: 19), controlPoint2: NSPoint(x: 13, y: 20))
        bone.curve(to: NSPoint(x: 6, y: 25), controlPoint1: NSPoint(x: 7, y: 20), controlPoint2: NSPoint(x: 5, y: 22))
        bone.curve(to: NSPoint(x: 9, y: 31), controlPoint1: NSPoint(x: 6, y: 28), controlPoint2: NSPoint(x: 7, y: 30))
        bone.curve(to: NSPoint(x: 15, y: 31), controlPoint1: NSPoint(x: 11, y: 33), controlPoint2: NSPoint(x: 14, y: 33))
        bone.curve(to: NSPoint(x: 19, y: 28), controlPoint1: NSPoint(x: 17, y: 30), controlPoint2: NSPoint(x: 18, y: 29))
        bone.line(to: NSPoint(x: 37, y: 28))
        bone.curve(to: NSPoint(x: 41, y: 31), controlPoint1: NSPoint(x: 38, y: 29), controlPoint2: NSPoint(x: 39, y: 30))
        bone.curve(to: NSPoint(x: 47, y: 31), controlPoint1: NSPoint(x: 43, y: 33), controlPoint2: NSPoint(x: 46, y: 33))
        bone.curve(to: NSPoint(x: 50, y: 25), controlPoint1: NSPoint(x: 49, y: 30), controlPoint2: NSPoint(x: 50, y: 28))
        bone.curve(to: NSPoint(x: 45, y: 20), controlPoint1: NSPoint(x: 51, y: 22), controlPoint2: NSPoint(x: 49, y: 20))
        bone.curve(to: NSPoint(x: 40, y: 18), controlPoint1: NSPoint(x: 43, y: 20), controlPoint2: NSPoint(x: 42, y: 19))
        bone.curve(to: NSPoint(x: 37, y: 21), controlPoint1: NSPoint(x: 39, y: 18), controlPoint2: NSPoint(x: 38, y: 19))
        bone.line(to: NSPoint(x: 19, y: 21))
        bone.curve(to: NSPoint(x: 16, y: 18), controlPoint1: NSPoint(x: 18, y: 20), controlPoint2: NSPoint(x: 17, y: 19))
        bone.close()

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.set()
        NSGradient(
            colors: [
                NSColor(calibratedRed: 0.98, green: 0.77, blue: 0.36, alpha: 1),
                NSColor(calibratedRed: 0.87, green: 0.50, blue: 0.16, alpha: 1)
            ]
        )?.draw(in: bone, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        NSColor(calibratedRed: 0.49, green: 0.27, blue: 0.09, alpha: 0.92).setStroke()
        bone.lineWidth = 1.35
        bone.stroke()

        NSColor.white.withAlphaComponent(0.38).setStroke()
        let highlight = NSBezierPath()
        highlight.move(to: NSPoint(x: 18, y: 26.5))
        highlight.curve(to: NSPoint(x: 38, y: 26.5), controlPoint1: NSPoint(x: 24, y: 28), controlPoint2: NSPoint(x: 32, y: 28))
        highlight.lineWidth = 1.2
        highlight.lineCapStyle = .round
        highlight.stroke()

        NSColor(calibratedRed: 0.45, green: 0.23, blue: 0.08, alpha: 0.38).setFill()
        for center in [NSPoint(x: 24, y: 23.6), NSPoint(x: 31.5, y: 24.2)] {
            NSBezierPath(ovalIn: NSRect(x: center.x - 1.15, y: center.y - 1.15, width: 2.3, height: 2.3)).fill()
        }
    }

    func startAnimation() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let bounce = CABasicAnimation(keyPath: "transform.translation.y")
        bounce.fromValue = -0.8
        bounce.toValue = 2.8
        bounce.duration = 0.68
        bounce.autoreverses = true
        bounce.repeatCount = .infinity
        bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(bounce, forKey: "treat-bounce")
    }

    func stopAnimation() {
        layer?.removeAnimation(forKey: "treat-bounce")
    }
}
