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
    let canChangeAppearance: Bool
}

@MainActor
final class AppearanceSettingsWindowController: NSWindowController, NSWindowDelegate {
    var onAppearanceSelected: ((String) -> Bool)?
    var onCrossfadeChanged: ((Bool) -> Void)?
    var onFollowCursorChanged: ((Bool) -> Void)?
    var onFreeRoamChanged: ((Bool) -> Void)?
    var onDirectionalLookChanged: ((Bool) -> Void)?
    var onDesktopInteractionsChanged: ((Bool) -> Void)?
    var onIconRearrangementChanged: ((Bool) -> Void)?

    private var snapshot: AppearanceSettingsSnapshot
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    private let appearanceSectionLabel = NSTextField(labelWithString: "")
    private let behaviorSectionLabel = NSTextField(labelWithString: "")
    private let videoSectionLabel = NSTextField(labelWithString: "")
    private let imageModeNote = NSTextField(wrappingLabelWithString: "")
    private let appearanceStack = NSStackView()
    private let videoOptionsStack = NSStackView()
    private let crossfadeSwitch = NSSwitch()
    private let followSwitch = NSSwitch()
    private let roamSwitch = NSSwitch()
    private let lookSwitch = NSSwitch()
    private let desktopInteractionsSwitch = NSSwitch()
    private let iconRearrangementSwitch = NSSwitch()
    private let crossfadeLabel = NSTextField(labelWithString: "")
    private let followLabel = NSTextField(labelWithString: "")
    private let roamLabel = NSTextField(labelWithString: "")
    private let lookLabel = NSTextField(labelWithString: "")
    private let desktopInteractionsLabel = NSTextField(labelWithString: "")
    private let iconRearrangementLabel = NSTextField(labelWithString: "")

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

        let main = makeMainContent()
        root.addSubview(main)

        NSLayoutConstraint.activate([
            main.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            main.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            main.topAnchor.constraint(equalTo: root.topAnchor),
            main.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
    }

    private func makeMainContent() -> NSView {
        let main = NSView()
        main.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 27, weight: .bold)
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 2

        appearanceSectionLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        behaviorSectionLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        videoSectionLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        appearanceStack.orientation = .horizontal
        appearanceStack.alignment = .top
        appearanceStack.distribution = .fillEqually
        appearanceStack.spacing = 10

        let interactionBox = makeInteractionBox()

        videoOptionsStack.orientation = .vertical
        videoOptionsStack.spacing = 8
        videoOptionsStack.alignment = .leading
        videoOptionsStack.addArrangedSubview(videoSectionLabel)
        videoOptionsStack.addArrangedSubview(makeToggleRow(label: crossfadeLabel, toggle: crossfadeSwitch))

        imageModeNote.font = .systemFont(ofSize: 12)
        imageModeNote.textColor = .tertiaryLabelColor
        imageModeNote.maximumNumberOfLines = 2

        let stack = NSStackView(views: [
            titleLabel,
            subtitleLabel,
            appearanceSectionLabel,
            appearanceStack,
            behaviorSectionLabel,
            interactionBox,
            videoOptionsStack,
            imageModeNote
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(4, after: titleLabel)
        stack.setCustomSpacing(20, after: subtitleLabel)
        stack.setCustomSpacing(7, after: appearanceSectionLabel)
        stack.setCustomSpacing(18, after: appearanceStack)
        stack.setCustomSpacing(7, after: behaviorSectionLabel)
        stack.setCustomSpacing(18, after: interactionBox)
        stack.translatesAutoresizingMaskIntoConstraints = false
        main.addSubview(stack)

        appearanceStack.translatesAutoresizingMaskIntoConstraints = false
        interactionBox.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -30),
            stack.topAnchor.constraint(equalTo: main.topAnchor, constant: 50),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: main.bottomAnchor, constant: -20),
            appearanceStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            appearanceStack.heightAnchor.constraint(equalToConstant: 100),
            interactionBox.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return main
    }

    private func makeInteractionBox() -> NSView {
        let box = settingsBox()
        let content = NSStackView(views: [
            makeToggleRow(label: followLabel, toggle: followSwitch),
            separator(),
            makeToggleRow(label: roamLabel, toggle: roamSwitch),
            separator(),
            makeToggleRow(label: lookLabel, toggle: lookSwitch),
            separator(),
            makeToggleRow(label: desktopInteractionsLabel, toggle: desktopInteractionsSwitch),
            separator(),
            makeToggleRow(label: iconRearrangementLabel, toggle: iconRearrangementSwitch)
        ])
        content.orientation = .vertical
        content.spacing = 7
        pin(content, inside: box)
        return box
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

    private func makeToggleRow(label: NSTextField, toggle: NSSwitch) -> NSStackView {
        label.font = .systemFont(ofSize: 13, weight: .medium)
        toggle.controlSize = .small
        toggle.target = self
        let stack = NSStackView(views: [label, NSView(), toggle])
        stack.orientation = .horizontal
        stack.distribution = .fill
        return stack
    }

    private func applySnapshot() {
        guard isWindowLoaded else { return }
        let language = snapshot.language
        titleLabel.stringValue = language.visualSettingsTitle
        subtitleLabel.stringValue = language.visualSettingsSubtitle
        appearanceSectionLabel.stringValue = language.appearanceSectionTitle
        behaviorSectionLabel.stringValue = language.behaviorSectionTitle
        videoSectionLabel.stringValue = language.videoOptionsTitle
        imageModeNote.stringValue = language.videoOptionsUnavailable
        crossfadeLabel.stringValue = language.crossfadeMenu
        followLabel.stringValue = language.followCursorMenu
        roamLabel.stringValue = language.freeRoamMenu
        lookLabel.stringValue = language.imageFacingMenu
        desktopInteractionsLabel.stringValue = language.desktopInteractionsSetting
        iconRearrangementLabel.stringValue = language.iconRearrangementSetting
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
        videoOptionsStack.isHidden = !isVideo
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
