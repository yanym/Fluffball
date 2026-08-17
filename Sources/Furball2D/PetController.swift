import AppKit

@MainActor
final class PetController: NSObject, NSMenuDelegate {
    private static let sizeValueLabelTag = 7101
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
            case .walk: 0.32
            case .slowRun: 0.16
            case .fastRun: 0.32
            }
        }

        var startTranslationRampDuration: TimeInterval {
            switch self {
            case .none: 0
            case .walk: 0.36
            case .slowRun: 0.26
            case .fastRun: 0.18
            }
        }
    }

    private let panel: PetPanel
    private let renderer: PetRenderer
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private let speechBubble = PetSpeechBubble()

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
    private var cursorFollowTimer: Timer?
    private var freeRoamTimer: Timer?
    private var facingTimer: Timer?
    private var statusItemHealthTimer: Timer?
    private var smoothedSpeechLocalFrame: NSRect?
    private var behaviorEpoch = 0
    private var patrolDirection: CGFloat = -1
    private var patrolDeadline: TimeInterval = 0
    private var currentlyInteractive = false
    private var locomotionMode: LocomotionMode = .none
    private var locomotionVelocity = NSPoint.zero
    private var locomotionGeneration = 0
    private var locomotionDirection: CGFloat = -1
    private var actionFacing: HorizontalFacing = .left
    private var lastLocomotionChangeTime: TimeInterval = 0
    private var pendingLocomotionMode: LocomotionMode?
    private var pendingLocomotionSince: TimeInterval = 0
    private var locomotionTranslationStartTime: TimeInterval = 0
    private var lastCursorLocation = NSPoint.zero
    private var lastCursorSampleTime: TimeInterval = 0
    private var smoothedCursorSpeed: CGFloat = 0
    private var facingView: PetFacingView = .leftProfile
    private var pendingFacingView: PetFacingView?
    private var lookDirection: PetLookDirection = .left
    private var pendingLookDirection: PetLookDirection?
    private var lastLookCursorLocation = NSPoint.zero
    private var lastLookCursorMotionTime: TimeInterval = 0
    private var directionalLookIsEngaged = false
    private var pendingFacingSince: TimeInterval = 0
    private var lastFacingChangeTime: TimeInterval = 0
    private var isUsingImageFacing = false
    private var facingTransitionGeneration = 0
    private var isReturningToActionProfile = false
    private var cursorMotionReadyTime: TimeInterval = 0
    private var freeRoamTarget: NSPoint?
    private var freeRoamPauseUntil: TimeInterval = 0
    private var lastFreeRoamSampleTime: TimeInterval = 0
    private var autonomousActionFacingUntil: TimeInterval = 0
    private var restFacingPreparedEpoch: Int?
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
        let capabilities = PetAssetCatalog.capabilities
        if capabilities.supportsModeSwitching {
            videoAnimationsEnabled = defaults.object(forKey: Self.videoAnimationsPreferenceKey) == nil
                ? true
                : defaults.bool(forKey: Self.videoAnimationsPreferenceKey)
        } else {
            videoAnimationsEnabled = capabilities.supportsVideoMode
        }
        appLanguage = AppLanguage.stored

        let size = NSSize(width: Self.basePetSize.width * initialScale, height: Self.basePetSize.height * initialScale)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: screen.maxX - size.width - 24, y: screen.minY + 18)
        renderer = try PetRenderer(
            frame: NSRect(origin: .zero, size: size),
            visualMode: videoAnimationsEnabled ? .video : .images
        )
        panel = PetPanel(contentRect: NSRect(origin: origin, size: size))
        super.init()

        posture = startingPosture
        panel.contentView = renderer.view
        configureInput()
        configureMenu()
    }

    func start() {
        panel.orderFrontRegardless()
        do {
            try renderer.play(PetClips.idle(for: posture))
        } catch {
            present(error)
            return
        }

        hitTestTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateClickThrough()
            }
        }
        startStatusItemHealthCheck()
        startFacingTracking()
        if freeRoamEnabled {
            beginFreeRoaming()
        } else if followCursor {
            beginCursorFollowing()
        } else {
            scheduleWake(epoch: behaviorEpoch)
        }
        scheduleNextSpeech(after: 1.4)
    }

    private func configureInput() {
        renderer.view.onMouseDown = { [weak self] event in self?.mouseDown(event) }
        renderer.view.onMouseDragged = { [weak self] event in self?.mouseDragged(event) }
        renderer.view.onMouseUp = { [weak self] event in self?.mouseUp(event) }
        renderer.view.onRightMouseDown = { [weak self] event in self?.showContextMenu(event) }
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
        menu.addItem(withTitle: appLanguage.interactMenu, action: #selector(interactFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: appLanguage.speakMenu, action: #selector(speakFromMenu), keyEquivalent: "")
        if !PetAssetCatalog.imageActions.isEmpty {
            menu.addItem(makeCuteActionsMenuItem())
        }
        menu.addItem(withTitle: appLanguage.imageTurnMenu, action: #selector(imageTurnFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: appLanguage.sleepMenu, action: #selector(sleepFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: appLanguage.visibilityMenu(isVisible: panel.isVisible), action: #selector(toggleVisibility), keyEquivalent: "")
        menu.addItem(.separator())

        let capabilities = PetAssetCatalog.capabilities
        let videoItem = menu.addItem(
            withTitle: appLanguage.videoAnimationsMenu,
            action: #selector(toggleVideoAnimations),
            keyEquivalent: ""
        )
        videoItem.state = renderer.visualMode == .video ? .on : .off
        videoItem.isEnabled = capabilities.supportsModeSwitching
            && !isTransitioning
            && locomotionMode == .none
        videoItem.toolTip = appLanguage.videoAnimationsTooltip(capabilities: capabilities)

        let passItem = menu.addItem(withTitle: appLanguage.passThroughMenu, action: #selector(togglePassThrough), keyEquivalent: "")
        passItem.state = fullPassThrough ? .on : .off
        let autoItem = menu.addItem(withTitle: appLanguage.autoBehaviorMenu, action: #selector(toggleAutoBehavior), keyEquivalent: "")
        autoItem.state = autoBehavior ? .on : .off
        let roamItem = menu.addItem(withTitle: appLanguage.freeRoamMenu, action: #selector(toggleFreeRoaming), keyEquivalent: "")
        roamItem.state = freeRoamEnabled ? .on : .off
        let followItem = menu.addItem(withTitle: appLanguage.followCursorMenu, action: #selector(toggleCursorFollowing), keyEquivalent: "")
        followItem.state = followCursor ? .on : .off
        let facingItem = menu.addItem(
            withTitle: usesDirectionalLook ? appLanguage.imageFacingMenu : appLanguage.legacyImageFacingMenu,
            action: #selector(toggleImageFacing),
            keyEquivalent: ""
        )
        facingItem.state = imageFacingEnabled ? .on : .off
        let fadeItem = menu.addItem(withTitle: appLanguage.crossfadeMenu, action: #selector(toggleCrossfade), keyEquivalent: "")
        fadeItem.state = renderer.crossfadeEnabled ? .on : .off
        let levelItem = menu.addItem(withTitle: appLanguage.alwaysOnTopMenu, action: #selector(toggleAlwaysOnTop), keyEquivalent: "")
        levelItem.state = panel.level == .floating ? .on : .off

        menu.addItem(makeSizeSliderItem())
        menu.addItem(makeLanguageMenuItem())

        menu.addItem(.separator())
        menu.addItem(withTitle: appLanguage.quitMenu, action: #selector(quit), keyEquivalent: "q")
        for item in menu.items where item.action != nil { item.target = self }
    }

    private func makeSizeSliderItem() -> NSMenuItem {
        let item = NSMenuItem(title: appLanguage.sizeMenu, action: nil, keyEquivalent: "")
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 228, height: 52))

        let titleLabel = NSTextField(labelWithString: appLanguage.sizeMenu)
        titleLabel.frame = NSRect(x: 13, y: 29, width: 130, height: 18)
        titleLabel.font = .menuFont(ofSize: 13)
        container.addSubview(titleLabel)

        let valueLabel = NSTextField(labelWithString: scaleLabel(petScale))
        valueLabel.frame = NSRect(x: 157, y: 29, width: 58, height: 18)
        valueLabel.font = .menuFont(ofSize: 12)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.tag = Self.sizeValueLabelTag
        container.addSubview(valueLabel)

        let slider = NSSlider(
            value: Double(petScale),
            minValue: Double(Self.minimumScale),
            maxValue: Double(Self.maximumScale),
            target: self,
            action: #selector(sizeSliderChanged(_:))
        )
        slider.frame = NSRect(x: 12, y: 4, width: 204, height: 24)
        slider.isContinuous = true
        slider.allowsTickMarkValuesOnly = false
        slider.toolTip = appLanguage.sizeTooltip
        container.addSubview(slider)

        item.view = container
        return item
    }

    private func makeLanguageMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: appLanguage.languageMenu, action: nil, keyEquivalent: "")
        let languageMenu = NSMenu(title: appLanguage.languageMenu)

        for language in AppLanguage.allCases {
            let languageItem = NSMenuItem(
                title: language.displayName,
                action: #selector(selectLanguage(_:)),
                keyEquivalent: ""
            )
            languageItem.target = self
            languageItem.representedObject = language.rawValue
            languageItem.state = language == appLanguage ? .on : .off
            languageMenu.addItem(languageItem)
        }

        item.submenu = languageMenu
        return item
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

    private func scaleLabel(_ scale: CGFloat) -> String {
        "\(Int((scale * 100).rounded()))%"
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
        if totalDragDistance < 6 {
            speakRandomly()
            if !followCursor, !freeRoamEnabled { advanceBehavior() }
        }
        registerUserActivity()
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
        let nextDelay = delay ?? Double.random(in: 18...34)
        speechTimer = Timer.scheduledTimer(withTimeInterval: nextDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.speakRandomly()
                self.scheduleNextSpeech()
            }
        }
    }

    private func speakRandomly() {
        guard panel.isVisible, let message = appLanguage.speechMessages(for: posture).randomElement() else { return }
        showSpeech(message)
    }

    private func showSpeech(_ message: String) {
        guard panel.isVisible else { return }
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
        let timer = Timer(timeInterval: 1.0 / 8.0, repeats: true) { [weak self] _ in
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
        let measured = measuredLocalPetFrame()
        if reset || smoothedSpeechLocalFrame == nil {
            smoothedSpeechLocalFrame = measured
        } else if refresh, let current = smoothedSpeechLocalFrame {
            let response: CGFloat = isTransitioning ? 0.10 : 0.16
            let deadZone = 2.2 * petScale
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
        directionalLookIsEngaged = false
        let timer = Timer(timeInterval: 0.10, repeats: true) { [weak self] _ in
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
        renderer.visualMode == .images && PetAssetCatalog.capabilities.supportsDirectionalLook
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

    private func desiredFacingView(for cursor: NSPoint = NSEvent.mouseLocation) -> PetFacingView {
        let normalizedX = (cursor.x - panel.frame.midX) / max(1, panel.frame.width)
        switch normalizedX {
        case ..<(-0.46): return .leftProfile
        case ..<(-0.34): return .frontNearProfileLeft
        case ..<(-0.20): return .frontThreeQuarterLeft
        case ..<(-0.07): return .frontNearCenterLeft
        case ...0.07: return .front
        case ...0.20: return .frontNearCenterRight
        case ...0.34: return .frontThreeQuarterRight
        case ...0.46: return .frontNearProfileRight
        default: return .rightProfile
        }
    }

    private func updateFacingTowardCursor() {
        guard canUseImageFacing else {
            pendingFacingView = nil
            pendingLookDirection = nil
            return
        }

        if renderer.visualMode == .images, PetAssetCatalog.capabilities.supportsDirectionalLook {
            updateDirectionalLookTowardCursor()
        } else {
            updateLegacyFacingTowardCursor()
        }
    }

    private func updateLegacyFacingTowardCursor() {
        pendingLookDirection = nil

        if !isUsingImageFacing {
            playFacingView(facingView, fadeDuration: 0.07)
            return
        }

        let desiredView = desiredFacingView()
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

        // The requested bucket must remain stable before one adjacent step is
        // accepted. Large cursor jumps therefore traverse every intermediate
        // view instead of snapping from one profile directly to the other. Once
        // accepted, keep that target pending so the remaining adjacent steps can
        // follow the shorter switch cooldown without repeating the full dwell.
        guard now - pendingFacingSince >= 0.18,
              now - lastFacingChangeTime >= 0.09 else { return }
        playFacingView(facingView.stepped(toward: desiredView), fadeDuration: 0.07)
    }

    private func updateDirectionalLookTowardCursor() {
        pendingFacingView = nil
        let cursor = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime
        let cursorTravel = hypot(
            cursor.x - lastLookCursorLocation.x,
            cursor.y - lastLookCursorLocation.y
        )
        if cursorTravel >= 3 {
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
            pendingLookDirection = nil
            if isUsingImageFacing {
                playDirectionalStandIdle(fadeDuration: 0.09)
            }
            return
        }

        let deltaX = cursor.x - panel.frame.midX
        let deltaY = cursor.y - panel.frame.midY
        guard hypot(deltaX, deltaY) >= 44 * petScale else {
            pendingLookDirection = nil
            directionalLookIsEngaged = false
            if isUsingImageFacing {
                playDirectionalStandIdle(fadeDuration: 0.09)
            }
            return
        }
        let desiredDirection = PetLookDirection(vectorX: deltaX, vectorY: deltaY)

        if !isUsingImageFacing {
            playLookDirection(lookDirection, fadeDuration: 0.065)
            return
        }
        guard desiredDirection != lookDirection else {
            pendingLookDirection = nil
            return
        }

        if pendingLookDirection != desiredDirection {
            pendingLookDirection = desiredDirection
            pendingFacingSince = now
            return
        }
        guard now - pendingFacingSince >= 0.15,
              now - lastFacingChangeTime >= 0.085 else { return }
        playLookDirection(lookDirection.stepped(toward: desiredDirection), fadeDuration: 0.065)
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
        pendingLookDirection = nil
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
            let nextView = facingView.stepped(toward: targetView)
            do {
                try renderer.play(PetClips.imageFacing(nextView), fadeDuration: 0.07)
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

            Timer.scheduledTimer(withTimeInterval: 0.11, repeats: false) { [weak self] _ in
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
        guard isUsingImageFacing, lookDirection != targetDirection else {
            completion()
            return
        }

        facingTransitionGeneration += 1
        let generation = facingTransitionGeneration
        isReturningToActionProfile = true
        isTransitioning = true
        pendingLookDirection = nil
        speechBubble.updateAppearance(mood: speechMood)

        func advance() {
            guard generation == facingTransitionGeneration else { return }
            let nextDirection = lookDirection.stepped(toward: targetDirection)
            do {
                try renderer.play(PetClips.lookDirection(nextDirection), fadeDuration: 0.065)
                lookDirection = nextDirection
                isUsingImageFacing = true
                lastFacingChangeTime = ProcessInfo.processInfo.systemUptime
            } catch {
                isReturningToActionProfile = false
                isTransitioning = false
                present(error)
                completion()
                return
            }

            Timer.scheduledTimer(withTimeInterval: 0.09, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, generation == self.facingTransitionGeneration else { return }
                    if self.lookDirection == targetDirection {
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
        renderer.setMirrored(actionFacing.isMirrored)
        speechBubble.updateAppearance(mood: speechMood)
        do {
            try renderer.play(clip) { [weak self] in
                guard let self else { return }
                self.isTransitioning = false
                self.playIdle(clip.resultingPosture)
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
        schedule(after: 12, epoch: epoch) { [weak self] in
            self?.settleDown(epoch: epoch)
        }
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
                   let action = PetAssetCatalog.imageActions
                    .filter(\.mayRunAutonomously)
                    .randomElement() {
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
        schedule(after: Double.random(in: 35...65), epoch: epoch) { [weak self] in
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
        cursorMotionReadyTime = lastCursorSampleTime + 0.10
        smoothedCursorSpeed = 0

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
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
        guard (followCursor || freeRoamEnabled), !isTransitioning else { return }
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
        smoothedCursorSpeed += (instantaneousCursorSpeed - smoothedCursorSpeed) * min(1, deltaTime * 7)
        lastCursorLocation = cursor
        lastCursorSampleTime = now

        let deadZone = 76 * petScale
        let distance = hypot(cursor.x - panel.frame.midX, cursor.y - panel.frame.midY)
        let demand = max(smoothedCursorSpeed, max(0, distance - deadZone) * 1.1)
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
        guard freeRoamEnabled else { return }
        isUsingImageFacing = false
        lastFreeRoamSampleTime = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateFreeRoaming()
            }
        }
        freeRoamTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        continueToStandForMovement()
    }

    private func stopFreeRoaming() {
        freeRoamTimer?.invalidate()
        freeRoamTimer = nil
        freeRoamTarget = nil
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
        guard freeRoamEnabled, panel.isVisible, !isDragging else { return }
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
            freeRoamTarget = makeRandomRoamTarget()
        }
        guard let target = freeRoamTarget else { return }

        let distance = hypot(target.x - center.x, target.y - center.y)
        let deadZone = 54 * petScale
        if distance <= deadZone {
            freeRoamTarget = nil
            freeRoamPauseUntil = now + Double.random(in: 3.8...6.4)
            updateMovement(toward: center, demand: 0, deadZone: 8, now: now, deltaTime: deltaTime)
            return
        }

        let demand = max(120, distance * 0.9)
        updateMovement(
            toward: target,
            demand: demand,
            deadZone: deadZone,
            now: now,
            deltaTime: deltaTime
        )
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

    private func updateMovement(
        toward target: NSPoint,
        demand: CGFloat,
        deadZone: CGFloat,
        now: TimeInterval,
        deltaTime: TimeInterval
    ) {
        let deltaX = target.x - panel.frame.midX
        let deltaY = target.y - panel.frame.midY
        let distance = hypot(deltaX, deltaY)
        let desiredMode = desiredLocomotionMode(distance: distance, demand: demand, deadZone: deadZone)

        if distance > deadZone + 18, abs(deltaX) > 18 * petScale {
            locomotionDirection = deltaX >= 0 ? 1 : -1
            actionFacing = locomotionDirection > 0 ? .right : .left
        }

        let canChangeMode = now - lastLocomotionChangeTime >= 0.70
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
        } else if canChangeMode, now - pendingLocomotionSince >= 0.18 {
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
            return
        } else {
            let rampDuration = max(
                0.01,
                renderer.visualMode == .video
                    ? locomotionMode.startTranslationRampDuration
                    : 0.14
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
        let velocityResponse = locomotionMode == .none ? 6.5 : 4.2
        let response = min(1, deltaTime * velocityResponse)
        locomotionVelocity.x += (targetVelocity.x - locomotionVelocity.x) * response
        locomotionVelocity.y += (targetVelocity.y - locomotionVelocity.y) * response

        guard hypot(locomotionVelocity.x, locomotionVelocity.y) > 0.25 else {
            locomotionVelocity = .zero
            return
        }

        let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let horizontalLimits = horizontalMovementLimits(in: visibleFrame)
        let verticalLimits = verticalMovementLimits(in: visibleFrame)
        var origin = panel.frame.origin
        let proposedX = origin.x + locomotionVelocity.x * deltaTime
        let proposedY = origin.y + locomotionVelocity.y * deltaTime
        origin.x = min(horizontalLimits.maximum, max(horizontalLimits.minimum, proposedX))
        origin.y = min(verticalLimits.maximum, max(verticalLimits.minimum, proposedY))

        if origin.x != proposedX { locomotionVelocity.x = 0 }
        if origin.y != proposedY { locomotionVelocity.y = 0 }
        panel.setFrameOrigin(origin)
        repositionSpeechBubble(refreshSilhouette: false)
    }

    private func desiredLocomotionMode(
        distance: CGFloat,
        demand: CGFloat,
        deadZone: CGFloat
    ) -> LocomotionMode {
        guard distance > deadZone else { return .none }

        switch locomotionMode {
        case .none:
            if demand > 650 || distance > 520 * petScale { return .fastRun }
            if demand > 260 || distance > 270 * petScale { return .slowRun }
            return .walk
        case .walk:
            if demand > 700 || distance > 560 * petScale { return .fastRun }
            if demand > 320 || distance > 300 * petScale { return .slowRun }
            return .walk
        case .slowRun:
            if demand > 720 || distance > 580 * petScale { return .fastRun }
            if demand < 175, distance < 220 * petScale { return .walk }
            return .slowRun
        case .fastRun:
            if demand < 430, distance < 390 * petScale { return .slowRun }
            return .fastRun
        }
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
        if previousMode == .none, newMode != .none {
            locomotionVelocity = .zero
            let translationDelay = renderer.visualMode == .video ? newMode.startTranslationDelay : 0
            locomotionTranslationStartTime = now + translationDelay
        } else if newMode == .none {
            locomotionTranslationStartTime = 0
        }
        speechBubble.updateAppearance(mood: speechMood)

        do {
            if newMode == .none {
                guard let stopClip = previousMode.clips?.stop else {
                    playIdle(.stand)
                    return
                }
                try renderer.play(stopClip, fadeDuration: 0.12) { [weak self] in
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
            } else {
                try renderer.play(clips.loop, fadeDuration: 0.12)
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
        pendingLookDirection = nil
        isUsingImageFacing = false
        renderer.setMirrored(false)
        isTransitioning = true
        showSpeech(appLanguage.imageTurnGreeting)
        speechBubble.updateAppearance(mood: speechMood)

        do {
            try renderer.play(PetClips.lookAroundImages, fadeDuration: 0.10) { [weak self] in
                guard let self else { return }
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
        pendingLookDirection = nil
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
        repositionSpeechBubble(resetSilhouette: true)
    }

    private func present(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = appLanguage.problemTitle
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private func performImageAction(_ action: PetImageAction, completion: (() -> Void)? = nil) {
        guard renderer.visualMode == .images,
              posture == .stand,
              !isTransitioning,
              locomotionMode == .none,
              patrolTimer == nil else { return }

        pendingFacingView = nil
        pendingLookDirection = nil
        isUsingImageFacing = false
        isTransitioning = true
        renderer.setMirrored(false)
        speechBubble.updateAppearance(mood: speechMood)
        let clip = PetClips.imageAction(action)
        do {
            try renderer.play(clip, fadeDuration: 0.10) { [weak self] in
                guard let self else { return }
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

    @objc private func performCuteActionFromMenu(_ sender: NSMenuItem) {
        guard let actionID = sender.representedObject as? String,
              let action = PetAssetCatalog.imageActions.first(where: { $0.id == actionID }) else { return }
        panel.orderFrontRegardless()
        registerUserActivity()
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

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = AppLanguage(rawValue: rawValue),
              language != appLanguage else { return }

        appLanguage = language
        statusItem?.button?.toolTip = language.statusTooltip
        rebuildMenu()
        showSpeech(language.languageChanged)
    }

    @objc private func toggleVisibility() {
        if panel.isVisible {
            hideSpeechBubble(animated: false)
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    @objc private func toggleVideoAnimations() {
        let capabilities = PetAssetCatalog.capabilities
        guard capabilities.supportsModeSwitching,
              !isTransitioning,
              locomotionMode == .none else { return }

        let previousValue = videoAnimationsEnabled
        let previousMode = renderer.visualMode
        videoAnimationsEnabled.toggle()
        do {
            isUsingImageFacing = false
            pendingFacingView = nil
            pendingLookDirection = nil
            try renderer.setVisualMode(
                videoAnimationsEnabled ? .video : .images,
                replaying: PetClips.idle(for: posture)
            )
            showSpeech(
                videoAnimationsEnabled
                    ? appLanguage.videoModeEnabled
                    : appLanguage.imageModeEnabled
            )
            repositionSpeechBubble(resetSilhouette: true)
        } catch {
            videoAnimationsEnabled = previousValue
            try? renderer.setVisualMode(previousMode, replaying: PetClips.idle(for: posture))
            present(error)
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

    @objc private func toggleCrossfade() {
        renderer.crossfadeEnabled.toggle()
    }

    @objc private func toggleAlwaysOnTop() {
        panel.level = panel.level == .floating ? .normal : .floating
        speechBubble.setLevel(panel.level)
    }

    @objc private func sizeSliderChanged(_ sender: NSSlider) {
        let scale = CGFloat(sender.doubleValue)
        setScale(scale)
        if let valueLabel = sender.superview?.viewWithTag(Self.sizeValueLabelTag) as? NSTextField {
            valueLabel.stringValue = scaleLabel(scale)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
