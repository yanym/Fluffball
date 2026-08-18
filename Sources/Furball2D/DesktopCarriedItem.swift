import AppKit
import QuartzCore

/// A lightweight visual proxy for a desktop file while the pet bites or carries
/// it. Finder is updated only once at drop time, so the animation stays smooth
/// and never floods Accessibility/Apple Events with per-frame mutations.
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
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func update(anchor: NSPoint, phase: CGFloat, biting: Bool) {
        let shake = biting ? sin(phase * .pi * 8) * 5 : sin(phase * .pi * 6) * 1.5
        let bob = biting ? cos(phase * .pi * 6) * 2 : sin(phase * .pi * 4) * 2.2
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: anchor.x - size.width / 2 + shake,
            y: anchor.y - size.height / 2 + bob
        ))
        let rotation = biting ? sin(phase * .pi * 8) * 0.10 : sin(phase * .pi * 4) * 0.035
        background.layer?.setAffineTransform(CGAffineTransform(rotationAngle: rotation))
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
