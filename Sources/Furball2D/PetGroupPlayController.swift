import AppKit

/// Runs several independent, image-backed pets without changing the global pet
/// picker. The coordinator owns only transparent app windows; it never touches
/// Finder, the desktop directory, or any user file.
@MainActor
final class PetGroupPlayController {
    struct Snapshot {
        let petIDs: [String]
        let visibleCount: Int
        let movingCount: Int
        let socialInteractionCount: Int
    }
    @MainActor
    private final class Companion {
        let petID: String
        let name: String
        let panel: PetPanel
        let renderer: PetRenderer
        var target: NSPoint
        var preciseOrigin: NSPoint
        var velocity = NSPoint.zero
        var isMoving = false
        var socialHoldUntil: TimeInterval = 0

        init(pet: PetLibraryPet, origin: NSPoint, size: NSSize, level: NSWindow.Level) throws {
            petID = pet.id
            name = pet.name
            preciseOrigin = origin
            target = NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
            renderer = try PetRenderer(frame: NSRect(origin: .zero, size: size), visualMode: .images)
            panel = PetPanel(contentRect: NSRect(origin: origin, size: size))
            panel.level = level
            panel.ignoresMouseEvents = true
            panel.contentView = renderer.view
            try play("stand.idle", fade: 0)
            panel.orderFrontRegardless()
        }

        func play(_ semanticID: String, fade: TimeInterval = 0.10, completion: (() -> Void)? = nil) throws {
            let animation = try PetAssetCatalog.groupImageAnimation(petID: petID, id: semanticID)
            try renderer.playImageAnimation(animation, fadeDuration: fade, completion: completion)
        }

        func setFacing(right: Bool) {
            renderer.setMirrored(right)
        }

        func stop() {
            panel.orderOut(nil)
        }
    }

    private var companions: [Companion] = []
    private var movementTimer: Timer?
    private var socialTimer: Timer?
    private var socialPair: (Int, Int)?
    private var socialStage = 0
    private var socialInteractionCount = 0
    private var lastTick = ProcessInfo.processInfo.systemUptime

    var isRunning: Bool { !companions.isEmpty }
    var hasVisibleCompanions: Bool { companions.contains(where: { $0.panel.isVisible }) }

    func setVisible(_ visible: Bool) {
        for companion in companions {
            if visible { companion.panel.orderFrontRegardless() }
            else { companion.panel.orderOut(nil) }
        }
    }

    func snapshot() -> Snapshot {
        Snapshot(
            petIDs: companions.map(\.petID),
            visibleCount: companions.filter { $0.panel.isVisible && $0.renderer.visibleContentRect() != nil }.count,
            movingCount: companions.filter(\.isMoving).count,
            socialInteractionCount: socialInteractionCount
        )
    }

    func start(petIDs: Set<String>, scale: CGFloat, level: NSWindow.Level) throws {
        stop()
        socialInteractionCount = 0
        guard let screen = NSScreen.main else { return }
        let pets = PetAssetCatalog.availablePets.filter {
            petIDs.contains($0.id) && PetAssetCatalog.imageCapablePetIDs.contains($0.id)
        }
        guard !pets.isEmpty else { return }

        let visible = screen.visibleFrame
        for (index, pet) in pets.enumerated() {
            let displayScale = min(1.0, max(0.56, scale * 0.82))
            let bodyScale = CGFloat(pet.bodySize) / 60.0
            let size = NSSize(
                width: 410 * displayScale * bodyScale,
                height: 231 * displayScale * bodyScale
            )
            let fraction = CGFloat(index + 1) / CGFloat(pets.count + 1)
            let x = visible.minX + fraction * visible.width - size.width / 2
            let y = visible.minY + 18 + CGFloat(index % 2) * min(70, visible.height * 0.10)
            let companion = try Companion(
                pet: pet,
                origin: clampedOrigin(NSPoint(x: x, y: y), size: size, visible: visible),
                size: size,
                level: level
            )
            companions.append(companion)
            chooseRoamTarget(for: companion, visible: visible)
        }
        lastTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        movementTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        scheduleSocialPlay(
            after: ProcessInfo.processInfo.environment["FURBALL_GROUP_PLAY_QA_REPORT"] == nil ? 4.5 : 0.6
        )
    }

    func stop() {
        movementTimer?.invalidate()
        movementTimer = nil
        socialTimer?.invalidate()
        socialTimer = nil
        socialPair = nil
        companions.forEach { $0.stop() }
        companions.removeAll()
    }

    private func tick() {
        guard let screen = NSScreen.main, !companions.isEmpty else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(1.0 / 30.0, max(1.0 / 240.0, now - lastTick))
        lastTick = now
        let visible = screen.visibleFrame

        advanceSocialPlan(now: now, visible: visible)
        for (index, companion) in companions.enumerated() {
            guard now >= companion.socialHoldUntil else { continue }
            var center = NSPoint(
                x: companion.preciseOrigin.x + companion.panel.frame.width / 2,
                y: companion.preciseOrigin.y + companion.panel.frame.height / 2
            )
            var dx = companion.target.x - center.x
            var dy = companion.target.y - center.y
            let distance = hypot(dx, dy)
            if distance < 7 {
                companion.velocity.x *= pow(0.025, dt)
                companion.velocity.y *= pow(0.025, dt)
                if companion.isMoving, hypot(companion.velocity.x, companion.velocity.y) < 9 {
                    companion.isMoving = false
                    try? companion.play("stand.idle", fade: 0.075)
                }
                if socialPair == nil { chooseRoamTarget(for: companion, visible: visible) }
                continue
            }

            dx /= distance
            dy /= distance
            // Gentle separation prevents pets from visually merging while they
            // cross paths; social meetings deliberately stop with a small gap.
            var repelX: CGFloat = 0
            var repelY: CGFloat = 0
            for (otherIndex, other) in companions.enumerated() where otherIndex != index {
                let otherCenter = NSPoint(x: other.panel.frame.midX, y: other.panel.frame.midY)
                let sx = center.x - otherCenter.x
                let sy = center.y - otherCenter.y
                let separation = max(1, hypot(sx, sy))
                if separation < companion.panel.frame.width * 0.58 {
                    let strength = (companion.panel.frame.width * 0.58 - separation) / separation
                    repelX += sx * strength * 1.8
                    repelY += sy * strength * 1.2
                }
            }
            let desiredSpeed = min(118, max(64, distance * 0.48))
            let desiredX = dx * desiredSpeed + repelX
            let desiredY = dy * min(82, desiredSpeed * 0.66) + repelY
            let response = min(1, CGFloat(dt * 4.8))
            companion.velocity.x += (desiredX - companion.velocity.x) * response
            companion.velocity.y += (desiredY - companion.velocity.y) * response

            if !companion.isMoving, hypot(companion.velocity.x, companion.velocity.y) > 14 {
                companion.isMoving = true
                try? companion.play("walk.loop", fade: 0.075)
            }
            companion.setFacing(right: companion.velocity.x > 0)
            companion.preciseOrigin.x += companion.velocity.x * dt
            companion.preciseOrigin.y += companion.velocity.y * dt
            let clamped = clampedOrigin(companion.preciseOrigin, size: companion.panel.frame.size, visible: visible)
            if abs(clamped.x - companion.preciseOrigin.x) > 0.1 {
                companion.velocity.x *= -0.42
                companion.target.x = clamped.x == visible.minX
                    ? visible.midX + visible.width * 0.24
                    : visible.midX - visible.width * 0.24
            }
            if abs(clamped.y - companion.preciseOrigin.y) > 0.1 {
                companion.velocity.y *= -0.42
                companion.target.y = visible.minY + visible.height * 0.22
            }
            companion.preciseOrigin = clamped
            companion.panel.setFrameOrigin(clamped)
            center = NSPoint(x: companion.panel.frame.midX, y: companion.panel.frame.midY)
            _ = center
        }
    }

    private func scheduleSocialPlay(after delay: TimeInterval) {
        socialTimer?.invalidate()
        socialTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.beginSocialPlay() }
        }
    }

    private func beginSocialPlay() {
        guard let screen = NSScreen.main, !companions.isEmpty else { return }
        let visible = screen.visibleFrame
        if companions.count == 1 {
            let companion = companions[0]
            companion.socialHoldUntil = ProcessInfo.processInfo.systemUptime + 1.5
            try? companion.play(["gesture.play-bow", "gesture.head-tilt", "gesture.happy-dance"].randomElement()!, fade: 0.08)
            scheduleSocialPlay(after: Double.random(in: 7.5...11.5))
            return
        }
        let first = Int.random(in: companions.indices)
        var second = Int.random(in: companions.indices)
        while second == first { second = Int.random(in: companions.indices) }
        socialPair = (first, second)
        socialStage = 0
        let isQA = ProcessInfo.processInfo.environment["FURBALL_GROUP_PLAY_QA_REPORT"] != nil
        let meetingX = isQA
            ? (companions[first].panel.frame.midX + companions[second].panel.frame.midX) / 2
            : CGFloat.random(in: (visible.minX + visible.width * 0.28)...(visible.maxX - visible.width * 0.28))
        let meetingY = isQA
            ? (companions[first].panel.frame.midY + companions[second].panel.frame.midY) / 2
            : CGFloat.random(in: (visible.minY + 80)...(visible.minY + min(260, visible.height * 0.34)))
        let gap = isQA ? min(92, companions[first].panel.frame.width * 0.32) : min(150, companions[first].panel.frame.width * 0.48)
        companions[first].target = NSPoint(x: meetingX - gap, y: meetingY)
        companions[second].target = NSPoint(x: meetingX + gap, y: meetingY)
    }

    private func advanceSocialPlan(now: TimeInterval, visible: NSRect) {
        guard let (first, second) = socialPair,
              companions.indices.contains(first), companions.indices.contains(second) else { return }
        let a = companions[first]
        let b = companions[second]
        let aDistance = hypot(a.target.x - a.panel.frame.midX, a.target.y - a.panel.frame.midY)
        let bDistance = hypot(b.target.x - b.panel.frame.midX, b.target.y - b.panel.frame.midY)
        guard aDistance < 16, bDistance < 16, socialStage == 0 else { return }
        socialStage = 1
        socialInteractionCount += 1
        a.velocity = .zero
        b.velocity = .zero
        a.isMoving = false
        b.isMoving = false
        a.setFacing(right: true)
        b.setFacing(right: false)
        a.socialHoldUntil = now + 2.8
        b.socialHoldUntil = now + 2.8
        try? a.play("gesture.play-bow", fade: 0.075)
        try? b.play("gesture.head-tilt", fade: 0.075)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) { [weak self, weak a, weak b] in
            guard let self, let a, let b else { return }
            try? a.play("gesture.happy-dance", fade: 0.08)
            try? b.play("gesture.wave", fade: 0.08)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.45) { [weak self, weak a, weak b] in
                guard let self, let a, let b else { return }
                try? a.play("stand.idle", fade: 0.08)
                try? b.play("stand.idle", fade: 0.08)
                self.socialPair = nil
                self.chooseRoamTarget(for: a, visible: visible)
                self.chooseRoamTarget(for: b, visible: visible)
                self.scheduleSocialPlay(after: Double.random(in: 7.5...11.5))
            }
        }
    }

    private func chooseRoamTarget(for companion: Companion, visible: NSRect) {
        let halfWidth = companion.panel.frame.width / 2
        let halfHeight = companion.panel.frame.height / 2
        companion.target = NSPoint(
            x: CGFloat.random(in: (visible.minX + halfWidth)...(visible.maxX - halfWidth)),
            y: CGFloat.random(in: (visible.minY + halfHeight * 0.55)...(visible.minY + min(visible.height * 0.46, 360)))
        )
    }

    private func clampedOrigin(_ origin: NSPoint, size: NSSize, visible: NSRect) -> NSPoint {
        NSPoint(
            x: min(visible.maxX - size.width, max(visible.minX, origin.x)),
            y: min(visible.maxY - size.height, max(visible.minY, origin.y))
        )
    }
}
