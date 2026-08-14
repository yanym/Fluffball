import AppKit

@MainActor
final class PetController: NSObject, NSMenuDelegate {
    private static let sizeValueLabelTag = 7101
    private static let basePetSize = NSSize(width: 520, height: 292.5)
    private static let minimumScale: CGFloat = 0.6
    private static let maximumScale: CGFloat = 1.4

    private enum PreferenceKey {
        static let petScale = "petScale"
        static let fullPassThrough = "fullPassThrough"
        static let autoBehavior = "autoBehavior"
    }

    private let panel: PetPanel
    private let renderer: PetRenderer
    private let statusItem: NSStatusItem
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
    private var behaviorEpoch = 0
    private var patrolDirection: CGFloat = -1
    private var patrolDeadline: TimeInterval = 0
    private var currentlyInteractive = false
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
        appLanguage = AppLanguage.stored

        let size = NSSize(width: Self.basePetSize.width * initialScale, height: Self.basePetSize.height * initialScale)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: screen.maxX - size.width - 24, y: screen.minY + 18)
        renderer = try PetRenderer(frame: NSRect(origin: .zero, size: size))
        panel = PetPanel(contentRect: NSRect(origin: origin, size: size))
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
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
        scheduleWake(epoch: behaviorEpoch)
        scheduleNextSpeech(after: 1.4)
    }

    private func configureInput() {
        renderer.view.onMouseDown = { [weak self] event in self?.mouseDown(event) }
        renderer.view.onMouseDragged = { [weak self] event in self?.mouseDragged(event) }
        renderer.view.onMouseUp = { [weak self] event in self?.mouseUp(event) }
        renderer.view.onRightMouseDown = { [weak self] event in self?.showContextMenu(event) }
    }

    private func configureMenu() {
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Furball2D")
        statusItem.button?.toolTip = appLanguage.statusTooltip
        statusItem.menu = menu
        menu.delegate = self
        rebuildMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        menu.addItem(withTitle: appLanguage.interactMenu, action: #selector(interactFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: appLanguage.speakMenu, action: #selector(speakFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: appLanguage.sleepMenu, action: #selector(sleepFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: appLanguage.visibilityMenu(isVisible: panel.isVisible), action: #selector(toggleVisibility), keyEquivalent: "")
        menu.addItem(.separator())

        let passItem = menu.addItem(withTitle: appLanguage.passThroughMenu, action: #selector(togglePassThrough), keyEquivalent: "")
        passItem.state = fullPassThrough ? .on : .off
        let autoItem = menu.addItem(withTitle: appLanguage.autoBehaviorMenu, action: #selector(toggleAutoBehavior), keyEquivalent: "")
        autoItem.state = autoBehavior ? .on : .off
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
        repositionSpeechBubble()
    }

    private func mouseUp(_ event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        if totalDragDistance < 6 {
            speakRandomly()
            advanceBehavior()
        }
        registerUserActivity()
    }

    private func clampedOrigin(_ proposed: NSPoint, panelSize: NSSize? = nil) -> NSPoint {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? panel.screen ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return proposed }
        let size = panelSize ?? panel.frame.size
        return NSPoint(
            x: min(frame.maxX - size.width * 0.25, max(frame.minX - size.width * 0.75, proposed.x)),
            y: min(frame.maxY - size.height * 0.25, max(frame.minY, proposed.y))
        )
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
        let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
        speechBubble.show(message: message, near: speechAnchorFrame(), in: visibleFrame, level: panel.level)

        speechHideTimer?.invalidate()
        speechHideTimer = Timer.scheduledTimer(withTimeInterval: 4.6, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.speechBubble.hide()
            }
        }
    }

    private func repositionSpeechBubble() {
        guard speechBubble.isVisible else { return }
        let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
        speechBubble.reposition(near: speechAnchorFrame(), in: visibleFrame)
    }

    private func speechAnchorFrame() -> NSRect {
        let transparentTopRatio: CGFloat
        switch posture {
        case .stand, .sit:
            transparentTopRatio = 0.08
        case .lie:
            transparentTopRatio = 0.24
        case .sleep:
            transparentTopRatio = 0.52
        }

        var anchorFrame = panel.frame
        anchorFrame.size.height *= 1 - transparentTopRatio
        return anchorFrame
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
        stopPatrol()
        isTransitioning = true
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
        renderer.setMirrored(false)
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
        guard autoBehavior else { return }
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
        guard behaviorEpoch == epoch, !isDragging else { return }
        if isTransitioning {
            schedule(after: 1, epoch: epoch) { [weak self] in self?.settleDown(epoch: epoch) }
            return
        }
        stopPatrol()
        switch posture {
        case .stand:
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
        if PetClips.walkIdle.isAvailable {
            do {
                try renderer.play(PetClips.walkIdle)
            } catch {
                present(error)
                schedule(after: 3, epoch: epoch) { [weak self] in self?.settleDown(epoch: epoch) }
                return
            }

            let screen = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            patrolDirection = panel.frame.midX < screen.midX ? 1 : -1
            renderer.setMirrored(patrolDirection > 0)
            patrolDeadline = ProcessInfo.processInfo.systemUptime + Double.random(in: 10...18)
            patrolTimer?.invalidate()
            patrolTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.updatePatrol(epoch: epoch)
                }
            }
        } else {
            // 当前左侧面素材没有步态循环；保持站立观察，避免用静止脚掌在桌面上滑行。
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
            playIdle(.stand)
            schedule(after: 1.2, epoch: epoch) { [weak self] in self?.settleDown(epoch: epoch) }
            return
        }

        let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var origin = panel.frame.origin
        origin.x += patrolDirection * (58.0 / 60.0)
        let leftLimit = visibleFrame.minX - panel.frame.width * 0.30
        let rightLimit = visibleFrame.maxX - panel.frame.width * 0.70
        if origin.x <= leftLimit || origin.x >= rightLimit {
            patrolDirection *= -1
            renderer.setMirrored(patrolDirection > 0)
            origin.x = min(rightLimit, max(leftLimit, origin.x))
        }
        panel.setFrameOrigin(origin)
        repositionSpeechBubble()
    }

    private func stopPatrol() {
        let wasPatrolling = patrolTimer != nil
        patrolTimer?.invalidate()
        patrolTimer = nil
        renderer.setMirrored(false)
        if wasPatrolling, posture == .stand, !isTransitioning {
            playIdle(.stand)
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
        guard autoBehavior else { return }
        if posture == .sleep {
            scheduleWake(epoch: epoch)
        } else {
            schedule(after: 12, epoch: epoch) { [weak self] in self?.settleDown(epoch: epoch) }
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
        repositionSpeechBubble()
    }

    private func present(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = appLanguage.problemTitle
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    @objc private func interactFromMenu() {
        panel.orderFrontRegardless()
        registerUserActivity()
        speakRandomly()
        advanceBehavior()
    }

    @objc private func speakFromMenu() {
        panel.orderFrontRegardless()
        speakRandomly()
    }

    @objc private func sleepFromMenu() {
        panel.orderFrontRegardless()
        showSpeech(appLanguage.sleepConfirmation)
        requestSleep()
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = AppLanguage(rawValue: rawValue),
              language != appLanguage else { return }

        appLanguage = language
        statusItem.button?.toolTip = language.statusTooltip
        rebuildMenu()
        showSpeech(language.languageChanged)
    }

    @objc private func toggleVisibility() {
        if panel.isVisible {
            speechBubble.hide(animated: false)
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
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
