import AppKit

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private weak var manager: DownloadManager?
    private var window: NSWindow?
    private let dirField = NSTextField(labelWithString: "")
    private let maxField = NSTextField(string: "")
    private let maxStepper = NSStepper()
    private let optionsView = NSTextView()
    private let binaryPathField = NSTextField(labelWithString: "")
    private let binaryVersionField = NSTextField(labelWithString: "")
    private let defaultBinaryButton = NSButton(title: "Use Default", target: nil, action: nil)
    private let saveButton = NSButton(title: "Save Changes", target: nil, action: nil)
    private var selectedBinaryPath: String?
    private var binaryCheckGeneration = 0
    private var retainedSelf: SettingsWindowController?

    init(manager: DownloadManager) {
        self.manager = manager
        super.init()
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        selectedBinaryPath = manager?.config?.aria2cPath
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 700),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "TrickleBar Settings"
        win.titlebarAppearsTransparent = true
        win.backgroundColor = .controlBackgroundColor
        win.contentView = buildContentView(cfg: manager?.config)
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        window = win
        retainedSelf = self
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(nil)
        refreshBinary()
    }

    private func label(_ title: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
                       color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: title)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    private func buildContentView(cfg: TrickleBarConfig?) -> NSView {
        let root = SettingsBackground(frame: NSRect(x: 0, y: 0, width: 540, height: 700))
        let downloadsTitle = label("Downloads", size: 14, weight: .semibold)
        let downloadsGroup = SettingsPanel()
        downloadsGroup.translatesAutoresizingMaskIntoConstraints = false

        let folderTitle = label("Download folder", size: 14)
        dirField.stringValue = cfg?.resolvedDownloadDir ?? TrickleBarConfig.defaultDownloadDir
        dirField.font = .systemFont(ofSize: 12)
        dirField.textColor = .secondaryLabelColor
        dirField.lineBreakMode = .byTruncatingMiddle
        dirField.isSelectable = true
        dirField.toolTip = dirField.stringValue
        dirField.translatesAutoresizingMaskIntoConstraints = false
        dirField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let choose = NSButton(title: "Choose…", target: self, action: #selector(chooseDir))
        choose.bezelStyle = .rounded
        choose.controlSize = .small
        choose.image = interfaceSymbol("folder", size: 13, description: "Choose download folder")
        choose.imagePosition = .imageLeading
        choose.translatesAutoresizingMaskIntoConstraints = false
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        let queueTitle = label("Max active downloads", size: 14)
        let queueHint = label("Limit how many downloads run at the same time.", size: 12, color: .secondaryLabelColor)
        let n = cfg?.resolvedMaxConcurrent ?? TrickleBarConfig.defaultMaxConcurrent
        let formatter = NumberFormatter()
        formatter.minimum = 1
        formatter.maximum = 50
        formatter.allowsFloats = false
        maxField.formatter = formatter
        maxField.integerValue = n
        maxField.alignment = .right
        maxField.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        maxField.isBezeled = false
        maxField.drawsBackground = false
        maxField.translatesAutoresizingMaskIntoConstraints = false
        maxField.target = self
        maxField.action = #selector(maxFieldChanged)
        maxField.setAccessibilityLabel("Maximum active downloads")
        maxStepper.minValue = 1
        maxStepper.maxValue = 50
        maxStepper.increment = 1
        maxStepper.integerValue = n
        maxStepper.target = self
        maxStepper.action = #selector(stepperChanged)
        maxStepper.translatesAutoresizingMaskIntoConstraints = false
        maxStepper.setAccessibilityLabel("Adjust maximum active downloads")

        let advancedTitle = label("Advanced", size: 14, weight: .semibold)
        let binaryGroup = SettingsPanel()
        binaryGroup.translatesAutoresizingMaskIntoConstraints = false
        let binaryTitle = label("aria2c binary", size: 14)
        binaryPathField.font = .systemFont(ofSize: 12)
        binaryPathField.textColor = .secondaryLabelColor
        binaryPathField.lineBreakMode = .byTruncatingMiddle
        binaryPathField.isSelectable = true
        binaryPathField.translatesAutoresizingMaskIntoConstraints = false
        binaryPathField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let chooseBinary = NSButton(title: "Choose…", target: self, action: #selector(chooseBinaryAction))
        chooseBinary.bezelStyle = .rounded
        chooseBinary.controlSize = .small
        chooseBinary.image = interfaceSymbol("folder", size: 13, description: "Choose aria2c binary")
        chooseBinary.imagePosition = .imageLeading
        chooseBinary.translatesAutoresizingMaskIntoConstraints = false
        let binaryDivider = NSBox()
        binaryDivider.boxType = .separator
        binaryDivider.translatesAutoresizingMaskIntoConstraints = false
        let versionTitle = label("Version", size: 14)
        binaryVersionField.font = .systemFont(ofSize: 12)
        binaryVersionField.textColor = .secondaryLabelColor
        binaryVersionField.lineBreakMode = .byTruncatingTail
        binaryVersionField.isSelectable = true
        binaryVersionField.translatesAutoresizingMaskIntoConstraints = false
        binaryVersionField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        defaultBinaryButton.target = self
        defaultBinaryButton.action = #selector(useDefaultBinary)
        defaultBinaryButton.bezelStyle = .rounded
        defaultBinaryButton.controlSize = .small
        defaultBinaryButton.translatesAutoresizingMaskIntoConstraints = false
        let binaryHint = label("Changing the binary restarts aria2c and resumes downloads.", size: 12, color: .secondaryLabelColor)
        let optionsGroup = SettingsPanel()
        optionsGroup.translatesAutoresizingMaskIntoConstraints = false
        let optionsTitle = label("Custom aria2c options", size: 14)
        let terminal = NSImageView()
        terminal.image = interfaceSymbol("terminal", size: 16)
        terminal.contentTintColor = .secondaryLabelColor
        terminal.translatesAutoresizingMaskIntoConstraints = false
        let optionsDivider = NSBox()
        optionsDivider.boxType = .separator
        optionsDivider.translatesAutoresizingMaskIntoConstraints = false
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        optionsView.isEditable = true
        optionsView.isSelectable = true
        optionsView.allowsUndo = true
        optionsView.isRichText = false
        optionsView.isAutomaticQuoteSubstitutionEnabled = false
        optionsView.isAutomaticDashSubstitutionEnabled = false
        optionsView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        optionsView.textColor = .labelColor
        optionsView.drawsBackground = false
        optionsView.textContainerInset = NSSize(width: 0, height: 8)
        optionsView.string = cfg?.customOptions ?? ""
        optionsView.minSize = NSSize(width: 0, height: 120)
        optionsView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        optionsView.isVerticallyResizable = true
        optionsView.isHorizontallyResizable = false
        optionsView.autoresizingMask = .width
        optionsView.textContainer?.widthTracksTextView = true
        optionsView.textContainer?.containerSize = NSSize(width: 450, height: CGFloat.greatestFiniteMagnitude)
        optionsView.frame = NSRect(x: 0, y: 0, width: 460, height: 120)
        optionsView.setAccessibilityLabel("Custom aria2c options, one flag per line")
        scroll.documentView = optionsView
        let optionsHint = label("One flag per line, e.g. --max-connection-per-server=16.\nThese options override the app defaults.", size: 12, color: .secondaryLabelColor)
        optionsHint.maximumNumberOfLines = 2
        optionsHint.lineBreakMode = .byWordWrapping

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelAction))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        cancel.translatesAutoresizingMaskIntoConstraints = false
        let save = saveButton
        save.target = self
        save.action = #selector(saveAction)
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.translatesAutoresizingMaskIntoConstraints = false

        for v in [downloadsTitle, downloadsGroup, queueHint, advancedTitle, binaryGroup, binaryHint, optionsGroup, optionsHint, cancel, save] {
            root.addSubview(v)
        }
        for v in [folderTitle, dirField, choose, divider, queueTitle, maxField, maxStepper] {
            downloadsGroup.addSubview(v)
        }
        for v in [optionsTitle, terminal, optionsDivider, scroll] { optionsGroup.addSubview(v) }
        for v in [binaryTitle, binaryPathField, chooseBinary, binaryDivider, versionTitle, binaryVersionField, defaultBinaryButton] {
            binaryGroup.addSubview(v)
        }
        NSLayoutConstraint.activate([
            downloadsTitle.topAnchor.constraint(equalTo: root.topAnchor, constant: 26),
            downloadsTitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            downloadsGroup.topAnchor.constraint(equalTo: downloadsTitle.bottomAnchor, constant: 12),
            downloadsGroup.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            downloadsGroup.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            downloadsGroup.heightAnchor.constraint(equalToConstant: 122),
            folderTitle.leadingAnchor.constraint(equalTo: downloadsGroup.leadingAnchor, constant: 14),
            folderTitle.topAnchor.constraint(equalTo: downloadsGroup.topAnchor, constant: 15),
            dirField.leadingAnchor.constraint(equalTo: folderTitle.leadingAnchor),
            dirField.topAnchor.constraint(equalTo: folderTitle.bottomAnchor, constant: 5),
            dirField.trailingAnchor.constraint(equalTo: choose.leadingAnchor, constant: -16),
            choose.trailingAnchor.constraint(equalTo: downloadsGroup.trailingAnchor, constant: -14),
            choose.centerYAnchor.constraint(equalTo: downloadsGroup.topAnchor, constant: 34),
            choose.widthAnchor.constraint(equalToConstant: 90),
            divider.leadingAnchor.constraint(equalTo: folderTitle.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: downloadsGroup.trailingAnchor, constant: -14),
            divider.topAnchor.constraint(equalTo: downloadsGroup.topAnchor, constant: 72),
            queueTitle.leadingAnchor.constraint(equalTo: folderTitle.leadingAnchor),
            queueTitle.centerYAnchor.constraint(equalTo: downloadsGroup.topAnchor, constant: 97),
            maxStepper.trailingAnchor.constraint(equalTo: downloadsGroup.trailingAnchor, constant: -14),
            maxStepper.centerYAnchor.constraint(equalTo: queueTitle.centerYAnchor),
            maxField.trailingAnchor.constraint(equalTo: maxStepper.leadingAnchor, constant: -8),
            maxField.centerYAnchor.constraint(equalTo: maxStepper.centerYAnchor),
            maxField.widthAnchor.constraint(equalToConstant: 40),
            queueHint.topAnchor.constraint(equalTo: downloadsGroup.bottomAnchor, constant: 10),
            queueHint.leadingAnchor.constraint(equalTo: downloadsTitle.leadingAnchor),
            advancedTitle.topAnchor.constraint(equalTo: queueHint.bottomAnchor, constant: 28),
            advancedTitle.leadingAnchor.constraint(equalTo: downloadsTitle.leadingAnchor),
            binaryGroup.topAnchor.constraint(equalTo: advancedTitle.bottomAnchor, constant: 12),
            binaryGroup.leadingAnchor.constraint(equalTo: downloadsGroup.leadingAnchor),
            binaryGroup.trailingAnchor.constraint(equalTo: downloadsGroup.trailingAnchor),
            binaryGroup.heightAnchor.constraint(equalToConstant: 114),
            binaryTitle.topAnchor.constraint(equalTo: binaryGroup.topAnchor, constant: 15),
            binaryTitle.leadingAnchor.constraint(equalTo: binaryGroup.leadingAnchor, constant: 14),
            binaryPathField.topAnchor.constraint(equalTo: binaryTitle.bottomAnchor, constant: 5),
            binaryPathField.leadingAnchor.constraint(equalTo: binaryTitle.leadingAnchor),
            binaryPathField.trailingAnchor.constraint(equalTo: chooseBinary.leadingAnchor, constant: -16),
            chooseBinary.trailingAnchor.constraint(equalTo: binaryGroup.trailingAnchor, constant: -14),
            chooseBinary.centerYAnchor.constraint(equalTo: binaryGroup.topAnchor, constant: 34),
            chooseBinary.widthAnchor.constraint(equalToConstant: 90),
            binaryDivider.topAnchor.constraint(equalTo: binaryGroup.topAnchor, constant: 72),
            binaryDivider.leadingAnchor.constraint(equalTo: binaryTitle.leadingAnchor),
            binaryDivider.trailingAnchor.constraint(equalTo: chooseBinary.trailingAnchor),
            versionTitle.leadingAnchor.constraint(equalTo: binaryTitle.leadingAnchor),
            versionTitle.centerYAnchor.constraint(equalTo: binaryGroup.topAnchor, constant: 93),
            binaryVersionField.leadingAnchor.constraint(equalTo: versionTitle.trailingAnchor, constant: 16),
            binaryVersionField.centerYAnchor.constraint(equalTo: versionTitle.centerYAnchor),
            binaryVersionField.trailingAnchor.constraint(equalTo: defaultBinaryButton.leadingAnchor, constant: -12),
            defaultBinaryButton.trailingAnchor.constraint(equalTo: chooseBinary.trailingAnchor),
            defaultBinaryButton.centerYAnchor.constraint(equalTo: versionTitle.centerYAnchor),
            defaultBinaryButton.widthAnchor.constraint(equalToConstant: 90),
            binaryHint.topAnchor.constraint(equalTo: binaryGroup.bottomAnchor, constant: 10),
            binaryHint.leadingAnchor.constraint(equalTo: advancedTitle.leadingAnchor),
            optionsGroup.topAnchor.constraint(equalTo: binaryHint.bottomAnchor, constant: 16),
            optionsGroup.leadingAnchor.constraint(equalTo: downloadsGroup.leadingAnchor),
            optionsGroup.trailingAnchor.constraint(equalTo: downloadsGroup.trailingAnchor),
            optionsGroup.heightAnchor.constraint(equalToConstant: 168),
            optionsTitle.leadingAnchor.constraint(equalTo: optionsGroup.leadingAnchor, constant: 14),
            optionsTitle.centerYAnchor.constraint(equalTo: optionsGroup.topAnchor, constant: 24),
            terminal.trailingAnchor.constraint(equalTo: optionsGroup.trailingAnchor, constant: -14),
            terminal.centerYAnchor.constraint(equalTo: optionsTitle.centerYAnchor),
            terminal.widthAnchor.constraint(equalToConstant: 20),
            terminal.heightAnchor.constraint(equalToConstant: 20),
            optionsDivider.topAnchor.constraint(equalTo: optionsGroup.topAnchor, constant: 48),
            optionsDivider.leadingAnchor.constraint(equalTo: optionsTitle.leadingAnchor),
            optionsDivider.trailingAnchor.constraint(equalTo: terminal.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: optionsDivider.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: optionsTitle.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: optionsGroup.trailingAnchor, constant: -14),
            scroll.bottomAnchor.constraint(equalTo: optionsGroup.bottomAnchor, constant: -12),
            optionsHint.topAnchor.constraint(equalTo: optionsGroup.bottomAnchor, constant: 10),
            optionsHint.leadingAnchor.constraint(equalTo: downloadsTitle.leadingAnchor),
            optionsHint.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            save.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            save.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
            save.topAnchor.constraint(greaterThanOrEqualTo: optionsHint.bottomAnchor, constant: 18),
            save.widthAnchor.constraint(equalToConstant: 112),
            cancel.trailingAnchor.constraint(equalTo: save.leadingAnchor, constant: -10),
            cancel.centerYAnchor.constraint(equalTo: save.centerYAnchor),
            cancel.widthAnchor.constraint(equalToConstant: 80),
        ])
        return root
    }

    @objc private func chooseDir() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose Folder"
        panel.directoryURL = URL(fileURLWithPath: dirField.stringValue)
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.dirField.stringValue = url.path
            self?.dirField.toolTip = url.path
        }
    }

    @objc private func stepperChanged() { maxField.integerValue = maxStepper.integerValue }
    @objc private func maxFieldChanged() {
        maxField.integerValue = min(max(maxField.integerValue, 1), 50)
        maxStepper.integerValue = maxField.integerValue
    }

    @objc private func saveAction() {
        window?.makeFirstResponder(nil)
        let dir = dirField.stringValue.trimmingCharacters(in: .whitespaces)
        let opts = optionsView.string
        manager?.applySettings(downloadDir: dir.isEmpty ? nil : dir,
                               maxConcurrent: min(max(maxField.integerValue, 1), 50),
                               customOptions: opts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : opts,
                               aria2cPath: selectedBinaryPath)
        window?.close()
    }

    @objc private func cancelAction() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        binaryCheckGeneration += 1
        window = nil
        retainedSelf = nil
    }

    @objc private func chooseBinaryAction() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.message = "Choose the aria2c executable."
        panel.prompt = "Choose Binary"
        if let path = Aria2Binary.resolve(customPath: selectedBinaryPath) {
            panel.directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
        }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.selectedBinaryPath = url.path
            self?.refreshBinary()
        }
    }

    @objc private func useDefaultBinary() {
        selectedBinaryPath = nil
        refreshBinary()
    }

    private func refreshBinary() {
        binaryCheckGeneration += 1
        let generation = binaryCheckGeneration
        defaultBinaryButton.isEnabled = selectedBinaryPath != nil
        saveButton.isEnabled = false
        let currentPath = selectedBinaryPath == manager?.config?.aria2cPath ? manager?.aria2cBinaryPath : nil
        let path = currentPath ?? Aria2Binary.resolve(customPath: selectedBinaryPath)
        binaryPathField.stringValue = path ?? "Not found — choose an aria2c binary"
        binaryPathField.toolTip = path
        binaryVersionField.stringValue = path == nil ? "Unavailable" : "Checking…"
        binaryVersionField.textColor = .secondaryLabelColor
        guard let path else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try Aria2Binary.version(at: path) }
            DispatchQueue.main.async {
                guard let self, self.window != nil, self.binaryCheckGeneration == generation else { return }
                switch result {
                case .success(let version):
                    self.binaryVersionField.stringValue = version
                    self.binaryVersionField.toolTip = nil
                    self.saveButton.isEnabled = true
                case .failure(let error):
                    self.binaryVersionField.stringValue = error.localizedDescription
                    self.binaryVersionField.toolTip = error.localizedDescription
                    self.binaryVersionField.textColor = .systemRed
                }
            }
        }
    }
}
