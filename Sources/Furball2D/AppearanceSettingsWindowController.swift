import AppKit

struct AppearanceSettingsSnapshot {
    let appearances: [PetAppearanceOption]
    let pets: [PetLibraryPet]
    let activePetID: String
    let selectedAppearanceID: String
    let language: AppLanguage
    let crossfadeEnabled: Bool
    let followCursor: Bool
    let freeRoam: Bool
    let directionalLook: Bool
    let desktopInteractions: Bool
    let alwaysOnTop: Bool
    let petScale: CGFloat
    let fullPassThrough: Bool
    let autoBehavior: Bool
    let speechBubbles: Bool
    let talkativeness: Double
    let canChangeAppearance: Bool
    let groupPlayEnabled: Bool
    let groupPetIDs: Set<String>
}

@MainActor
final class AppearanceSettingsWindowController: NSWindowController, NSWindowDelegate {
    enum Page: CaseIterable {
        case general
        case appearance
        case behavior
        case interaction
        case group
        case speech
    }

    var onAppearanceSelected: ((String) -> Bool)?
    var onPetSelected: ((String) -> Bool)?
    var onCrossfadeChanged: ((Bool) -> Void)?
    var onFollowCursorChanged: ((Bool) -> Void)?
    var onFreeRoamChanged: ((Bool) -> Void)?
    var onDirectionalLookChanged: ((Bool) -> Void)?
    var onDesktopInteractionsChanged: ((Bool) -> Void)?
    var onInspectTrashNow: (() -> Void)?
    var onPlayWithDesktopItemNow: (() -> Void)?
    var onGroupPlayChanged: ((Bool) -> Void)?
    var onGroupPetSelectionChanged: ((Set<String>) -> Void)?
    var onAlwaysOnTopChanged: ((Bool) -> Void)?
    var onPetScaleChanged: ((CGFloat) -> Void)?
    var onPassThroughChanged: ((Bool) -> Void)?
    var onAutoBehaviorChanged: ((Bool) -> Void)?
    var onSpeechBubblesChanged: ((Bool) -> Void)?
    var onTalkativenessChanged: ((Double) -> Void)?
    var onPreviewSpeech: (() -> Void)?

    private var snapshot: AppearanceSettingsSnapshot
    private var pages: [Page: NSView] = [:]
    private var selectedPage: Page = .general
    private let imageModeNote = NSTextField(wrappingLabelWithString: "")
    private let petPopup = NSPopUpButton()
    private let appearancePopup = NSPopUpButton()
    private let appearanceStack = NSStackView()
    private let crossfadeSwitch = NSSwitch()
    private weak var crossfadeRow: NSView?
    private let followSwitch = NSSwitch()
    private let roamSwitch = NSSwitch()
    private let lookSwitch = NSSwitch()
    private let desktopInteractionsSwitch = NSSwitch()
    private let inspectTrashButton = NSButton()
    private let playWithItemButton = NSButton()
    private let groupPlaySwitch = NSSwitch()
    private let groupPetStack = NSStackView()
    private var groupPetCheckboxes: [String: NSButton] = [:]
    private let alwaysOnTopSwitch = NSSwitch()
    private let passThroughSwitch = NSSwitch()
    private let autoBehaviorSwitch = NSSwitch()
    private let speechBubblesSwitch = NSSwitch()
    private let petSizeSlider = NSSlider()
    private let petSizeValue = NSTextField(labelWithString: "")
    private let talkativenessSlider = NSSlider()
    private let talkativenessValue = NSTextField(labelWithString: "")
    private let previewSpeechButton = NSButton()

    init(snapshot: AppearanceSettingsSnapshot) {
        self.snapshot = snapshot

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 740, height: 600)
        window.center()

        super.init(window: window)
        window.delegate = self
        buildInterface()
        applySnapshot()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(snapshot: AppearanceSettingsSnapshot) {
        self.snapshot = snapshot
        applySnapshot()
    }

    /// Exercises the same NSButton target/action path as a real user click.
    /// This intentionally avoids calling the controller callback directly so
    /// regression QA catches broken hit targets and disconnected card actions.
    @discardableResult
    func performAppearanceClickForQA(id: String) -> Bool {
        guard let card = appearanceStack.arrangedSubviews
            .compactMap({ $0 as? AppearanceCardView })
            .first(where: { $0.identifier?.rawValue == "appearance-card-\(id)" }) else { return false }
        card.activateForQA()
        return true
    }

    @discardableResult
    func performPetSelectionForQA(id: String) -> Bool {
        guard let item = petPopup.itemArray.first(where: { ($0.representedObject as? String) == id }) else {
            return false
        }
        petPopup.select(item)
        activePetChanged(petPopup)
        return true
    }

    func present() {
        guard let window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        VisualQACapture.schedule(view: window.contentView, name: "visual-settings")
    }

    func show(page: Page) {
        selectedPage = page
        for (candidate, view) in pages { view.isHidden = candidate != page }
    }

    /// Transfers the settings page into the unified Settings window while the
    /// controller continues to own its controls and callbacks.
    func contentViewForEmbedding() -> NSView {
        guard let window, let content = window.contentView else { return NSView() }
        window.contentView = NSView()
        content.removeFromSuperview()
        return content
    }

    private func buildInterface() {
        guard let window else { return }
        let root = NSVisualEffectView()
        root.material = .contentBackground
        root.blendingMode = .behindWindow
        root.state = .active
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root

        for page in Page.allCases {
            let view = makePage(page)
            pages[page] = view
            root.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                view.topAnchor.constraint(equalTo: root.topAnchor),
                view.bottomAnchor.constraint(equalTo: root.bottomAnchor)
            ])
        }
        show(page: selectedPage)
    }

    private func makePage(_ page: Page) -> NSView {
        let main = NSView()
        main.translatesAutoresizingMaskIntoConstraints = false
        let language = snapshot.language
        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 13
        badge.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
        let badgeIcon = NSImageView()
        badgeIcon.image = NSImage(systemSymbolName: pageSymbol(page), accessibilityDescription: nil)
        badgeIcon.contentTintColor = .controlAccentColor
        badgeIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        badgeIcon.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(badgeIcon)
        badge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 46),
            badge.heightAnchor.constraint(equalToConstant: 46),
            badgeIcon.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            badgeIcon.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            badgeIcon.widthAnchor.constraint(equalToConstant: 24),
            badgeIcon.heightAnchor.constraint(equalToConstant: 24)
        ])
        let title = NSTextField(labelWithString: pageTitle(page, language: language))
        title.font = .systemFont(ofSize: 26, weight: .bold)
        let subtitle = NSTextField(wrappingLabelWithString: pageSubtitle(page, language: language))
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 3
        let heading = NSStackView(views: [title, subtitle])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 3
        let header = NSStackView(views: [badge, heading])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 14

        let body: NSView
        switch page {
        case .general: body = makeGeneralBox(language: language)
        case .appearance: body = makeAppearanceContent(language: language)
        case .behavior: body = makeBehaviorBox(language: language)
        case .interaction: body = makeInteractionBox(language: language)
        case .group: body = makeGroupBox(language: language)
        case .speech: body = makeSpeechBox(language: language)
        }

        let stack = NSStackView(views: [header, body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        main.addSubview(stack)
        body.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 38),
            stack.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -38),
            stack.topAnchor.constraint(equalTo: main.topAnchor, constant: 48),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: main.bottomAnchor, constant: -32),
            body.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return main
    }

    private func makeGeneralBox(language: AppLanguage) -> NSView {
        petSizeSlider.minValue = 0.6
        petSizeSlider.maxValue = 1.4
        petSizeSlider.isContinuous = true
        petSizeSlider.target = self
        petSizeSlider.action = #selector(petSizeChanged(_:))
        let rows = NSStackView(views: [
            makeSliderRow(title: "Pet Size", slider: petSizeSlider, value: petSizeValue),
            separator(),
            makeToggleRow(title: "Always on Top", toggle: alwaysOnTopSwitch, action: #selector(alwaysOnTopChanged(_:))),
            separator(),
            makeToggleRow(title: "Click Through Completely", toggle: passThroughSwitch, action: #selector(passThroughChanged(_:))),
            separator(),
            makeToggleRow(title: "Autonomous Routine", toggle: autoBehaviorSwitch, action: #selector(autoBehaviorChanged(_:)))
        ])
        return boxed(rows)
    }

    private func makeAppearanceContent(language: AppLanguage) -> NSView {
        petPopup.target = self
        petPopup.action = #selector(activePetChanged(_:))
        appearancePopup.target = self
        appearancePopup.action = #selector(activeAppearanceChanged(_:))
        appearanceStack.orientation = .horizontal
        appearanceStack.alignment = .top
        appearanceStack.distribution = .fillEqually
        appearanceStack.spacing = 12
        imageModeNote.font = .systemFont(ofSize: 12)
        imageModeNote.textColor = .tertiaryLabelColor
        imageModeNote.maximumNumberOfLines = 2
        let crossfadeRow = makeToggleRow(title: language.crossfadeMenu, toggle: crossfadeSwitch, action: #selector(crossfadeChanged(_:)))
        self.crossfadeRow = crossfadeRow
        let petRow = makeValueRow(title: "Pet", control: petPopup)
        let modeRow = makeValueRow(title: "Appearance Mode", control: appearancePopup)
        let stack = NSStackView(views: [petRow, modeRow, appearanceStack, crossfadeRow, imageModeNote])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        appearanceStack.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        appearanceStack.heightAnchor.constraint(equalToConstant: 140).isActive = true
        petRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        modeRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        crossfadeRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func makeBehaviorBox(language: AppLanguage) -> NSView {
        let rows = NSStackView(views: [
            makeToggleRow(title: language.followCursorMenu, toggle: followSwitch, action: #selector(followChanged(_:))),
            separator(),
            makeToggleRow(title: language.freeRoamMenu, toggle: roamSwitch, action: #selector(roamChanged(_:))),
            separator(),
            makeToggleRow(title: language.imageFacingMenu, toggle: lookSwitch, action: #selector(lookChanged(_:)))
        ])
        return boxed(rows)
    }

    private func makeInteractionBox(language: AppLanguage) -> NSView {
        let box = settingsBox()
        let quickTitle = NSTextField(labelWithString: "Play Now")
        quickTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        quickTitle.textColor = .secondaryLabelColor
        inspectTrashButton.title = "Inspect Trash"
        configureActionButton(
            inspectTrashButton,
            symbol: "trash.fill",
            action: #selector(inspectTrashNow)
        )
        playWithItemButton.title = "Play with Desktop Item"
        configureActionButton(
            playWithItemButton,
            symbol: "doc.fill.badge.plus",
            action: #selector(playWithDesktopItemNow)
        )
        let quickActions = NSStackView(views: [inspectTrashButton, playWithItemButton])
        quickActions.orientation = .horizontal
        quickActions.distribution = .fillEqually
        quickActions.spacing = 10
        let content = NSStackView(views: [
            makeToggleRow(title: "Play with safe visual copies of desktop items", toggle: desktopInteractionsSwitch, action: #selector(desktopInteractionsChanged(_:))),
            separator(),
            quickTitle,
            quickActions
        ])
        content.orientation = .vertical
        content.spacing = 7
        pin(content, inside: box)
        return box
    }

    private func makeSpeechBox(language: AppLanguage) -> NSView {
        talkativenessSlider.minValue = 0
        talkativenessSlider.maxValue = 1
        talkativenessSlider.isContinuous = true
        talkativenessSlider.target = self
        talkativenessSlider.action = #selector(talkativenessChanged(_:))
        previewSpeechButton.title = "Preview Bubble"
        previewSpeechButton.bezelStyle = .rounded
        previewSpeechButton.target = self
        previewSpeechButton.action = #selector(previewSpeech)
        let rows = NSStackView(views: [
            makeToggleRow(title: "Show Pet Speech", toggle: speechBubblesSwitch, action: #selector(speechBubblesChanged(_:))),
            separator(),
            makeSliderRow(title: "Talkativeness", slider: talkativenessSlider, value: talkativenessValue),
            separator(),
            makeValueRow(title: "Bubble Style & Motion", control: previewSpeechButton)
        ])
        return boxed(rows)
    }

    private func makeGroupBox(language: AppLanguage) -> NSView {
        groupPetStack.orientation = .vertical
        groupPetStack.alignment = .leading
        groupPetStack.spacing = 9
        let note = NSTextField(wrappingLabelWithString: "Choose the companions that appear together. Group Play uses each pet’s validated image atlas so they can roam and react independently.")
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabelColor
        note.maximumNumberOfLines = 3
        let rows = NSStackView(views: [
            makeToggleRow(title: "Group Play", toggle: groupPlaySwitch, action: #selector(groupPlayChanged(_:))),
            separator(),
            note,
            groupPetStack
        ])
        return boxed(rows)
    }

    private func settingsBox() -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 16
        box.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.82).cgColor
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.34).cgColor
        box.layer?.shadowColor = NSColor.black.withAlphaComponent(0.18).cgColor
        box.layer?.shadowOpacity = 0.16
        box.layer?.shadowRadius = 12
        box.layer?.shadowOffset = CGSize(width: 0, height: -3)
        return box
    }

    private func separator() -> NSBox {
        let line = NSBox()
        line.boxType = .separator
        return line
    }

    private func pin(_ content: NSView, inside box: NSView) {
        content.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -18),
            content.topAnchor.constraint(equalTo: box.topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -14)
        ])
    }

    private func makeToggleRow(title: String, toggle: NSSwitch, action: Selector) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13.5, weight: .medium)
        toggle.controlSize = .regular
        toggle.target = self
        toggle.action = action
        let stack = NSStackView(views: [label, NSView(), toggle])
        stack.orientation = .horizontal
        stack.distribution = .fill
        stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
        return stack
    }

    private func makeValueRow(title: String, control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        let row = NSStackView(views: [label, NSView(), control])
        row.orientation = .horizontal
        row.alignment = .centerY
        return row
    }

    private func makeSliderRow(title: String, slider: NSSlider, value: NSTextField) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        value.textColor = .secondaryLabelColor
        value.alignment = .right
        value.setContentHuggingPriority(.required, for: .horizontal)
        slider.widthAnchor.constraint(equalToConstant: 210).isActive = true
        let row = NSStackView(views: [label, NSView(), slider, value])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func boxed(_ rows: NSStackView) -> NSView {
        rows.orientation = .vertical
        rows.spacing = 11
        let box = settingsBox()
        pin(rows, inside: box)
        return box
    }

    private func pageTitle(_ page: Page, language: AppLanguage) -> String {
        switch page {
        case .general: "General"
        case .appearance: "Appearance & Animation"
        case .behavior: "Behavior"
        case .interaction: "Desktop Interaction"
        case .group: "Pet Group"
        case .speech: "Speech"
        }
    }

    private func pageSymbol(_ page: Page) -> String {
        switch page {
        case .general: "slider.horizontal.3"
        case .appearance: "sparkles.rectangle.stack.fill"
        case .behavior: "figure.walk.motion"
        case .interaction: "macwindow.badge.plus"
        case .group: "pawprint.circle.fill"
        case .speech: "bubble.left.and.bubble.right.fill"
        }
    }

    private func configureActionButton(_ button: NSButton, symbol: String, action: Selector) {
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.contentTintColor = .controlAccentColor
        button.target = self
        button.action = action
        button.heightAnchor.constraint(equalToConstant: 38).isActive = true
    }

    private func pageSubtitle(_ page: Page, language: AppLanguage) -> String {
        switch page {
        case .general: "Adjust pet size and window behavior."
        case .appearance: "Choose an asset appearance and tune transitions for continuous video."
        case .behavior: "Choose how your pet watches, follows, and explores."
        case .interaction: "The pet may look at item names and icons, but the real files and Finder layout always remain untouched."
        case .group: "Let several selected pets roam together and respond to one another."
        case .speech: "Control speaking frequency and preview the calmer, polished bubble."
        }
    }

    private func applySnapshot() {
        guard isWindowLoaded else { return }
        let language = snapshot.language
        imageModeNote.stringValue = language.videoOptionsUnavailable
        petPopup.removeAllItems()
        for pet in snapshot.pets {
            petPopup.addItem(withTitle: pet.name)
            petPopup.lastItem?.representedObject = pet.id
        }
        if let index = petPopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == snapshot.activePetID }) {
            petPopup.selectItem(at: index)
        }
        appearancePopup.removeAllItems()
        for appearance in snapshot.appearances {
            appearancePopup.addItem(withTitle: appearance.title(for: language))
            appearancePopup.lastItem?.representedObject = appearance.id
        }
        appearancePopup.isEnabled = snapshot.canChangeAppearance && snapshot.appearances.count > 1
        if let index = appearancePopup.itemArray.firstIndex(where: {
            ($0.representedObject as? String) == snapshot.selectedAppearanceID
        }) {
            appearancePopup.selectItem(at: index)
        }
        appearanceStack.arrangedSubviews.forEach {
            appearanceStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for option in snapshot.appearances {
            let card = AppearanceCardView(
                option: option,
                language: language,
                isSelected: option.id == snapshot.selectedAppearanceID,
                isEnabled: snapshot.canChangeAppearance
            ) { [weak self] id in
                self?.selectAppearance(id)
            }
            appearanceStack.addArrangedSubview(card)
        }

        crossfadeSwitch.state = snapshot.crossfadeEnabled ? .on : .off
        followSwitch.state = snapshot.followCursor ? .on : .off
        roamSwitch.state = snapshot.freeRoam ? .on : .off
        lookSwitch.state = snapshot.directionalLook ? .on : .off
        desktopInteractionsSwitch.state = snapshot.desktopInteractions ? .on : .off
        alwaysOnTopSwitch.state = snapshot.alwaysOnTop ? .on : .off
        passThroughSwitch.state = snapshot.fullPassThrough ? .on : .off
        autoBehaviorSwitch.state = snapshot.autoBehavior ? .on : .off
        speechBubblesSwitch.state = snapshot.speechBubbles ? .on : .off
        petSizeSlider.doubleValue = Double(snapshot.petScale)
        petSizeValue.stringValue = "\(Int((snapshot.petScale * 100).rounded()))%"
        talkativenessSlider.doubleValue = snapshot.talkativeness
        talkativenessValue.stringValue = "\(Int((snapshot.talkativeness * 100).rounded()))%"
        talkativenessSlider.isEnabled = snapshot.speechBubbles
        previewSpeechButton.isEnabled = snapshot.speechBubbles
        rebuildGroupPetSelection()

        crossfadeSwitch.target = self
        crossfadeSwitch.action = #selector(crossfadeChanged(_:))
        followSwitch.target = self
        followSwitch.action = #selector(followChanged(_:))
        roamSwitch.target = self
        roamSwitch.action = #selector(roamChanged(_:))
        lookSwitch.target = self
        lookSwitch.action = #selector(lookChanged(_:))
        desktopInteractionsSwitch.target = self
        desktopInteractionsSwitch.action = #selector(desktopInteractionsChanged(_:))

        let isVideo = snapshot.appearances.first(where: {
            $0.id == snapshot.selectedAppearanceID
        })?.kind == .continuousVideo
        crossfadeRow?.isHidden = !isVideo
        imageModeNote.isHidden = isVideo
    }

    @objc private func activePetChanged(_ sender: NSPopUpButton) {
        guard let petID = sender.selectedItem?.representedObject as? String,
              petID != snapshot.activePetID else { return }
        if onPetSelected?(petID) != true,
           let previous = sender.itemArray.firstIndex(where: { ($0.representedObject as? String) == snapshot.activePetID }) {
            sender.selectItem(at: previous)
        }
    }

    @objc private func activeAppearanceChanged(_ sender: NSPopUpButton) {
        guard let appearanceID = sender.selectedItem?.representedObject as? String else { return }
        selectAppearance(appearanceID)
    }

    private func selectAppearance(_ id: String) {
        guard id != snapshot.selectedAppearanceID else { return }
        guard onAppearanceSelected?(id) == true else {
            if let previous = appearancePopup.itemArray.firstIndex(where: {
                ($0.representedObject as? String) == snapshot.selectedAppearanceID
            }) {
                appearancePopup.selectItem(at: previous)
            }
            return
        }
        // The callback synchronously refreshes the complete Settings snapshot.
        // Reapply only if a standalone host did not provide that refresh.
        if snapshot.selectedAppearanceID != id {
            snapshot = AppearanceSettingsSnapshot(
                appearances: snapshot.appearances,
                pets: snapshot.pets,
                activePetID: snapshot.activePetID,
                selectedAppearanceID: id,
                language: snapshot.language,
                crossfadeEnabled: snapshot.crossfadeEnabled,
                followCursor: snapshot.followCursor,
                freeRoam: snapshot.freeRoam,
                directionalLook: snapshot.directionalLook,
                desktopInteractions: snapshot.desktopInteractions,
                alwaysOnTop: snapshot.alwaysOnTop,
                petScale: snapshot.petScale,
                fullPassThrough: snapshot.fullPassThrough,
                autoBehavior: snapshot.autoBehavior,
                speechBubbles: snapshot.speechBubbles,
                talkativeness: snapshot.talkativeness,
                canChangeAppearance: snapshot.canChangeAppearance,
                groupPlayEnabled: snapshot.groupPlayEnabled,
                groupPetIDs: snapshot.groupPetIDs
            )
            applySnapshot()
        }
    }

    @objc private func crossfadeChanged(_ sender: NSSwitch) {
        onCrossfadeChanged?(sender.state == .on)
    }

    @objc private func followChanged(_ sender: NSSwitch) {
        if sender.state == .on, roamSwitch.state == .on { roamSwitch.state = .off }
        onFollowCursorChanged?(sender.state == .on)
    }

    @objc private func roamChanged(_ sender: NSSwitch) {
        if sender.state == .on, followSwitch.state == .on { followSwitch.state = .off }
        onFreeRoamChanged?(sender.state == .on)
    }

    @objc private func lookChanged(_ sender: NSSwitch) {
        onDirectionalLookChanged?(sender.state == .on)
    }

    @objc private func desktopInteractionsChanged(_ sender: NSSwitch) {
        onDesktopInteractionsChanged?(sender.state == .on)
    }

    @objc private func inspectTrashNow() { onInspectTrashNow?() }
    @objc private func playWithDesktopItemNow() { onPlayWithDesktopItemNow?() }

    @objc private func groupPlayChanged(_ sender: NSSwitch) {
        onGroupPlayChanged?(sender.state == .on)
    }

    @objc private func groupPetChanged(_ sender: NSButton) {
        guard let petID = sender.identifier?.rawValue else { return }
        var selected = snapshot.groupPetIDs
        if sender.state == .on { selected.insert(petID) } else { selected.remove(petID) }
        if selected.isEmpty {
            sender.state = .on
            return
        }
        onGroupPetSelectionChanged?(selected)
    }

    private func rebuildGroupPetSelection() {
        groupPlaySwitch.state = snapshot.groupPlayEnabled ? .on : .off
        groupPetStack.arrangedSubviews.forEach {
            groupPetStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        groupPetCheckboxes.removeAll()
        for pet in snapshot.pets {
            let supported = PetAssetCatalog.imageCapablePetIDs.contains(pet.id)
            let button = NSButton(
                checkboxWithTitle: "\(pet.name)  ·  \(supported ? "Ready" : "No image atlas")",
                target: self,
                action: #selector(groupPetChanged(_:))
            )
            button.identifier = NSUserInterfaceItemIdentifier(pet.id)
            button.state = snapshot.groupPetIDs.contains(pet.id) ? .on : .off
            button.isEnabled = supported
            groupPetStack.addArrangedSubview(button)
            groupPetCheckboxes[pet.id] = button
        }
    }

    @objc private func alwaysOnTopChanged(_ sender: NSSwitch) { onAlwaysOnTopChanged?(sender.state == .on) }
    @objc private func passThroughChanged(_ sender: NSSwitch) { onPassThroughChanged?(sender.state == .on) }
    @objc private func autoBehaviorChanged(_ sender: NSSwitch) { onAutoBehaviorChanged?(sender.state == .on) }
    @objc private func petSizeChanged(_ sender: NSSlider) {
        petSizeValue.stringValue = "\(Int((sender.doubleValue * 100).rounded()))%"
        onPetScaleChanged?(CGFloat(sender.doubleValue))
    }
    @objc private func speechBubblesChanged(_ sender: NSSwitch) {
        let enabled = sender.state == .on
        talkativenessSlider.isEnabled = enabled
        previewSpeechButton.isEnabled = enabled
        onSpeechBubblesChanged?(enabled)
    }
    @objc private func talkativenessChanged(_ sender: NSSlider) {
        talkativenessValue.stringValue = "\(Int((sender.doubleValue * 100).rounded()))%"
        onTalkativenessChanged?(sender.doubleValue)
    }
    @objc private func previewSpeech() { onPreviewSpeech?() }

}

@MainActor
final class AppearanceCardView: NSView {
    private let optionID: String
    private let onSelect: (String) -> Void
    private let selected: Bool
    private let cardIsEnabled: Bool
    private var trackingAreaToken: NSTrackingArea?
    private var hovering = false

    init(
        option: PetAppearanceOption,
        language: AppLanguage,
        isSelected: Bool,
        isEnabled: Bool,
        onSelect: @escaping (String) -> Void
    ) {
        optionID = option.id
        self.onSelect = onSelect
        selected = isSelected
        cardIsEnabled = isEnabled
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("appearance-card-\(option.id)")
        setAccessibilityRole(.button)
        setAccessibilityLabel(option.title(for: language))
        setAccessibilityEnabled(isEnabled)
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.borderWidth = isSelected ? 1.5 : 1
        updateCardAppearance()

        let iconBadge = NSView()
        iconBadge.wantsLayer = true
        iconBadge.layer?.cornerRadius = 11
        iconBadge.layer?.backgroundColor = (isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.16)
            : NSColor.secondaryLabelColor.withAlphaComponent(0.08)).cgColor
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: option.systemImage, accessibilityDescription: nil)
        icon.contentTintColor = isSelected ? .controlAccentColor : .secondaryLabelColor
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconBadge.addSubview(icon)

        let title = NSTextField(labelWithString: option.title(for: language))
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: option.subtitle(for: language))
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2

        let status = NSImageView()
        status.image = NSImage(
            systemSymbolName: isSelected ? "checkmark.circle.fill" : "circle",
            accessibilityDescription: isSelected ? "Selected" : "Not selected"
        )
        status.contentTintColor = isSelected ? .controlAccentColor : .tertiaryLabelColor
        status.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)

        for view in [iconBadge, title, subtitle, status] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconBadge.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            iconBadge.widthAnchor.constraint(equalToConstant: 42),
            iconBadge.heightAnchor.constraint(equalToConstant: 42),
            icon.centerXAnchor.constraint(equalTo: iconBadge.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconBadge.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
            status.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
            status.topAnchor.constraint(equalTo: topAnchor, constant: 15),
            status.widthAnchor.constraint(equalToConstant: 19),
            status.heightAnchor.constraint(equalToConstant: 19),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            title.topAnchor.constraint(equalTo: iconBadge.bottomAnchor, constant: 10),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            subtitle.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10)
        ])

        // A native button sits above all decorative labels and icons. The
        // previous card used its content views as hit targets, so AppKit sent
        // real clicks to a static text field instead of the selection action.
        let clickOverlay = NSButton(title: "", target: self, action: #selector(cardClicked))
        clickOverlay.isBordered = false
        clickOverlay.focusRingType = .none
        clickOverlay.setButtonType(.momentaryChange)
        clickOverlay.isEnabled = isEnabled
        clickOverlay.setAccessibilityLabel(option.title(for: language))
        clickOverlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clickOverlay)
        NSLayoutConstraint.activate([
            clickOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            clickOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            clickOverlay.topAnchor.constraint(equalTo: topAnchor),
            clickOverlay.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaToken { removeTrackingArea(trackingAreaToken) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaToken = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        updateCardAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        updateCardAppearance()
    }

    override var mouseDownCanMoveWindow: Bool { false }

    @objc private func cardClicked() {
        guard cardIsEnabled else { return }
        // Do not rebuild this card while AppKit is still finishing its mouse
        // tracking callback. Deferring one run-loop turn keeps consecutive
        // physical clicks alive after the first appearance change.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onSelect(self.optionID)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard cardIsEnabled else { return false }
        onSelect(optionID)
        return true
    }

    func activateForQA() {
        guard cardIsEnabled else { return }
        onSelect(optionID)
    }

    private func updateCardAppearance() {
        let accent = NSColor.controlAccentColor
        layer?.borderColor = (selected ? accent : NSColor.separatorColor)
            .withAlphaComponent(selected ? 0.85 : (hovering ? 0.68 : 0.34)).cgColor
        layer?.backgroundColor = (selected
            ? accent.withAlphaComponent(0.11)
            : NSColor.controlBackgroundColor.withAlphaComponent(hovering ? 0.95 : 0.74)).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = hovering || selected ? 0.14 : 0.06
        layer?.shadowRadius = hovering ? 10 : 6
        layer?.shadowOffset = CGSize(width: 0, height: -2)
    }
}

extension NSView {
    func viewWithIdentifier(_ rawValue: String) -> NSView? {
        if identifier?.rawValue == rawValue { return self }
        for subview in subviews {
            if let match = subview.viewWithIdentifier(rawValue) { return match }
        }
        return nil
    }
}
