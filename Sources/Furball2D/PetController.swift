import AppKit

@MainActor
final class PetController: NSObject, NSMenuDelegate {
    private static let basePetSize = NSSize(width: 520, height: 292.5)
    private static let minimumScale: CGFloat = 0.6
    private static let maximumScale: CGFloat = 1.4
    private static let minimumVisibleHorizontalRatio: CGFloat = 0.94
    private static let minimumVisibleVerticalRatio: CGFloat = 0.94

    private enum PreferenceKey {
        static let petScale = "petScale"
        static let fullPassThrough = "fullPassThrough"
        static let autoBehavior = "autoBehavior"
        static let followCursor = "followCursor"
        static let freeRoam = "freeRoam"
        static let imageFacing = "imageFacing"
        static let videoAnimations = "videoAnimationsEnabled"
        static let desktopInteractions = "desktopInteractions"
        static let alwaysOnTop = "alwaysOnTop"
        static let speechBubbles = "speechBubblesEnabled"
        static let talkativeness = "petTalkativeness"
        static let groupPlay = "groupPlayEnabled"
        static let groupPetIDs = "groupPlayPetIDs"
    }

    private static var videoAnimationsPreferenceKey: String {
        "\(PreferenceKey.videoAnimations).\(PetAssetCatalog.petID)"
    }

    private enum HorizontalFacing {
        case left
        case right

        var direction: CGFloat { self == .right ? 1 : -1 }
        var isMirrored: Bool { self == .right }
        var profileView: PetFacingView { self == .right ? .rightProfile : .leftProfile }
    }

    private enum LocomotionMode: Equatable {
        case none
        case walk
        case slowRun
        case fastRun

        var pointsPerSecond: CGFloat {
            switch self {
            case .none: 0
            case .walk: 76
            case .slowRun: 154
            case .fastRun: 285
            }
        }

        var clips: PetMotionClipSet? {
            switch self {
            case .none: nil
            case .walk: PetClips.walk
            case .slowRun: PetClips.slowRun
            case .fastRun: PetClips.fastRun
            }
        }

        var startTranslationDelay: TimeInterval {
            switch self {
            case .none: 0
            case .walk: 0.12
            case .slowRun: 0.07
            case .fastRun: 0.10
            }
        }

        var startTranslationRampDuration: TimeInterval {
            switch self {
            case .none: 0
            case .walk: 0.18
            case .slowRun: 0.13
            case .fastRun: 0.10
            }
        }
    }

    private struct MovementBoundaryCollision {
        /// -1 is the left/bottom wall, +1 is the right/top wall, 0 is no hit.
        var horizontalWall: CGFloat = 0
        var verticalWall: CGFloat = 0

        var occurred: Bool { horizontalWall != 0 || verticalWall != 0 }
    }

    private let panel: PetPanel
    private let renderer: PetRenderer
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private let speechBubble = PetSpeechBubble()
    private let desktopTreat = DesktopTreat()
    private let desktopCarriedItem = DesktopCarriedItem()
    private let groupPlayController = PetGroupPlayController()
    private let desktopInteractionService = DesktopInteractionService()
    private var settingsWindowController: UnifiedSettingsWindowController?

    private var posture: PetPosture = .stand
    private var isTransitioning = false
    private var isDragging = false
    private var dragStartMouse = NSPoint.zero
    private var dragStartOrigin = NSPoint.zero
    private var totalDragDistance: CGFloat = 0
    private var hitTestTimer: Timer?
    private var behaviorTimer: Timer?
    private var patrolTimer: Timer?
    private var speechTimer: Timer?
    private var speechHideTimer: Timer?
    private var speechFollowTimer: Timer?
    private var recentSpeechMessages: [String] = []
    private var cursorFollowTimer: Timer?
    private var freeRoamTimer: Timer?
    private var facingTimer: Timer?
    private var statusItemHealthTimer: Timer?
    private var treatChaseTimer: Timer?
    private var hoverActionTimer: Timer?
    private var mindTimer: Timer?
    private var desktopInteractionTimer: Timer?
    private var motionQATimer: Timer?
    private var motionQATickCount = 0
    private var motionQAMaximumTickGap: TimeInterval = 0
    private var motionQALastTickTime: TimeInterval?
    private var startupVisibilityGeneration = 0
    private var smoothedSpeechLocalFrame: NSRect?
    private var behaviorEpoch = 0
    private var patrolDirection: CGFloat = -1
    private var patrolDeadline: TimeInterval = 0
    private var currentlyInteractive = false
    private var locomotionMode: LocomotionMode = .none
    private var locomotionVelocity = NSPoint.zero
    /// NSWindow origins are integral on many displays. Preserve sub-point
    /// movement between 120 Hz updates so a 76 pt/s walk does not repeatedly
    /// round each 0.63 pt step back to the same window position.
    private var preciseLocomotionOrigin: NSPoint?
    private var locomotionGeneration = 0
    private var locomotionDirection: CGFloat = -1
    private var actionFacing: HorizontalFacing = .left
    private var lastLocomotionChangeTime: TimeInterval = 0
    private var locomotionModeLockUntil: TimeInterval = 0
    private var pendingLocomotionMode: LocomotionMode?
    private var pendingLocomotionSince: TimeInterval = 0
    private var locomotionTranslationStartTime: TimeInterval = 0
    private var lastCursorLocation = NSPoint.zero
    private var lastCursorSampleTime: TimeInterval = 0
    private var smoothedCursorSpeed: CGFloat = 0
    private var facingView: PetFacingView = .leftProfile
    private var pendingFacingView: PetFacingView?
    private var lookDirection: PetLookDirection = .left
    private var lastLookCursorLocation = NSPoint.zero
    private var lastLookCursorMotionTime: TimeInterval = 0
    private var lastDirectionalLookSampleTime: TimeInterval = 0
    private var smoothedDirectionalLookAngle: Double?
    private var directionalLookIsEngaged = false
    private var pendingFacingSince: TimeInterval = 0
    private var lastFacingChangeTime: TimeInterval = 0
    private var isUsingImageFacing = false
    private var facingTransitionGeneration = 0
    private var profileSwitchGeneration = 0
    private var isReturningToActionProfile = false
    private var cursorMotionReadyTime: TimeInterval = 0
    private var freeRoamTarget: NSPoint?
    private var pendingDesktopInteraction: DesktopInteractionService.Destination?
    private var desktopInteractionInProgress = false
    private var immediateDesktopInteractionResume: (follow: Bool, roam: Bool)?
    private var immediateInteractionQAObservedKinds: [String] = []
    private var immediateInteractionQAMovementTicks = 0
    private var freeRoamPauseUntil: TimeInterval = 0
    private var lastFreeRoamSampleTime: TimeInterval = 0
    private var treatTarget: NSPoint?
    private var treatLastSampleTime: TimeInterval = 0
    private var treatDeadline: TimeInterval = 0
    private let behaviorQAReportPath = ProcessInfo.processInfo.environment["FURBALL_BEHAVIOR_QA_REPORT"]
    private var behaviorQAStartedAt: TimeInterval?
    private var behaviorQAOutcome: String?
    private var behaviorQAReportWritten = false
    private var resumeFollowingAfterTreat = false
    private var resumeRoamingAfterTreat = false
    private var lastHoverActionTime: TimeInterval = 0
    private var autonomousActionFacingUntil: TimeInterval = 0
    private var restFacingPreparedEpoch: Int?
    private var mindPetID = ""
    private var petMind = PetMindSnapshot.default
    private var lastMindTickTime: TimeInterval = 0
    private let behaviorTimeScale: Double = ProcessInfo.processInfo.environment["FURBALL_FAST_BEHAVIOR"] == "1" ? 0.08 : 1

    private var petScale: CGFloat {
        didSet { UserDefaults.standard.set(petScale, forKey: PreferenceKey.petScale) }
    }

    private var fullPassThrough: Bool {
        didSet { UserDefaults.standard.set(fullPassThrough, forKey: PreferenceKey.fullPassThrough) }
    }

    private var autoBehavior: Bool {
        didSet { UserDefaults.standard.set(autoBehavior, forKey: PreferenceKey.autoBehavior) }
    }

    private var followCursor: Bool {
        didSet { UserDefaults.standard.set(followCursor, forKey: PreferenceKey.followCursor) }
    }

    private var freeRoamEnabled: Bool {
        didSet { UserDefaults.standard.set(freeRoamEnabled, forKey: PreferenceKey.freeRoam) }
    }

    private var imageFacingEnabled: Bool {
        didSet { UserDefaults.standard.set(imageFacingEnabled, forKey: PreferenceKey.imageFacing) }
    }

    private var desktopInteractionsEnabled: Bool {
        didSet { UserDefaults.standard.set(desktopInteractionsEnabled, forKey: PreferenceKey.desktopInteractions) }
    }

    private var speechBubblesEnabled: Bool {
        didSet { UserDefaults.standard.set(speechBubblesEnabled, forKey: PreferenceKey.speechBubbles) }
    }

    private var talkativeness: Double {
        didSet { UserDefaults.standard.set(talkativeness, forKey: PreferenceKey.talkativeness) }
    }

    private var groupPlayEnabled: Bool {
        didSet { UserDefaults.standard.set(groupPlayEnabled, forKey: PreferenceKey.groupPlay) }
    }

    private var groupPetIDs: Set<String> {
        didSet { UserDefaults.standard.set(groupPetIDs.sorted(), forKey: PreferenceKey.groupPetIDs) }
    }

    private var videoAnimationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(
                videoAnimationsEnabled,
                forKey: Self.videoAnimationsPreferenceKey
            )
        }
    }

    private var appLanguage: AppLanguage {
        didSet { UserDefaults.standard.set(appLanguage.rawValue, forKey: AppLanguage.preferenceKey) }
    }

    init(startingPosture: PetPosture) throws {
        let defaults = UserDefaults.standard
        let savedScale = CGFloat(defaults.double(forKey: PreferenceKey.petScale))
        let initialScale = min(Self.maximumScale, max(Self.minimumScale, savedScale == 0 ? 1 : savedScale))
        petScale = initialScale
        fullPassThrough = defaults.bool(forKey: PreferenceKey.fullPassThrough)
        autoBehavior = defaults.object(forKey: PreferenceKey.autoBehavior) == nil
            ? true
            : defaults.bool(forKey: PreferenceKey.autoBehavior)
        freeRoamEnabled = defaults.bool(forKey: PreferenceKey.freeRoam)
        followCursor = freeRoamEnabled ? false : defaults.bool(forKey: PreferenceKey.followCursor)
        imageFacingEnabled = defaults.object(forKey: PreferenceKey.imageFacing) == nil
            ? true
            : defaults.bool(forKey: PreferenceKey.imageFacing)
        desktopInteractionsEnabled = defaults.object(forKey: PreferenceKey.desktopInteractions) == nil
            ? true
            : defaults.bool(forKey: PreferenceKey.desktopInteractions)
        speechBubblesEnabled = defaults.object(forKey: PreferenceKey.speechBubbles) == nil
            ? true
            : defaults.bool(forKey: PreferenceKey.speechBubbles)
        let savedTalkativeness = defaults.object(forKey: PreferenceKey.talkativeness) == nil
            ? 0.55
            : defaults.double(forKey: PreferenceKey.talkativeness)
        talkativeness = min(1, max(0, savedTalkativeness))
        groupPlayEnabled = defaults.bool(forKey: PreferenceKey.groupPlay)
        let imageCapableIDs = PetAssetCatalog.imageCapablePetIDs
        let savedGroupIDs = Set(defaults.stringArray(forKey: PreferenceKey.groupPetIDs) ?? [])
        let validSavedGroupIDs = savedGroupIDs.intersection(imageCapableIDs)
        groupPetIDs = validSavedGroupIDs.isEmpty ? imageCapableIDs : validSavedGroupIDs
        if ProcessInfo.processInfo.environment["FURBALL_GROUP_PLAY"] == "1" {
            groupPlayEnabled = true
            groupPetIDs = imageCapableIDs
        }
        // Appearance selection is the source of truth. The old Boolean is
        // retained only so existing installs keep their previous preference.
        videoAnimationsEnabled = PetAssetCatalog.activeAppearance.kind == .continuousVideo
        appLanguage = AppLanguage.stored

        let size = NSSize(width: Self.basePetSize.width * initialScale, height: Self.basePetSize.height * initialScale)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: screen.maxX - size.width - 24, y: screen.minY + 18)
        renderer = try PetRenderer(
            frame: NSRect(origin: .zero, size: size),
            visualMode: videoAnimationsEnabled ? .video : .images
        )
        panel = PetPanel(contentRect: NSRect(origin: origin, size: size))
        let alwaysOnTop = defaults.object(forKey: PreferenceKey.alwaysOnTop) == nil
            ? true
            : defaults.bool(forKey: PreferenceKey.alwaysOnTop)
        panel.level = alwaysOnTop ? .floating : .normal
        super.init()

        posture = startingPosture
        mindPetID = PetAssetCatalog.petID
        petMind = PetMindStore.load(petID: mindPetID)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(petMindDidChange(_:)),
            name: .petMindDidChange,
            object: nil
        )
        panel.contentView = renderer.view
        configureInput()
        configureMenu()
    }

    func start() {
        showPetWindow()
        do {
            try renderer.play(PetClips.idle(for: posture))
        } catch {
            present(error)
            return
        }

        // A borderless accessory panel can be on screen while its first Metal/
        // AV frame is still empty. Verify actual rendered content after launch
        // and recover from a stale display or unavailable preferred renderer.
        scheduleStartupVisibilityChecks()

        hitTestTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.renderer.ensureDisplayRefresh()
                self?.updateClickThrough()
            }
        }
        startStatusItemHealthCheck()
        startMindTracking()
        startFacingTracking()
        if freeRoamEnabled {
            beginFreeRoaming()
        } else if followCursor {
            beginCursorFollowing()
        } else {
            scheduleWake(epoch: behaviorEpoch)
        }
        scheduleNextSpeech(after: 1.4)
        if groupPlayEnabled {
            DispatchQueue.main.async { [weak self] in self?.activateGroupPlay() }
        }

        // Opt-in visual QA hooks used by packaging checks; normal launches do
        // not set these environment variables.
        if ProcessInfo.processInfo.environment["FURBALL_OPEN_VISUAL_SETTINGS"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.showVisualSettings()
            }
        } else if ProcessInfo.processInfo.environment["FURBALL_OPEN_PET_CREATOR"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.showPetCreatorForQA()
            }
        } else if ProcessInfo.processInfo.environment["FURBALL_OPEN_PET_LIBRARY"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.showPetLibrary()
            }
        }
        if let reportPath = ProcessInfo.processInfo.environment["FURBALL_SMOKE_REPORT"],
           !reportPath.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) { [weak self] in
                self?.writeSmokeReport(to: reportPath)
            }
        }
        if let reportPath = ProcessInfo.processInfo.environment["FURBALL_BOUNDARY_QA_REPORT"],
           !reportPath.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.runBoundaryReflectionQA(reportPath: reportPath)
            }
        }
        if let reportPath = ProcessInfo.processInfo.environment["FURBALL_APPEARANCE_SWITCH_QA_REPORT"],
           !reportPath.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.runAppearanceSwitchQA(reportPath: reportPath, step: 0, results: [])
            }
        }
        if let reportPath = ProcessInfo.processInfo.environment["FURBALL_IMMEDIATE_INTERACTION_QA_REPORT"],
           !reportPath.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.inspectTrashImmediately()
            }
            // A far-side desktop target plus a three-gesture inspection can
            // legitimately take longer than the old single-action 15 seconds.
            DispatchQueue.main.asyncAfter(deadline: .now() + 32) { [weak self] in
                guard let self,
                      !FileManager.default.fileExists(atPath: reportPath) else { return }
                self.writeImmediateInteractionQAReport(
                    path: reportPath,
                    pass: false,
                    reason: "watchdog-timeout"
                )
            }
        }
        if let reportPath = ProcessInfo.processInfo.environment["FURBALL_GROUP_PLAY_QA_REPORT"],
           !reportPath.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) { [weak self] in
                self?.writeGroupPlayQAReport(to: reportPath)
            }
        }
        if let reportPath = ProcessInfo.processInfo.environment["FURBALL_LIVE_MOTION_QA_REPORT"],
           !reportPath.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.startLiveMotionQA(reportPath: reportPath)
            }
        }
        if let reportPath = behaviorQAReportPath, !reportPath.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in
                self?.startTreatBehaviorQA()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 19.5) { [weak self] in
                guard let self, !self.behaviorQAReportWritten else { return }
                if self.behaviorQAOutcome == nil { self.behaviorQAOutcome = "watchdog-timeout" }
                self.writeBehaviorQAReport(to: reportPath)
            }
        }
    }

    private func runAppearanceSwitchQA(
        reportPath: String,
        step: Int,
        results: [[String: Any]]
    ) {
        guard RuntimeSafetyPolicy.permitsDeveloperQAFileWrites else { return }
        let appearanceIDs = ["continuous-video", "cute-2d", "realistic-2d"]
        if step == 0,
           !Set(appearanceIDs).isSubset(of: Set(PetAssetCatalog.availableAppearances.map(\.id))),
           let referencePet = PetAssetCatalog.availablePets.first(where: {
               Set(appearanceIDs).isSubset(of: Set($0.appearances.map(\.id)))
           }) {
            if settingsWindowController == nil { showVisualSettings() }
            guard settingsWindowController?.performPetSelectionForQA(id: referencePet.id) == true else {
                writeAppearanceSwitchQAReport(
                    reportPath: reportPath,
                    results: [["requestedPet": referencePet.id, "pass": false]]
                )
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
                self?.runAppearanceSwitchQA(reportPath: reportPath, step: 0, results: results)
            }
            return
        }
        guard step < appearanceIDs.count else {
            writeAppearanceSwitchQAReport(reportPath: reportPath, results: results)
            return
        }

        let requestedID = appearanceIDs[step]
        if settingsWindowController == nil { showVisualSettings() }
        let clickWasDelivered = settingsWindowController?.performAppearanceClickForQA(id: requestedID) == true
        DispatchQueue.main.asyncAfter(deadline: .now() + (requestedID == "continuous-video" ? 1.15 : 0.35)) { [weak self] in
            guard let self else { return }
            let active = PetAssetCatalog.activeAppearance
            let expectedMode: PetVisualMode = active.kind.visualMode
            var nextResults = results
            nextResults.append([
                "requested": requestedID,
                "active": active.id,
                "mode": self.renderer.visualMode == .video ? "video" : "images",
                "hasVisibleContent": self.renderer.visibleContentRect() != nil,
                "clickWasDelivered": clickWasDelivered,
                "pass": clickWasDelivered
                    && active.id == requestedID
                    && self.renderer.visualMode == expectedMode
                    && self.renderer.visibleContentRect() != nil
            ])
            self.runAppearanceSwitchQA(reportPath: reportPath, step: step + 1, results: nextResults)
        }
    }

    private func writeAppearanceSwitchQAReport(reportPath: String, results: [[String: Any]]) {
        let pass = results.count == 3 && results.allSatisfy { ($0["pass"] as? Bool) == true }
        let report: [String: Any] = [
            "pass": pass,
            "petID": PetAssetCatalog.petID,
            "results": results
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: reportPath), options: .atomic)
        } catch {
            NSLog("Furball2D appearance switch QA failed: %@", error.localizedDescription)
        }
        if ProcessInfo.processInfo.environment["FURBALL_APPEARANCE_SWITCH_QA_EXIT"] == "1" {
            NSApp.terminate(nil)
        }
    }

    private func startLiveMotionQA(reportPath: String) {
        guard RuntimeSafetyPolicy.permitsDeveloperQAFileWrites else { return }
        if groupPlayEnabled {
            groupPlayEnabled = false
            groupPlayController.stop()
            showPetWindow()
        }
        _ = switchAppearance(to: "continuous-video")
        followCursor = false
        freeRoamEnabled = false
        posture = .stand
        motionQATickCount = 0
        motionQAMaximumTickGap = 0
        motionQALastTickTime = nil
        renderer.beginVideoFrameDiagnostics()
        setLocomotionMode(.fastRun, direction: 1)

        let timer = Timer(timeInterval: 1.0 / movementRefreshRate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = ProcessInfo.processInfo.systemUptime
                let deltaTime = self.motionQALastTickTime
                    .map { min(1.0 / 20.0, max(1.0 / 120.0, now - $0)) }
                    ?? 1.0 / self.movementRefreshRate
                if let previous = self.motionQALastTickTime {
                    self.motionQAMaximumTickGap = max(self.motionQAMaximumTickGap, now - previous)
                }
                self.motionQALastTickTime = now
                self.motionQATickCount += 1
                let visible = self.panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? self.panel.frame
                let targetX = self.locomotionDirection > 0 ? visible.maxX + 400 : visible.minX - 400
                let target = NSPoint(x: targetX, y: visible.midY)
                let collision = self.updateMovement(
                    toward: target,
                    demand: 900,
                    deadZone: 1,
                    now: now,
                    deltaTime: deltaTime
                )
                if collision.horizontalWall != 0 {
                    self.locomotionDirection = -collision.horizontalWall
                    self.actionFacing = self.locomotionDirection > 0 ? .right : .left
                }
            }
        }
        motionQATimer = timer
        RunLoop.main.add(timer, forMode: .common)

        DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) { [weak self] in
            self?.finishLiveMotionQA(reportPath: reportPath)
        }
    }

    private func finishLiveMotionQA(reportPath: String) {
        motionQATimer?.invalidate()
        motionQATimer = nil
        let diagnostics = renderer.finishVideoFrameDiagnostics()
        let expectedFPS = movementRefreshRate
        let minimumExpectedCallbacks = Int(expectedFPS * 7 * 0.80)
        let pass = diagnostics.drawCallbacks >= minimumExpectedCallbacks
            && diagnostics.freshFrameRatio >= 0.88
            && diagnostics.maximumDrawGap <= 0.050
            && motionQAMaximumTickGap <= 0.050
            && renderer.visibleContentRect() != nil
        let report: [String: Any] = [
            "pass": pass,
            "displayFPS": expectedFPS,
            "drawCallbacks": diagnostics.drawCallbacks,
            "freshVideoFrames": diagnostics.freshVideoFrames,
            "freshFrameRatio": diagnostics.freshFrameRatio,
            "averageDrawGap": diagnostics.averageDrawGap,
            "maximumDrawGap": diagnostics.maximumDrawGap,
            "movementTicks": motionQATickCount,
            "maximumMovementTickGap": motionQAMaximumTickGap,
            "activeAppearance": PetAssetCatalog.activeAppearance.id,
            "visibleContent": renderer.visibleContentRect() != nil
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: reportPath), options: .atomic)
        } catch {
            NSLog("Furball2D live motion QA report failed: %@", error.localizedDescription)
        }
        if ProcessInfo.processInfo.environment["FURBALL_LIVE_MOTION_QA_EXIT"] == "1" {
            NSApp.terminate(nil)
        }
    }

    private func writeSmokeReport(to path: String) {
        guard RuntimeSafetyPolicy.permitsDeveloperQAFileWrites else { return }
        var animationErrors: [String] = []
        if renderer.visualMode == .images {
            let clips: [PetClip] = [
                PetClips.standIdle, PetClips.lookAroundImages, PetClips.sitDown,
                PetClips.sitIdle, PetClips.sitToLie, PetClips.lieIdle,
                PetClips.lieToSleep, PetClips.sleepIdle, PetClips.sleepToStand,
                PetClips.walk.start, PetClips.walk.loop, PetClips.walk.stop,
                PetClips.slowRun.start, PetClips.slowRun.loop, PetClips.slowRun.stop,
                PetClips.fastRun.start, PetClips.fastRun.loop, PetClips.fastRun.stop
            ] + PetAssetCatalog.imageActions.map(PetClips.imageAction)
            for clip in clips {
                do { _ = try clip.imageAnimation }
                catch { animationErrors.append("\(clip.id): \(error.localizedDescription)") }
            }
            for index in 0..<PetLookDirection.count {
                let clip = PetClips.lookDirection(PetLookDirection(index: index))
                do { _ = try clip.imageAnimation }
                catch { animationErrors.append("\(clip.id): \(error.localizedDescription)") }
            }
        }
        let rect = renderer.visibleContentRect()
        let report: [String: Any] = [
            "activePet": PetAssetCatalog.activePet?.id ?? NSNull(),
            "availablePets": PetAssetCatalog.availablePets.map(\.id),
            "appearance": PetAssetCatalog.activeAppearance.id,
            "mode": renderer.visualMode == .video ? "video" : "images",
            "panelVisible": panel.isVisible,
            "contentVisible": rect != nil,
            "contentRect": rect.map(NSStringFromRect) ?? NSNull(),
            "statusItemAvailable": statusItem?.button != nil,
            "publishedImageActions": PetAssetCatalog.imageActions.count,
            "animationErrors": animationErrors
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            NSLog("Furball2D smoke report: %@", path)
        } catch {
            NSLog("Furball2D smoke report failed: %@", error.localizedDescription)
        }
        if ProcessInfo.processInfo.environment["FURBALL_SMOKE_EXIT"] == "1" {
            NSApp.terminate(nil)
        }
    }

    private func writeGroupPlayQAReport(to path: String) {
        guard RuntimeSafetyPolicy.permitsDeveloperQAFileWrites else { return }
        let snapshot = groupPlayController.snapshot()
        let expected = groupPetIDs.intersection(PetAssetCatalog.imageCapablePetIDs)
        let report: [String: Any] = [
            "pass": groupPlayEnabled
                && Set(snapshot.petIDs) == expected
                && snapshot.visibleCount == expected.count
                && (snapshot.movingCount > 0 || snapshot.socialInteractionCount > 0)
                && snapshot.socialInteractionCount > 0
                && !panel.isVisible,
            "selectedPetIDs": expected.sorted(),
            "runningPetIDs": snapshot.petIDs,
            "visibleCount": snapshot.visibleCount,
            "movingCount": snapshot.movingCount,
            "socialInteractionCount": snapshot.socialInteractionCount,
            "primaryPanelHidden": !panel.isVisible
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            NSLog("Furball2D group QA report failed: %@", error.localizedDescription)
        }
        if ProcessInfo.processInfo.environment["FURBALL_GROUP_PLAY_QA_EXIT"] == "1" {
            NSApp.terminate(nil)
        }
    }

    private func runBoundaryReflectionQA(reportPath: String) {
        guard let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else {
            writeBoundaryQAReport(path: reportPath, values: ["pass": false, "reason": "No screen"])
            return
        }
        let limits = horizontalMovementLimits(in: visibleFrame)
        var origin = panel.frame.origin
        origin.x = limits.maximum
        panel.setFrameOrigin(origin)
        posture = .stand
        isTransitioning = false
        locomotionMode = .walk
        locomotionTranslationStartTime = 0
        locomotionDirection = 1
        actionFacing = .right
        locomotionVelocity = NSPoint(x: 120, y: 0)

        let centerBefore = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let outsideTarget = NSPoint(x: centerBefore.x + 600, y: centerBefore.y)
        let collision = updateMovement(
            toward: outsideTarget,
            demand: 500,
            deadZone: 8,
            now: ProcessInfo.processInfo.systemUptime,
            deltaTime: 1.0 / 60.0
        )
        redirectFreeRoamAfterBoundaryCollision(collision, previousTarget: outsideTarget)
        let reflectedTarget = freeRoamTarget
        let passed = collision.horizontalWall == 1
            && locomotionDirection < 0
            && actionFacing == .left
            && locomotionVelocity.x < 0
            && (reflectedTarget?.x ?? .greatestFiniteMagnitude) < panel.frame.midX
        writeBoundaryQAReport(path: reportPath, values: [
            "pass": passed,
            "hitRightWall": collision.horizontalWall == 1,
            "reversedFacing": actionFacing == .left,
            "reversedVelocity": locomotionVelocity.x < 0,
            "targetMovedInside": (reflectedTarget?.x ?? .greatestFiniteMagnitude) < panel.frame.midX
        ])
    }

    private func writeBoundaryQAReport(path: String, values: [String: Any]) {
        guard RuntimeSafetyPolicy.permitsDeveloperQAFileWrites else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            NSLog("Furball2D boundary QA report failed: %@", error.localizedDescription)
        }
        if ProcessInfo.processInfo.environment["FURBALL_BOUNDARY_QA_EXIT"] == "1" {
            NSApp.terminate(nil)
        }
    }

    private func startTreatBehaviorQA() {
        guard let reportPath = behaviorQAReportPath, !reportPath.isEmpty else { return }
        behaviorQAStartedAt = ProcessInfo.processInfo.systemUptime
        behaviorQAOutcome = nil
        let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
        let horizontalOffset: CGFloat = panel.frame.midX > visibleFrame.midX ? -360 : 360
        let target = NSPoint(
            x: min(visibleFrame.maxX - 36, max(visibleFrame.minX + 36, panel.frame.midX + horizontalOffset)),
            y: min(visibleFrame.maxY - 44, max(visibleFrame.minY + 44, panel.frame.midY + 46))
        )
        guard beginTreatChase(at: target) else {
            behaviorQAOutcome = "could-not-start"
            writeBehaviorQAReport(to: reportPath)
            return
        }
    }

    private func writeBehaviorQAReport(to path: String) {
        guard RuntimeSafetyPolicy.permitsDeveloperQAFileWrites else { return }
        guard !behaviorQAReportWritten else { return }
        behaviorQAReportWritten = true
        let contentRect = renderer.visibleContentRect()
        let elapsed = behaviorQAStartedAt.map { ProcessInfo.processInfo.systemUptime - $0 } ?? 0
        let treatMemoryRecorded = petMind.memories.contains { $0.kind == .treat }
        let passed = behaviorQAOutcome == "completed"
            && treatTarget == nil
            && treatChaseTimer == nil
            && !desktopTreat.isVisible
            && locomotionMode == .none
            && panel.isVisible
            && contentRect != nil
            && statusItem?.button != nil
            && treatMemoryRecorded
        let report: [String: Any] = [
            "pass": passed,
            "scenario": "throw-treat-reach-consume-stop",
            "outcome": behaviorQAOutcome ?? "unknown",
            "elapsedSeconds": elapsed,
            "petPanelVisible": panel.isVisible,
            "petContentVisible": contentRect != nil,
            "statusItemAvailable": statusItem?.button != nil,
            "treatTargetCleared": treatTarget == nil,
            "treatWindowHidden": !desktopTreat.isVisible,
            "treatTimerStopped": treatChaseTimer == nil,
            "locomotionStopped": locomotionMode == .none,
            "treatMemoryRecorded": treatMemoryRecorded
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            NSLog("Furball2D behavior QA report: %@", path)
        } catch {
            NSLog("Furball2D behavior QA report failed: %@", error.localizedDescription)
        }
        if ProcessInfo.processInfo.environment["FURBALL_BEHAVIOR_QA_EXIT"] == "1" {
            NSApp.terminate(nil)
        }
    }

    private func showPetWindow() {
        panel.alphaValue = 1
        panel.setFrameOrigin(clampedOrigin(panel.frame.origin))
        panel.orderFrontRegardless()
    }

    private func scheduleStartupVisibilityChecks() {
        startupVisibilityGeneration += 1
        let generation = startupVisibilityGeneration
        for (attempt, delay) in [0.45, 1.40, 3.00, 4.80].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.startupVisibilityGeneration == generation else { return }
                self.recoverStartupVisibilityIfNeeded(attempt: attempt)
            }
        }
    }

    private func recoverStartupVisibilityIfNeeded(attempt: Int) {
        if groupPlayEnabled {
            panel.orderOut(nil)
            startupVisibilityGeneration += 1
            return
        }
        showPetWindow()
        let contentRect = renderer.visibleContentRect()
        guard contentRect == nil else {
            startupVisibilityGeneration += 1
            return
        }

        do {
            if attempt >= 2,
               ProcessInfo.processInfo.environment["FURBALL_APPEARANCE"] == nil,
               renderer.visualMode == .video,
               let fallback = PetAssetCatalog.availableAppearances.first(where: {
                   $0.kind == .spriteAtlas
               }),
               PetAssetCatalog.selectAppearance(id: fallback.id) {
                videoAnimationsEnabled = false
                try renderer.setVisualMode(.images, replaying: PetClips.idle(for: posture))
            } else if attempt >= 3, posture != .stand {
                posture = .stand
                renderer.setMirrored(false)
                try renderer.play(PetClips.standIdle, fadeDuration: 0)
            } else {
                try renderer.play(PetClips.idle(for: posture), fadeDuration: 0)
            }
        } catch {
            NSLog("Furball2D startup visibility recovery failed: %@", error.localizedDescription)
        }
    }

    private func configureInput() {
        renderer.view.onMouseDown = { [weak self] event in self?.mouseDown(event) }
        renderer.view.onMouseDragged = { [weak self] event in self?.mouseDragged(event) }
        renderer.view.onMouseUp = { [weak self] event in self?.mouseUp(event) }
        renderer.view.onRightMouseDown = { [weak self] event in self?.showContextMenu(event) }
        renderer.view.onMouseEntered = { [weak self] event in self?.mouseEnteredPet(event) }
        renderer.view.onMouseExited = { [weak self] event in self?.mouseExitedPet(event) }
    }

    private func configureMenu() {
        // Capability-gated items (for example an image-only pack's video
        // switch) must keep their explicit disabled state. AppKit otherwise
        // re-enables any item whose target responds to its action.
        menu.autoenablesItems = false
        menu.delegate = self
        rebuildMenu()
        repairStatusItemIfNeeded()
    }

    private func startStatusItemHealthCheck() {
        statusItemHealthTimer?.invalidate()
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.repairStatusItemIfNeeded()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        statusItemHealthTimer = timer

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemDisplayConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDisplayConfigurationChanged),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func systemDisplayConfigurationChanged() {
        // Menu-bar ownership can move between displays after wake or a monitor
        // change. Reattach on the next turn after AppKit finishes that migration.
        DispatchQueue.main.async { [weak self] in
            self?.repairStatusItemIfNeeded()
        }
    }

    private func repairStatusItemIfNeeded() {
        if let item = statusItem, item.button == nil {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }

        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        }

        guard let item = statusItem, let button = item.button else { return }
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let image = NSImage(
            systemSymbolName: "pawprint.fill",
            accessibilityDescription: "Furball2D"
        )?.withSymbolConfiguration(symbolConfiguration)
        image?.isTemplate = true

        item.length = NSStatusItem.squareLength
        item.menu = menu
        item.isVisible = true
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = appLanguage.statusTooltip
        button.isEnabled = true
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        if groupPlayEnabled {
            menu.addItem(
                withTitle: appLanguage.visibilityMenu(isVisible: groupPlayController.hasVisibleCompanions),
                action: #selector(toggleVisibility),
                keyEquivalent: ""
            )
            menu.addItem(.separator())
            menu.addItem(withTitle: appLanguage.settingsMenu, action: #selector(showVisualSettings), keyEquivalent: ",")
            menu.addItem(.separator())
            menu.addItem(withTitle: appLanguage.quitMenu, action: #selector(quit), keyEquivalent: "q")
            for item in menu.items where item.action != nil { item.target = self }
            return
        }
        menu.addItem(withTitle: appLanguage.interactMenu, action: #selector(interactFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: appLanguage.speakMenu, action: #selector(speakFromMenu), keyEquivalent: "")
        if renderer.visualMode == .images {
            menu.addItem(withTitle: appLanguage.throwTreatMenu, action: #selector(throwTreatFromMenu), keyEquivalent: "")
        }
        if !PetAssetCatalog.imageActions.isEmpty {
            menu.addItem(makeCuteActionsMenuItem())
        }
        menu.addItem(withTitle: appLanguage.imageTurnMenu, action: #selector(imageTurnFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: appLanguage.sleepMenu, action: #selector(sleepFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: appLanguage.visibilityMenu(isVisible: panel.isVisible), action: #selector(toggleVisibility), keyEquivalent: "")
        menu.addItem(.separator())

        menu.addItem(
            withTitle: appLanguage.settingsMenu,
            action: #selector(showVisualSettings),
            keyEquivalent: ","
        )
        menu.addItem(.separator())
        menu.addItem(withTitle: appLanguage.quitMenu, action: #selector(quit), keyEquivalent: "q")
        for item in menu.items where item.action != nil { item.target = self }
    }

    private func makeCuteActionsMenuItem() -> NSMenuItem {
        let root = NSMenuItem(title: appLanguage.cuteActionsMenu, action: nil, keyEquivalent: "")
        let actionMenu = NSMenu(title: appLanguage.cuteActionsMenu)
        let actionsAreAvailable = renderer.visualMode == .images
            && posture == .stand
            && !isTransitioning
            && locomotionMode == .none
            && patrolTimer == nil

        for action in PetAssetCatalog.imageActions {
            let item = NSMenuItem(
                title: action.title(for: appLanguage),
                action: #selector(performCuteActionFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = action.id
            item.isEnabled = actionsAreAvailable
            actionMenu.addItem(item)
        }
        root.submenu = actionMenu
        root.isEnabled = actionsAreAvailable
        return root
    }

    private func mouseDown(_ event: NSEvent) {
        registerUserActivity()
        isDragging = true
        totalDragDistance = 0
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = panel.frame.origin
        setPanelIgnoresMouseEvents(false)
    }

    private func mouseDragged(_ event: NSEvent) {
        guard isDragging else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - dragStartMouse.x
        let dy = mouse.y - dragStartMouse.y
        totalDragDistance = max(totalDragDistance, hypot(dx, dy))
        panel.setFrameOrigin(clampedOrigin(NSPoint(x: dragStartOrigin.x + dx, y: dragStartOrigin.y + dy)))
        repositionSpeechBubble(refreshSilhouette: false)
    }

    private func mouseUp(_ event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        if followCursor {
            lastCursorLocation = NSEvent.mouseLocation
            lastCursorSampleTime = ProcessInfo.processInfo.systemUptime
            smoothedCursorSpeed = 0
        }
        if totalDragDistance < 6, event.clickCount >= 2,
           renderer.visualMode == .images,
           let action = PetAssetCatalog.imageActions.first(where: { $0.id == "gesture.high-five" }) {
            showSpeech(appLanguage.highFiveGreeting)
            remember(
                .play,
                text: "we shared a high five",
                salience: 0.72,
                energy: -0.015,
                curiosity: -0.02,
                affinity: 0.035
            )
            performImageAction(action)
        } else if totalDragDistance < 6 {
            remember(
                .affection,
                text: "you gave me a gentle pet",
                salience: 0.48,
                affinity: 0.018
            )
            speakRandomly()
            if !followCursor, !freeRoamEnabled { advanceBehavior() }
        }
        registerUserActivity()
    }

    private func mouseEnteredPet(_ event: NSEvent) {
        hoverActionTimer?.invalidate()
        guard renderer.visualMode == .images,
              posture == .stand,
              !followCursor,
              !freeRoamEnabled,
              treatTarget == nil,
              ProcessInfo.processInfo.systemUptime - lastHoverActionTime > 12 else { return }
        hoverActionTimer = Timer.scheduledTimer(withTimeInterval: 0.72, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self,
                      !self.isTransitioning,
                      self.locomotionMode == .none,
                      self.panel.frame.contains(NSEvent.mouseLocation) else { return }
                let local = self.panel.convertPoint(fromScreen: NSEvent.mouseLocation)
                guard (self.renderer.alpha(at: local) ?? 0) > 0.08,
                      let action = PetAssetCatalog.imageActions.first(where: { $0.id == "gesture.head-tilt" })
                else { return }
                self.lastHoverActionTime = ProcessInfo.processInfo.systemUptime
                self.showSpeech(self.appLanguage.hoverGreeting)
                self.performImageAction(action)
            }
        }
    }

    private func mouseExitedPet(_ event: NSEvent) {
        hoverActionTimer?.invalidate()
        hoverActionTimer = nil
    }

    private func clampedOrigin(_ proposed: NSPoint, panelSize: NSSize? = nil) -> NSPoint {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? panel.screen ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return proposed }
        let size = panelSize ?? panel.frame.size
        let horizontalLimits = horizontalMovementLimits(in: frame, panelWidth: size.width)
        let verticalLimits = verticalMovementLimits(in: frame, panelHeight: size.height)
        return NSPoint(
            x: min(horizontalLimits.maximum, max(horizontalLimits.minimum, proposed.x)),
            y: min(verticalLimits.maximum, max(verticalLimits.minimum, proposed.y))
        )
    }

    private func horizontalMovementLimits(
        in visibleFrame: NSRect,
        panelWidth: CGFloat? = nil
    ) -> (minimum: CGFloat, maximum: CGFloat) {
        let width = panelWidth ?? panel.frame.width
        if panelWidth == nil,
           let content = renderer.visibleContentRect(), !content.isEmpty {
            let allowedOverflow = content.width * (1 - Self.minimumVisibleHorizontalRatio)
            let minimum = visibleFrame.minX - content.minX - allowedOverflow
            let maximum = visibleFrame.maxX - content.maxX + allowedOverflow
            if minimum <= maximum { return (minimum, maximum) }
        }
        let overflow = width * (1 - Self.minimumVisibleHorizontalRatio)
        let minimum = visibleFrame.minX - overflow
        let maximum = visibleFrame.maxX - width + overflow
        if minimum <= maximum { return (minimum, maximum) }

        let centered = visibleFrame.midX - width / 2
        return (centered, centered)
    }

    private func verticalMovementLimits(
        in visibleFrame: NSRect,
        panelHeight: CGFloat? = nil
    ) -> (minimum: CGFloat, maximum: CGFloat) {
        let height = panelHeight ?? panel.frame.height
        if panelHeight == nil,
           let content = renderer.visibleContentRect(), !content.isEmpty {
            let allowedOverflow = content.height * (1 - Self.minimumVisibleVerticalRatio)
            let minimum = visibleFrame.minY - content.minY - allowedOverflow
            let maximum = visibleFrame.maxY - content.maxY + allowedOverflow
            if minimum <= maximum { return (minimum, maximum) }
        }
        let overflow = height * (1 - Self.minimumVisibleVerticalRatio)
        let minimum = visibleFrame.minY - overflow
        let maximum = visibleFrame.maxY - height + overflow
        if minimum <= maximum { return (minimum, maximum) }

        let centered = visibleFrame.midY - height / 2
        return (centered, centered)
    }

    private func showContextMenu(_ event: NSEvent) {
        NSMenu.popUpContextMenu(menu, with: event, for: renderer.view)
    }

    private func setPanelIgnoresMouseEvents(_ ignoresMouseEvents: Bool) {
        if panel.ignoresMouseEvents != ignoresMouseEvents {
            panel.ignoresMouseEvents = ignoresMouseEvents
        }
    }

    private func scheduleNextSpeech(after delay: TimeInterval? = nil) {
        speechTimer?.invalidate()
        guard speechBubblesEnabled, talkativeness > 0.01 else { return }
        let affection = petMind.traits.affection
        let frequencyScale = 1.65 - talkativeness * 1.10
        let nextDelay = delay ?? Double.random(in: (22 - affection * 5)...(39 - affection * 7)) * frequencyScale
        speechTimer = Timer.scheduledTimer(withTimeInterval: nextDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.speakRandomly()
                self.scheduleNextSpeech()
            }
        }
    }

    private func speakRandomly() {
        guard panel.isVisible else { return }
        let baseMessages = appLanguage.speechMessages(for: posture)
        let contextual = petMind.contextualSpeech(for: appLanguage)
        let contextChance = 0.24 + petMind.traits.affection * 0.18 + petMind.state.affinity * 0.12
        let messages = !contextual.isEmpty && Double.random(in: 0...1) < contextChance
            ? contextual
            : baseMessages
        let candidates = messages.filter { !recentSpeechMessages.contains($0) }
        guard let message = (candidates.isEmpty ? messages : candidates).randomElement() else { return }
        showSpeech(message)
    }

    @objc private func petMindDidChange(_ notification: Notification) {
        guard let petID = notification.userInfo?["petID"] as? String,
              petID == mindPetID else { return }
        petMind = PetMindStore.load(petID: petID)
    }

    private func startMindTracking() {
        mindTimer?.invalidate()
        lastMindTickTime = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMindState() }
        }
        mindTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateMindState() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsedMinutes = min(60, max(0, now - lastMindTickTime)) / 60
        lastMindTickTime = now
        guard elapsedMinutes > 0 else { return }

        let isMoving = locomotionMode != .none || patrolTimer != nil || freeRoamEnabled
        let energyRate: Double
        if posture == .sleep {
            energyRate = 0.020 + petMind.traits.composure * 0.008
        } else if isMoving {
            energyRate = -(0.010 + (1 - petMind.traits.vitality) * 0.008)
        } else {
            energyRate = -(0.0025 + petMind.traits.vitality * 0.0015)
        }
        let curiosityRate = 0.004 + petMind.traits.curiosity * 0.006
        let hasRecentAffection = petMind.memories.contains {
            $0.kind == .affection && Date().timeIntervalSince($0.date) < 20 * 60
        }
        let affinityRate = hasRecentAffection ? 0 : -0.0008

        petMind.state.adjust(
            energy: energyRate * elapsedMinutes,
            curiosity: curiosityRate * elapsedMinutes,
            affinity: affinityRate * elapsedMinutes
        )
        petMind = PetMindStore.updateState(
            petMind.state,
            petID: mindPetID,
            notify: true
        )
    }

    private func remember(
        _ kind: PetMemoryKind,
        text: String,
        salience: Double = 0.55,
        energy: Double = 0,
        curiosity: Double = 0,
        affinity: Double = 0
    ) {
        petMind = PetMindStore.record(
            petID: mindPetID,
            kind: kind,
            text: text,
            salience: salience,
            energy: energy,
            curiosity: curiosity,
            affinity: affinity
        )
    }

    private func showSpeech(_ message: String) {
        guard panel.isVisible, speechBubblesEnabled else { return }
        recentSpeechMessages.removeAll(where: { $0 == message })
        recentSpeechMessages.append(message)
        if recentSpeechMessages.count > 4 { recentSpeechMessages.removeFirst() }
        smoothedSpeechLocalFrame = nil
        let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
        speechBubble.show(
            message: message,
            avoiding: stabilizedVisiblePetFrame(refresh: true, reset: true),
            in: visibleFrame,
            level: panel.level,
            petScale: petScale,
            mood: speechMood
        )
        startSpeechFollowing()

        speechHideTimer?.invalidate()
        speechHideTimer = Timer.scheduledTimer(withTimeInterval: 4.6, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hideSpeechBubble()
            }
        }
    }

    private func repositionSpeechBubble(refreshSilhouette: Bool = true, resetSilhouette: Bool = false) {
        guard speechBubble.isVisible else { return }
        let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
        speechBubble.reposition(
            avoiding: stabilizedVisiblePetFrame(refresh: refreshSilhouette, reset: resetSilhouette),
            in: visibleFrame,
            petScale: petScale
        )
    }

    private func startSpeechFollowing() {
        speechFollowTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.repositionSpeechBubble()
            }
        }
        speechFollowTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func hideSpeechBubble(animated: Bool = true) {
        speechFollowTimer?.invalidate()
        speechFollowTimer = nil
        smoothedSpeechLocalFrame = nil
        speechBubble.hide(animated: animated)
    }

    private var speechMood: PetSpeechBubbleMood {
        if isTransitioning || patrolTimer != nil || locomotionMode != .none { return .active }
        switch posture {
        case .stand: return .stand
        case .sit: return .sit
        case .lie: return .lie
        case .sleep: return .sleep
        }
    }

    private func stabilizedVisiblePetFrame(refresh: Bool, reset: Bool = false) -> NSRect {
        if !refresh, !reset, let localFrame = smoothedSpeechLocalFrame {
            return NSRect(
                x: panel.frame.minX + localFrame.minX,
                y: panel.frame.minY + localFrame.minY,
                width: localFrame.width,
                height: localFrame.height
            )
        }
        let measured = measuredLocalPetFrame()
        if reset || smoothedSpeechLocalFrame == nil {
            smoothedSpeechLocalFrame = measured
        } else if refresh, let current = smoothedSpeechLocalFrame {
            let response: CGFloat = isTransitioning ? 0.08 : 0.20
            let deadZone = 4.0 * petScale
            func filtered(_ old: CGFloat, _ new: CGFloat) -> CGFloat {
                let delta = new - old
                guard abs(delta) > deadZone else { return old }
                return old + delta * response
            }
            let minimumX = filtered(current.minX, measured.minX)
            let minimumY = filtered(current.minY, measured.minY)
            let maximumX = filtered(current.maxX, measured.maxX)
            let maximumY = filtered(current.maxY, measured.maxY)
            smoothedSpeechLocalFrame = NSRect(
                x: minimumX,
                y: minimumY,
                width: max(1, maximumX - minimumX),
                height: max(1, maximumY - minimumY)
            )
        }

        let localFrame = smoothedSpeechLocalFrame ?? measured
        return NSRect(
            x: panel.frame.minX + localFrame.minX,
            y: panel.frame.minY + localFrame.minY,
            width: localFrame.width,
            height: localFrame.height
        )
    }

    private func measuredLocalPetFrame() -> NSRect {
        if let localFrame = renderer.visibleContentRect(), !localFrame.isEmpty { return localFrame }

        let transparentTopRatio: CGFloat
        switch posture {
        case .stand, .sit:
            transparentTopRatio = 0.08
        case .lie:
            transparentTopRatio = 0.24
        case .sleep:
            transparentTopRatio = 0.52
        }

        return NSRect(
            x: 0,
            y: 0,
            width: panel.frame.width,
            height: panel.frame.height * (1 - transparentTopRatio)
        )
    }

    private func updateClickThrough() {
        if fullPassThrough {
            setPanelIgnoresMouseEvents(true)
            currentlyInteractive = false
            return
        }
        if isDragging {
            setPanelIgnoresMouseEvents(false)
            return
        }

        let mouse = NSEvent.mouseLocation
        guard panel.frame.contains(mouse) else {
            currentlyInteractive = false
            setPanelIgnoresMouseEvents(true)
            return
        }

        let localPoint = NSPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
        let alpha = renderer.alpha(at: localPoint) ?? 0
        let threshold: Float = currentlyInteractive ? 0.06 : 0.15
        currentlyInteractive = alpha >= threshold
        setPanelIgnoresMouseEvents(!currentlyInteractive)
    }

    private func startFacingTracking() {
        facingTimer?.invalidate()
        lastLookCursorLocation = NSEvent.mouseLocation
        lastLookCursorMotionTime = ProcessInfo.processInfo.systemUptime
        lastDirectionalLookSampleTime = lastLookCursorMotionTime
        smoothedDirectionalLookAngle = nil
        directionalLookIsEngaged = false
        // Track at display cadence. The former 10 Hz sampler plus an extra
        // 150 ms dwell made the eyes feel as if they noticed the pointer late.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateFacingTowardCursor()
            }
        }
        facingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private var canUseImageFacing: Bool {
        imageFacingEnabled
            && !followCursor
            && !freeRoamEnabled
            && posture == .stand
            && !isTransitioning
            && !isDragging
            && locomotionMode == .none
            && patrolTimer == nil
            && ProcessInfo.processInfo.systemUptime >= autonomousActionFacingUntil
            && panel.isVisible
    }

    private var usesDirectionalLook: Bool {
        renderer.visualMode == .images && PetAssetCatalog.supportsDirectionalLook
    }

    private var actionProfileLookDirection: PetLookDirection {
        actionFacing == .right ? .right : .left
    }

    private var imageFacingMatchesActionProfile: Bool {
        guard isUsingImageFacing else { return true }
        if usesDirectionalLook {
            return lookDirection == actionProfileLookDirection
        }
        return facingView == actionFacing.profileView
    }

    private var liveMotionFacingAnchors: [PetFacingView] {
        [.leftProfile, .frontThreeQuarterLeft, .front, .frontThreeQuarterRight, .rightProfile]
    }

    private func desiredLiveMotionFacingView(for cursor: NSPoint = NSEvent.mouseLocation) -> PetFacingView {
        let normalizedX = (cursor.x - panel.frame.midX) / max(1, panel.frame.width)
        switch normalizedX {
        case ..<(-0.34): return .leftProfile
        case ..<(-0.11): return .frontThreeQuarterLeft
        case ...0.11: return .front
        case ...0.34: return .frontThreeQuarterRight
        default: return .rightProfile
        }
    }

    private func nextLiveMotionFacingView(toward target: PetFacingView) -> PetFacingView {
        let anchors = liveMotionFacingAnchors
        guard let targetIndex = anchors.firstIndex(of: target) else { return target }
        let currentIndex = anchors.indices.min {
            abs(anchors[$0].rawValue - facingView.rawValue) < abs(anchors[$1].rawValue - facingView.rawValue)
        } ?? targetIndex
        guard currentIndex != targetIndex else { return target }
        return anchors[currentIndex + (targetIndex > currentIndex ? 1 : -1)]
    }

    private func updateFacingTowardCursor() {
        guard canUseImageFacing else {
            pendingFacingView = nil
            return
        }

        if renderer.visualMode == .images, PetAssetCatalog.supportsDirectionalLook {
            updateDirectionalLookTowardCursor()
        } else {
            updateLegacyFacingTowardCursor()
        }
    }

    private func updateLegacyFacingTowardCursor() {

        if !isUsingImageFacing {
            playFacingView(facingView, fadeDuration: 0.11)
            return
        }

        let desiredView = desiredLiveMotionFacingView()
        guard desiredView != facingView else {
            pendingFacingView = nil
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        if pendingFacingView != desiredView {
            pendingFacingView = desiredView
            pendingFacingSince = now
            return
        }

        // Live Motion uses still multi-view video ports. Treating all nine ports
        // as a 20 Hz flipbook causes repeated decoder crossfades and visible
        // double faces. Five deliberate anchors plus a short dwell reads as a
        // smooth head turn while still responding quickly to an intentional
        // cursor move.
        guard now - pendingFacingSince >= 0.12,
              now - lastFacingChangeTime >= 0.14 else { return }
        playFacingView(nextLiveMotionFacingView(toward: desiredView), fadeDuration: 0.11)
        pendingFacingSince = now
    }

    private func updateDirectionalLookTowardCursor() {
        pendingFacingView = nil
        let cursor = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime
        let cursorTravel = hypot(
            cursor.x - lastLookCursorLocation.x,
            cursor.y - lastLookCursorLocation.y
        )
        if cursorTravel >= 1 {
            lastLookCursorLocation = cursor
            lastLookCursorMotionTime = now
            directionalLookIsEngaged = true
        }

        // The sprite should notice a moving pointer, then resume its richer
        // breathing/blinking idle after the pointer has been still for a moment.
        // Without this timeout a single directional cell can permanently mask
        // the animated idle row.
        if !directionalLookIsEngaged || now - lastLookCursorMotionTime >= 2.4 {
            directionalLookIsEngaged = false
            smoothedDirectionalLookAngle = nil
            if isUsingImageFacing {
                playDirectionalStandIdle(fadeDuration: 0.09)
            }
            return
        }

        let deltaX = cursor.x - panel.frame.midX
        let deltaY = cursor.y - panel.frame.midY
        guard hypot(deltaX, deltaY) >= 32 * petScale else {
            directionalLookIsEngaged = false
            smoothedDirectionalLookAngle = nil
            if isUsingImageFacing {
                playDirectionalStandIdle(fadeDuration: 0.09)
            }
            return
        }
        let targetAngle = atan2(Double(deltaX), Double(deltaY))
        let deltaTime = min(1.0 / 20.0, max(1.0 / 120.0, now - lastDirectionalLookSampleTime))
        lastDirectionalLookSampleTime = now

        let currentAngle = smoothedDirectionalLookAngle ?? targetAngle
        var shortestDelta = targetAngle - currentAngle
        while shortestDelta > .pi { shortestDelta -= .pi * 2 }
        while shortestDelta < -.pi { shortestDelta += .pi * 2 }
        // A critically damped angular low-pass removes cursor jitter without
        // making the gaze trail behind deliberate movement.
        let response = 1 - exp(-deltaTime * 24)
        let smoothedAngle = currentAngle + shortestDelta * response
        smoothedDirectionalLookAngle = smoothedAngle
        displayDirectionalLook(angle: smoothedAngle, entryFadeDuration: isUsingImageFacing ? 0 : 0.055)
    }

    private func displayDirectionalLook(angle: Double, entryFadeDuration: TimeInterval) {
        let twoPi = Double.pi * 2
        var normalized = angle.truncatingRemainder(dividingBy: twoPi)
        if normalized < 0 { normalized += twoPi }
        let fractionalIndex = normalized / twoPi * Double(PetLookDirection.count)
        let lowerIndex = Int(floor(fractionalIndex)) % PetLookDirection.count
        let upperIndex = (lowerIndex + 1) % PetLookDirection.count
        let weight = Float(fractionalIndex - floor(fractionalIndex))
        let nearest = PetLookDirection(index: Int(fractionalIndex.rounded()))

        renderer.setMirrored(false)
        do {
            try renderer.displayDirectionalBlend(
                first: PetClips.lookDirection(PetLookDirection(index: lowerIndex)),
                second: PetClips.lookDirection(PetLookDirection(index: upperIndex)),
                weight: weight,
                entryFadeDuration: entryFadeDuration
            )
            let directionChanged = nearest != lookDirection
            lookDirection = nearest
            if (1...7).contains(nearest.index) {
                actionFacing = .right
            } else if (9...15).contains(nearest.index) {
                actionFacing = .left
            }
            isUsingImageFacing = true
            if directionChanged {
                lastFacingChangeTime = ProcessInfo.processInfo.systemUptime
                repositionSpeechBubble(resetSilhouette: true)
            }
        } catch {
            isUsingImageFacing = false
            present(error)
        }
    }

    private func playFacingView(_ view: PetFacingView, fadeDuration: TimeInterval) {
        renderer.setMirrored(false)
        do {
            try renderer.play(PetClips.imageFacing(view), fadeDuration: fadeDuration)
            facingView = view
            if view.rawValue < PetFacingView.front.rawValue {
                actionFacing = .left
            } else if view.rawValue > PetFacingView.front.rawValue {
                actionFacing = .right
            }
            isUsingImageFacing = true
            lastFacingChangeTime = ProcessInfo.processInfo.systemUptime
            repositionSpeechBubble(resetSilhouette: true)
        } catch {
            isUsingImageFacing = false
            present(error)
        }
    }

    private func playLookDirection(_ direction: PetLookDirection, fadeDuration: TimeInterval) {
        renderer.setMirrored(false)
        do {
            try renderer.play(PetClips.lookDirection(direction), fadeDuration: fadeDuration)
            lookDirection = direction
            if (1...7).contains(direction.index) {
                actionFacing = .right
            } else if (9...15).contains(direction.index) {
                actionFacing = .left
            }
            isUsingImageFacing = true
            lastFacingChangeTime = ProcessInfo.processInfo.systemUptime
            repositionSpeechBubble(resetSilhouette: true)
        } catch {
            isUsingImageFacing = false
            present(error)
        }
    }

    private func playDirectionalStandIdle(fadeDuration: TimeInterval) {
        renderer.setMirrored(false)
        do {
            try renderer.play(PetClips.standIdle, fadeDuration: fadeDuration)
            smoothedDirectionalLookAngle = nil
            isUsingImageFacing = false
            lastFacingChangeTime = ProcessInfo.processInfo.systemUptime
            repositionSpeechBubble(resetSilhouette: true)
        } catch {
            isUsingImageFacing = false
            present(error)
        }
    }

    private func returnDirectionalLookToStandIdle(completion: @escaping () -> Void) {
        guard isUsingImageFacing else {
            completion()
            return
        }

        facingTransitionGeneration += 1
        let generation = facingTransitionGeneration
        isReturningToActionProfile = true
        isTransitioning = true
        directionalLookIsEngaged = false
        playDirectionalStandIdle(fadeDuration: 0.09)

        Timer.scheduledTimer(withTimeInterval: 0.11, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, generation == self.facingTransitionGeneration else { return }
                self.isReturningToActionProfile = false
                self.isTransitioning = false
                completion()
            }
        }
    }

    private func returnImageFacingToActionProfile(completion: @escaping () -> Void) {
        if usesDirectionalLook {
            returnDirectionalLookToActionProfile(completion: completion)
            return
        }
        let targetView = actionFacing.profileView
        guard isUsingImageFacing, facingView != targetView else {
            completion()
            return
        }

        facingTransitionGeneration += 1
        let generation = facingTransitionGeneration
        isReturningToActionProfile = true
        isTransitioning = true
        pendingFacingView = nil
        speechBubble.updateAppearance(mood: speechMood)

        func advance() {
            guard generation == facingTransitionGeneration else { return }
            let nextView = nextLiveMotionFacingView(toward: targetView)
            do {
                try renderer.play(PetClips.imageFacing(nextView), fadeDuration: 0.11)
                facingView = nextView
                isUsingImageFacing = true
                lastFacingChangeTime = ProcessInfo.processInfo.systemUptime
            } catch {
                isReturningToActionProfile = false
                isTransitioning = false
                present(error)
                completion()
                return
            }

            Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, generation == self.facingTransitionGeneration else { return }
                    if self.facingView == targetView {
                        self.isReturningToActionProfile = false
                        self.isTransitioning = false
                        self.speechBubble.updateAppearance(mood: self.speechMood)
                        completion()
                    } else {
                        advance()
                    }
                }
            }
        }

        advance()
    }

    private func returnDirectionalLookToActionProfile(completion: @escaping () -> Void) {
        let targetDirection = actionProfileLookDirection
        guard isUsingImageFacing else {
            completion()
            return
        }

        facingTransitionGeneration += 1
        let generation = facingTransitionGeneration
        isReturningToActionProfile = true
        isTransitioning = true
        speechBubble.updateAppearance(mood: speechMood)
        let twoPi = Double.pi * 2
        let targetAngle = Double(targetDirection.index) / Double(PetLookDirection.count) * twoPi
        let startAngle = smoothedDirectionalLookAngle
            ?? Double(lookDirection.index) / Double(PetLookDirection.count) * twoPi
        var angleDelta = targetAngle - startAngle
        while angleDelta > .pi { angleDelta -= twoPi }
        while angleDelta < -Double.pi { angleDelta += twoPi }
        guard abs(angleDelta) >= 0.01 else {
            lookDirection = targetDirection
            smoothedDirectionalLookAngle = targetAngle
            isReturningToActionProfile = false
            isTransitioning = false
            speechBubble.updateAppearance(mood: speechMood)
            completion()
            return
        }
        let startTime = ProcessInfo.processInfo.systemUptime
        let duration = 0.16
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, generation == self.facingTransitionGeneration else {
                    timer.invalidate()
                    return
                }
                let linear = min(1, max(0, (ProcessInfo.processInfo.systemUptime - startTime) / duration))
                let eased = linear * linear * (3 - 2 * linear)
                let angle = startAngle + angleDelta * eased
                self.smoothedDirectionalLookAngle = angle
                self.displayDirectionalLook(angle: angle, entryFadeDuration: 0)
                guard linear >= 1 else { return }
                timer.invalidate()
                self.lookDirection = targetDirection
                self.isReturningToActionProfile = false
                self.isTransitioning = false
                self.speechBubble.updateAppearance(mood: self.speechMood)
                completion()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func advanceBehavior() {
        guard !isTransitioning else { return }
        switch posture {
        case .stand:
            playTransition(PetClips.sitDown)
        case .sit:
            playTransition(PetClips.sitToLie)
        case .lie:
            playTransition(PetClips.lieToSleep)
        case .sleep:
            playTransition(PetClips.sleepToStand)
        }
    }

    private func playTransition(_ clip: PetClip, completion: (() -> Void)? = nil) {
        if posture == .stand, isUsingImageFacing {
            if usesDirectionalLook {
                returnDirectionalLookToStandIdle { [weak self] in
                    self?.playTransition(clip, completion: completion)
                }
                return
            }
            if !imageFacingMatchesActionProfile {
                returnImageFacingToActionProfile { [weak self] in
                    self?.playTransition(clip, completion: completion)
                }
                return
            }
        }

        stopPatrol()
        locomotionGeneration += 1
        locomotionMode = .none
        locomotionVelocity = .zero
        pendingLocomotionMode = nil
        isUsingImageFacing = false
        isTransitioning = true
        let profileGeneration = profileSwitchGeneration
        renderer.setMirrored(actionFacing.isMirrored)
        speechBubble.updateAppearance(mood: speechMood)
        do {
            try renderer.play(clip) { [weak self] in
                guard let self, self.profileSwitchGeneration == profileGeneration else { return }
                self.isTransitioning = false
                self.playIdle(clip.resultingPosture)
                if clip.resultingPosture == .sleep {
                    self.remember(
                        .rest,
                        text: "I had a cozy nap in a corner of the desktop",
                        salience: 0.35,
                        curiosity: -0.015
                    )
                }
                completion?()
            }
        } catch {
            isTransitioning = false
            present(error)
        }
    }

    private func playIdle(_ newPosture: PetPosture) {
        posture = newPosture
        isTransitioning = false
        renderer.setMirrored(actionFacing.isMirrored)
        speechBubble.updateAppearance(mood: speechMood)

        if newPosture == .stand,
           imageFacingEnabled,
           !followCursor,
           !freeRoamEnabled,
           patrolTimer == nil,
           locomotionMode == .none,
            ProcessInfo.processInfo.systemUptime >= autonomousActionFacingUntil {
            if usesDirectionalLook {
                lastLookCursorLocation = NSEvent.mouseLocation
                lastLookCursorMotionTime = ProcessInfo.processInfo.systemUptime
                directionalLookIsEngaged = false
                playDirectionalStandIdle(fadeDuration: 0.09)
            } else {
                facingView = actionFacing.profileView
                playFacingView(facingView, fadeDuration: 0.07)
            }
            return
        }

        isUsingImageFacing = false
        do {
            try renderer.play(PetClips.idle(for: newPosture))
        } catch {
            present(error)
        }
    }

    private func registerUserActivity() {
        behaviorEpoch += 1
        let epoch = behaviorEpoch
        behaviorTimer?.invalidate()
        stopPatrol()
        guard autoBehavior, !followCursor, !freeRoamEnabled else { return }
        schedule(after: personalityRestDelay, epoch: epoch) { [weak self] in
            self?.settleDown(epoch: epoch)
        }
    }

    private var personalityRestDelay: TimeInterval {
        let traits = petMind.traits
        let state = petMind.state
        return 7.5
            + state.energy * 5.5
            + traits.vitality * 3.5
            + traits.composure * 1.5
    }

    private func autonomousAction() -> PetImageAction? {
        let actions = PetAssetCatalog.imageActions.filter(\.mayRunAutonomously)
        guard !actions.isEmpty else { return nil }
        let energeticIDs: Set<String> = [
            "gesture.jump", "gesture.happy-dance", "gesture.tail-chase", "gesture.paw-tap"
        ]
        let curiousIDs: Set<String> = [
            "gesture.review", "gesture.sniff", "gesture.head-tilt", "gesture.working"
        ]
        let calmIDs: Set<String> = [
            "gesture.yawn", "gesture.stretch", "gesture.waiting", "gesture.wave"
        ]
        let weighted = actions.map { action -> (PetImageAction, Double) in
            var weight = 0.35
            if energeticIDs.contains(action.id) {
                weight += petMind.traits.vitality * 1.2 + petMind.state.energy
                if petMind.state.energy < 0.25 { weight *= 0.12 }
            }
            if curiousIDs.contains(action.id) {
                weight += petMind.traits.curiosity + petMind.state.curiosityNeed * 1.15
            }
            if calmIDs.contains(action.id) {
                weight += petMind.traits.composure + (1 - petMind.state.energy) * 0.7
            }
            return (action, max(0.01, weight))
        }
        let total = weighted.reduce(0) { $0 + $1.1 }
        var roll = Double.random(in: 0..<total)
        for candidate in weighted {
            roll -= candidate.1
            if roll <= 0 { return candidate.0 }
        }
        return weighted.last?.0
    }

    private func schedule(
        after delay: TimeInterval,
        epoch: Int,
        requiresAutoBehavior: Bool = true,
        action: @MainActor @Sendable @escaping () -> Void
    ) {
        behaviorTimer?.invalidate()
        behaviorTimer = Timer.scheduledTimer(withTimeInterval: delay * behaviorTimeScale, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.behaviorEpoch == epoch,
                      !requiresAutoBehavior || self.autoBehavior else { return }
                action()
            }
        }
    }

    private func settleDown(epoch: Int) {
        guard behaviorEpoch == epoch, !isDragging, !freeRoamEnabled else { return }
        if isTransitioning {
            schedule(after: 1, epoch: epoch) { [weak self] in self?.settleDown(epoch: epoch) }
            return
        }
        stopPatrol()
        switch posture {
        case .stand:
            if restFacingPreparedEpoch != epoch {
                restFacingPreparedEpoch = epoch
                if renderer.visualMode == .images,
                   let action = autonomousAction() {
                    performImageAction(action) { [weak self] in
                        self?.schedule(after: 1.0, epoch: epoch) { [weak self] in
                            self?.settleDown(epoch: epoch)
                        }
                    }
                    return
                }
                actionFacing = Bool.random() ? .left : .right
                returnImageFacingToActionProfile { [weak self] in
                    self?.showAutonomousStandFacing(epoch: epoch)
                }
                return
            }
            restFacingPreparedEpoch = nil
            playTransition(PetClips.sitDown) { [weak self] in
                self?.schedule(after: 0.7, epoch: epoch) { [weak self] in self?.settleDown(epoch: epoch) }
            }
        case .sit:
            playTransition(PetClips.sitToLie) { [weak self] in
                self?.schedule(after: 0.7, epoch: epoch) { [weak self] in self?.settleDown(epoch: epoch) }
            }
        case .lie:
            playTransition(PetClips.lieToSleep) { [weak self] in
                self?.scheduleWake(epoch: epoch)
            }
        case .sleep:
            scheduleWake(epoch: epoch)
        }
    }

    private func showAutonomousStandFacing(epoch: Int) {
        guard behaviorEpoch == epoch, posture == .stand, !freeRoamEnabled else { return }
        autonomousActionFacingUntil = ProcessInfo.processInfo.systemUptime + 1.35
        if usesDirectionalLook {
            playLookDirection(actionProfileLookDirection, fadeDuration: 0.065)
        } else {
            isUsingImageFacing = false
            renderer.setMirrored(actionFacing.isMirrored)
            do {
                try renderer.play(PetClips.standIdle, fadeDuration: 0.09)
            } catch {
                present(error)
            }
        }
        schedule(after: 1.15, epoch: epoch) { [weak self] in
            self?.settleDown(epoch: epoch)
        }
    }

    private func scheduleWake(epoch: Int) {
        let traits = petMind.traits
        let state = petMind.state
        let center = 30 + (1 - state.energy) * 26 + traits.composure * 12 - traits.vitality * 8
        let duration = max(24, center + Double.random(in: -7...7))
        schedule(after: duration, epoch: epoch) { [weak self] in
            self?.beginOuting(epoch: epoch)
        }
    }

    private func beginOuting(epoch: Int) {
        guard behaviorEpoch == epoch, posture == .sleep, !isTransitioning else {
            schedule(after: 5, epoch: epoch) { [weak self] in self?.beginOuting(epoch: epoch) }
            return
        }
        playTransition(PetClips.sleepToStand) { [weak self] in
            self?.schedule(after: 1.2, epoch: epoch) { [weak self] in self?.startPatrol(epoch: epoch) }
        }
    }

    private func startPatrol(epoch: Int) {
        guard behaviorEpoch == epoch, posture == .stand else { return }
        let screen = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        patrolDirection = panel.frame.midX < screen.midX ? 1 : -1
        actionFacing = patrolDirection > 0 ? .right : .left
        if isUsingImageFacing, !imageFacingMatchesActionProfile {
            returnImageFacingToActionProfile { [weak self] in
                self?.startPatrol(epoch: epoch)
            }
            return
        }

        let walkAssetIsAvailable = renderer.visualMode == .video
            ? PetClips.walkIdle.isAvailable
            : PetClips.walkIdle.isImageAvailable
        if walkAssetIsAvailable {
            isUsingImageFacing = false
            renderer.setMirrored(actionFacing.isMirrored)
            do {
                try renderer.play(PetClips.walkIdle)
            } catch {
                present(error)
                schedule(after: 3, epoch: epoch) { [weak self] in self?.settleDown(epoch: epoch) }
                return
            }

            patrolDeadline = ProcessInfo.processInfo.systemUptime + Double.random(in: 10...18)
            speechBubble.updateAppearance(mood: .active)
            patrolTimer?.invalidate()
            patrolTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.updatePatrol(epoch: epoch)
                }
            }
        } else {
            // Keep the pet standing when the active representation does not
            // provide locomotion instead of sliding an unanimated silhouette.
            playIdle(.stand)
            schedule(after: Double.random(in: 7...12), epoch: epoch) { [weak self] in
                self?.settleDown(epoch: epoch)
            }
        }
    }

    private func updatePatrol(epoch: Int) {
        guard behaviorEpoch == epoch, !isDragging,
              ProcessInfo.processInfo.systemUptime < patrolDeadline else {
            patrolTimer?.invalidate()
            patrolTimer = nil
            autonomousActionFacingUntil = ProcessInfo.processInfo.systemUptime + 1.25
            playIdle(.stand)
            schedule(after: 1.2, epoch: epoch) { [weak self] in self?.settleDown(epoch: epoch) }
            return
        }

        let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var origin = panel.frame.origin
        origin.x += patrolDirection * (58.0 / 60.0)
        let horizontalLimits = horizontalMovementLimits(in: visibleFrame)
        let leftLimit = horizontalLimits.minimum
        let rightLimit = horizontalLimits.maximum
        if origin.x <= leftLimit || origin.x >= rightLimit {
            patrolDirection *= -1
            actionFacing = patrolDirection > 0 ? .right : .left
            renderer.setMirrored(actionFacing.isMirrored)
            origin.x = min(rightLimit, max(leftLimit, origin.x))
        }
        panel.setFrameOrigin(origin)
        repositionSpeechBubble(refreshSilhouette: false)
    }

    private func stopPatrol() {
        let wasPatrolling = patrolTimer != nil
        patrolTimer?.invalidate()
        patrolTimer = nil
        if wasPatrolling, posture == .stand, !isTransitioning {
            autonomousActionFacingUntil = ProcessInfo.processInfo.systemUptime + 1.25
            playIdle(.stand)
        }
    }

    private func beginCursorFollowing() {
        behaviorEpoch += 1
        behaviorTimer?.invalidate()
        stopPatrol()
        cursorFollowTimer?.invalidate()

        let horizontalDelta = NSEvent.mouseLocation.x - panel.frame.midX
        if abs(horizontalDelta) > 20 * petScale {
            actionFacing = horizontalDelta > 0 ? .right : .left
            locomotionDirection = actionFacing.direction
        }

        if posture == .stand, isUsingImageFacing, !imageFacingMatchesActionProfile {
            returnImageFacingToActionProfile { [weak self] in
                self?.activateCursorFollowing()
            }
            return
        }

        activateCursorFollowing()
    }

    private func activateCursorFollowing() {
        guard followCursor else { return }
        isUsingImageFacing = false
        lastCursorLocation = NSEvent.mouseLocation
        lastCursorSampleTime = ProcessInfo.processInfo.systemUptime
        cursorMotionReadyTime = lastCursorSampleTime
        smoothedCursorSpeed = 0

        // Synchronize panel movement to the actual display. Driving a 60 Hz
        // WindowServer at 120 unsynchronised updates steals main-thread time
        // from HEVC-alpha presentation and produces visible uneven cadence.
        let movementFPS = movementRefreshRate
        let timer = Timer(timeInterval: 1.0 / movementFPS, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateCursorFollowing()
            }
        }
        cursorFollowTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        continueToStandForMovement()
    }

    private func stopCursorFollowing() {
        cursorFollowTimer?.invalidate()
        cursorFollowTimer = nil
        smoothedCursorSpeed = 0
        if isReturningToActionProfile {
            facingTransitionGeneration += 1
            isReturningToActionProfile = false
            isTransitioning = false
        }
        let wasStopped = locomotionMode == .none
        setLocomotionMode(.none, direction: locomotionDirection)
        if wasStopped, posture == .stand, !isTransitioning {
            playIdle(.stand)
        }
    }

    private func continueToStandForMovement() {
        guard (followCursor || freeRoamEnabled || treatTarget != nil
               || immediateDesktopInteractionResume != nil),
              !isTransitioning else { return }
        switch posture {
        case .stand:
            return
        case .sit:
            playTransition(PetClips.sitToLie) { [weak self] in
                self?.continueToStandForMovement()
            }
        case .lie:
            playTransition(PetClips.lieToSleep) { [weak self] in
                self?.continueToStandForMovement()
            }
        case .sleep:
            playTransition(PetClips.sleepToStand) { [weak self] in
                self?.continueToStandForMovement()
            }
        }
    }

    private func updateCursorFollowing() {
        guard followCursor, panel.isVisible, !isDragging else { return }
        guard posture == .stand, !isTransitioning else {
            if !isTransitioning { continueToStandForMovement() }
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        guard now >= cursorMotionReadyTime else {
            lastCursorLocation = NSEvent.mouseLocation
            lastCursorSampleTime = now
            return
        }
        let deltaTime = min(1.0 / 20.0, max(1.0 / 120.0, now - lastCursorSampleTime))
        let cursor = NSEvent.mouseLocation
        let cursorDelta = hypot(cursor.x - lastCursorLocation.x, cursor.y - lastCursorLocation.y)
        let instantaneousCursorSpeed = cursorDelta / deltaTime
        smoothedCursorSpeed += (instantaneousCursorSpeed - smoothedCursorSpeed) * min(1, deltaTime * 24)
        lastCursorLocation = cursor
        lastCursorSampleTime = now

        let deadZone = 58 * petScale
        let distance = hypot(cursor.x - panel.frame.midX, cursor.y - panel.frame.midY)
        let demand = max(smoothedCursorSpeed, max(0, distance - deadZone) * 1.35)
        updateMovement(
            toward: cursor,
            demand: demand,
            deadZone: deadZone,
            now: now,
            deltaTime: deltaTime
        )
    }

    private func beginFreeRoaming() {
        behaviorEpoch += 1
        behaviorTimer?.invalidate()
        stopPatrol()
        freeRoamTimer?.invalidate()
        freeRoamTarget = makeRandomRoamTarget()
        freeRoamPauseUntil = 0

        if let target = freeRoamTarget {
            let horizontalDelta = target.x - panel.frame.midX
            if abs(horizontalDelta) > 20 * petScale {
                actionFacing = horizontalDelta > 0 ? .right : .left
                locomotionDirection = actionFacing.direction
            }
        }

        if posture == .stand, isUsingImageFacing, !imageFacingMatchesActionProfile {
            returnImageFacingToActionProfile { [weak self] in
                self?.activateFreeRoaming()
            }
            return
        }

        activateFreeRoaming()
    }

    private func activateFreeRoaming() {
        guard freeRoamEnabled || immediateDesktopInteractionResume != nil else { return }
        isUsingImageFacing = false
        lastFreeRoamSampleTime = ProcessInfo.processInfo.systemUptime
        let movementFPS = movementRefreshRate
        let timer = Timer(timeInterval: 1.0 / movementFPS, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateFreeRoaming()
            }
        }
        freeRoamTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        continueToStandForMovement()
    }

    private func stopFreeRoaming() {
        cancelDesktopItemInteraction()
        freeRoamTimer?.invalidate()
        freeRoamTimer = nil
        freeRoamTarget = nil
        pendingDesktopInteraction = nil
        freeRoamPauseUntil = 0
        if isReturningToActionProfile {
            facingTransitionGeneration += 1
            isReturningToActionProfile = false
            isTransitioning = false
        }
        let wasStopped = locomotionMode == .none
        setLocomotionMode(.none, direction: locomotionDirection)
        if wasStopped, posture == .stand, !isTransitioning {
            playIdle(.stand)
        }
    }

    private func updateFreeRoaming() {
        guard freeRoamEnabled || immediateDesktopInteractionResume != nil,
              panel.isVisible, !isDragging else { return }
        if immediateDesktopInteractionResume != nil {
            immediateInteractionQAMovementTicks += 1
        }
        if desktopInteractionInProgress { return }
        guard posture == .stand, !isTransitioning else {
            if !isTransitioning { continueToStandForMovement() }
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        let deltaTime = min(1.0 / 20.0, max(1.0 / 120.0, now - lastFreeRoamSampleTime))
        lastFreeRoamSampleTime = now
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)

        if now < freeRoamPauseUntil {
            updateMovement(toward: center, demand: 0, deadZone: 8, now: now, deltaTime: deltaTime)
            return
        }

        if freeRoamTarget == nil {
            let explorationChance = min(
                0.62,
                0.10 + petMind.traits.curiosity * 0.22 + petMind.state.curiosityNeed * 0.28
            )
            if desktopInteractionsEnabled,
               Double.random(in: 0...1) < explorationChance,
               let screen = panel.screen ?? NSScreen.main,
               let interaction = desktopInteractionService.destination(in: screen) {
                pendingDesktopInteraction = interaction
                freeRoamTarget = reachablePanelCenterTarget(for: interaction.point)
            } else {
                pendingDesktopInteraction = nil
                freeRoamTarget = makeRandomRoamTarget()
            }
        }
        guard let target = freeRoamTarget else { return }

        let distance = hypot(target.x - center.x, target.y - center.y)
        let deadZone = 54 * petScale
        if distance <= deadZone {
            freeRoamTarget = nil
            let interaction = pendingDesktopInteraction
            pendingDesktopInteraction = nil
            freeRoamPauseUntil = now + (interaction == nil ? Double.random(in: 3.8...6.4) : 5.6)
            updateMovement(toward: center, demand: 0, deadZone: 8, now: now, deltaTime: deltaTime)
            if let interaction { performDesktopInteraction(interaction) }
            return
        }

        let demand = max(120, distance * 0.9)
        let collision = updateMovement(
            toward: target,
            demand: demand,
            deadZone: deadZone,
            now: now,
            deltaTime: deltaTime
        )
        if collision.occurred {
            if let interaction = pendingDesktopInteraction {
                pendingDesktopInteraction = nil
                freeRoamTarget = nil
                updateMovement(
                    toward: NSPoint(x: panel.frame.midX, y: panel.frame.midY),
                    demand: 0,
                    deadZone: 8,
                    now: now,
                    deltaTime: deltaTime
                )
                performDesktopInteraction(interaction)
            } else {
                redirectFreeRoamAfterBoundaryCollision(collision, previousTarget: target)
            }
        }
    }

    private func redirectFreeRoamAfterBoundaryCollision(
        _ collision: MovementBoundaryCollision,
        previousTarget: NSPoint
    ) {
        guard let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        let horizontalLimits = horizontalMovementLimits(in: visibleFrame)
        let verticalLimits = verticalMovementLimits(in: visibleFrame)
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let centerXLimits = (
            minimum: horizontalLimits.minimum + panel.frame.width / 2,
            maximum: horizontalLimits.maximum + panel.frame.width / 2
        )
        let centerYLimits = (
            minimum: verticalLimits.minimum + panel.frame.height / 2,
            maximum: verticalLimits.maximum + panel.frame.height / 2
        )
        let horizontalRebound = min(
            440 * petScale,
            max(180 * petScale, (centerXLimits.maximum - centerXLimits.minimum) * 0.48)
        )
        let verticalRebound = min(
            300 * petScale,
            max(130 * petScale, (centerYLimits.maximum - centerYLimits.minimum) * 0.42)
        )

        var target = previousTarget
        if collision.horizontalWall != 0 {
            target.x = center.x - collision.horizontalWall * horizontalRebound
            locomotionVelocity.x = -collision.horizontalWall * max(42, abs(locomotionVelocity.x) * 0.45)
            locomotionDirection = -collision.horizontalWall
            actionFacing = locomotionDirection > 0 ? .right : .left
            renderer.setMirrored(actionFacing.isMirrored)
        }
        if collision.verticalWall != 0 {
            target.y = center.y - collision.verticalWall * verticalRebound
            locomotionVelocity.y = -collision.verticalWall * max(34, abs(locomotionVelocity.y) * 0.45)
        }
        target.x = min(centerXLimits.maximum, max(centerXLimits.minimum, target.x))
        target.y = min(centerYLimits.maximum, max(centerYLimits.minimum, target.y))
        pendingDesktopInteraction = nil
        freeRoamPauseUntil = 0
        freeRoamTarget = target
    }

    private func performDesktopInteraction(_ destination: DesktopInteractionService.Destination) {
        switch destination.kind {
        case .trash:
            recordImmediateInteractionQA(kind: "trash")
            remember(
                .exploration,
                text: "I carefully inspected the Trash",
                salience: 0.46,
                curiosity: -0.08
            )
            showSpeech(appLanguage.sniffTrashSpeech)
            if let action = PetAssetCatalog.imageActions.first(where: { $0.id == "gesture.sniff" }) {
                performImageAction(action) { [weak self] in
                    self?.finishImmediateDesktopInteractionIfNeeded()
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
                    self?.finishImmediateDesktopInteractionIfNeeded()
                }
            }
        case .desktopItem:
            recordImmediateInteractionQA(kind: "desktop-item")
            guard let name = destination.itemName, let url = destination.itemURL,
                  !desktopInteractionInProgress else { return }
            desktopInteractionInProgress = true
            remember(
                .desktop,
                text: "I discovered “\(name)” on the desktop",
                salience: 0.62,
                curiosity: -0.11
            )
            showSpeech(appLanguage.inspectDesktopItemSpeech(name))
            let style = Int.random(in: 0...2)
            switch style {
            case 0:
                showSpeech("What is this, \(name)? Let me inspect it very carefully…")
                performImageActionSequence(
                    ids: ["gesture.head-tilt", "gesture.sniff", "gesture.paw-tap"]
                ) { [weak self] in
                    self?.finishDesktopItemInspection(name: name)
                }
            case 1:
                showSpeech("A tiny sniff, a polite play bow… and maybe a little carry!")
                performImageActionSequence(
                    ids: ["gesture.play-bow", "gesture.sniff"]
                ) { [weak self] in
                    self?.beginDesktopItemCarry(destination: destination, url: url, name: name)
                }
            default:
                showSpeech("I’ll guard \(name) for one very serious second.")
                performImageActionSequence(
                    ids: ["gesture.waiting", "gesture.review", "gesture.happy-dance"]
                ) { [weak self] in
                    self?.finishDesktopItemInspection(name: name)
                }
            }
        }
    }

    private func performImageActionSequence(ids: [String], completion: @escaping () -> Void) {
        guard renderer.visualMode == .images, let firstID = ids.first,
              let action = PetAssetCatalog.imageActions.first(where: { $0.id == firstID }) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { completion() }
            return
        }
        performImageAction(action) { [weak self] in
            guard let self else { return }
            let remaining = Array(ids.dropFirst())
            if remaining.isEmpty {
                completion()
            } else {
                self.performImageActionSequence(ids: remaining, completion: completion)
            }
        }
    }

    private func finishDesktopItemInspection(name: String) {
        desktopInteractionInProgress = false
        freeRoamPauseUntil = ProcessInfo.processInfo.systemUptime + 1.8
        try? renderer.play(PetClips.standIdle, fadeDuration: 0.075)
        showSpeech("Inspection complete. \(name) stayed exactly where it was. ✨")
        finishImmediateDesktopInteractionIfNeeded()
    }

    private func beginDesktopItemCarry(
        destination: DesktopInteractionService.Destination,
        url: URL,
        name: String
    ) {
        guard desktopInteractionInProgress,
              let screen = panel.screen ?? NSScreen.main else {
            cancelDesktopItemInteraction()
            return
        }
        showSpeech(appLanguage.carryingDesktopItemSpeech(name))
        let startOrigin = panel.frame.origin
        let visible = screen.visibleFrame
        let horizontalRoomRight = visible.maxX - panel.frame.maxX
        let horizontalRoomLeft = panel.frame.minX - visible.minX
        let direction: CGFloat = horizontalRoomRight >= horizontalRoomLeft ? 1 : -1
        actionFacing = direction > 0 ? .right : .left
        locomotionDirection = direction
        renderer.setMirrored(actionFacing.isMirrored)

        let travel = min(150 * petScale, max(78 * petScale, max(horizontalRoomRight, horizontalRoomLeft) * 0.34))
        let proposedEnd = NSPoint(
            x: startOrigin.x + direction * travel,
            y: startOrigin.y + CGFloat.random(in: (-22 * petScale)...(22 * petScale))
        )
        let endOrigin = clampedOrigin(proposedEnd)
        desktopCarriedItem.show(
            url: url,
            near: destination.point,
            level: panel.level,
            petScale: petScale
        )

        desktopInteractionTimer?.invalidate()
        let startedAt = ProcessInfo.processInfo.systemUptime
        let biteDuration: TimeInterval = 0.52
        let pawPlantDelay: TimeInterval = renderer.visualMode == .video ? 0.10 : 0.035
        let travelDuration: TimeInterval = 1.34
        var locomotionStarted = false
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.desktopInteractionInProgress else {
                    timer.invalidate()
                    return
                }
                let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
                if elapsed < biteDuration {
                    let progress = CGFloat(elapsed / biteDuration)
                    self.desktopCarriedItem.update(
                        anchor: self.desktopCarryMouthPoint(direction: direction),
                        phase: progress,
                        biting: true
                    )
                    return
                }
                if !locomotionStarted {
                    locomotionStarted = true
                    self.setLocomotionMode(.walk, direction: direction)
                }
                let walkingElapsed = elapsed - biteDuration
                if walkingElapsed < pawPlantDelay {
                    self.desktopCarriedItem.update(
                        anchor: self.desktopCarryMouthPoint(direction: direction),
                        phase: 0,
                        biting: false
                    )
                    return
                }
                let linear = min(1, max(0, (walkingElapsed - pawPlantDelay) / travelDuration))
                let eased = linear * linear * (3 - 2 * linear)
                let origin = NSPoint(
                    x: startOrigin.x + (endOrigin.x - startOrigin.x) * eased,
                    y: startOrigin.y + (endOrigin.y - startOrigin.y) * eased
                )
                self.panel.setFrameOrigin(origin)
                self.desktopCarriedItem.update(
                    anchor: self.desktopCarryMouthPoint(direction: direction),
                    phase: CGFloat(linear),
                    biting: false
                )
                self.repositionSpeechBubble(refreshSilhouette: false)
                if linear >= 1 {
                    timer.invalidate()
                    self.finishDesktopItemCarry(name: name)
                }
            }
        }
        desktopInteractionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func desktopCarryMouthPoint(direction: CGFloat) -> NSPoint {
        let local = renderer.visibleContentRect() ?? renderer.view.bounds
        let x = direction > 0
            ? panel.frame.minX + local.maxX - local.width * 0.08
            : panel.frame.minX + local.minX + local.width * 0.08
        let y = panel.frame.minY + local.minY + local.height * 0.57
        return NSPoint(x: x, y: y)
    }

    private func finishDesktopItemCarry(name: String) {
        desktopInteractionTimer?.invalidate()
        desktopInteractionTimer = nil
        setLocomotionMode(.none, direction: locomotionDirection)
        desktopCarriedItem.hide()
        desktopInteractionInProgress = false
        freeRoamPauseUntil = ProcessInfo.processInfo.systemUptime + 2.4
        showSpeech("Hehe—I carried a safe little picture of “\(name)”. The real item never moved.")
        finishImmediateDesktopInteractionIfNeeded()
    }

    private func cancelDesktopItemInteraction() {
        desktopInteractionTimer?.invalidate()
        desktopInteractionTimer = nil
        desktopCarriedItem.hide(animated: false)
        desktopInteractionInProgress = false
    }

    private func beginImmediateDesktopInteraction(
        _ destination: DesktopInteractionService.Destination
    ) {
        panel.orderFrontRegardless()
        showPetWindow()
        registerUserActivity()
        desktopInteractionsEnabled = true
        let resumeModes = interruptCurrentActivityForProfileSwitch()
        immediateDesktopInteractionResume = resumeModes
        pendingDesktopInteraction = destination
        freeRoamTarget = reachablePanelCenterTarget(for: destination.point)
        freeRoamPauseUntil = 0
        renderer.setMirrored(actionFacing.isMirrored)
        do {
            try renderer.play(PetClips.standIdle, fadeDuration: 0.05)
        } catch {
            immediateDesktopInteractionResume = nil
            present(error)
            return
        }
        activateFreeRoaming()
        refreshAppearanceSettings()
    }

    private func finishImmediateDesktopInteractionIfNeeded() {
        guard let resumeModes = immediateDesktopInteractionResume else { return }
        immediateDesktopInteractionResume = nil
        freeRoamTimer?.invalidate()
        freeRoamTimer = nil
        freeRoamTarget = nil
        pendingDesktopInteraction = nil
        freeRoamPauseUntil = 0
        setLocomotionMode(.none, direction: locomotionDirection)
        if let reportPath = ProcessInfo.processInfo.environment["FURBALL_IMMEDIATE_INTERACTION_QA_REPORT"],
           !reportPath.isEmpty {
            if immediateInteractionQAObservedKinds == ["trash"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                    self?.playWithDesktopItemImmediately()
                }
                return
            }
            let pass = immediateInteractionQAObservedKinds == ["trash", "desktop-item"]
            writeImmediateInteractionQAReport(
                path: reportPath,
                pass: pass,
                reason: pass ? "completed" : "unexpected-sequence"
            )
            return
        }
        if resumeModes.follow, followCursor {
            beginCursorFollowing()
        } else if resumeModes.roam, freeRoamEnabled {
            beginFreeRoaming()
        } else {
            restartAutonomy()
        }
    }

    private func inspectTrashImmediately() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        beginImmediateDesktopInteraction(desktopInteractionService.trashDestination(in: screen))
    }

    private func playWithDesktopItemImmediately() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        guard let destination = desktopInteractionService.desktopItemDestination(in: screen) else {
            panel.orderFrontRegardless()
            showSpeech("I couldn’t find a desktop item to play with yet.")
            if let reportPath = ProcessInfo.processInfo.environment["FURBALL_IMMEDIATE_INTERACTION_QA_REPORT"],
               !reportPath.isEmpty {
                writeImmediateInteractionQAReport(
                    path: reportPath,
                    pass: false,
                    reason: "no-desktop-item"
                )
            }
            return
        }
        beginImmediateDesktopInteraction(destination)
    }

    private func recordImmediateInteractionQA(kind: String) {
        guard ProcessInfo.processInfo.environment["FURBALL_IMMEDIATE_INTERACTION_QA_REPORT"] != nil,
              !immediateInteractionQAObservedKinds.contains(kind) else { return }
        immediateInteractionQAObservedKinds.append(kind)
    }

    private func writeImmediateInteractionQAReport(path: String, pass: Bool, reason: String) {
        guard RuntimeSafetyPolicy.permitsDeveloperQAFileWrites else { return }
        guard !FileManager.default.fileExists(atPath: path) else { return }
        let report: [String: Any] = [
            "pass": pass,
            "reason": reason,
            "observed": immediateInteractionQAObservedKinds,
            "desktopInteractionsEnabled": desktopInteractionsEnabled,
            "petVisible": panel.isVisible,
            "posture": posture.rawValue,
            "isTransitioning": isTransitioning,
            "freeRoamEnabled": freeRoamEnabled,
            "hasImmediateState": immediateDesktopInteractionResume != nil,
            "hasFreeRoamTimer": freeRoamTimer?.isValid == true,
            "hasPendingDestination": pendingDesktopInteraction != nil,
            "movementTicks": immediateInteractionQAMovementTicks,
            "targetX": freeRoamTarget?.x ?? NSNull(),
            "targetY": freeRoamTarget?.y ?? NSNull(),
            "centerX": panel.frame.midX,
            "centerY": panel.frame.midY,
            "velocityX": locomotionVelocity.x,
            "velocityY": locomotionVelocity.y
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            NSLog("Furball2D immediate interaction QA failed: %@", error.localizedDescription)
        }
        if ProcessInfo.processInfo.environment["FURBALL_IMMEDIATE_INTERACTION_QA_EXIT"] == "1" {
            NSApp.terminate(nil)
        }
    }

    @discardableResult
    private func beginTreatChase(at requestedPoint: NSPoint? = nil) -> Bool {
        guard renderer.visualMode == .images,
              panel.isVisible,
              !isTransitioning,
              treatTarget == nil else { return false }
        registerUserActivity()
        resumeFollowingAfterTreat = followCursor
        resumeRoamingAfterTreat = freeRoamEnabled
        cursorFollowTimer?.invalidate()
        cursorFollowTimer = nil
        freeRoamTimer?.invalidate()
        freeRoamTimer = nil
        behaviorTimer?.invalidate()
        stopPatrol()

        let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
        treatTarget = desktopTreat.show(
            at: requestedPoint ?? NSEvent.mouseLocation,
            level: panel.level,
            in: visibleFrame
        )
        showSpeech(appLanguage.treatChaseStarted)
        treatLastSampleTime = ProcessInfo.processInfo.systemUptime
        treatDeadline = treatLastSampleTime + 18
        treatChaseTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateTreatChase() }
        }
        treatChaseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        continueToStandForMovement()
        return true
    }

    private func updateTreatChase() {
        guard let target = treatTarget else { return }
        guard panel.isVisible, !isDragging else {
            cancelTreatChase(resume: true)
            return
        }
        guard posture == .stand, !isTransitioning else {
            if !isTransitioning { continueToStandForMovement() }
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard now < treatDeadline else {
            if behaviorQAReportPath != nil { behaviorQAOutcome = "timed-out" }
            cancelTreatChase(resume: true)
            showSpeech(appLanguage.treatTimedOut)
            if let reportPath = behaviorQAReportPath {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                    self?.writeBehaviorQAReport(to: reportPath)
                }
            }
            return
        }
        let deltaTime = min(1.0 / 20.0, max(1.0 / 120.0, now - treatLastSampleTime))
        treatLastSampleTime = now
        let contact = petContactPoint(toward: target)
        let contactDistance = hypot(target.x - contact.x, target.y - contact.y)
        let contactRadius = 24 * petScale
        guard contactDistance > contactRadius else {
            finishTreatChase()
            return
        }
        let movementTarget = panelCenterTarget(bringingPetTo: target)
        let centerDistance = hypot(movementTarget.x - panel.frame.midX, movementTarget.y - panel.frame.midY)
        updateMovement(
            toward: movementTarget,
            demand: max(180, centerDistance * 1.15),
            deadZone: 8 * petScale,
            now: now,
            deltaTime: deltaTime
        )
    }

    private func petContactPoint(toward target: NSPoint) -> NSPoint {
        let local = renderer.visibleContentRect() ?? renderer.view.bounds
        let targetLocal = NSPoint(x: target.x - panel.frame.minX, y: target.y - panel.frame.minY)
        return NSPoint(
            x: panel.frame.minX + min(local.maxX, max(local.minX, targetLocal.x)),
            y: panel.frame.minY + min(local.maxY, max(local.minY, targetLocal.y))
        )
    }

    private func panelCenterTarget(bringingPetTo target: NSPoint) -> NSPoint {
        let local = renderer.visibleContentRect() ?? renderer.view.bounds
        let currentCenter = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let horizontalDirection = target.x - currentCenter.x
        let verticalDirection = target.y - currentCenter.y
        let localContact = NSPoint(
            x: horizontalDirection >= 0 ? local.maxX : local.minX,
            y: abs(verticalDirection) > abs(horizontalDirection) * 0.72
                ? (verticalDirection >= 0 ? local.maxY : local.minY)
                : min(local.maxY, max(local.minY, target.y - panel.frame.minY))
        )
        return NSPoint(
            x: target.x - localContact.x + panel.frame.width / 2,
            y: target.y - localContact.y + panel.frame.height / 2
        )
    }

    private func reachablePanelCenterTarget(for desktopPoint: NSPoint) -> NSPoint {
        var target = panelCenterTarget(bringingPetTo: desktopPoint)
        guard let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else {
            return target
        }
        let horizontal = horizontalMovementLimits(in: visibleFrame)
        let vertical = verticalMovementLimits(in: visibleFrame)
        target.x = min(
            horizontal.maximum + panel.frame.width / 2,
            max(horizontal.minimum + panel.frame.width / 2, target.x)
        )
        target.y = min(
            vertical.maximum + panel.frame.height / 2,
            max(vertical.minimum + panel.frame.height / 2, target.y)
        )
        return target
    }

    private func finishTreatChase() {
        if behaviorQAReportPath != nil { behaviorQAOutcome = "completed" }
        treatChaseTimer?.invalidate()
        treatChaseTimer = nil
        treatTarget = nil
        treatDeadline = 0
        desktopTreat.hide()
        setLocomotionMode(.none, direction: locomotionDirection)
        remember(
            .treat,
            text: "you tossed me a delicious treat",
            salience: 0.90,
            energy: 0.10,
            curiosity: -0.08,
            affinity: 0.045
        )
        showSpeech(appLanguage.treatFound)
        let completion: () -> Void = { [weak self] in
            self?.resumeAfterTreatChase()
        }
        if let action = PetAssetCatalog.imageActions.first(where: { $0.id == "gesture.sniff" }) {
            performImageAction(action, completion: completion)
        } else {
            completion()
        }
        if let reportPath = behaviorQAReportPath {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.writeBehaviorQAReport(to: reportPath)
            }
        }
    }

    private func resumeAfterTreatChase() {
        if behaviorQAReportPath != nil {
            resumeFollowingAfterTreat = false
            resumeRoamingAfterTreat = false
            return
        }
        if resumeFollowingAfterTreat, followCursor {
            beginCursorFollowing()
        } else if resumeRoamingAfterTreat, freeRoamEnabled {
            beginFreeRoaming()
        } else {
            restartAutonomy()
        }
        resumeFollowingAfterTreat = false
        resumeRoamingAfterTreat = false
    }

    private func cancelTreatChase(resume: Bool) {
        guard treatTarget != nil else { return }
        if behaviorQAReportPath != nil, behaviorQAOutcome == nil {
            behaviorQAOutcome = "cancelled"
        }
        treatChaseTimer?.invalidate()
        treatChaseTimer = nil
        treatTarget = nil
        treatDeadline = 0
        desktopTreat.hide()
        setLocomotionMode(.none, direction: locomotionDirection)
        if resume { resumeAfterTreatChase() }
    }

    private func makeRandomRoamTarget() -> NSPoint? {
        let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        guard let visibleFrame else { return nil }
        let horizontalLimits = horizontalMovementLimits(in: visibleFrame)
        let verticalLimits = verticalMovementLimits(in: visibleFrame)
        let currentCenter = NSPoint(x: panel.frame.midX, y: panel.frame.midY)

        var candidate = currentCenter
        for _ in 0..<8 {
            let origin = NSPoint(
                x: CGFloat.random(in: horizontalLimits.minimum...horizontalLimits.maximum),
                y: CGFloat.random(in: verticalLimits.minimum...verticalLimits.maximum)
            )
            candidate = NSPoint(x: origin.x + panel.frame.width / 2, y: origin.y + panel.frame.height / 2)
            if hypot(candidate.x - currentCenter.x, candidate.y - currentCenter.y) > 210 * petScale {
                break
            }
        }
        return candidate
    }

    @discardableResult
    private func updateMovement(
        toward target: NSPoint,
        demand: CGFloat,
        deadZone: CGFloat,
        now: TimeInterval,
        deltaTime: TimeInterval
    ) -> MovementBoundaryCollision {
        let deltaX = target.x - panel.frame.midX
        let deltaY = target.y - panel.frame.midY
        let distance = hypot(deltaX, deltaY)
        let desiredMode = desiredLocomotionMode(distance: distance, demand: demand, deadZone: deadZone)

        if distance > deadZone + 18, abs(deltaX) > 18 * petScale {
            locomotionDirection = deltaX >= 0 ? 1 : -1
            actionFacing = locomotionDirection > 0 ? .right : .left
        }

        let minimumModeInterval = renderer.visualMode == .video ? 0.84 : 0.32
        let requiredDwell = renderer.visualMode == .video ? 0.30 : 0.12
        let canChangeMode = now - lastLocomotionChangeTime >= minimumModeInterval
            && now >= locomotionModeLockUntil
            && !renderer.isVideoTransitionActive
            || desiredMode == .none
            || locomotionMode == .none
        if desiredMode == locomotionMode {
            pendingLocomotionMode = nil
        } else if desiredMode == .none || locomotionMode == .none {
            pendingLocomotionMode = nil
            setLocomotionMode(desiredMode, direction: locomotionDirection)
        } else if pendingLocomotionMode != desiredMode {
            pendingLocomotionMode = desiredMode
            pendingLocomotionSince = now
        } else if canChangeMode, now - pendingLocomotionSince >= requiredDwell {
            pendingLocomotionMode = nil
            setLocomotionMode(desiredMode, direction: locomotionDirection)
        }
        if locomotionMode != .none {
            renderer.setMirrored(actionFacing.isMirrored)
        }

        let translationProgress: CGFloat
        if locomotionMode == .none {
            translationProgress = 1
        } else if now < locomotionTranslationStartTime {
            locomotionVelocity = .zero
            return MovementBoundaryCollision()
        } else {
            let rampDuration = max(
                0.01,
                renderer.visualMode == .video
                    ? locomotionMode.startTranslationRampDuration
                    : 0.07
            )
            let linearProgress = min(1, max(0, (now - locomotionTranslationStartTime) / rampDuration))
            translationProgress = CGFloat(linearProgress * linearProgress * (3 - 2 * linearProgress))
        }

        let scaleSpeed = min(1.16, max(0.82, sqrt(petScale)))
        let targetSpeed = locomotionMode.pointsPerSecond * scaleSpeed * translationProgress
        let targetVelocity: NSPoint
        if locomotionMode == .none || distance < 1 {
            targetVelocity = .zero
        } else {
            targetVelocity = NSPoint(
                x: deltaX / distance * targetSpeed,
                y: deltaY / distance * targetSpeed
            )
        }
        let velocityResponse = locomotionMode == .none ? 18.0 : 12.0
        let response = min(1, deltaTime * velocityResponse)
        locomotionVelocity.x += (targetVelocity.x - locomotionVelocity.x) * response
        locomotionVelocity.y += (targetVelocity.y - locomotionVelocity.y) * response

        guard hypot(locomotionVelocity.x, locomotionVelocity.y) > 0.25 else {
            locomotionVelocity = .zero
            return MovementBoundaryCollision()
        }

        let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let horizontalLimits = horizontalMovementLimits(in: visibleFrame)
        let verticalLimits = verticalMovementLimits(in: visibleFrame)
        var origin = preciseLocomotionOrigin ?? panel.frame.origin
        let proposedX = origin.x + locomotionVelocity.x * deltaTime
        let proposedY = origin.y + locomotionVelocity.y * deltaTime
        var collision = MovementBoundaryCollision()
        if proposedX < horizontalLimits.minimum { collision.horizontalWall = -1 }
        else if proposedX > horizontalLimits.maximum { collision.horizontalWall = 1 }
        if proposedY < verticalLimits.minimum { collision.verticalWall = -1 }
        else if proposedY > verticalLimits.maximum { collision.verticalWall = 1 }
        origin.x = min(horizontalLimits.maximum, max(horizontalLimits.minimum, proposedX))
        origin.y = min(verticalLimits.maximum, max(verticalLimits.minimum, proposedY))

        if origin.x != proposedX { locomotionVelocity.x = 0 }
        if origin.y != proposedY { locomotionVelocity.y = 0 }
        preciseLocomotionOrigin = origin
        panel.setFrameOrigin(origin)
        repositionSpeechBubble(refreshSilhouette: false)
        return collision
    }

    private func desiredLocomotionMode(
        distance: CGFloat,
        demand: CGFloat,
        deadZone: CGFloat
    ) -> LocomotionMode {
        guard distance > deadZone else { return .none }

        let desired: LocomotionMode
        switch locomotionMode {
        case .none:
            if demand > 650 || distance > 520 * petScale { desired = .fastRun }
            else if demand > 260 || distance > 270 * petScale { desired = .slowRun }
            else { desired = .walk }
        case .walk:
            if demand > 700 || distance > 560 * petScale { desired = .fastRun }
            else if demand > 320 || distance > 300 * petScale { desired = .slowRun }
            else { desired = .walk }
        case .slowRun:
            if demand > 720 || distance > 580 * petScale { desired = .fastRun }
            else if demand < 175, distance < 220 * petScale { desired = .walk }
            else { desired = .slowRun }
        case .fastRun:
            desired = demand < 430 && distance < 390 * petScale ? .slowRun : .fastRun
        }

        if petMind.state.energy < 0.18 { return .walk }
        if petMind.state.energy < 0.38, desired == .fastRun { return .slowRun }
        return desired
    }

    private func setLocomotionMode(_ newMode: LocomotionMode, direction: CGFloat) {
        guard newMode != locomotionMode else { return }
        let previousMode = locomotionMode
        locomotionMode = newMode
        if newMode != .none { isUsingImageFacing = false }
        locomotionDirection = direction
        locomotionGeneration += 1
        pendingLocomotionMode = nil
        let generation = locomotionGeneration
        let now = ProcessInfo.processInfo.systemUptime
        lastLocomotionChangeTime = now
        locomotionModeLockUntil = newMode == .none
            ? 0
            : now + (renderer.visualMode == .video ? 0.78 : 0.24)
        if previousMode == .none, newMode != .none {
            locomotionVelocity = .zero
            preciseLocomotionOrigin = panel.frame.origin
            let translationDelay = renderer.visualMode == .video ? newMode.startTranslationDelay : 0
            locomotionTranslationStartTime = now + translationDelay
        } else if newMode == .none {
            locomotionTranslationStartTime = 0
            locomotionVelocity = .zero
            preciseLocomotionOrigin = nil
        }
        speechBubble.updateAppearance(mood: speechMood)

        do {
            if newMode == .none {
                if renderer.visualMode == .images {
                    // Atlas gait stop cells are still running poses. A short
                    // dissolve directly to planted idle reads as an immediate
                    // arrival instead of continuing to run in place.
                    try renderer.play(PetClips.standIdle, fadeDuration: 0.075)
                    return
                }
                guard let stopClip = previousMode.clips?.stop else {
                    playIdle(.stand)
                    return
                }
                try renderer.play(stopClip, fadeDuration: 0.09) { [weak self] in
                    guard let self, self.locomotionGeneration == generation,
                          self.locomotionMode == .none,
                          !self.isTransitioning else { return }
                    self.playIdle(.stand)
                }
                return
            }

            guard let clips = newMode.clips else { return }
            actionFacing = direction > 0 ? .right : .left
            renderer.setMirrored(actionFacing.isMirrored)
            if previousMode == .none {
                try renderer.play(clips.start, fadeDuration: 0.12) { [weak self] in
                    guard let self, self.locomotionGeneration == generation,
                          self.locomotionMode == newMode else { return }
                    self.playLocomotionLoop(newMode, direction: self.locomotionDirection)
                }
                if renderer.visualMode == .video {
                    // Warm the loop decoder while the authored start footage is
                    // playing. The held first frame is released only at the
                    // matching start port, eliminating the old cold-decoder pause.
                    try renderer.prepareVideo(clips.loop)
                }
            } else {
                try renderer.play(clips.loop, fadeDuration: renderer.visualMode == .video ? 0.075 : 0.10)
            }
        } catch {
            locomotionMode = .none
            locomotionVelocity = .zero
            present(error)
        }
    }

    private func playLocomotionLoop(_ mode: LocomotionMode, direction: CGFloat) {
        guard let loopClip = mode.clips?.loop else { return }
        actionFacing = direction > 0 ? .right : .left
        renderer.setMirrored(actionFacing.isMirrored)
        do {
            try renderer.play(loopClip, fadeDuration: 0.12)
        } catch {
            locomotionMode = .none
            locomotionVelocity = .zero
            present(error)
        }
    }

    private var movementRefreshRate: Double {
        let screenFPS = panel.screen?.maximumFramesPerSecond
            ?? NSScreen.main?.maximumFramesPerSecond
            ?? 60
        return Double(min(120, max(60, screenFPS)))
    }

    private func requestSleep() {
        behaviorEpoch += 1
        let epoch = behaviorEpoch
        behaviorTimer?.invalidate()
        forceSleep(epoch: epoch)
    }

    private func forceSleep(epoch: Int) {
        guard behaviorEpoch == epoch, !isDragging else { return }
        if isTransitioning {
            schedule(after: 0.5, epoch: epoch, requiresAutoBehavior: false) { [weak self] in
                self?.forceSleep(epoch: epoch)
            }
            return
        }

        stopPatrol()
        switch posture {
        case .stand:
            playTransition(PetClips.sitDown) { [weak self] in
                self?.forceSleep(epoch: epoch)
            }
        case .sit:
            playTransition(PetClips.sitToLie) { [weak self] in
                self?.forceSleep(epoch: epoch)
            }
        case .lie:
            playTransition(PetClips.lieToSleep) { [weak self] in
                guard let self, self.autoBehavior else { return }
                self.scheduleWake(epoch: epoch)
            }
        case .sleep:
            if autoBehavior { scheduleWake(epoch: epoch) }
        }
    }

    private func restartAutonomy() {
        behaviorEpoch += 1
        let epoch = behaviorEpoch
        behaviorTimer?.invalidate()
        stopPatrol()
        guard autoBehavior, !followCursor, !freeRoamEnabled else { return }
        if posture == .sleep {
            scheduleWake(epoch: epoch)
        } else {
            schedule(after: 12, epoch: epoch) { [weak self] in self?.settleDown(epoch: epoch) }
        }
    }

    private func prepareStandForImageTurn(resumeFollowing: Bool, resumeFreeRoaming: Bool) {
        guard !isTransitioning else { return }
        switch posture {
        case .stand:
            actionFacing = .left
            if isUsingImageFacing, !usesDirectionalLook, !imageFacingMatchesActionProfile {
                returnImageFacingToActionProfile { [weak self] in
                    self?.playImageTurn(
                        resumeFollowing: resumeFollowing,
                        resumeFreeRoaming: resumeFreeRoaming
                    )
                }
            } else {
                playImageTurn(resumeFollowing: resumeFollowing, resumeFreeRoaming: resumeFreeRoaming)
            }
        case .sit:
            playTransition(PetClips.sitToLie) { [weak self] in
                self?.prepareStandForImageTurn(
                    resumeFollowing: resumeFollowing,
                    resumeFreeRoaming: resumeFreeRoaming
                )
            }
        case .lie:
            playTransition(PetClips.lieToSleep) { [weak self] in
                self?.prepareStandForImageTurn(
                    resumeFollowing: resumeFollowing,
                    resumeFreeRoaming: resumeFreeRoaming
                )
            }
        case .sleep:
            playTransition(PetClips.sleepToStand) { [weak self] in
                self?.prepareStandForImageTurn(
                    resumeFollowing: resumeFollowing,
                    resumeFreeRoaming: resumeFreeRoaming
                )
            }
        }
    }

    private func playImageTurn(resumeFollowing: Bool, resumeFreeRoaming: Bool) {
        locomotionGeneration += 1
        locomotionMode = .none
        locomotionVelocity = .zero
        pendingLocomotionMode = nil
        actionFacing = .left
        facingView = .leftProfile
        lookDirection = .left
        pendingFacingView = nil
        isUsingImageFacing = false
        renderer.setMirrored(false)
        isTransitioning = true
        let profileGeneration = profileSwitchGeneration
        showSpeech(appLanguage.imageTurnGreeting)
        speechBubble.updateAppearance(mood: speechMood)

        do {
            try renderer.play(PetClips.lookAroundImages, fadeDuration: 0.10) { [weak self] in
                guard let self, self.profileSwitchGeneration == profileGeneration else { return }
                self.isTransitioning = false
                self.playIdle(.stand)
                if resumeFollowing, self.followCursor {
                    self.beginCursorFollowing()
                } else if resumeFreeRoaming, self.freeRoamEnabled {
                    self.beginFreeRoaming()
                } else {
                    self.restartAutonomy()
                }
            }
        } catch {
            isTransitioning = false
            if resumeFollowing, followCursor { beginCursorFollowing() }
            else if resumeFreeRoaming, freeRoamEnabled { beginFreeRoaming() }
            else { restartAutonomy() }
            present(error)
        }
    }

    private func switchToStandIdle() {
        guard posture == .stand else { return }
        isUsingImageFacing = false
        facingView = actionFacing.profileView
        lookDirection = actionProfileLookDirection
        pendingFacingView = nil
        renderer.setMirrored(actionFacing.isMirrored)
        do {
            try renderer.play(PetClips.standIdle, fadeDuration: 0.08)
        } catch {
            present(error)
        }
    }

    private func setScale(_ scale: CGFloat) {
        let clampedScale = min(Self.maximumScale, max(Self.minimumScale, scale))
        let oldFrame = panel.frame
        petScale = clampedScale
        let newSize = NSSize(
            width: Self.basePetSize.width * clampedScale,
            height: Self.basePetSize.height * clampedScale
        )
        let newOrigin = NSPoint(x: oldFrame.midX - newSize.width / 2, y: oldFrame.minY)
        panel.setFrame(NSRect(origin: clampedOrigin(newOrigin, panelSize: newSize), size: newSize), display: true)
        if groupPlayEnabled {
            try? groupPlayController.start(petIDs: groupPetIDs, scale: petScale, level: panel.level)
            panel.orderOut(nil)
        }
        repositionSpeechBubble(resetSilhouette: true)
    }

    private func present(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = appLanguage.problemTitle
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    func importPetPack(at url: URL) {
        do {
            let summary = try PetPackLibraryManager.installPack(from: url)
            rebuildMenu()
            refreshAppearanceSettings()
            _ = switchPet(to: summary.id)
            let alert = NSAlert()
            alert.messageText = appLanguage.importSuccessTitle
            alert.informativeText = appLanguage.importedPetMessage(summary.name)
            alert.addButton(withTitle: "OK")
            alert.runModal()
        } catch PetPackLibraryError.petAlreadyExists(let name) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Replace \(name)?"
            alert.informativeText = "The existing pet pack will be replaced by this version."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            do {
                let summary = try PetPackLibraryManager.installPack(from: url, replacingExisting: true)
                rebuildMenu()
                refreshAppearanceSettings()
                _ = switchPet(to: summary.id)
            } catch {
                present(error)
            }
        } catch {
            present(error)
        }
    }

    private func performImageAction(_ action: PetImageAction, completion: (() -> Void)? = nil) {
        guard renderer.visualMode == .images,
              posture == .stand,
              !isTransitioning,
              locomotionMode == .none,
              patrolTimer == nil else { return }

        pendingFacingView = nil
        isUsingImageFacing = false
        isTransitioning = true
        let profileGeneration = profileSwitchGeneration
        renderer.setMirrored(false)
        speechBubble.updateAppearance(mood: speechMood)
        let clip = PetClips.imageAction(action)
        do {
            try renderer.play(clip, fadeDuration: 0.10) { [weak self] in
                guard let self, self.profileSwitchGeneration == profileGeneration else { return }
                self.posture = clip.resultingPosture
                self.isTransitioning = false
                self.playIdle(clip.resultingPosture)
                completion?()
            }
        } catch {
            isTransitioning = false
            present(error)
        }
    }

    @objc private func interactFromMenu() {
        panel.orderFrontRegardless()
        registerUserActivity()
        speakRandomly()
        if renderer.visualMode == .images,
           posture == .stand,
           !followCursor,
           !freeRoamEnabled,
           let action = PetAssetCatalog.imageActions
            .filter({ $0.id == "gesture.wave" || $0.id == "gesture.jump" })
            .randomElement() {
            performImageAction(action)
        } else if !followCursor, !freeRoamEnabled {
            advanceBehavior()
        }
    }

    @objc private func speakFromMenu() {
        panel.orderFrontRegardless()
        speakRandomly()
    }

    @objc private func throwTreatFromMenu() {
        panel.orderFrontRegardless()
        beginTreatChase()
    }

    @objc private func performCuteActionFromMenu(_ sender: NSMenuItem) {
        guard let actionID = sender.representedObject as? String,
              let action = PetAssetCatalog.imageActions.first(where: { $0.id == actionID }) else { return }
        panel.orderFrontRegardless()
        registerUserActivity()
        remember(
            .play,
            text: "you asked me to perform a cute trick",
            salience: 0.58,
            energy: -0.012,
            affinity: 0.012
        )
        performImageAction(action)
    }

    @objc private func imageTurnFromMenu() {
        panel.orderFrontRegardless()
        guard !isTransitioning else {
            showSpeech(appLanguage.imageTurnBusy)
            return
        }

        behaviorEpoch += 1
        behaviorTimer?.invalidate()
        stopPatrol()
        let resumeFollowing = followCursor
        let resumeFreeRoaming = freeRoamEnabled
        cursorFollowTimer?.invalidate()
        cursorFollowTimer = nil
        freeRoamTimer?.invalidate()
        freeRoamTimer = nil
        smoothedCursorSpeed = 0
        prepareStandForImageTurn(
            resumeFollowing: resumeFollowing,
            resumeFreeRoaming: resumeFreeRoaming
        )
    }

    @objc private func sleepFromMenu() {
        panel.orderFrontRegardless()
        cancelTreatChase(resume: false)
        if followCursor {
            followCursor = false
            stopCursorFollowing()
        }
        if freeRoamEnabled {
            freeRoamEnabled = false
            stopFreeRoaming()
        }
        showSpeech(appLanguage.sleepConfirmation)
        requestSleep()
    }

    @objc private func showVisualSettings() {
        let controller: UnifiedSettingsWindowController
        if let existing = settingsWindowController {
            controller = existing
            controller.update(snapshot: appearanceSettingsSnapshot(), language: appLanguage)
        } else {
            controller = UnifiedSettingsWindowController(
                snapshot: appearanceSettingsSnapshot(),
                language: appLanguage
            )
            controller.onAppearanceSelected = { [weak self] id in
                self?.switchAppearance(to: id) ?? false
            }
            controller.onCrossfadeChanged = { [weak self] enabled in
                guard let self, self.renderer.crossfadeEnabled != enabled else { return }
                self.renderer.crossfadeEnabled = enabled
                self.rebuildMenu()
            }
            controller.onFollowCursorChanged = { [weak self] enabled in
                guard let self, self.followCursor != enabled else { return }
                self.toggleCursorFollowing()
                self.refreshAppearanceSettings()
            }
            controller.onFreeRoamChanged = { [weak self] enabled in
                guard let self, self.freeRoamEnabled != enabled else { return }
                self.toggleFreeRoaming()
                self.refreshAppearanceSettings()
            }
            controller.onDirectionalLookChanged = { [weak self] enabled in
                guard let self, self.imageFacingEnabled != enabled else { return }
                self.toggleImageFacing()
            }
            controller.onDesktopInteractionsChanged = { [weak self] enabled in
                guard let self else { return }
                self.desktopInteractionsEnabled = enabled
                if !enabled {
                    self.cancelDesktopItemInteraction()
                    self.setLocomotionMode(.none, direction: self.locomotionDirection)
                }
                self.refreshAppearanceSettings()
            }
            controller.onInspectTrashNow = { [weak self] in
                self?.inspectTrashImmediately()
            }
            controller.onPlayWithDesktopItemNow = { [weak self] in
                self?.playWithDesktopItemImmediately()
            }
            controller.onGroupPlayChanged = { [weak self] enabled in
                self?.setGroupPlay(enabled)
            }
            controller.onGroupPetSelectionChanged = { [weak self] ids in
                guard let self else { return }
                self.groupPetIDs = ids.intersection(PetAssetCatalog.imageCapablePetIDs)
                if self.groupPlayEnabled { self.activateGroupPlay() }
                self.refreshAppearanceSettings()
            }
            controller.onAlwaysOnTopChanged = { [weak self] enabled in
                guard let self else { return }
                self.panel.level = enabled ? .floating : .normal
                UserDefaults.standard.set(enabled, forKey: PreferenceKey.alwaysOnTop)
                self.speechBubble.setLevel(self.panel.level)
                self.refreshAppearanceSettings()
            }
            controller.onPetScaleChanged = { [weak self] scale in
                self?.setScale(scale)
                self?.refreshAppearanceSettings()
            }
            controller.onPassThroughChanged = { [weak self] enabled in
                guard let self else { return }
                self.fullPassThrough = enabled
                self.updateClickThrough()
                self.refreshAppearanceSettings()
            }
            controller.onAutoBehaviorChanged = { [weak self] enabled in
                guard let self, self.autoBehavior != enabled else { return }
                self.toggleAutoBehavior()
                self.refreshAppearanceSettings()
            }
            controller.onSpeechBubblesChanged = { [weak self] enabled in
                guard let self else { return }
                self.speechBubblesEnabled = enabled
                if enabled {
                    self.scheduleNextSpeech(after: 0.8)
                } else {
                    self.speechTimer?.invalidate()
                    self.hideSpeechBubble()
                }
                self.refreshAppearanceSettings()
            }
            controller.onTalkativenessChanged = { [weak self] value in
                guard let self else { return }
                self.talkativeness = min(1, max(0, value))
                self.scheduleNextSpeech()
            }
            controller.onPreviewSpeech = { [weak self] in
                guard let self else { return }
                self.showSpeech("I’m right here. Shall we explore the desktop together?")
            }
            controller.onSelectPet = { [weak self] id in
                self?.switchPet(to: id) ?? false
            }
            controller.onLibraryChanged = { [weak self] in
                guard let self else { return }
                self.rebuildMenu()
                self.refreshAppearanceSettings()
            }
            settingsWindowController = controller
        }
        let qaSection = ProcessInfo.processInfo.environment["FURBALL_SETTINGS_SECTION"]
            .flatMap(Int.init)
            .flatMap(UnifiedSettingsWindowController.Section.init(rawValue:))
        controller.present(section: qaSection ?? .general)
    }

    @objc private func showPetLibrary() {
        let controller: UnifiedSettingsWindowController
        if let existing = settingsWindowController {
            controller = existing
            controller.update(snapshot: appearanceSettingsSnapshot(), language: appLanguage)
        } else {
            showVisualSettings()
            settingsWindowController?.present(section: .library)
            return
        }
        controller.present(section: .library)
    }

    private func showPetCreatorForQA() {
        if settingsWindowController == nil {
            showVisualSettings()
        }
        settingsWindowController?.update(snapshot: appearanceSettingsSnapshot(), language: appLanguage)
        settingsWindowController?.present(section: .creator)
    }

    private func appearanceSettingsSnapshot() -> AppearanceSettingsSnapshot {
        AppearanceSettingsSnapshot(
            appearances: PetAssetCatalog.availableAppearances,
            pets: PetAssetCatalog.availablePets,
            activePetID: PetAssetCatalog.activePet?.id ?? "",
            selectedAppearanceID: PetAssetCatalog.activeAppearance.id,
            language: appLanguage,
            crossfadeEnabled: renderer.crossfadeEnabled,
            followCursor: followCursor,
            freeRoam: freeRoamEnabled,
            directionalLook: imageFacingEnabled,
            desktopInteractions: desktopInteractionsEnabled,
            alwaysOnTop: panel.level == .floating,
            petScale: petScale,
            fullPassThrough: fullPassThrough,
            autoBehavior: autoBehavior,
            speechBubbles: speechBubblesEnabled,
            talkativeness: talkativeness,
            canChangeAppearance: true,
            groupPlayEnabled: groupPlayEnabled,
            groupPetIDs: groupPetIDs
        )
    }

    private func setGroupPlay(_ enabled: Bool) {
        guard groupPlayEnabled != enabled else { return }
        groupPlayEnabled = enabled
        if enabled {
            activateGroupPlay()
        } else {
            deactivateGroupPlay()
        }
        rebuildMenu()
        refreshAppearanceSettings()
    }

    private func activateGroupPlay() {
        guard groupPlayEnabled else { return }
        let validIDs = groupPetIDs.intersection(PetAssetCatalog.imageCapablePetIDs)
        guard !validIDs.isEmpty else {
            groupPlayEnabled = false
            refreshAppearanceSettings()
            return
        }
        _ = interruptCurrentActivityForProfileSwitch()
        panel.orderOut(nil)
        do {
            try groupPlayController.start(petIDs: validIDs, scale: petScale, level: panel.level)
            rebuildMenu()
        } catch {
            groupPlayEnabled = false
            groupPlayController.stop()
            showPetWindow()
            try? renderer.play(PetClips.standIdle, fadeDuration: 0.05)
            restartAutonomy()
            present(error)
        }
    }

    private func deactivateGroupPlay() {
        groupPlayController.stop()
        showPetWindow()
        posture = .stand
        try? renderer.play(PetClips.standIdle, fadeDuration: 0.06)
        rebuildMenu()
        restartAutonomy()
    }

    private func refreshAppearanceSettings() {
        settingsWindowController?.update(snapshot: appearanceSettingsSnapshot(), language: appLanguage)
    }

    @discardableResult
    private func switchAppearance(to id: String) -> Bool {
        let previous = PetAssetCatalog.activeAppearance
        guard previous.id != id else { return true }
        guard let next = PetAssetCatalog.availableAppearances.first(where: { $0.id == id }),
              PetAssetCatalog.availableAppearances.contains(where: { $0.id == id }) else { return false }

        // A direct appearance choice is authoritative. Group Play has its own
        // image-only renderers, so leaving it active would hide the selected
        // Nina representation and make a successful click look like a no-op.
        if groupPlayEnabled {
            groupPlayEnabled = false
            groupPlayController.stop()
            showPetWindow()
        }
        let resumeModes = interruptCurrentActivityForProfileSwitch()
        guard PetAssetCatalog.selectAppearance(id: id) else { return false }

        do {
            videoAnimationsEnabled = next.kind == .continuousVideo
            try renderer.setVisualMode(
                next.kind.visualMode,
                replaying: PetClips.standIdle,
                forceReload: true
            )
            if groupPlayEnabled {
                try groupPlayController.start(
                    petIDs: groupPetIDs,
                    scale: petScale,
                    level: panel.level
                )
                panel.orderOut(nil)
            }
            renderer.setMirrored(actionFacing.isMirrored)
            repositionSpeechBubble(resetSilhouette: true)
            remember(
                .appearance,
                text: "I changed into my “\(next.title(for: .english))” look",
                salience: 0.42
            )
            rebuildMenu()
            refreshAppearanceSettings()
            showSpeech(appLanguage.appearanceChanged(next.title(for: appLanguage)))
            resumeAfterProfileSwitch(resumeModes)
            return true
        } catch {
            _ = PetAssetCatalog.selectAppearance(id: previous.id)
            videoAnimationsEnabled = previous.kind == .continuousVideo
            try? renderer.setVisualMode(
                previous.kind.visualMode,
                replaying: PetClips.standIdle,
                forceReload: true
            )
            rebuildMenu()
            refreshAppearanceSettings()
            resumeAfterProfileSwitch(resumeModes)
            present(error)
            return false
        }
    }

    @discardableResult
    private func switchPet(to id: String) -> Bool {
        guard let previousPet = PetAssetCatalog.activePet else { return false }
        guard previousPet.id != id else { return true }
        let previousAppearance = PetAssetCatalog.activeAppearance
        guard PetAssetCatalog.availablePets.contains(where: { $0.id == id }) else { return false }
        // An explicit pet selection is authoritative. Group Play renders its
        // own companions and otherwise hides the primary pet panel.
        if groupPlayEnabled {
            groupPlayEnabled = false
            groupPlayController.stop()
            showPetWindow()
        }
        let resumeModes = interruptCurrentActivityForProfileSwitch()
        guard PetAssetCatalog.selectPet(id: id), let nextPet = PetAssetCatalog.activePet else { return false }
        let nextAppearance = PetAssetCatalog.activeAppearance

        do {
            videoAnimationsEnabled = nextAppearance.kind == .continuousVideo
            try renderer.setVisualMode(
                nextAppearance.kind.visualMode,
                replaying: PetClips.standIdle,
                forceReload: true
            )
            renderer.setMirrored(actionFacing.isMirrored)
            mindPetID = nextPet.id
            petMind = PetMindStore.load(petID: mindPetID)
            rebuildMenu()
            refreshAppearanceSettings()
            showSpeech(appLanguage.appearanceChanged(nextPet.name))
            resumeAfterProfileSwitch(resumeModes)
            return true
        } catch {
            _ = PetAssetCatalog.selectPet(id: previousPet.id)
            _ = PetAssetCatalog.selectAppearance(id: previousAppearance.id)
            mindPetID = previousPet.id
            petMind = PetMindStore.load(petID: mindPetID)
            videoAnimationsEnabled = previousAppearance.kind == .continuousVideo
            try? renderer.setVisualMode(
                previousAppearance.kind.visualMode,
                replaying: PetClips.standIdle,
                forceReload: true
            )
            rebuildMenu()
            refreshAppearanceSettings()
            resumeAfterProfileSwitch(resumeModes)
            present(error)
            return false
        }
    }

    /// Appearance and pet selection are user commands, so they preempt every
    /// autonomous action instead of waiting for a transition, chase, or gait.
    private func interruptCurrentActivityForProfileSwitch() -> (follow: Bool, roam: Bool) {
        let resumeModes = (follow: followCursor, roam: freeRoamEnabled)
        behaviorEpoch += 1
        locomotionGeneration += 1
        facingTransitionGeneration += 1
        profileSwitchGeneration += 1
        behaviorTimer?.invalidate()
        behaviorTimer = nil
        patrolTimer?.invalidate()
        patrolTimer = nil
        cursorFollowTimer?.invalidate()
        cursorFollowTimer = nil
        freeRoamTimer?.invalidate()
        freeRoamTimer = nil
        facingTimer?.invalidate()
        facingTimer = nil
        cancelTreatChase(resume: false)
        cancelDesktopItemInteraction()
        immediateDesktopInteractionResume = nil
        hideSpeechBubble(animated: false)
        freeRoamTarget = nil
        pendingDesktopInteraction = nil
        pendingFacingView = nil
        pendingLocomotionMode = nil
        locomotionMode = .none
        locomotionVelocity = .zero
        preciseLocomotionOrigin = nil
        isUsingImageFacing = false
        directionalLookIsEngaged = false
        isReturningToActionProfile = false
        isTransitioning = false
        posture = .stand
        return resumeModes
    }

    private func resumeAfterProfileSwitch(_ modes: (follow: Bool, roam: Bool)) {
        if modes.follow, followCursor {
            beginCursorFollowing()
        } else if modes.roam, freeRoamEnabled {
            beginFreeRoaming()
        } else {
            restartAutonomy()
        }
    }

    @objc private func toggleVisibility() {
        if groupPlayEnabled {
            groupPlayController.setVisible(!groupPlayController.hasVisibleCompanions)
            return
        }
        if panel.isVisible {
            cancelTreatChase(resume: false)
            hideSpeechBubble(animated: false)
            panel.orderOut(nil)
        } else {
            showPetWindow()
            do {
                try renderer.play(PetClips.idle(for: posture), fadeDuration: 0)
            } catch {
                present(error)
            }
        }
    }

    @objc private func togglePassThrough() {
        fullPassThrough.toggle()
        updateClickThrough()
    }

    @objc private func toggleAutoBehavior() {
        autoBehavior.toggle()
        restartAutonomy()
    }

    @objc private func toggleCursorFollowing() {
        cancelTreatChase(resume: false)
        if followCursor {
            followCursor = false
            stopCursorFollowing()
            restartAutonomy()
        } else {
            if freeRoamEnabled {
                freeRoamEnabled = false
                stopFreeRoaming()
            }
            followCursor = true
            beginCursorFollowing()
        }
    }

    @objc private func toggleFreeRoaming() {
        cancelTreatChase(resume: false)
        if freeRoamEnabled {
            freeRoamEnabled = false
            stopFreeRoaming()
            showSpeech(appLanguage.freeRoamStopped)
            restartAutonomy()
        } else {
            if followCursor {
                followCursor = false
                stopCursorFollowing()
            }
            freeRoamEnabled = true
            showSpeech(appLanguage.freeRoamStarted)
            beginFreeRoaming()
        }
    }

    @objc private func toggleImageFacing() {
        imageFacingEnabled.toggle()
        pendingFacingView = nil
        guard posture == .stand, !followCursor, !freeRoamEnabled,
              locomotionMode == .none, patrolTimer == nil,
              !isTransitioning else { return }

        if imageFacingEnabled {
            if usesDirectionalLook {
                playLookDirection(lookDirection, fadeDuration: 0.065)
            } else {
                playFacingView(facingView, fadeDuration: 0.07)
            }
        } else if isUsingImageFacing, !imageFacingMatchesActionProfile {
            returnImageFacingToActionProfile { [weak self] in
                self?.switchToStandIdle()
            }
        } else {
            switchToStandIdle()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
