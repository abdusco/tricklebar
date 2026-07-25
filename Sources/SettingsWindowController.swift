import AppKit

// A small, code-built settings form shown in its own window. Kept separate from the
// popover so the folder picker (NSOpenPanel) isn't nested inside a modal alert.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private weak var manager: DownloadManager?
    private var window: NSWindow?

    // Controls
    private let dirField = NSTextField(labelWithString: "")
    private let maxField = NSTextField(string: "")
    private let maxStepper = NSStepper()
    private let optionsView = NSTextView()

    // Retain self while the window is open so callbacks stay alive.
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

        let cfg = manager?.config
        let content = buildContentView(cfg: cfg)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "TrickleBar Settings"
        win.contentView = content
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        win.initialFirstResponder = maxField
        window = win
        retainedSelf = self

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    // MARK: - Layout

    private func buildContentView(cfg: TrickleBarConfig?) -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 360))

        // ── Download folder ─────────────────────────────────────────────
        let dirTitle = sectionLabel("Download folder")
        dirField.stringValue = cfg?.resolvedDownloadDir ?? TrickleBarConfig.defaultDownloadDir
        dirField.lineBreakMode = .byTruncatingMiddle
        dirField.isSelectable = true
        dirField.font = .systemFont(ofSize: 12)
        dirField.translatesAutoresizingMaskIntoConstraints = false
        dirField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let chooseBtn = NSButton(title: "Choose…", target: self, action: #selector(chooseDir))
        chooseBtn.bezelStyle = .rounded
        chooseBtn.translatesAutoresizingMaskIntoConstraints = false

        // ── Max active downloads ────────────────────────────────────────
        let maxTitle = sectionLabel("Max active downloads")
        let n = cfg?.resolvedMaxConcurrent ?? TrickleBarConfig.defaultMaxConcurrent
        let fmt = NumberFormatter()
        fmt.minimum = 1; fmt.maximum = 50; fmt.allowsFloats = false
        maxField.formatter = fmt
        maxField.integerValue = n
        maxField.alignment = .center
        maxField.translatesAutoresizingMaskIntoConstraints = false
        maxStepper.minValue = 1; maxStepper.maxValue = 50; maxStepper.increment = 1
        maxStepper.integerValue = n
        maxStepper.valueWraps = false
        maxStepper.target = self; maxStepper.action = #selector(stepperChanged)
        maxStepper.translatesAutoresizingMaskIntoConstraints = false
        maxField.target = self; maxField.action = #selector(maxFieldChanged)

        // ── Custom aria2c options ───────────────────────────────────────
        let optTitle = sectionLabel("Custom aria2c options")
        let hint = NSTextField(labelWithString: "One flag per line, e.g. --max-connection-per-server=16. Overrides the app defaults.")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 2
        hint.translatesAutoresizingMaskIntoConstraints = false

        let optScroll = NSScrollView()
        optScroll.hasVerticalScroller = true
        optScroll.borderType = .bezelBorder
        optScroll.translatesAutoresizingMaskIntoConstraints = false
        optionsView.isEditable = true; optionsView.isSelectable = true
        optionsView.allowsUndo = true; optionsView.isRichText = false
        optionsView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        optionsView.textContainerInset = NSSize(width: 2, height: 4)
        optionsView.string = cfg?.customOptions ?? ""
        optionsView.autoresizingMask = [.width]
        optScroll.documentView = optionsView

        // ── Buttons ─────────────────────────────────────────────────────
        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.keyEquivalent = "\u{1b}" // Esc
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        let saveBtn = NSButton(title: "Save", target: self, action: #selector(save))
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        saveBtn.translatesAutoresizingMaskIntoConstraints = false

        for v in [dirTitle, dirField, chooseBtn, maxTitle, maxField, maxStepper,
                  optTitle, hint, optScroll, cancelBtn, saveBtn] {
            root.addSubview(v)
        }

        let pad: CGFloat = 20
        NSLayoutConstraint.activate([
            dirTitle.topAnchor.constraint(equalTo: root.topAnchor, constant: pad),
            dirTitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: pad),

            chooseBtn.centerYAnchor.constraint(equalTo: dirField.centerYAnchor),
            chooseBtn.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -pad),
            dirField.topAnchor.constraint(equalTo: dirTitle.bottomAnchor, constant: 4),
            dirField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: pad),
            dirField.trailingAnchor.constraint(equalTo: chooseBtn.leadingAnchor, constant: -8),

            maxTitle.topAnchor.constraint(equalTo: dirField.bottomAnchor, constant: 16),
            maxTitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: pad),
            maxField.topAnchor.constraint(equalTo: maxTitle.bottomAnchor, constant: 4),
            maxField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: pad),
            maxField.widthAnchor.constraint(equalToConstant: 56),
            maxStepper.centerYAnchor.constraint(equalTo: maxField.centerYAnchor),
            maxStepper.leadingAnchor.constraint(equalTo: maxField.trailingAnchor, constant: 4),

            optTitle.topAnchor.constraint(equalTo: maxField.bottomAnchor, constant: 16),
            optTitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: pad),
            hint.topAnchor.constraint(equalTo: optTitle.bottomAnchor, constant: 2),
            hint.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: pad),
            hint.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -pad),
            optScroll.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 6),
            optScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: pad),
            optScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -pad),
            optScroll.bottomAnchor.constraint(equalTo: saveBtn.topAnchor, constant: -16),

            saveBtn.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -pad),
            saveBtn.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -pad),
            saveBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            cancelBtn.centerYAnchor.constraint(equalTo: saveBtn.centerYAnchor),
            cancelBtn.trailingAnchor.constraint(equalTo: saveBtn.leadingAnchor, constant: -10),
        ])
        return root
    }

    private func sectionLabel(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: 12, weight: .semibold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }

    // MARK: - Actions

    @objc private func chooseDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: dirField.stringValue)
        if panel.runModal() == .OK, let url = panel.url {
            dirField.stringValue = url.path
        }
    }

    @objc private func stepperChanged() { maxField.integerValue = maxStepper.integerValue }
    @objc private func maxFieldChanged() { maxStepper.integerValue = maxField.integerValue }

    @objc private func save() {
        let dir = dirField.stringValue.trimmingCharacters(in: .whitespaces)
        let n = min(max(maxField.integerValue, 1), 50)
        let opts = optionsView.string
        manager?.applySettings(
            downloadDir: dir.isEmpty ? nil : dir,
            maxConcurrent: n,
            customOptions: opts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : opts
        )
        close()
    }

    @objc private func cancel() { close() }

    private func close() {
        window?.close()
        window = nil
        retainedSelf = nil
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        retainedSelf = nil
    }
}
