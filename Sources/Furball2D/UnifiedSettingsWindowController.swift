import AppKit

@MainActor
final class UnifiedSettingsWindowController: NSWindowController, NSWindowDelegate {
    enum Section: Int {
        case appearance
        case library
        case creator
    }

    var onAppearanceSelected: ((String) -> Bool)? {
        didSet { appearanceController.onAppearanceSelected = onAppearanceSelected }
    }
    var onCrossfadeChanged: ((Bool) -> Void)? {
        didSet { appearanceController.onCrossfadeChanged = onCrossfadeChanged }
    }
    var onFollowCursorChanged: ((Bool) -> Void)? {
        didSet { appearanceController.onFollowCursorChanged = onFollowCursorChanged }
    }
    var onFreeRoamChanged: ((Bool) -> Void)? {
        didSet { appearanceController.onFreeRoamChanged = onFreeRoamChanged }
    }
    var onDirectionalLookChanged: ((Bool) -> Void)? {
        didSet { appearanceController.onDirectionalLookChanged = onDirectionalLookChanged }
    }
    var onDesktopInteractionsChanged: ((Bool) -> Void)? {
        didSet { appearanceController.onDesktopInteractionsChanged = onDesktopInteractionsChanged }
    }
    var onIconRearrangementChanged: ((Bool) -> Void)? {
        didSet { appearanceController.onIconRearrangementChanged = onIconRearrangementChanged }
    }
    var onSelectPet: ((String) -> Bool)? {
        didSet { libraryController.onSelectPet = onSelectPet }
    }
    var onLibraryChanged: (() -> Void)? {
        didSet { libraryController.onLibraryChanged = onLibraryChanged }
    }

    private let appearanceController: AppearanceSettingsWindowController
    private let libraryController: PetLibraryWindowController
    private let appearancePage: NSView
    private let libraryPage: NSView
    private let sidebarTitle = NSTextField(labelWithString: "")
    private let appearanceButton = NSButton()
    private let libraryButton = NSButton()
    private let creatorButton = NSButton()
    private var language: AppLanguage
    private var selectedSection: Section = .appearance

    init(snapshot: AppearanceSettingsSnapshot, language: AppLanguage) {
        self.language = language
        appearanceController = AppearanceSettingsWindowController(snapshot: snapshot)
        libraryController = PetLibraryWindowController(language: language, embedded: true)
        appearancePage = appearanceController.contentViewForEmbedding()
        libraryPage = libraryController.contentViewForEmbedding()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 900, height: 590)
        window.center()
        super.init(window: window)
        window.delegate = self
        buildInterface()
        applyLanguage()
        select(.appearance)
    }

    required init?(coder: NSCoder) { nil }

    func update(snapshot: AppearanceSettingsSnapshot, language: AppLanguage) {
        self.language = language
        appearanceController.update(snapshot: snapshot)
        libraryController.refresh(language: language)
        applyLanguage()
    }

    func present(section: Section) {
        select(section)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        VisualQACapture.schedule(view: window?.contentView, name: "settings-\(section.rawValue)")
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
        sidebarTitle.font = .systemFont(ofSize: 20, weight: .bold)

        configureSidebarButton(appearanceButton, symbol: "sparkles.rectangle.stack", action: #selector(showAppearance))
        configureSidebarButton(libraryButton, symbol: "square.grid.2x2", action: #selector(showLibrary))
        configureSidebarButton(creatorButton, symbol: "wand.and.stars", action: #selector(showCreator))
        let navigation = NSStackView(views: [appearanceButton, libraryButton, creatorButton])
        navigation.orientation = .vertical
        navigation.alignment = .leading
        navigation.spacing = 5

        for view in [sidebarTitle, navigation] {
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
            sidebar.widthAnchor.constraint(equalToConstant: 196),
            sidebarTitle.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            sidebarTitle.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 52),
            navigation.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 10),
            navigation.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -10),
            navigation.topAnchor.constraint(equalTo: sidebarTitle.bottomAnchor, constant: 22),
            appearanceButton.widthAnchor.constraint(equalTo: navigation.widthAnchor),
            libraryButton.widthAnchor.constraint(equalTo: navigation.widthAnchor),
            creatorButton.widthAnchor.constraint(equalTo: navigation.widthAnchor),
            content.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.topAnchor.constraint(equalTo: root.topAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
    }

    private func configureSidebarButton(_ button: NSButton, symbol: String, action: Selector) {
        button.bezelStyle = .recessed
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.alignment = .left
        button.controlSize = .large
        button.target = self
        button.action = action
    }

    private func applyLanguage() {
        sidebarTitle.stringValue = language == .simplifiedChinese ? "设置" : "Settings"
        appearanceButton.title = language == .simplifiedChinese ? "视觉与动画" : "Visual & Motion"
        libraryButton.title = language.libraryTab
        creatorButton.title = language.creatorTab
        window?.title = sidebarTitle.stringValue
    }

    private func select(_ section: Section) {
        selectedSection = section
        appearancePage.isHidden = section != .appearance
        libraryPage.isHidden = section == .appearance
        if section == .library { libraryController.showLibraryEmbedded() }
        if section == .creator { libraryController.showCreatorEmbedded() }
        appearanceButton.state = section == .appearance ? .on : .off
        libraryButton.state = section == .library ? .on : .off
        creatorButton.state = section == .creator ? .on : .off
    }

    @objc private func showAppearance() { select(.appearance) }
    @objc private func showLibrary() { select(.library) }
    @objc private func showCreator() { select(.creator) }
}
