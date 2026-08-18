import AppKit
import UniformTypeIdentifiers

@MainActor
final class PetLibraryWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var onSelectPet: ((String) -> Bool)?
    var onLibraryChanged: (() -> Void)?

    private var language: AppLanguage
    private let isEmbedded: Bool
    private var pets: [PetLibraryPet] = []
    private var selectedPetID: String?
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
    private let appearanceStack = NSStackView()
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
    private let cuteCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let realisticCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let photosLabel = NSTextField(labelWithString: "")
    private let choosePhotosButton = NSButton()
    private let createRequestButton = NSButton()
    private let downloadSkillButton = NSButton()

    init(language: AppLanguage, embedded: Bool = false) {
        self.language = language
        isEmbedded = embedded
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 830, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 760, height: 550)
        window.center()
        super.init(window: window)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(petMindDidChange(_:)),
            name: .petMindDidChange,
            object: nil
        )
        window.delegate = self
        buildInterface()
        refresh(language: language)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func refresh(language: AppLanguage) {
        self.language = language
        pets = PetAssetCatalog.availablePets
        selectedPetID = selectedPetID.flatMap { id in pets.contains(where: { $0.id == id }) ? id : nil }
            ?? PetAssetCatalog.activePet?.id
            ?? pets.first?.id
        applyLanguage()
        tableView.reloadData()
        if let selectedPetID, let row = pets.firstIndex(where: { $0.id == selectedPetID }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        }
        updateDetails()
    }

    func present() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        VisualQACapture.schedule(view: window?.contentView, name: segmented.selectedSegment == 0 ? "pet-library" : "pet-creator")
    }

    func presentCreator() {
        segmented.selectedSegment = 1
        libraryPage.isHidden = true
        creatorPage.isHidden = false
        present()
    }

    func showLibraryEmbedded() {
        segmented.selectedSegment = 0
        libraryPage.isHidden = false
        creatorPage.isHidden = true
    }

    func showCreatorEmbedded() {
        segmented.selectedSegment = 1
        libraryPage.isHidden = true
        creatorPage.isHidden = false
    }

    /// Transfers the library/creator page into the unified Settings window.
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
        window.contentView = root

        segmented.target = self
        segmented.action = #selector(tabChanged(_:))
        segmented.selectedSegment = 0
        segmented.segmentStyle = .capsule
        segmented.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        if !isEmbedded { root.addSubview(segmented) }
        root.addSubview(contentContainer)

        for page in [libraryPage, creatorPage] {
            page.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview(page)
            NSLayoutConstraint.activate([
                page.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
                page.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                page.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
            ])
        }
        creatorPage.isHidden = true
        buildLibraryPage()
        buildCreatorPage()

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

    private func buildLibraryPage() {
        libraryPage.wantsLayer = true
        libraryPage.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
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
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(scroll)

        importButton.bezelStyle = .rounded
        importButton.target = self
        importButton.action = #selector(importPack)
        importButton.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(importButton)

        let details = NSView()
        details.wantsLayer = true
        details.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        details.translatesAutoresizingMaskIntoConstraints = false
        petName.font = .systemFont(ofSize: 28, weight: .bold)
        petMeta.font = .systemFont(ofSize: 12.5, weight: .medium)
        petMeta.textColor = .secondaryLabelColor
        builtInBadge.font = .systemFont(ofSize: 10, weight: .bold)
        builtInBadge.textColor = .systemOrange
        appearanceHeading.font = .systemFont(ofSize: 11, weight: .semibold)
        appearanceHeading.textColor = .secondaryLabelColor
        appearanceStack.orientation = .vertical
        appearanceStack.spacing = 8
        appearanceStack.alignment = .leading
        configureProfileSection()

        useButton.bezelStyle = .rounded
        useButton.keyEquivalent = "\r"
        useButton.target = self
        useButton.action = #selector(useSelectedPet)
        exportButton.bezelStyle = .rounded
        exportButton.target = self
        exportButton.action = #selector(exportSelectedPet)
        removeButton.bezelStyle = .rounded
        removeButton.contentTintColor = .systemRed
        removeButton.target = self
        removeButton.action = #selector(removeSelectedPet)

        let buttonRow = NSStackView(views: [useButton, exportButton, removeButton, NSView()])
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
            NSView(), buttonRow
        ])
        detailsStack.orientation = .vertical
        detailsStack.alignment = .leading
        detailsStack.spacing = 7
        detailsStack.setCustomSpacing(22, after: builtInBadge)
        detailsStack.setCustomSpacing(17, after: appearanceStack)
        detailsStack.setCustomSpacing(15, after: personalityStack)
        detailsStack.setCustomSpacing(15, after: stateStack)
        detailsStack.translatesAutoresizingMaskIntoConstraints = false
        details.addSubview(detailsStack)

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
            detailsStack.leadingAnchor.constraint(equalTo: details.leadingAnchor, constant: 34),
            detailsStack.trailingAnchor.constraint(equalTo: details.trailingAnchor, constant: -34),
            detailsStack.topAnchor.constraint(equalTo: details.topAnchor, constant: 32),
            detailsStack.bottomAnchor.constraint(equalTo: details.bottomAnchor, constant: -24),
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
        cuteCheckbox.state = .on
        realisticCheckbox.state = .on

        choosePhotosButton.bezelStyle = .rounded
        choosePhotosButton.target = self
        choosePhotosButton.action = #selector(choosePhotos)
        createRequestButton.bezelStyle = .rounded
        createRequestButton.keyEquivalent = "\r"
        createRequestButton.target = self
        createRequestButton.action = #selector(exportCreationRequest)
        downloadSkillButton.bezelStyle = .rounded
        downloadSkillButton.target = self
        downloadSkillButton.action = #selector(downloadCreatorSkill)
        photosLabel.textColor = .secondaryLabelColor

        let form = NSGridView(views: [
            [formLabel("pet-name"), nameField],
            [formLabel("species"), speciesPopup],
            [formLabel("styles"), NSStackView(views: [cuteCheckbox, realisticCheckbox])],
            [formLabel("photos"), NSStackView(views: [choosePhotosButton, photosLabel])]
        ])
        form.rowSpacing = 13
        form.columnSpacing = 18
        form.column(at: 0).xPlacement = .trailing
        form.column(at: 1).xPlacement = .fill
        form.column(at: 1).width = 380

        let buttons = NSStackView(views: [createRequestButton, downloadSkillButton, NSView()])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let stack = NSStackView(views: [creatorTitle, creatorIntro, form, buttons])
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
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor)
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
        importButton.title = language.importPetPackButton
        exportButton.title = language.exportPetPackButton
        removeButton.title = language.removePetButton
        appearanceHeading.stringValue = language.appearanceCountLabel
        personalityHeading.stringValue = language.personalityHeading
        stateHeading.stringValue = language.currentStateHeading
        memoryHeading.stringValue = language.shortMemoryHeading
        clearMemoriesButton.title = language.clearMemoriesButton
        for trait in PetPersonalityTrait.allCases {
            (libraryPage.viewWithIdentifier("trait-title-\(trait.rawValue)") as? NSTextField)?.stringValue = language.personalityTraitTitle(trait)
        }
        (libraryPage.viewWithIdentifier("state-title-energy") as? NSTextField)?.stringValue = language.energyStateLabel
        (libraryPage.viewWithIdentifier("state-title-curiosity") as? NSTextField)?.stringValue = language.curiosityStateLabel
        (libraryPage.viewWithIdentifier("state-title-affinity") as? NSTextField)?.stringValue = language.affinityStateLabel
        builtInBadge.stringValue = language.builtInBadge
        creatorTitle.stringValue = language.creatorTab
        creatorIntro.stringValue = language.creatorIntro
        cuteCheckbox.title = language.cuteStyleLabel
        realisticCheckbox.title = language.realisticStyleLabel
        choosePhotosButton.title = language.choosePhotosButton
        photosLabel.stringValue = language.selectedPhotosLabel(selectedPhotos.count)
        createRequestButton.title = language.exportCreationRequestButton
        downloadSkillButton.title = language.downloadSkillButton
        (creatorPage.viewWithIdentifier("pet-name") as? NSTextField)?.stringValue = language.petNameField
        (creatorPage.viewWithIdentifier("species") as? NSTextField)?.stringValue = language.speciesField
        (creatorPage.viewWithIdentifier("styles") as? NSTextField)?.stringValue = language.stylesField
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
        let meta = NSTextField(labelWithString: "\(pet.appearances.count) · \(pet.species.capitalized)")
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
        selectedPetID = pets[row].id
        updateDetails()
    }

    private func updateDetails() {
        guard let pet = selectedPet else {
            petName.stringValue = "—"
            return
        }
        petName.stringValue = pet.name
        let species = language == .simplifiedChinese
            ? (["dog": "狗狗", "cat": "猫咪", "other": "其他"] [pet.species] ?? pet.species)
            : pet.species.capitalized
        petMeta.stringValue = "\(species) · v\(pet.assetVersion)"
        builtInBadge.isHidden = !pet.isBundled
        appearanceStack.arrangedSubviews.forEach {
            appearanceStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for appearance in pet.appearances {
            let icon = NSImageView()
            icon.image = NSImage(systemSymbolName: appearance.systemImage, accessibilityDescription: nil)
            icon.contentTintColor = .controlAccentColor
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            let title = NSTextField(labelWithString: appearance.title(for: language))
            title.font = .systemFont(ofSize: 13, weight: .semibold)
            let subtitle = NSTextField(labelWithString: appearance.subtitle(for: language))
            subtitle.font = .systemFont(ofSize: 11)
            subtitle.textColor = .secondaryLabelColor
            let row = NSStackView(views: [icon, title, subtitle, NSView()])
            row.orientation = .horizontal
            row.spacing = 8
            appearanceStack.addArrangedSubview(row)
        }
        let isActive = pet.id == PetAssetCatalog.activePet?.id
        useButton.title = isActive ? language.activePetButton : language.usePetButton
        useButton.isEnabled = !isActive
        removeButton.isHidden = pet.isBundled
        removeButton.isEnabled = !isActive
        updateMindDetails(for: pet.id)
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
                let label = NSTextField(wrappingLabelWithString: "• \(memory.text(for: language))  ·  \(time)")
                label.font = .systemFont(ofSize: 11)
                label.textColor = .secondaryLabelColor
                label.maximumNumberOfLines = 2
                label.widthAnchor.constraint(equalTo: memoryStack.widthAnchor).isActive = true
                memoryStack.addArrangedSubview(label)
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
        libraryPage.isHidden = sender.selectedSegment != 0
        creatorPage.isHidden = sender.selectedSegment != 1
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
        panel.prompt = language == .simplifiedChinese ? "导入" : "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let summary = try PetPackLibraryManager.installPack(from: url)
            handleSuccessfulImport(summary)
        } catch PetPackLibraryError.petAlreadyExists(let name) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = language == .simplifiedChinese ? "替换 \(name)？" : "Replace \(name)?"
            alert.informativeText = language == .simplifiedChinese
                ? "新版本通过完整验证后才会原子替换现有宠物包。"
                : "The existing pack is atomically replaced only after the new version passes validation."
            alert.addButton(withTitle: language == .simplifiedChinese ? "替换" : "Replace")
            alert.addButton(withTitle: language == .simplifiedChinese ? "取消" : "Cancel")
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
        panel.prompt = language == .simplifiedChinese ? "导出到这里" : "Export Here"
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
        alert.messageText = language == .simplifiedChinese ? "移除 \(pet.name)？" : "Remove \(pet.name)?"
        alert.informativeText = language == .simplifiedChinese
            ? "宠物包会移到废纸篓，可以恢复。"
            : "The pet pack will move to Trash and can be recovered."
        alert.addButton(withTitle: language.removePetButton)
        alert.addButton(withTitle: language == .simplifiedChinese ? "取消" : "Cancel")
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
        panel.prompt = language == .simplifiedChinese ? "选择照片" : "Choose Photos"
        guard panel.runModal() == .OK else { return }
        guard (6...12).contains(panel.urls.count) else {
            showMessage(language.invalidCreationInput)
            return
        }
        selectedPhotos = panel.urls
        photosLabel.stringValue = language.selectedPhotosLabel(selectedPhotos.count)
    }

    @objc private func exportCreationRequest() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let styles = [
            cuteCheckbox.state == .on ? "cute-2d" : nil,
            realisticCheckbox.state == .on ? "realistic-2d" : nil
        ].compactMap { $0 }
        guard !name.isEmpty, !styles.isEmpty, (6...12).contains(selectedPhotos.count) else {
            showMessage(language.invalidCreationInput)
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = language == .simplifiedChinese ? "创建到这里" : "Create Here"
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        let species = ["dog", "cat", "other"][max(0, speciesPopup.indexOfSelectedItem)]
        do {
            let output = try PetPackLibraryManager.makeCreationRequest(
                name: name,
                species: species,
                styles: styles,
                photos: selectedPhotos,
                in: directory
            )
            NSWorkspace.shared.activateFileViewerSelecting([output])
        } catch { show(error) }
    }

    @objc private func downloadCreatorSkill() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = language == .simplifiedChinese ? "下载到这里" : "Download Here"
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        do {
            let output = try PetPackLibraryManager.exportCreatorSkill(to: directory)
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
