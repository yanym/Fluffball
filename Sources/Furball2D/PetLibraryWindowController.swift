import AppKit
import UniformTypeIdentifiers

@MainActor
final class PetLibraryWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var onSelectPet: ((String) -> Bool)?
    var onAppearanceSelected: ((String) -> Bool)?
    var onAnimationSpeedChanged: ((Double) -> Void)?
    var onBodySizeChanged: ((String, Int) -> Void)?
    var onLibraryChanged: (() -> Void)?

    private var language: AppLanguage
    private let isEmbedded: Bool
    private var pets: [PetLibraryPet] = []
    private var selectedPetID: String?
    private var isRestoringSelection = false
    private var selectedPhotos: [URL] = []

    private let segmented = NSSegmentedControl(labels: ["", ""], trackingMode: .selectOne, target: nil, action: nil)
    private let contentContainer = NSView()
    private let libraryPage = NSView()
    private let creatorPage = NSView()
    private let tableView = NSTableView()
    private let petName = NSTextField(labelWithString: "")
    private let petMeta = NSTextField(labelWithString: "")
    private let builtInBadge = NSTextField(labelWithString: "")
    private let appearanceHeading = NSTextField(labelWithString: "")
    private let appearanceIntro = NSTextField(wrappingLabelWithString: "")
    private let appearanceStack = NSStackView()
    private let profileAnimationSpeedSlider = NSSlider(value: 0.82, minValue: 0.5, maxValue: 1.5, target: nil, action: nil)
    private let profileAnimationSpeedValue = NSTextField(labelWithString: "82%")
    private let profileBodySizeSlider = NSSlider(value: 60, minValue: 1, maxValue: 100, target: nil, action: nil)
    private let profileBodySizeValue = NSTextField(labelWithString: "60 / 100")
    private let personalityHeading = NSTextField(labelWithString: "")
    private let personalitySummary = NSTextField(wrappingLabelWithString: "")
    private let personalityStack = NSStackView()
    private var traitSliders: [PetPersonalityTrait: NSSlider] = [:]
    private var traitValueLabels: [PetPersonalityTrait: NSTextField] = [:]
    private let stateHeading = NSTextField(labelWithString: "")
    private let stateStack = NSStackView()
    private var stateIndicators: [String: NSProgressIndicator] = [:]
    private let memoryHeading = NSTextField(labelWithString: "")
    private let memoryStack = NSStackView()
    private let clearMemoriesButton = NSButton()
    private let useButton = NSButton()
    private let importButton = NSButton()
    private let exportButton = NSButton()
    private let removeButton = NSButton()

    private let creatorTitle = NSTextField(labelWithString: "")
    private let creatorIntro = NSTextField(wrappingLabelWithString: "")
    private let nameField = NSTextField()
    private let speciesPopup = NSPopUpButton()
    private let bodySizeSlider = NSSlider(value: 60, minValue: 1, maxValue: 100, target: nil, action: nil)
    private let bodySizeValue = NSTextField(labelWithString: "60 / 100")
    private let photosLabel = NSTextField(labelWithString: "")
    private let choosePhotosButton = NSButton()
    private let oneClickCodexButton = NSButton()
    private let createRequestButton = NSButton()
    private let downloadSkillButton = NSButton()
    private let downloadLiveMotionSkillButton = NSButton()
    private let creationProgress = NSProgressIndicator()
    private let creationStatus = NSTextField(wrappingLabelWithString: "")
    private var codexCreationJob: CodexPetCreationJob?
    private var codexCreationWasCancelled = false

    init(language: AppLanguage, embedded: Bool = false) {
        self.language = language
        isEmbedded = embedded
        let window: NSWindow?
        if embedded {
            window = nil
        } else {
            let standaloneWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 830, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            standaloneWindow.titlebarAppearsTransparent = true
            standaloneWindow.titleVisibility = .hidden
            standaloneWindow.isMovableByWindowBackground = true
            standaloneWindow.minSize = NSSize(width: 760, height: 550)
            standaloneWindow.center()
            window = standaloneWindow
        }
        super.init(window: window)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(petMindDidChange(_:)),
            name: .petMindDidChange,
            object: nil
        )
        window?.delegate = self
        if embedded {
            buildEmbeddedInterface()
        } else {
            buildInterface()
        }
        refresh(language: language)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func refresh(language: AppLanguage) {
        self.language = language
        pets = PetAssetCatalog.availablePets
        selectedPetID = PetAssetCatalog.activePet?.id
            ?? selectedPetID.flatMap { id in pets.contains(where: { $0.id == id }) ? id : nil }
            ?? pets.first?.id
        applyLanguage()
        tableView.reloadData()
        isRestoringSelection = true
        if let selectedPetID, let row = pets.firstIndex(where: { $0.id == selectedPetID }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        }
        isRestoringSelection = false
        updateDetails()
    }

    func updateProfileControls(animationSpeed: Double) {
        profileAnimationSpeedSlider.doubleValue = min(1.5, max(0.5, animationSpeed))
        profileAnimationSpeedValue.stringValue = "\(Int((profileAnimationSpeedSlider.doubleValue * 100).rounded()))%"
    }

    func present() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        VisualQACapture.schedule(view: window?.contentView, name: segmented.selectedSegment == 0 ? "pet-library" : "pet-creator")
    }

    func presentCreator() {
        segmented.selectedSegment = 1
        installPage(creatorPage)
        present()
    }

    func showLibraryEmbedded() {
        segmented.selectedSegment = 0
        installPage(libraryPage)
        contentContainer.superview?.layoutSubtreeIfNeeded()
        contentContainer.layoutSubtreeIfNeeded()
        libraryPage.layoutSubtreeIfNeeded()
        VisualQACapture.schedule(view: libraryPage, name: "pet-library-embedded")
    }

    func showCreatorEmbedded() {
        segmented.selectedSegment = 1
        installPage(creatorPage)
        contentContainer.superview?.layoutSubtreeIfNeeded()
        contentContainer.layoutSubtreeIfNeeded()
        creatorPage.layoutSubtreeIfNeeded()
        VisualQACapture.schedule(view: creatorPage, name: "pet-creator-embedded")
    }

    /// Transfers the library/creator page into the unified Settings window.
    func contentViewForEmbedding() -> NSView {
        if isEmbedded {
            contentContainer.translatesAutoresizingMaskIntoConstraints = false
            return contentContainer
        }
        guard let window, let formerRoot = window.contentView else { return NSView() }
        let formerHostingConstraints = formerRoot.constraints.filter { constraint in
            (constraint.firstItem as? NSView) === contentContainer
                || (constraint.secondItem as? NSView) === contentContainer
        }
        NSLayoutConstraint.deactivate(formerHostingConstraints)
        window.contentView = NSView()
        // Embed the actual page container, not the former NSWindow content root.
        // A detached NSVisualEffectView can collapse to zero before it joins the
        // unified hierarchy, leaving My Pets as an empty black page.
        contentContainer.removeFromSuperview()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        return contentContainer
    }

    private func buildInterface() {
        guard let window else { return }
        let root = NSVisualEffectView()
        root.material = .contentBackground
        root.blendingMode = .behindWindow
        root.state = .active
        window.contentView = root

        segmented.target = self
        segmented.action = #selector(tabChanged(_:))
        segmented.selectedSegment = 0
        segmented.segmentStyle = .capsule
        segmented.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        if !isEmbedded { root.addSubview(segmented) }
        root.addSubview(contentContainer)
        buildContentPages()

        var constraints = [
            contentContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ]
        if isEmbedded {
            constraints.append(contentContainer.topAnchor.constraint(equalTo: root.topAnchor))
        } else {
            constraints.append(contentsOf: [
                segmented.centerXAnchor.constraint(equalTo: root.centerXAnchor),
                segmented.topAnchor.constraint(equalTo: root.topAnchor, constant: 48),
                segmented.widthAnchor.constraint(equalToConstant: 280),
                contentContainer.topAnchor.constraint(equalTo: segmented.bottomAnchor, constant: 14)
            ])
        }
        NSLayoutConstraint.activate(constraints)
    }

    private func buildEmbeddedInterface() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        buildContentPages()
    }

    private func buildContentPages() {
        buildLibraryPage()
        buildCreatorPage()
        installPage(libraryPage)
    }

    private func installPage(_ page: NSView) {
        guard page.superview !== contentContainer else {
            page.isHidden = false
            return
        }
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        page.isHidden = false
        page.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(page)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            page.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            page.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
    }

    private func buildLibraryPage() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pets"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 58
        tableView.style = .plain
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = .controlBackgroundColor

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .controlBackgroundColor
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let sidebar = NSView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(scroll)

        importButton.bezelStyle = .rounded
        importButton.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
        importButton.imagePosition = .imageLeading
        importButton.target = self
        importButton.action = #selector(importPack)
        importButton.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(importButton)

        let details = NSView()
        details.translatesAutoresizingMaskIntoConstraints = false
        petName.font = .systemFont(ofSize: 28, weight: .bold)
        petMeta.font = .systemFont(ofSize: 12.5, weight: .medium)
        petMeta.textColor = .secondaryLabelColor
        builtInBadge.font = .systemFont(ofSize: 10, weight: .bold)
        builtInBadge.textColor = .systemOrange
        appearanceHeading.font = .systemFont(ofSize: 11, weight: .semibold)
        appearanceHeading.textColor = .secondaryLabelColor
        appearanceIntro.font = .systemFont(ofSize: 12.5, weight: .medium)
        appearanceIntro.textColor = .secondaryLabelColor
        appearanceIntro.maximumNumberOfLines = 2
        appearanceStack.orientation = .vertical
        appearanceStack.spacing = 11
        appearanceStack.alignment = .width
        configureProfileSection()

        useButton.bezelStyle = .rounded
        useButton.keyEquivalent = "\r"
        useButton.target = self
        useButton.action = #selector(useSelectedPet)
        let readOnlyBadge = NSTextField(labelWithString: "Validated Pet Packs only")
        readOnlyBadge.font = .systemFont(ofSize: 11, weight: .medium)
        readOnlyBadge.textColor = .secondaryLabelColor
        let buttonRow = NSStackView(views: [useButton, readOnlyBadge, NSView()])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        let memoryHeader = NSStackView(views: [memoryHeading, NSView(), clearMemoriesButton])
        memoryHeader.orientation = .horizontal
        memoryHeader.alignment = .centerY
        memoryHeader.spacing = 8
        let detailsStack = NSStackView(views: [
            petName, petMeta, builtInBadge,
            appearanceHeading, appearanceStack,
            personalityHeading, personalitySummary, personalityStack,
            stateHeading, stateStack,
            memoryHeader, memoryStack,
            buttonRow
        ])
        detailsStack.orientation = .vertical
        detailsStack.alignment = .leading
        detailsStack.spacing = 7
        detailsStack.setCustomSpacing(22, after: builtInBadge)
        detailsStack.setCustomSpacing(17, after: appearanceStack)
        detailsStack.setCustomSpacing(15, after: personalityStack)
        detailsStack.setCustomSpacing(15, after: stateStack)
        detailsStack.translatesAutoresizingMaskIntoConstraints = false
        let detailsDocument = NSView()
        detailsDocument.translatesAutoresizingMaskIntoConstraints = false
        detailsDocument.addSubview(detailsStack)
        let detailsScroll = NSScrollView()
        detailsScroll.documentView = detailsDocument
        detailsScroll.hasVerticalScroller = true
        detailsScroll.autohidesScrollers = true
        detailsScroll.drawsBackground = false
        detailsScroll.borderType = .noBorder
        detailsScroll.translatesAutoresizingMaskIntoConstraints = false
        details.addSubview(detailsScroll)

        libraryPage.addSubview(sidebar)
        libraryPage.addSubview(details)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: libraryPage.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: libraryPage.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: libraryPage.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 250),
            scroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: importButton.topAnchor, constant: -10),
            importButton.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14),
            importButton.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
            importButton.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -18),
            details.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            details.trailingAnchor.constraint(equalTo: libraryPage.trailingAnchor),
            details.topAnchor.constraint(equalTo: libraryPage.topAnchor),
            details.bottomAnchor.constraint(equalTo: libraryPage.bottomAnchor),
            detailsScroll.leadingAnchor.constraint(equalTo: details.leadingAnchor),
            detailsScroll.trailingAnchor.constraint(equalTo: details.trailingAnchor),
            detailsScroll.topAnchor.constraint(equalTo: details.topAnchor),
            detailsScroll.bottomAnchor.constraint(equalTo: details.bottomAnchor),
            detailsDocument.widthAnchor.constraint(equalTo: detailsScroll.contentView.widthAnchor),
            detailsStack.leadingAnchor.constraint(equalTo: detailsDocument.leadingAnchor, constant: 34),
            detailsStack.trailingAnchor.constraint(equalTo: detailsDocument.trailingAnchor, constant: -34),
            detailsStack.topAnchor.constraint(equalTo: detailsDocument.topAnchor, constant: 32),
            detailsStack.bottomAnchor.constraint(equalTo: detailsDocument.bottomAnchor, constant: -28),
            appearanceStack.widthAnchor.constraint(equalTo: detailsStack.widthAnchor),
            personalitySummary.widthAnchor.constraint(equalTo: detailsStack.widthAnchor),
            personalityStack.widthAnchor.constraint(equalTo: detailsStack.widthAnchor),
            stateStack.widthAnchor.constraint(equalTo: detailsStack.widthAnchor),
            memoryHeader.widthAnchor.constraint(equalTo: detailsStack.widthAnchor),
            memoryStack.widthAnchor.constraint(equalTo: detailsStack.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: detailsStack.widthAnchor)
        ])
    }

    private func configureProfileSection() {
        for heading in [personalityHeading, stateHeading, memoryHeading] {
            heading.font = .systemFont(ofSize: 11, weight: .semibold)
            heading.textColor = .secondaryLabelColor
        }
        personalitySummary.font = .systemFont(ofSize: 12.5, weight: .medium)
        personalitySummary.textColor = .labelColor
        personalitySummary.maximumNumberOfLines = 2

        profileBodySizeSlider.isContinuous = true
        profileBodySizeSlider.target = self
        profileBodySizeSlider.action = #selector(profileBodySizeChanged(_:))
        profileAnimationSpeedSlider.isContinuous = true
        profileAnimationSpeedSlider.target = self
        profileAnimationSpeedSlider.action = #selector(profileAnimationSpeedChanged(_:))
        for value in [profileBodySizeValue, profileAnimationSpeedValue] {
            value.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            value.textColor = .secondaryLabelColor
            value.alignment = .right
            value.widthAnchor.constraint(equalToConstant: 62).isActive = true
        }

        personalityStack.orientation = .vertical
        personalityStack.spacing = 4
        personalityStack.alignment = .leading
        for (index, trait) in PetPersonalityTrait.allCases.enumerated() {
            let title = NSTextField(labelWithString: "")
            title.identifier = NSUserInterfaceItemIdentifier("trait-title-\(trait.rawValue)")
            title.font = .systemFont(ofSize: 11.5, weight: .medium)
            title.widthAnchor.constraint(equalToConstant: 92).isActive = true
            let slider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: self, action: #selector(personalitySliderChanged(_:)))
            slider.tag = index
            slider.isContinuous = true
            let value = NSTextField(labelWithString: "50%")
            value.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
            value.textColor = .secondaryLabelColor
            value.alignment = .right
            value.widthAnchor.constraint(equalToConstant: 38).isActive = true
            let row = NSStackView(views: [title, slider, value])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            personalityStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: personalityStack.widthAnchor).isActive = true
            traitSliders[trait] = slider
            traitValueLabels[trait] = value
        }

        stateStack.orientation = .vertical
        stateStack.spacing = 5
        stateStack.alignment = .leading
        for key in ["energy", "curiosity", "affinity"] {
            let title = NSTextField(labelWithString: "")
            title.identifier = NSUserInterfaceItemIdentifier("state-title-\(key)")
            title.font = .systemFont(ofSize: 11.5, weight: .medium)
            title.widthAnchor.constraint(equalToConstant: 92).isActive = true
            let indicator = NSProgressIndicator()
            indicator.style = .bar
            indicator.controlSize = .small
            indicator.minValue = 0
            indicator.maxValue = 1
            indicator.isIndeterminate = false
            let row = NSStackView(views: [title, indicator])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            stateStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stateStack.widthAnchor).isActive = true
            stateIndicators[key] = indicator
        }

        memoryStack.orientation = .vertical
        memoryStack.spacing = 4
        memoryStack.alignment = .leading
        clearMemoriesButton.bezelStyle = .inline
        clearMemoriesButton.controlSize = .small
        clearMemoriesButton.target = self
        clearMemoriesButton.action = #selector(clearSelectedPetMemories)
    }

    private func buildCreatorPage() {
        creatorTitle.font = .systemFont(ofSize: 27, weight: .bold)
        creatorIntro.font = .systemFont(ofSize: 13)
        creatorIntro.textColor = .secondaryLabelColor
        creatorIntro.maximumNumberOfLines = 4

        nameField.placeholderString = "Nina"
        nameField.controlSize = .large
        speciesPopup.addItems(withTitles: ["Dog", "Cat", "Other"])
        bodySizeSlider.isContinuous = true
        bodySizeSlider.target = self
        bodySizeSlider.action = #selector(creationBodySizeChanged(_:))
        bodySizeSlider.widthAnchor.constraint(equalToConstant: 250).isActive = true
        bodySizeValue.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        bodySizeValue.textColor = .secondaryLabelColor

        choosePhotosButton.bezelStyle = .rounded
        choosePhotosButton.target = self
        choosePhotosButton.action = #selector(choosePhotos)
        oneClickCodexButton.bezelStyle = .rounded
        oneClickCodexButton.keyEquivalent = "\r"
        oneClickCodexButton.target = self
        oneClickCodexButton.action = #selector(buildWithCodex)
        createRequestButton.bezelStyle = .rounded
        createRequestButton.target = self
        createRequestButton.action = #selector(exportCreationRequest)
        downloadSkillButton.bezelStyle = .rounded
        downloadSkillButton.target = self
        downloadSkillButton.action = #selector(downloadCreatorSkill)
        downloadLiveMotionSkillButton.bezelStyle = .rounded
        downloadLiveMotionSkillButton.target = self
        downloadLiveMotionSkillButton.action = #selector(downloadLiveMotionSkill)
        photosLabel.textColor = .secondaryLabelColor
        creationProgress.style = .spinning
        creationProgress.controlSize = .small
        creationProgress.isDisplayedWhenStopped = false
        creationStatus.font = .systemFont(ofSize: 11.5)
        creationStatus.textColor = .secondaryLabelColor
        creationStatus.maximumNumberOfLines = 3

        let form = NSGridView(views: [
            [formLabel("pet-name"), nameField],
            [formLabel("species"), speciesPopup],
            [formLabel("body-size"), NSStackView(views: [bodySizeSlider, bodySizeValue])],
            [formLabel("style"), NSTextField(labelWithString: language.realisticStyleLabel)],
            [formLabel("photos"), NSStackView(views: [choosePhotosButton, photosLabel])]
        ])
        form.rowSpacing = 13
        form.columnSpacing = 18
        form.column(at: 0).xPlacement = .trailing
        form.column(at: 1).xPlacement = .fill
        form.column(at: 1).width = 380

        let buttons = NSStackView(views: [oneClickCodexButton, createRequestButton, NSView()])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let skillButtons = NSStackView(views: [downloadSkillButton, downloadLiveMotionSkillButton, NSView()])
        skillButtons.orientation = .horizontal
        skillButtons.spacing = 8
        let statusRow = NSStackView(views: [creationProgress, creationStatus, NSView()])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 8
        let stack = NSStackView(views: [creatorTitle, creatorIntro, form, buttons, skillButtons, statusRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.setCustomSpacing(6, after: creatorTitle)
        stack.setCustomSpacing(28, after: creatorIntro)
        stack.translatesAutoresizingMaskIntoConstraints = false
        creatorPage.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: creatorPage.leadingAnchor, constant: 52),
            stack.trailingAnchor.constraint(equalTo: creatorPage.trailingAnchor, constant: -52),
            stack.topAnchor.constraint(equalTo: creatorPage.topAnchor, constant: 34),
            creatorIntro.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            skillButtons.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func formLabel(_ identifier: String) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.identifier = NSUserInterfaceItemIdentifier(identifier)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func applyLanguage() {
        segmented.setLabel(language.libraryTab, forSegment: 0)
        segmented.setLabel(language.creatorTab, forSegment: 1)
        window?.title = language.petLibraryTitle
        appearanceHeading.stringValue = "APPEARANCE · PICK YOUR PET'S LOOK"
        appearanceIntro.stringValue = "Switch styles any time. Live Motion uses cinematic video; Realistic 2D uses a lightweight illustrated sprite pack."
        personalityHeading.stringValue = language.personalityHeading
        stateHeading.stringValue = language.currentStateHeading
        memoryHeading.stringValue = language.shortMemoryHeading
        clearMemoriesButton.title = language.clearMemoriesButton
        importButton.title = language.importPetPackButton
        for trait in PetPersonalityTrait.allCases {
            (libraryPage.viewWithIdentifier("trait-title-\(trait.rawValue)") as? NSTextField)?.stringValue = language.personalityTraitTitle(trait)
        }
        (libraryPage.viewWithIdentifier("state-title-energy") as? NSTextField)?.stringValue = language.energyStateLabel
        (libraryPage.viewWithIdentifier("state-title-curiosity") as? NSTextField)?.stringValue = language.curiosityStateLabel
        (libraryPage.viewWithIdentifier("state-title-affinity") as? NSTextField)?.stringValue = language.affinityStateLabel
        builtInBadge.stringValue = language.builtInBadge
        creatorTitle.stringValue = language.creatorTab
        creatorIntro.stringValue = language.creatorIntro
        choosePhotosButton.title = language.choosePhotosButton
        photosLabel.stringValue = language.selectedPhotosLabel(selectedPhotos.count)
        oneClickCodexButton.title = codexCreationJob == nil
            ? language.oneClickCodexButton
            : language.cancelCodexCreationButton
        createRequestButton.title = language.exportCreationRequestButton
        downloadSkillButton.title = language.downloadSkillButton
        downloadLiveMotionSkillButton.title = language.downloadLiveMotionSkillButton
        if codexCreationJob == nil {
            oneClickCodexButton.isEnabled = PetPackLibraryManager.codexExecutableURL != nil
            creationStatus.stringValue = PetPackLibraryManager.codexExecutableURL == nil
                ? language.codexNotInstalledLabel
                : ""
        }
        (creatorPage.viewWithIdentifier("pet-name") as? NSTextField)?.stringValue = language.petNameField
        (creatorPage.viewWithIdentifier("species") as? NSTextField)?.stringValue = language.speciesField
        (creatorPage.viewWithIdentifier("body-size") as? NSTextField)?.stringValue = "Body Size"
        (creatorPage.viewWithIdentifier("style") as? NSTextField)?.stringValue = language.styleField
        (creatorPage.viewWithIdentifier("photos") as? NSTextField)?.stringValue = language.choosePhotosButton
    }

    func numberOfRows(in tableView: NSTableView) -> Int { pets.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard pets.indices.contains(row) else { return nil }
        let pet = pets[row]
        let cell = NSTableCellView()
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: pet.species == "cat" ? "cat.fill" : "dog.fill", accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: nil)
        icon.contentTintColor = pet.id == PetAssetCatalog.activePet?.id ? .controlAccentColor : .secondaryLabelColor
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 21, weight: .semibold)
        let name = NSTextField(labelWithString: pet.name)
        name.font = .systemFont(ofSize: 13.5, weight: .semibold)
        let meta = NSTextField(labelWithString: "\(pet.appearances.count) · \(pet.species.capitalized) · Size \(pet.bodySize)")
        meta.font = .systemFont(ofSize: 10.5)
        meta.textColor = .secondaryLabelColor
        for view in [icon, name, meta] {
            view.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            name.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            name.topAnchor.constraint(equalTo: cell.topAnchor, constant: 10),
            meta.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            meta.trailingAnchor.constraint(equalTo: name.trailingAnchor),
            meta.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 2)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard pets.indices.contains(row) else { return }
        let pet = pets[row]
        selectedPetID = pet.id
        updateDetails()
        guard !isRestoringSelection, pet.id != PetAssetCatalog.activePet?.id else { return }
        // Pet rows are commands, not a separate preview state. Requiring a
        // hidden second click on “Use Pet” left Appearance bound to the old pet
        // and made Nina's three cards appear broken while Fortune was active.
        if onSelectPet?(pet.id) != true {
            selectedPetID = PetAssetCatalog.activePet?.id
            refresh(language: language)
        }
    }

    private func updateDetails() {
        guard let pet = selectedPet else {
            petName.stringValue = "—"
            return
        }
        petName.stringValue = pet.name
        let species = pet.species.capitalized
        petMeta.stringValue = "\(species) · Body size \(pet.bodySize)/100 · v\(pet.assetVersion)"
        builtInBadge.isHidden = !pet.isBundled
        appearanceStack.arrangedSubviews.forEach {
            appearanceStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let selectedAppearanceID = pet.id == PetAssetCatalog.activePet?.id
            ? PetAssetCatalog.activeAppearance.id
            : UserDefaults.standard.string(forKey: "selectedAppearance.\(pet.id)")
                ?? pet.appearances.first(where: \.isDefault)?.id
                ?? pet.appearances.first?.id
        profileBodySizeSlider.doubleValue = Double(pet.bodySize)
        profileBodySizeValue.stringValue = "\(pet.bodySize) / 100"

        appearanceStack.addArrangedSubview(appearanceIntro)
        appearanceIntro.widthAnchor.constraint(equalTo: appearanceStack.widthAnchor).isActive = true
        let cards = NSStackView()
        cards.orientation = .horizontal
        cards.alignment = .top
        cards.distribution = .fillEqually
        cards.spacing = 12
        for appearance in pet.appearances {
            let card = AppearanceCardView(
                option: appearance,
                language: language,
                isSelected: appearance.id == selectedAppearanceID,
                isEnabled: true
            ) { [weak self] id in
                self?.selectProfileAppearance(id)
            }
            cards.addArrangedSubview(card)
            card.heightAnchor.constraint(equalToConstant: 126).isActive = true
        }
        appearanceStack.addArrangedSubview(cards)
        cards.widthAnchor.constraint(equalTo: appearanceStack.widthAnchor).isActive = true

        let bodySizeRow = profileControlRow(title: "Body Size", control: profileBodySizeSlider, value: profileBodySizeValue)
        let speedRow = profileControlRow(title: "Animation Speed", control: profileAnimationSpeedSlider, value: profileAnimationSpeedValue)
        [bodySizeRow, speedRow].forEach {
            appearanceStack.addArrangedSubview($0)
            $0.widthAnchor.constraint(equalTo: appearanceStack.widthAnchor).isActive = true
        }
        let isActive = pet.id == PetAssetCatalog.activePet?.id
        useButton.title = isActive ? language.activePetButton : language.usePetButton
        useButton.isEnabled = !isActive
        updateMindDetails(for: pet.id)
    }

    private func profileControlRow(title: String, control: NSView, value: NSTextField?) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12.5, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: 112).isActive = true
        if control is NSSlider {
            control.widthAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true
            control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        let views = value.map { [label, control, $0] } ?? [label, control, NSView()]
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 9
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
        return row
    }

    private func activateSelectedPetIfNeeded() -> Bool {
        guard let pet = selectedPet else { return false }
        return pet.id == PetAssetCatalog.activePet?.id || onSelectPet?(pet.id) == true
    }

    private func selectProfileAppearance(_ id: String) {
        guard activateSelectedPetIfNeeded(),
              onAppearanceSelected?(id) == true else {
            refresh(language: language)
            return
        }
        refresh(language: language)
    }

    @objc private func profileAnimationSpeedChanged(_ sender: NSSlider) {
        let value = min(1.5, max(0.5, sender.doubleValue))
        profileAnimationSpeedValue.stringValue = "\(Int((value * 100).rounded()))%"
        onAnimationSpeedChanged?(value)
    }

    @objc private func profileBodySizeChanged(_ sender: NSSlider) {
        guard let pet = selectedPet else { return }
        let value = min(100, max(1, Int(sender.doubleValue.rounded())))
        profileBodySizeValue.stringValue = "\(value) / 100"
        onBodySizeChanged?(pet.id, value)
        pets = PetAssetCatalog.availablePets
        tableView.reloadData()
        petMeta.stringValue = "\(pet.species.capitalized) · Body size \(value)/100 · v\(pet.assetVersion)"
    }

    private func updateMindDetails(for petID: String) {
        let snapshot = PetMindStore.load(petID: petID)
        personalitySummary.stringValue = snapshot.personalitySummary(for: language)
        for trait in PetPersonalityTrait.allCases {
            traitSliders[trait]?.doubleValue = snapshot.traits[trait]
            traitValueLabels[trait]?.stringValue = "\(Int((snapshot.traits[trait] * 100).rounded()))%"
        }
        stateIndicators["energy"]?.doubleValue = snapshot.state.energy
        stateIndicators["curiosity"]?.doubleValue = snapshot.state.curiosityNeed
        stateIndicators["affinity"]?.doubleValue = snapshot.state.affinity

        memoryStack.arrangedSubviews.forEach {
            memoryStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        if snapshot.memories.isEmpty {
            let empty = NSTextField(wrappingLabelWithString: language.noMemoriesLabel)
            empty.font = .systemFont(ofSize: 11)
            empty.textColor = .tertiaryLabelColor
            memoryStack.addArrangedSubview(empty)
            clearMemoriesButton.isEnabled = false
        } else {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            formatter.locale = Locale(identifier: language.rawValue)
            for memory in snapshot.memories.prefix(3) {
                let time = formatter.localizedString(for: memory.date, relativeTo: Date())
                let label = NSTextField(wrappingLabelWithString: "• \(memory.text)  ·  \(time)")
                label.font = .systemFont(ofSize: 11)
                label.textColor = .secondaryLabelColor
                label.maximumNumberOfLines = 2
                memoryStack.addArrangedSubview(label)
                label.widthAnchor.constraint(equalTo: memoryStack.widthAnchor).isActive = true
            }
            clearMemoriesButton.isEnabled = true
        }
    }

    @objc private func personalitySliderChanged(_ sender: NSSlider) {
        guard let pet = selectedPet,
              PetPersonalityTrait.allCases.indices.contains(sender.tag) else { return }
        let trait = PetPersonalityTrait.allCases[sender.tag]
        var snapshot = PetMindStore.load(petID: pet.id)
        snapshot.traits[trait] = sender.doubleValue
        traitValueLabels[trait]?.stringValue = "\(Int((sender.doubleValue * 100).rounded()))%"
        personalitySummary.stringValue = snapshot.personalitySummary(for: language)
        PetMindStore.updateTraits(snapshot.traits, petID: pet.id)
    }

    @objc private func clearSelectedPetMemories() {
        guard let pet = selectedPet else { return }
        PetMindStore.clearMemories(petID: pet.id)
    }

    @objc private func petMindDidChange(_ notification: Notification) {
        guard let petID = notification.userInfo?["petID"] as? String,
              petID == selectedPetID else { return }
        updateMindDetails(for: petID)
    }

    private var selectedPet: PetLibraryPet? {
        selectedPetID.flatMap { id in pets.first(where: { $0.id == id }) }
    }

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        installPage(sender.selectedSegment == 0 ? libraryPage : creatorPage)
    }

    @objc private func useSelectedPet() {
        guard let pet = selectedPet, onSelectPet?(pet.id) == true else { return }
        refresh(language: language)
    }

    @objc private func importPack() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let summary = try PetPackLibraryManager.installPack(from: url)
            handleSuccessfulImport(summary)
        } catch PetPackLibraryError.petAlreadyExists(let name) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Replace \(name)?"
            alert.informativeText = "The existing pack is atomically replaced only after the new version passes validation."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            do {
                let summary = try PetPackLibraryManager.installPack(from: url, replacingExisting: true)
                handleSuccessfulImport(summary)
            } catch { show(error) }
        } catch { show(error) }
    }

    private func handleSuccessfulImport(_ summary: ValidatedPetPack) {
        onLibraryChanged?()
        selectedPetID = summary.id
        refresh(language: language)
        let alert = NSAlert()
        alert.messageText = language.importSuccessTitle
        alert.informativeText = language.importedPetMessage(summary.name)
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func exportSelectedPet() {
        guard let pet = selectedPet else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        do {
            let output = try PetPackLibraryManager.exportPet(pet, to: directory)
            NSWorkspace.shared.activateFileViewerSelecting([output])
        } catch { show(error) }
    }

    @objc private func removeSelectedPet() {
        guard let pet = selectedPet, !pet.isBundled else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remove \(pet.name)?"
        alert.informativeText = "The pet pack will move to Trash and can be recovered."
        alert.addButton(withTitle: language.removePetButton)
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try PetPackLibraryManager.removePet(pet)
            onLibraryChanged?()
            selectedPetID = PetAssetCatalog.activePet?.id
            refresh(language: language)
        } catch { show(error) }
    }

    @objc private func choosePhotos() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        panel.prompt = "Choose Photos"
        guard panel.runModal() == .OK else { return }
        guard (6...12).contains(panel.urls.count) else {
            showMessage(language.invalidCreationInput)
            return
        }
        selectedPhotos = panel.urls
        photosLabel.stringValue = language.selectedPhotosLabel(selectedPhotos.count)
    }

    @objc private func exportCreationRequest() {
        guard let input = validatedCreationInput() else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Create Here"
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        do {
            let output = try PetPackLibraryManager.makeCreationRequest(
                name: input.name,
                species: input.species,
                bodySize: input.bodySize,
                styles: input.styles,
                photos: selectedPhotos,
                in: directory
            )
            NSWorkspace.shared.activateFileViewerSelecting([output])
        } catch { show(error) }
    }

    private func validatedCreationInput() -> (name: String, species: String, bodySize: Int, styles: [String])? {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let styles = ["realistic-2d"]
        guard !name.isEmpty, (6...12).contains(selectedPhotos.count) else {
            showMessage(language.invalidCreationInput)
            return nil
        }
        let species = ["dog", "cat", "other"][max(0, speciesPopup.indexOfSelectedItem)]
        return (name, species, Int(bodySizeSlider.doubleValue.rounded()), styles)
    }

    @objc private func creationBodySizeChanged(_ sender: NSSlider) {
        bodySizeValue.stringValue = "\(Int(sender.doubleValue.rounded())) / 100"
    }

    @objc private func buildWithCodex() {
        if let job = codexCreationJob {
            codexCreationWasCancelled = true
            job.process.terminate()
            oneClickCodexButton.isEnabled = false
            return
        }
        guard let input = validatedCreationInput() else { return }
        let consent = NSAlert()
        consent.alertStyle = .informational
        consent.messageText = language.codexPhotoConsentTitle
        consent.informativeText = language.codexPhotoConsentBody
        consent.addButton(withTitle: language.oneClickCodexButton)
        consent.addButton(withTitle: "Cancel")
        guard consent.runModal() == .alertFirstButtonReturn else { return }

        do {
            let job = try PetPackLibraryManager.startCodexCreation(
                name: input.name,
                species: input.species,
                bodySize: input.bodySize,
                styles: input.styles,
                photos: selectedPhotos
            )
            codexCreationJob = job
            codexCreationWasCancelled = false
            creationProgress.startAnimation(nil)
            creationStatus.stringValue = language.codexCreationRunningLabel
            oneClickCodexButton.title = language.cancelCodexCreationButton
            createRequestButton.isEnabled = false
            downloadSkillButton.isEnabled = false
            downloadLiveMotionSkillButton.isEnabled = false
            job.process.terminationHandler = { [weak self, weak job] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, let job else { return }
                        self.completeCodexCreation(job)
                    }
                }
            }
            if !job.process.isRunning {
                completeCodexCreation(job)
            }
        } catch {
            show(error)
        }
    }

    private func completeCodexCreation(_ job: CodexPetCreationJob) {
        guard codexCreationJob === job else { return }
        codexCreationJob = nil
        creationProgress.stopAnimation(nil)
        oneClickCodexButton.title = language.oneClickCodexButton
        oneClickCodexButton.isEnabled = PetPackLibraryManager.codexExecutableURL != nil
        createRequestButton.isEnabled = true
        downloadSkillButton.isEnabled = true
        downloadLiveMotionSkillButton.isEnabled = true
        if codexCreationWasCancelled {
            try? job.logHandle.close()
            creationStatus.stringValue = language.codexCreationCancelledLabel
            codexCreationWasCancelled = false
            return
        }
        do {
            let summary = try PetPackLibraryManager.finishCodexCreation(job)
            onLibraryChanged?()
            selectedPetID = summary.id
            refresh(language: language)
            creationStatus.stringValue = language.codexCreationSucceeded(summary.name)
            showMessage(language.codexCreationSucceeded(summary.name))
        } catch {
            creationStatus.stringValue = error.localizedDescription
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Generation Did Not Finish"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "Show Log")
            alert.addButton(withTitle: "Close")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([job.logURL])
            }
        }
    }

    @objc private func downloadCreatorSkill() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Download Here"
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        do {
            let output = try PetPackLibraryManager.exportCreatorSkill(to: directory)
            NSWorkspace.shared.activateFileViewerSelecting([output])
        } catch { show(error) }
    }

    @objc private func downloadLiveMotionSkill() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Download Here"
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        do {
            let output = try PetPackLibraryManager.exportLiveMotionSkill(to: directory)
            NSWorkspace.shared.activateFileViewerSelecting([output])
        } catch { show(error) }
    }

    private func show(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    private func showMessage(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
