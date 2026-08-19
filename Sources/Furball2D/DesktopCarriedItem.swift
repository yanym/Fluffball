import AppKit
import QuartzCore

/// A lightweight, app-owned visual proxy for a desktop item while the pet bites
/// or carries it. The real Finder item is never moved or modified.
@MainActor
final class DesktopCarriedItem {
    private let panel: NSPanel
    private let background = NSVisualEffectView()
    private let iconView = NSImageView()
    private var itemSize: CGFloat = 54

    var isVisible: Bool { panel.isVisible }
    var center: NSPoint { NSPoint(x: panel.frame.midX, y: panel.frame.midY) }

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 66, height: 66),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        background.material = .hudWindow
        background.blendingMode = .withinWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 15
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor.white.withAlphaComponent(0.45).cgColor
        background.addSubview(iconView)
        panel.contentView = background
        iconView.imageScaling = .scaleProportionallyUpOrDown
    }

    func show(url: URL, near point: NSPoint, level: NSWindow.Level, petScale: CGFloat) {
        itemSize = min(68, max(44, 54 * sqrt(petScale)))
        let panelSize = itemSize + 12
        panel.setContentSize(NSSize(width: panelSize, height: panelSize))
        iconView.frame = NSRect(x: 6, y: 6, width: itemSize, height: itemSize)
        iconView.image = NSWorkspace.shared.icon(forFile: url.path)
        panel.level = NSWindow.Level(rawValue: level.rawValue + 2)
        panel.setFrameOrigin(NSPoint(x: point.x - panelSize / 2, y: point.y - panelSize / 2))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        background.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.72, y: 0.72))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.92, 0.25, 1)
            panel.animator().alphaValue = 1
        }
        let settle = CASpringAnimation(keyPath: "transform.scale")
        settle.fromValue = 0.72
        settle.toValue = 1
        settle.mass = 0.7
        settle.stiffness = 190
        settle.damping = 15
        settle.initialVelocity = 0.8
        settle.duration = settle.settlingDuration
        background.layer?.add(settle, forKey: "pickup-pop")
        background.layer?.setAffineTransform(.identity)
    }

    func update(anchor: NSPoint, phase: CGFloat, biting: Bool) {
        let shake = biting ? sin(phase * .pi * 5) * 2.4 : sin(phase * .pi * 4) * 0.9
        let bob = biting ? cos(phase * .pi * 4) * 1.3 : sin(phase * .pi * 3) * 1.5
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: anchor.x - size.width / 2 + shake,
            y: anchor.y - size.height / 2 + bob
        ))
        let rotation = biting ? sin(phase * .pi * 5) * 0.055 : sin(phase * .pi * 3) * 0.022
        let scale = biting ? 0.96 + sin(phase * .pi) * 0.06 : 1
        background.layer?.setAffineTransform(CGAffineTransform(rotationAngle: rotation).scaledBy(x: scale, y: scale))
    }

    func setDown(at point: NSPoint, completion: @escaping () -> Void) {
        let size = panel.frame.size
        let end = NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.30
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.74, 0.25, 1)
            panel.animator().setFrameOrigin(end)
            panel.animator().alphaValue = 0.82
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
                bounce.values = [1, 0.86, 1.05, 1]
                bounce.keyTimes = [0, 0.28, 0.68, 1]
                bounce.duration = 0.24
                self.background.layer?.add(bounce, forKey: "set-down-bounce")
                self.panel.setFrameOrigin(end)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: completion)
            }
        }
    }

    func hide(animated: Bool = true) {
        guard panel.isVisible else { return }
        background.layer?.setAffineTransform(.identity)
        guard animated else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.panel.orderOut(nil) }
        }
    }
}
