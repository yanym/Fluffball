import AppKit

struct AppearanceSettingsSnapshot {
    let petName: String
    let appearances: [PetAppearanceOption]
    let selectedAppearanceID: String
    let language: AppLanguage
    let petScale: CGFloat
    let crossfadeEnabled: Bool
    let alwaysOnTop: Bool
    let followCursor: Bool
    let freeRoam: Bool
    let directionalLook: Bool
    let canChangeAppearance: Bool
}

@MainActor
final class AppearanceSettingsWindowController: NSWindowController, NSWindowDelegate {
    var onAppearanceSelected: ((String) -> Bool)?
    var onScaleChanged: ((CGFloat) -> Void)?
    var onCrossfadeChanged: ((Bool) -> Void)?
    var onAlwaysOnTopChanged: ((Bool) -> Void)?
    var onFollowCursorChanged: ((Bool) -> Void)?
    var onFreeRoamChanged: ((Bool) -> Void)?
    var onDirectionalLookChanged: ((Bool) -> Void)?

    private var snapshot: AppearanceSettingsSnapshot
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    private let petNameLabel = NSTextField(labelWithString: "")
    private let petCaptionLabel = NSTextField(wrappingLabelWithString: "")
    private let appearanceSectionLabel = NSTextField(labelWithString: "")
    private let displaySectionLabel = NSTextField(labelWithString: "")
    private let behaviorSectionLabel = NSTextField(labelWithString: "")
    private let videoSectionLabel = NSTextField(labelWithString: "")
    private let imageModeNote = NSTextField(wrappingLabelWithString: "")
    private let appearanceStack = NSStackView()
    private let videoOptionsStack = NSStackView()
    private let sizeLabel = NSTextField(labelWithString: "")
    private let sizeValueLabel = NSTextField(labelWithString: "")
    private let sizeSlider = NSSlider()
    private let crossfadeSwitch = NSSwitch()
    private let alwaysOnTopSwitch = NSSwitch()
    private let followSwitch = NSSwitch()
    private let roamSwitch = NSSwitch()
    private let lookSwitch = NSSwitch()
    private let crossfadeLabel = NSTextField(labelWithString: "")
    private let alwaysOnTopLabel = NSTextField(labelWithString: "")
    private let followLabel = NSTextField(labelWithString: "")
    private let roamLabel = NSTextField(labelWithString: "")
    private let lookLabel = NSTextField(labelWithString: "")
    private let doneButton = NSButton()

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

    private func buildInterface() {
        guard let window else { return }
        let root = NSVisualEffectView()
        root.material = .contentBackground
        root.blendingMode = .behindWindow
        root.state = .active
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root

        let sidebar = makeSidebar()
        let main = makeMainContent()
        root.addSubview(sidebar)
        root.addSubview(main)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 214),
            main.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            main.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            main.topAnchor.constraint(equalTo: root.topAnchor),
            main.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
    }

    private func makeSidebar() -> NSView {
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .withinWindow
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let currentLabel = NSTextField(labelWithString: "")
        currentLabel.identifier = NSUserInterfaceItemIdentifier("current-pet-label")
        currentLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        currentLabel.textColor = .secondaryLabelColor

        let avatar = NSImageView()
        avatar.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: nil)
        avatar.contentTintColor = .white
        avatar.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        avatar.imageScaling = .scaleProportionallyUpOrDown

        let avatarBackground = NSView()
        avatarBackground.wantsLayer = true
        avatarBackground.layer?.cornerRadius = 20
        avatarBackground.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.88).cgColor
        avatarBackground.translatesAutoresizingMaskIntoConstraints = false
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatarBackground.addSubview(avatar)

        petNameLabel.font = .systemFont(ofSize: 18, weight: .bold)
        petCaptionLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        petCaptionLabel.textColor = .secondaryLabelColor
        petCaptionLabel.maximumNumberOfLines = 2

        let petCard = NSView()
        petCard.wantsLayer = true
        petCard.layer?.cornerRadius = 14
        petCard.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.70).cgColor
        petCard.layer?.borderWidth = 1
        petCard.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        petCard.translatesAutoresizingMaskIntoConstraints = false
        for view in [avatarBackground, petNameLabel, petCaptionLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            petCard.addSubview(view)
        }

        let libraryHint = NSTextField(wrappingLabelWithString: "")
        libraryHint.identifier = NSUserInterfaceItemIdentifier("library-hint")
        libraryHint.font = .systemFont(ofSize: 11.5)
        libraryHint.textColor = .tertiaryLabelColor

        currentLabel.translatesAutoresizingMaskIntoConstraints = false
        libraryHint.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(currentLabel)
        sidebar.addSubview(petCard)
        sidebar.addSubview(libraryHint)

        NSLayoutConstraint.activate([
            currentLabel.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            currentLabel.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -18),
            currentLabel.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 58),

            petCard.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            petCard.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            petCard.topAnchor.constraint(equalTo: currentLabel.bottomAnchor, constant: 10),
            petCard.heightAnchor.constraint(equalToConstant: 108),

            avatarBackground.leadingAnchor.constraint(equalTo: petCard.leadingAnchor, constant: 14),
            avatarBackground.centerYAnchor.constraint(equalTo: petCard.centerYAnchor),
            avatarBackground.widthAnchor.constraint(equalToConstant: 58),
            avatarBackground.heightAnchor.constraint(equalToConstant: 58),
            avatar.centerXAnchor.constraint(equalTo: avatarBackground.centerXAnchor),
            avatar.centerYAnchor.constraint(equalTo: avatarBackground.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 34),
            avatar.heightAnchor.constraint(equalToConstant: 34),

            petNameLabel.leadingAnchor.constraint(equalTo: avatarBackground.trailingAnchor, constant: 12),
            petNameLabel.trailingAnchor.constraint(equalTo: petCard.trailingAnchor, constant: -10),
            petNameLabel.topAnchor.constraint(equalTo: petCard.topAnchor, constant: 25),
            petCaptionLabel.leadingAnchor.constraint(equalTo: petNameLabel.leadingAnchor),
            petCaptionLabel.trailingAnchor.constraint(equalTo: petNameLabel.trailingAnchor),
            petCaptionLabel.topAnchor.constraint(equalTo: petNameLabel.bottomAnchor, constant: 4),

            libraryHint.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            libraryHint.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -18),
            libraryHint.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -22)
        ])
        return sidebar
    }

    private func makeMainContent() -> NSView {
        let main = NSView()
        main.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 27, weight: .bold)
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 2

        appearanceSectionLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        displaySectionLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        behaviorSectionLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        videoSectionLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        appearanceStack.orientation = .horizontal
        appearanceStack.alignment = .top
        appearanceStack.distribution = .fillEqually
        appearanceStack.spacing = 10

        let displayBox = makeDisplayBox()
        let interactionBox = makeInteractionBox()

        videoOptionsStack.orientation = .vertical
        videoOptionsStack.spacing = 8
        videoOptionsStack.alignment = .leading
        videoOptionsStack.addArrangedSubview(videoSectionLabel)
        videoOptionsStack.addArrangedSubview(makeToggleRow(label: crossfadeLabel, toggle: crossfadeSwitch))

        imageModeNote.font = .systemFont(ofSize: 12)
        imageModeNote.textColor = .tertiaryLabelColor
        imageModeNote.maximumNumberOfLines = 2

        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.target = self
        doneButton.action = #selector(closeWindow)

        let footer = NSStackView(views: [NSView(), doneButton])
        footer.orientation = .horizontal
        footer.distribution = .fill

        let stack = NSStackView(views: [
            titleLabel,
            subtitleLabel,
            appearanceSectionLabel,
            appearanceStack,
            displaySectionLabel,
            displayBox,
            behaviorSectionLabel,
            interactionBox,
            videoOptionsStack,
            imageModeNote,
            footer
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(4, after: titleLabel)
        stack.setCustomSpacing(20, after: subtitleLabel)
        stack.setCustomSpacing(7, after: appearanceSectionLabel)
        stack.setCustomSpacing(18, after: appearanceStack)
        stack.setCustomSpacing(7, after: displaySectionLabel)
        stack.setCustomSpacing(18, after: displayBox)
        stack.setCustomSpacing(7, after: behaviorSectionLabel)
        stack.setCustomSpacing(18, after: interactionBox)
        stack.translatesAutoresizingMaskIntoConstraints = false
        main.addSubview(stack)

        appearanceStack.translatesAutoresizingMaskIntoConstraints = false
        displayBox.translatesAutoresizingMaskIntoConstraints = false
        interactionBox.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -30),
            stack.topAnchor.constraint(equalTo: main.topAnchor, constant: 50),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: main.bottomAnchor, constant: -20),
            appearanceStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            appearanceStack.heightAnchor.constraint(equalToConstant: 100),
            displayBox.widthAnchor.constraint(equalTo: stack.widthAnchor),
            interactionBox.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return main
    }

    private func makeDisplayBox() -> NSView {
        let box = settingsBox()
        sizeLabel.font = .systemFont(ofSize: 13, weight: .medium)
        sizeValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        sizeValueLabel.textColor = .secondaryLabelColor
        sizeValueLabel.alignment = .right
        sizeSlider.minValue = 0.6
        sizeSlider.maxValue = 1.4
        sizeSlider.isContinuous = true
        sizeSlider.target = self
        sizeSlider.action = #selector(scaleChanged(_:))

        let sizeHeader = NSStackView(views: [sizeLabel, NSView(), sizeValueLabel])
        sizeHeader.orientation = .horizontal
        sizeHeader.distribution = .fill
        let sizeStack = NSStackView(views: [sizeHeader, sizeSlider])
        sizeStack.orientation = .vertical
        sizeStack.spacing = 3

        let alwaysRow = makeToggleRow(label: alwaysOnTopLabel, toggle: alwaysOnTopSwitch)
        let content = NSStackView(views: [sizeStack, separator(), alwaysRow])
        content.orientation = .vertical
        content.spacing = 9
        pin(content, inside: box)
        return box
    }

    private func makeInteractionBox() -> NSView {
        let box = settingsBox()
        let content = NSStackView(views: [
            makeToggleRow(label: followLabel, toggle: followSwitch),
            separator(),
            makeToggleRow(label: roamLabel, toggle: roamSwitch),
            separator(),
            makeToggleRow(label: lookLabel, toggle: lookSwitch)
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
        petNameLabel.stringValue = snapshot.petName
        petCaptionLabel.stringValue = language.includedPetLabel
        appearanceSectionLabel.stringValue = language.appearanceSectionTitle
        displaySectionLabel.stringValue = language.displaySectionTitle
        behaviorSectionLabel.stringValue = language.behaviorSectionTitle
        videoSectionLabel.stringValue = language.videoOptionsTitle
        imageModeNote.stringValue = language.videoOptionsUnavailable
        sizeLabel.stringValue = language.sizeMenu
        crossfadeLabel.stringValue = language.crossfadeMenu
        alwaysOnTopLabel.stringValue = language.alwaysOnTopMenu
        followLabel.stringValue = language.followCursorMenu
        roamLabel.stringValue = language.freeRoamMenu
        lookLabel.stringValue = language.imageFacingMenu
        doneButton.title = language.closeButton

        if let current = window?.contentView?.subviews.first?.viewWithIdentifier("current-pet-label") as? NSTextField {
            current.stringValue = language.currentPetLabel
        }
        if let hint = window?.contentView?.subviews.first?.viewWithIdentifier("library-hint") as? NSTextField {
            hint.stringValue = language == .simplifiedChinese
                ? "更多宠物、导入与创建工具可从“宠物素材库”进入。"
                : "Open Pet Library for more pets, import, export, and creation tools."
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
                guard let self else { return }
                if self.onAppearanceSelected?(id) == true {
                    self.snapshot = AppearanceSettingsSnapshot(
                        petName: self.snapshot.petName,
                        appearances: self.snapshot.appearances,
                        selectedAppearanceID: id,
                        language: self.snapshot.language,
                        petScale: self.snapshot.petScale,
                        crossfadeEnabled: self.snapshot.crossfadeEnabled,
                        alwaysOnTop: self.snapshot.alwaysOnTop,
                        followCursor: self.snapshot.followCursor,
                        freeRoam: self.snapshot.freeRoam,
                        directionalLook: self.snapshot.directionalLook,
                        canChangeAppearance: self.snapshot.canChangeAppearance
                    )
                    self.applySnapshot()
                }
            }
            appearanceStack.addArrangedSubview(card)
        }

        sizeSlider.doubleValue = Double(snapshot.petScale)
        sizeValueLabel.stringValue = "\(Int((snapshot.petScale * 100).rounded()))%"
        crossfadeSwitch.state = snapshot.crossfadeEnabled ? .on : .off
        alwaysOnTopSwitch.state = snapshot.alwaysOnTop ? .on : .off
        followSwitch.state = snapshot.followCursor ? .on : .off
        roamSwitch.state = snapshot.freeRoam ? .on : .off
        lookSwitch.state = snapshot.directionalLook ? .on : .off

        crossfadeSwitch.target = self
        crossfadeSwitch.action = #selector(crossfadeChanged(_:))
        alwaysOnTopSwitch.target = self
        alwaysOnTopSwitch.action = #selector(alwaysOnTopChanged(_:))
        followSwitch.target = self
        followSwitch.action = #selector(followChanged(_:))
        roamSwitch.target = self
        roamSwitch.action = #selector(roamChanged(_:))
        lookSwitch.target = self
        lookSwitch.action = #selector(lookChanged(_:))

        let isVideo = snapshot.appearances.first(where: {
            $0.id == snapshot.selectedAppearanceID
        })?.kind == .continuousVideo
        videoOptionsStack.isHidden = !isVideo
        imageModeNote.isHidden = isVideo
    }

    @objc private func scaleChanged(_ sender: NSSlider) {
        let scale = CGFloat(sender.doubleValue)
        sizeValueLabel.stringValue = "\(Int((scale * 100).rounded()))%"
        onScaleChanged?(scale)
    }

    @objc private func crossfadeChanged(_ sender: NSSwitch) {
        onCrossfadeChanged?(sender.state == .on)
    }

    @objc private func alwaysOnTopChanged(_ sender: NSSwitch) {
        onAlwaysOnTopChanged?(sender.state == .on)
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

    @objc private func closeWindow() {
        window?.close()
    }
}

@MainActor
private final class AppearanceCardView: NSControl {
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
