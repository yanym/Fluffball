import AppKit
import QuartzCore

@MainActor
final class DesktopTreat {
    private let panel: NSPanel
    private let view: TreatView
    private var animationGeneration = 0
    private var throwTimer: Timer?

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

    func throwTreat(
        from start: NSPoint,
        to requestedEnd: NSPoint,
        level: NSWindow.Level,
        in visibleFrame: NSRect,
        completion: @escaping (NSPoint) -> Void
    ) {
        animationGeneration += 1
        let generation = animationGeneration
        throwTimer?.invalidate()
        let size = panel.frame.size
        let end = NSPoint(
            x: min(visibleFrame.maxX - size.width / 2, max(visibleFrame.minX + size.width / 2, requestedEnd.x)),
            y: min(visibleFrame.maxY - size.height / 2, max(visibleFrame.minY + size.height / 2, requestedEnd.y))
        )
        panel.level = NSWindow.Level(rawValue: level.rawValue + 1)
        panel.setFrameOrigin(NSPoint(x: start.x - size.width / 2, y: start.y - size.height / 2))
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        view.stopAnimation()
        view.setThrowing(true)
        let startedAt = ProcessInfo.processInfo.systemUptime
        let distance = hypot(end.x - start.x, end.y - start.y)
        let duration = min(0.78, max(0.42, 0.38 + TimeInterval(distance / 1_300)))
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.animationGeneration == generation else {
                    timer.invalidate()
                    return
                }
                let linear = min(1, (ProcessInfo.processInfo.systemUptime - startedAt) / duration)
                let eased = linear * linear * (3 - 2 * linear)
                let arc = sin(Double.pi * linear) * min(92, max(42, distance * 0.16))
                let center = NSPoint(
                    x: start.x + (end.x - start.x) * eased,
                    y: start.y + (end.y - start.y) * eased + arc
                )
                self.panel.setFrameOrigin(NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
                self.view.setThrowProgress(CGFloat(linear))
                if linear >= 1 {
                    timer.invalidate()
                    self.throwTimer = nil
                    self.view.setThrowing(false)
                    self.view.startAnimation()
                    completion(end)
                }
            }
        }
        throwTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func hide() {
        guard panel.isVisible else { return }
        animationGeneration += 1
        throwTimer?.invalidate()
        throwTimer = nil
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
    private lazy var treatImage: NSImage? = Self.loadTreatImage()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let shadowPath = NSBezierPath(ovalIn: NSRect(x: 9, y: 7, width: 39, height: 11))
        NSColor.black.withAlphaComponent(0.13).setFill()
        shadowPath.fill()
        treatImage?.draw(in: NSRect(x: 5, y: 7, width: bounds.width - 10, height: bounds.height - 8),
                         from: .zero, operation: .sourceOver, fraction: 1)
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

    func setThrowing(_ throwing: Bool) {
        if !throwing { layer?.setAffineTransform(.identity) }
    }

    func setThrowProgress(_ progress: CGFloat) {
        let rotation = CGFloat.pi * 4.2 * progress
        let scale = 0.86 + sin(.pi * progress) * 0.24
        layer?.setAffineTransform(CGAffineTransform(rotationAngle: rotation).scaledBy(x: scale, y: scale))
    }

    static func loadTreatImage() -> NSImage? {
        let candidates = [
            Bundle.module.url(forResource: "treat-bone", withExtension: "png", subdirectory: "Assets/UI"),
            Bundle.main.resourceURL?.appendingPathComponent("Assets/UI/treat-bone.png")
        ]
        return candidates.compactMap { $0 }.first(where: { FileManager.default.fileExists(atPath: $0.path) }).flatMap(NSImage.init(contentsOf:))
    }
}

@MainActor
final class TreatPlacementOverlay {
    private var panels: [NSPanel] = []

    var isActive: Bool { !panels.isEmpty }

    func begin(level: NSWindow.Level, onSelect: @escaping (NSPoint) -> Void, onCancel: @escaping () -> Void) {
        cancel()
        let image = TreatView.loadTreatImage()?.resized(to: NSSize(width: 42, height: 42))
        let cursor = image.map { NSCursor(image: $0, hotSpot: NSPoint(x: 21, y: 21)) } ?? .crosshair
        for screen in NSScreen.screens {
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            let view = TreatPlacementView(frame: NSRect(origin: .zero, size: screen.frame.size), cursor: cursor)
            view.onSelect = { [weak self] localPoint in
                let point = NSPoint(x: screen.frame.minX + localPoint.x, y: screen.frame.minY + localPoint.y)
                self?.cancel()
                onSelect(point)
            }
            view.onCancel = { [weak self] in self?.cancel(); onCancel() }
            panel.contentView = view
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = NSWindow.Level(rawValue: level.rawValue + 3)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }

    func cancel() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }
}

private final class TreatPlacementView: NSView {
    let cursor: NSCursor
    var onSelect: ((NSPoint) -> Void)?
    var onCancel: (() -> Void)?

    init(frame: NSRect, cursor: NSCursor) {
        self.cursor = cursor
        super.init(frame: frame)
        addCursorRect(bounds, cursor: cursor)
    }

    required init?(coder: NSCoder) { nil }
    override func resetCursorRects() { addCursorRect(bounds, cursor: cursor) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onSelect?(convert(event.locationInWindow, from: nil)) }
    override func rightMouseDown(with event: NSEvent) { onCancel?() }
}

private extension NSImage {
    func resized(to size: NSSize) -> NSImage {
        let output = NSImage(size: size)
        output.lockFocus()
        draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
        output.unlockFocus()
        return output
    }
}
