import AppKit

struct AppearanceSettingsSnapshot {
    let appearances: [PetAppearanceOption]
    let selectedAppearanceID: String
    let language: AppLanguage
    let crossfadeEnabled: Bool
    let followCursor: Bool
    let freeRoam: Bool
    let directionalLook: Bool
    let desktopInteractions: Bool
    let allowIconRearrangement: Bool
    let alwaysOnTop: Bool
    let petScale: CGFloat
    let fullPassThrough: Bool
    let autoBehavior: Bool
    let speechBubbles: Bool
    let talkativeness: Double
    let canChangeAppearance: Bool
}

@MainActor
final class AppearanceSettingsWindowController: NSWindowController, NSWindowDelegate {
    enum Page: CaseIterable {
        case general
        case appearance
        case behavior
        case interaction
        case speech
    }

    var onAppearanceSelected: ((String) -> Bool)?
    var onCrossfadeChanged: ((Bool) -> Void)?
    var onFollowCursorChanged: ((Bool) -> Void)?
    var onFreeRoamChanged: ((Bool) -> Void)?
    var onDirectionalLookChanged: ((Bool) -> Void)?
    var onDesktopInteractionsChanged: ((Bool) -> Void)?
    var onIconRearrangementChanged: ((Bool) -> Void)?
    var onAlwaysOnTopChanged: ((Bool) -> Void)?
    var onPetScaleChanged: ((CGFloat) -> Void)?
    var onPassThroughChanged: ((Bool) -> Void)?
    var onAutoBehaviorChanged: ((Bool) -> Void)?
    var onLanguageChanged: ((AppLanguage) -> Void)?
    var onSpeechBubblesChanged: ((Bool) -> Void)?
    var onTalkativenessChanged: ((Double) -> Void)?
    var onPreviewSpeech: (() -> Void)?

    private var snapshot: AppearanceSettingsSnapshot
    private var pages: [Page: NSView] = [:]
    private var selectedPage: Page = .general
    private let imageModeNote = NSTextField(wrappingLabelWithString: "")
    private let appearanceStack = NSStackView()
    private let crossfadeSwitch = NSSwitch()
    private weak var crossfadeRow: NSView?
    private let followSwitch = NSSwitch()
    private let roamSwitch = NSSwitch()
    private let lookSwitch = NSSwitch()
    private let desktopInteractionsSwitch = NSSwitch()
    private let iconRearrangementSwitch = NSSwitch()
    private let alwaysOnTopSwitch = NSSwitch()
    private let passThroughSwitch = NSSwitch()
    private let autoBehaviorSwitch = NSSwitch()
    private let speechBubblesSwitch = NSSwitch()
    private let petSizeSlider = NSSlider()
    private let petSizeValue = NSTextField(labelWithString: "")
    private let talkativenessSlider = NSSlider()
    private let talkativenessValue = NSTextField(labelWithString: "")
    private let languagePopup = NSPopUpButton()
    private let previewSpeechButton = NSButton()

    init(snapshot: AppearanceSettingsSnapshot) {
        self.snapshot = snapshot

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 590),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 720, height: 560)
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
        let title = NSTextField(labelWithString: pageTitle(page, language: language))
        title.font = .systemFont(ofSize: 27, weight: .bold)
        let subtitle = NSTextField(wrappingLabelWithString: pageSubtitle(page, language: language))
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 3

        let body: NSView
        switch page {
        case .general: body = makeGeneralBox(language: language)
        case .appearance: body = makeAppearanceContent(language: language)
        case .behavior: body = makeBehaviorBox(language: language)
        case .interaction: body = makeInteractionBox(language: language)
        case .speech: body = makeSpeechBox(language: language)
        }

        let stack = NSStackView(views: [title, subtitle, body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.setCustomSpacing(5, after: title)
        stack.translatesAutoresizingMaskIntoConstraints = false
        main.addSubview(stack)
        body.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 34),
            stack.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -34),
            stack.topAnchor.constraint(equalTo: main.topAnchor, constant: 52),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: main.bottomAnchor, constant: -28),
            body.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return main
    }

    private func makeGeneralBox(language: AppLanguage) -> NSView {
        languagePopup.removeAllItems()
        AppLanguage.allCases.forEach { languagePopup.addItem(withTitle: $0.displayName) }
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))
        petSizeSlider.minValue = 0.6
        petSizeSlider.maxValue = 1.4
        petSizeSlider.isContinuous = true
        petSizeSlider.target = self
        petSizeSlider.action = #selector(petSizeChanged(_:))
        let rows = NSStackView(views: [
            makeValueRow(title: language == .simplifiedChinese ? "语言" : "Language", control: languagePopup),
            separator(),
            makeSliderRow(title: language == .simplifiedChinese ? "宠物大小" : "Pet Size", slider: petSizeSlider, value: petSizeValue),
            separator(),
            makeToggleRow(title: language == .simplifiedChinese ? "始终置顶" : "Always on Top", toggle: alwaysOnTopSwitch, action: #selector(alwaysOnTopChanged(_:))),
            separator(),
            makeToggleRow(title: language == .simplifiedChinese ? "完全鼠标穿透" : "Click Through Completely", toggle: passThroughSwitch, action: #selector(passThroughChanged(_:))),
            separator(),
            makeToggleRow(title: language == .simplifiedChinese ? "自动作息与活动" : "Autonomous Routine", toggle: autoBehaviorSwitch, action: #selector(autoBehaviorChanged(_:)))
        ])
        return boxed(rows)
    }

    private func makeAppearanceContent(language: AppLanguage) -> NSView {
        appearanceStack.orientation = .horizontal
        appearanceStack.alignment = .top
        appearanceStack.distribution = .fillEqually
        appearanceStack.spacing = 10
        imageModeNote.font = .systemFont(ofSize: 12)
        imageModeNote.textColor = .tertiaryLabelColor
        imageModeNote.maximumNumberOfLines = 2
        let crossfadeRow = makeToggleRow(title: language.crossfadeMenu, toggle: crossfadeSwitch, action: #selector(crossfadeChanged(_:)))
        self.crossfadeRow = crossfadeRow
        let stack = NSStackView(views: [appearanceStack, crossfadeRow, imageModeNote])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        appearanceStack.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        appearanceStack.heightAnchor.constraint(equalToConstant: 116).isActive = true
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
        let content = NSStackView(views: [
            makeToggleRow(title: language == .simplifiedChinese ? "和桌面物品玩耍、撕咬与叼取" : "Play, bite, and carry desktop items", toggle: desktopInteractionsSwitch, action: #selector(desktopInteractionsChanged(_:))),
            separator(),
            makeToggleRow(title: language.iconRearrangementSetting, toggle: iconRearrangementSwitch, action: #selector(iconRearrangementChanged(_:)))
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
        previewSpeechButton.title = language == .simplifiedChinese ? "预览新气泡" : "Preview Bubble"
        previewSpeechButton.bezelStyle = .rounded
        previewSpeechButton.target = self
        previewSpeechButton.action = #selector(previewSpeech)
        let rows = NSStackView(views: [
            makeToggleRow(title: language == .simplifiedChinese ? "显示宠物对话" : "Show Pet Speech", toggle: speechBubblesSwitch, action: #selector(speechBubblesChanged(_:))),
            separator(),
            makeSliderRow(title: language == .simplifiedChinese ? "话痨程度" : "Talkativeness", slider: talkativenessSlider, value: talkativenessValue),
            separator(),
            makeValueRow(title: language == .simplifiedChinese ? "气泡样式与跟随效果" : "Bubble Style & Motion", control: previewSpeechButton)
        ])
        return boxed(rows)
    }

    private func settingsBox() -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 12
        box.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.42).cgColor
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
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            content.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -10)
        ])
    }

    private func makeToggleRow(title: String, toggle: NSSwitch, action: Selector) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        toggle.controlSize = .small
        toggle.target = self
        toggle.action = action
        let stack = NSStackView(views: [label, NSView(), toggle])
        stack.orientation = .horizontal
        stack.distribution = .fill
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
        rows.spacing = 10
        let box = settingsBox()
        pin(rows, inside: box)
        return box
    }

    private func pageTitle(_ page: Page, language: AppLanguage) -> String {
        switch (page, language) {
        case (.general, .simplifiedChinese): "常规"
        case (.general, .english): "General"
        case (.appearance, .simplifiedChinese): "外观与动画"
        case (.appearance, .english): "Appearance & Animation"
        case (.behavior, .simplifiedChinese): "行为"
        case (.behavior, .english): "Behavior"
        case (.interaction, .simplifiedChinese): "桌面互动"
        case (.interaction, .english): "Desktop Interaction"
        case (.speech, .simplifiedChinese): "对话"
        case (.speech, .english): "Speech"
        }
    }

    private func pageSubtitle(_ page: Page, language: AppLanguage) -> String {
        switch (page, language) {
        case (.general, .simplifiedChinese): "调整窗口、尺寸和应用语言。"
        case (.general, .english): "Adjust window behavior, size, and app language."
        case (.appearance, .simplifiedChinese): "选择素材外观；连续动画可单独控制自然转场。"
        case (.appearance, .english): "Choose an asset appearance and tune transitions for continuous video."
        case (.behavior, .simplifiedChinese): "决定它如何观察、跟随和自主探索桌面。"
        case (.behavior, .english): "Choose how your pet watches, follows, and explores."
        case (.interaction, .simplifiedChinese): "让它发现文件、轻轻撕咬并叼着走一小段。真正移动 Finder 图标仍需单独授权。"
        case (.interaction, .english): "Let it discover, nibble, and carry files briefly. Moving Finder icons remains a separate opt-in."
        case (.speech, .simplifiedChinese): "控制说话频率，并预览更克制、更精致的新气泡。"
        case (.speech, .english): "Control speaking frequency and preview the calmer, polished bubble."
        }
    }

    private func applySnapshot() {
        guard isWindowLoaded else { return }
        let language = snapshot.language
        imageModeNote.stringValue = language.videoOptionsUnavailable
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
                guard let self else { return }
                if self.onAppearanceSelected?(id) == true {
                    self.snapshot = AppearanceSettingsSnapshot(
                        appearances: self.snapshot.appearances,
                        selectedAppearanceID: id,
                        language: self.snapshot.language,
                        crossfadeEnabled: self.snapshot.crossfadeEnabled,
                        followCursor: self.snapshot.followCursor,
                        freeRoam: self.snapshot.freeRoam,
                        directionalLook: self.snapshot.directionalLook,
                        desktopInteractions: self.snapshot.desktopInteractions,
                        allowIconRearrangement: self.snapshot.allowIconRearrangement,
                        alwaysOnTop: self.snapshot.alwaysOnTop,
                        petScale: self.snapshot.petScale,
                        fullPassThrough: self.snapshot.fullPassThrough,
                        autoBehavior: self.snapshot.autoBehavior,
                        speechBubbles: self.snapshot.speechBubbles,
                        talkativeness: self.snapshot.talkativeness,
                        canChangeAppearance: self.snapshot.canChangeAppearance
                    )
                    self.applySnapshot()
                }
            }
            appearanceStack.addArrangedSubview(card)
        }

        crossfadeSwitch.state = snapshot.crossfadeEnabled ? .on : .off
        followSwitch.state = snapshot.followCursor ? .on : .off
        roamSwitch.state = snapshot.freeRoam ? .on : .off
        lookSwitch.state = snapshot.directionalLook ? .on : .off
        desktopInteractionsSwitch.state = snapshot.desktopInteractions ? .on : .off
        iconRearrangementSwitch.state = snapshot.allowIconRearrangement ? .on : .off
        iconRearrangementSwitch.isEnabled = snapshot.desktopInteractions
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
        languagePopup.selectItem(at: AppLanguage.allCases.firstIndex(of: language) ?? 0)

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
        iconRearrangementSwitch.target = self
        iconRearrangementSwitch.action = #selector(iconRearrangementChanged(_:))

        let isVideo = snapshot.appearances.first(where: {
            $0.id == snapshot.selectedAppearanceID
        })?.kind == .continuousVideo
        crossfadeRow?.isHidden = !isVideo
        imageModeNote.isHidden = isVideo
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
        iconRearrangementSwitch.isEnabled = sender.state == .on
        if sender.state == .off { iconRearrangementSwitch.state = .off }
        onDesktopInteractionsChanged?(sender.state == .on)
        if sender.state == .off { onIconRearrangementChanged?(false) }
    }

    @objc private func iconRearrangementChanged(_ sender: NSSwitch) {
        onIconRearrangementChanged?(sender.state == .on)
    }

    @objc private func alwaysOnTopChanged(_ sender: NSSwitch) { onAlwaysOnTopChanged?(sender.state == .on) }
    @objc private func passThroughChanged(_ sender: NSSwitch) { onPassThroughChanged?(sender.state == .on) }
    @objc private func autoBehaviorChanged(_ sender: NSSwitch) { onAutoBehaviorChanged?(sender.state == .on) }
    @objc private func petSizeChanged(_ sender: NSSlider) {
        petSizeValue.stringValue = "\(Int((sender.doubleValue * 100).rounded()))%"
        onPetScaleChanged?(CGFloat(sender.doubleValue))
    }
    @objc private func languageChanged(_ sender: NSPopUpButton) {
        guard sender.indexOfSelectedItem >= 0 else { return }
        onLanguageChanged?(AppLanguage.allCases[sender.indexOfSelectedItem])
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
final class AppearanceCardView: NSControl {
    private let optionID: String
    private let onSelect: (String) -> Void

    init(
        option: PetAppearanceOption,
        language: AppLanguage,
        isSelected: Bool,
        isEnabled: Bool,
        onSelect: @escaping (String) -> Void
    ) {
        optionID = option.id
        self.onSelect = onSelect
        super.init(frame: .zero)
        self.isEnabled = isEnabled
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = isSelected ? 2 : 1
        layer?.borderColor = (isSelected ? NSColor.controlAccentColor : NSColor.separatorColor)
            .withAlphaComponent(isSelected ? 0.90 : 0.45).cgColor
        layer?.backgroundColor = (isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.10)
            : NSColor.controlBackgroundColor.withAlphaComponent(0.72)).cgColor

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: option.systemImage, accessibilityDescription: nil)
        icon.contentTintColor = isSelected ? .controlAccentColor : .secondaryLabelColor
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)

        let title = NSTextField(labelWithString: option.title(for: language))
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: option.subtitle(for: language))
        subtitle.font = .systemFont(ofSize: 10.5)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2

        let radio = NSButton(radioButtonWithTitle: "", target: self, action: #selector(selectCard))
        radio.state = isSelected ? .on : .off
        radio.isEnabled = isEnabled

        for view in [icon, title, subtitle, radio] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            icon.widthAnchor.constraint(equalToConstant: 23),
            icon.heightAnchor.constraint(equalToConstant: 23),
            radio.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            radio.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 7),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            subtitle.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        onSelect(optionID)
    }

    @objc private func selectCard() {
        guard isEnabled else { return }
        onSelect(optionID)
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
