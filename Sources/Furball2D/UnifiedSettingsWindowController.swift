import AppKit

@MainActor
final class UnifiedSettingsWindowController: NSWindowController, NSWindowDelegate {
    enum Section: Int {
        case general
        case library
        case behavior
        case group
        case creator
    }

    var onAppearanceSelected: ((String) -> Bool)? {
        didSet {
            appearanceController.onAppearanceSelected = onAppearanceSelected
            libraryController.onAppearanceSelected = onAppearanceSelected
        }
    }
    var onCrossfadeChanged: ((Bool) -> Void)? {
        didSet { appearanceController.onCrossfadeChanged = onCrossfadeChanged }
    }
    var onAnimationSpeedChanged: ((Double) -> Void)? {
        didSet {
            appearanceController.onAnimationSpeedChanged = onAnimationSpeedChanged
            libraryController.onAnimationSpeedChanged = onAnimationSpeedChanged
        }
    }
    var onBodySizeChanged: ((String, Int) -> Void)? {
        didSet { libraryController.onBodySizeChanged = onBodySizeChanged }
    }
    var onFollowCursorChanged: ((Bool) -> Void)? {
        didSet { appearanceController.onFollowCursorChanged = onFollowCursorChanged }
    }
    var onFreeRoamChanged: ((Bool) -> Void)? {
        didSet { appearanceController.onFreeRoamChanged = onFreeRoamChanged }
    }
    var onFreeRoamRestIntervalChanged: ((Double) -> Void)? {
        didSet { appearanceController.onFreeRoamRestIntervalChanged = onFreeRoamRestIntervalChanged }
    }
    var onDirectionalLookChanged: ((Bool) -> Void)? {
        didSet { appearanceController.onDirectionalLookChanged = onDirectionalLookChanged }
    }
    var onDesktopInteractionsChanged: ((Bool) -> Void)? {
        didSet { appearanceController.onDesktopInteractionsChanged = onDesktopInteractionsChanged }
    }
    var onInspectTrashNow: (() -> Void)? {
        didSet { appearanceController.onInspectTrashNow = onInspectTrashNow }
    }
    var onPlayWithDesktopItemNow: (() -> Void)? {
        didSet { appearanceController.onPlayWithDesktopItemNow = onPlayWithDesktopItemNow }
    }
    var onGroupPlayChanged: ((Bool) -> Void)? {
        didSet { appearanceController.onGroupPlayChanged = onGroupPlayChanged }
    }
    var onGroupPetSelectionChanged: ((Set<String>) -> Void)? {
        didSet { appearanceController.onGroupPetSelectionChanged = onGroupPetSelectionChanged }
    }
    var onAlwaysOnTopChanged: ((Bool) -> Void)? {
        didSet { appearanceController.onAlwaysOnTopChanged = onAlwaysOnTopChanged }
    }
    var onPetScaleChanged: ((CGFloat) -> Void)? {
        didSet { appearanceController.onPetScaleChanged = onPetScaleChanged }
    }
    var onPassThroughChanged: ((Bool) -> Void)? {
        didSet { appearanceController.onPassThroughChanged = onPassThroughChanged }
    }
    var onAutoBehaviorChanged: ((Bool) -> Void)? {
        didSet { appearanceController.onAutoBehaviorChanged = onAutoBehaviorChanged }
    }
    var onSpeechBubblesChanged: ((Bool) -> Void)? {
        didSet { appearanceController.onSpeechBubblesChanged = onSpeechBubblesChanged }
    }
    var onTalkativenessChanged: ((Double) -> Void)? {
        didSet { appearanceController.onTalkativenessChanged = onTalkativenessChanged }
    }
    var onSpeechBubbleStyleChanged: ((PetSpeechBubbleStyle) -> Void)? {
        didSet { appearanceController.onSpeechBubbleStyleChanged = onSpeechBubbleStyleChanged }
    }
    var onPreviewSpeech: (() -> Void)? {
        didSet { appearanceController.onPreviewSpeech = onPreviewSpeech }
    }
    var onSelectPet: ((String) -> Bool)? {
        didSet {
            libraryController.onSelectPet = onSelectPet
            appearanceController.onPetSelected = onSelectPet
        }
    }
    var onLibraryChanged: (() -> Void)? {
        didSet { libraryController.onLibraryChanged = onLibraryChanged }
    }

    private let appearanceController: AppearanceSettingsWindowController
    private let libraryController: PetLibraryWindowController
    private let appearancePage: NSView
    private let libraryPage: NSView
    private let sidebarTitle = NSTextField(labelWithString: "")
    private let generalButton = NSButton()
    private let behaviorButton = NSButton()
    private let groupButton = NSButton()
    private let libraryButton = NSButton()
    private let creatorButton = NSButton()
    private var language: AppLanguage
    private var selectedSection: Section = .general

    init(snapshot: AppearanceSettingsSnapshot, language: AppLanguage) {
        self.language = language
        appearanceController = AppearanceSettingsWindowController(snapshot: snapshot)
        libraryController = PetLibraryWindowController(language: language, embedded: true)
        appearancePage = appearanceController.contentViewForEmbedding()
        libraryPage = libraryController.contentViewForEmbedding()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1020, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 920, height: 620)
        window.center()
        super.init(window: window)
        window.delegate = self
        buildInterface()
        libraryController.updateProfileControls(animationSpeed: snapshot.animationSpeed)
        applyLanguage()
        select(.general)
    }

    required init?(coder: NSCoder) { nil }

    func update(snapshot: AppearanceSettingsSnapshot, language: AppLanguage) {
        self.language = language
        appearanceController.update(snapshot: snapshot)
        libraryController.refresh(language: language)
        libraryController.updateProfileControls(animationSpeed: snapshot.animationSpeed)
        applyLanguage()
    }

    func present(section: Section) {
        select(section)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        VisualQACapture.schedule(view: window?.contentView, name: "settings-\(section.rawValue)")
    }

    @discardableResult
    func performAppearanceClickForQA(id: String) -> Bool {
        window?.contentView?.layoutSubtreeIfNeeded()
        return appearanceController.performAppearanceClickForQA(id: id)
    }

    @discardableResult
    func performPetSelectionForQA(id: String) -> Bool {
        window?.contentView?.layoutSubtreeIfNeeded()
        return appearanceController.performPetSelectionForQA(id: id)
    }

    private func buildInterface() {
        guard let window else { return }
        let root = NSVisualEffectView()
        root.material = .contentBackground
        root.blendingMode = .behindWindow
        root.state = .active
        window.contentView = root

        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .withinWindow
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebarTitle.font = .systemFont(ofSize: 22, weight: .bold)

        let brandIcon = NSImageView()
        brandIcon.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: nil)
        brandIcon.contentTintColor = .controlAccentColor
        brandIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 19, weight: .bold)
        let brand = NSStackView(views: [brandIcon, sidebarTitle])
        brand.orientation = .horizontal
        brand.alignment = .centerY
        brand.spacing = 9

        configureSidebarButton(generalButton, symbol: "gearshape", action: #selector(showGeneral))
        configureSidebarButton(behaviorButton, symbol: "figure.walk.motion", action: #selector(showBehavior))
        configureSidebarButton(groupButton, symbol: "pawprint.circle", action: #selector(showGroup))
        configureSidebarButton(libraryButton, symbol: "square.grid.2x2", action: #selector(showLibrary))
        configureSidebarButton(creatorButton, symbol: "wand.and.stars", action: #selector(showCreator))
        let companionLabel = sidebarSectionLabel("FURBALL")
        let creationLabel = sidebarSectionLabel("CREATE")
        let navigation = NSStackView(views: [
            companionLabel, generalButton, libraryButton, behaviorButton, groupButton,
            creationLabel, creatorButton
        ])
        navigation.orientation = .vertical
        navigation.alignment = .leading
        navigation.spacing = 6
        navigation.setCustomSpacing(13, after: groupButton)

        for view in [brand, navigation] {
            view.translatesAutoresizingMaskIntoConstraints = false
            sidebar.addSubview(view)
        }

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.wantsLayer = true
        content.layer?.masksToBounds = true
        for page in [appearancePage, libraryPage] {
            page.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(page)
            NSLayoutConstraint.activate([
                page.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                page.topAnchor.constraint(equalTo: content.topAnchor),
                page.bottomAnchor.constraint(equalTo: content.bottomAnchor)
            ])
        }

        root.addSubview(sidebar)
        root.addSubview(content)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 228),
            brand.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            brand.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 48),
            navigation.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            navigation.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            navigation.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 28),
            generalButton.widthAnchor.constraint(equalTo: navigation.widthAnchor),
            behaviorButton.widthAnchor.constraint(equalTo: navigation.widthAnchor),
            groupButton.widthAnchor.constraint(equalTo: navigation.widthAnchor),
            libraryButton.widthAnchor.constraint(equalTo: navigation.widthAnchor),
            creatorButton.widthAnchor.constraint(equalTo: navigation.widthAnchor),
            content.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.topAnchor.constraint(equalTo: root.topAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
    }

    private func configureSidebarButton(_ button: NSButton, symbol: String, action: Selector) {
        button.isBordered = false
        button.bezelStyle = .inline
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.alignment = .left
        button.controlSize = .large
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.contentTintColor = .secondaryLabelColor
        button.wantsLayer = true
        button.layer?.cornerRadius = 9
        button.heightAnchor.constraint(equalToConstant: 38).isActive = true
        button.target = self
        button.action = action
    }

    private func sidebarSectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        return label
    }

    private func applyLanguage() {
        sidebarTitle.stringValue = "Settings"
        generalButton.title = "General"
        behaviorButton.title = "Behavior"
        groupButton.title = "Group Play"
        libraryButton.title = "My Pets"
        creatorButton.title = language.creatorTab
        window?.title = sidebarTitle.stringValue
    }

    private func select(_ section: Section) {
        selectedSection = section
        let corePage: AppearanceSettingsWindowController.Page?
        switch section {
        case .general: corePage = .general
        case .behavior: corePage = .behavior
        case .group: corePage = .group
        case .library, .creator: corePage = nil
        }
        appearancePage.isHidden = corePage == nil
        libraryPage.isHidden = corePage != nil
        if let corePage {
            appearanceController.show(page: corePage)
        } else {
            if section == .library { libraryController.showLibraryEmbedded() }
            if section == .creator { libraryController.showCreatorEmbedded() }
        }
        generalButton.state = section == .general ? .on : .off
        behaviorButton.state = section == .behavior ? .on : .off
        groupButton.state = section == .group ? .on : .off
        libraryButton.state = section == .library ? .on : .off
        creatorButton.state = section == .creator ? .on : .off
        updateSidebarSelection()
    }

    private func updateSidebarSelection() {
        let selectedButton: NSButton
        switch selectedSection {
        case .general: selectedButton = generalButton
        case .library: selectedButton = libraryButton
        case .behavior: selectedButton = behaviorButton
        case .group: selectedButton = groupButton
        case .creator: selectedButton = creatorButton
        }
        for button in [
            generalButton, libraryButton, behaviorButton, groupButton, creatorButton
        ] {
            let isSelected = button === selectedButton
            button.contentTintColor = isSelected ? .controlAccentColor : .secondaryLabelColor
            button.font = .systemFont(ofSize: 13, weight: isSelected ? .semibold : .medium)
            button.layer?.backgroundColor = (isSelected
                ? NSColor.controlAccentColor.withAlphaComponent(0.14)
                : NSColor.clear).cgColor
        }
    }

    @objc private func showGeneral() { select(.general) }
    @objc private func showBehavior() { select(.behavior) }
    @objc private func showGroup() { select(.group) }
    @objc private func showLibrary() { select(.library) }
    @objc private func showCreator() { select(.creator) }
}
