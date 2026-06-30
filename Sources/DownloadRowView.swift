import AppKit

// MARK: - Thin progress bar

final class ProgressBarView: NSView {
    var progress: Double = 0 { didSet { needsDisplay = true } }
    var fillColor: NSColor = .systemBlue

    override func draw(_ dirtyRect: NSRect) {
        let r: CGFloat = bounds.height / 2
        let track = NSBezierPath(roundedRect: bounds, xRadius: r, yRadius: r)
        NSColor.quaternaryLabelColor.setFill()
        track.fill()
        guard progress > 0 else { return }
        let w = max(bounds.height, bounds.width * CGFloat(min(progress, 1)))
        let fill = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: bounds.height),
                                xRadius: r, yRadius: r)
        fillColor.setFill()
        fill.fill()
    }
}

// MARK: - Section header

final class SectionHeaderView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        textField = label
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String) { label.stringValue = title }
}

// MARK: - Download row

final class DownloadRowView: NSTableCellView {
    // Subviews
    private let iconView: NSImageView = {
        let v = NSImageView()
        v.imageScaling = .scaleProportionallyUpOrDown
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    private let nameLabel: NSTextField = {
        let f = NSTextField(labelWithString: "")
        f.font = .systemFont(ofSize: 13, weight: .medium)
        f.lineBreakMode = .byTruncatingMiddle
        f.translatesAutoresizingMaskIntoConstraints = false
        return f
    }()
    private let progressBar: ProgressBarView = {
        let v = ProgressBarView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    private let detailLabel: NSTextField = {
        let f = NSTextField(labelWithString: "")
        f.font = .systemFont(ofSize: 11)
        f.textColor = .secondaryLabelColor
        f.lineBreakMode = .byTruncatingTail
        f.translatesAutoresizingMaskIntoConstraints = false
        return f
    }()
    // Three icon buttons (tertiary may be hidden)
    private let btn1 = DownloadRowView.makeIconButton()
    private let btn2 = DownloadRowView.makeIconButton()
    private let btn3 = DownloadRowView.makeIconButton()

    // Action closures set by the table delegate
    var action1: (() -> Void)?
    var action2: (() -> Void)?
    var action3: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        for v in [iconView, nameLabel, progressBar, detailLabel, btn1, btn2, btn3] {
            addSubview(v)
        }
        btn1.target = self; btn1.action = #selector(tap1)
        btn2.target = self; btn2.action = #selector(tap2)
        btn3.target = self; btn3.action = #selector(tap3)

        NSLayoutConstraint.activate([
            // Icon
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),

            // Buttons — right-aligned, three slots always reserved
            btn1.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            btn1.centerYAnchor.constraint(equalTo: centerYAnchor),
            btn1.widthAnchor.constraint(equalToConstant: 22),
            btn1.heightAnchor.constraint(equalToConstant: 22),

            btn2.trailingAnchor.constraint(equalTo: btn1.leadingAnchor, constant: -8),
            btn2.centerYAnchor.constraint(equalTo: centerYAnchor),
            btn2.widthAnchor.constraint(equalToConstant: 22),
            btn2.heightAnchor.constraint(equalToConstant: 22),

            btn3.trailingAnchor.constraint(equalTo: btn2.leadingAnchor, constant: -8),
            btn3.centerYAnchor.constraint(equalTo: centerYAnchor),
            btn3.widthAnchor.constraint(equalToConstant: 22),
            btn3.heightAnchor.constraint(equalToConstant: 22),

            // Text area: between icon and btn3 (widest button layout)
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: btn3.leadingAnchor, constant: -8),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            nameLabel.heightAnchor.constraint(equalToConstant: 16),

            progressBar.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            progressBar.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            progressBar.heightAnchor.constraint(equalToConstant: 3),

            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 4),
            detailLabel.heightAnchor.constraint(equalToConstant: 14),
        ])
    }

    // MARK: - Configure

    func configure(with dl: Download) {
        nameLabel.stringValue = dl.displayName
        iconView.image = stateImage(dl.status)
        detailLabel.stringValue = detailString(dl)

        let showBar = (dl.status == .active || dl.status == .paused) && dl.totalLength > 0
        progressBar.isHidden = !showBar
        if showBar {
            progressBar.progress = dl.progress
            progressBar.fillColor = dl.status == .active ? .systemBlue : .systemOrange
        }
    }

    func setActions(
        primary: (() -> Void)?, primarySymbol: String, primaryTint: NSColor, primaryTip: String,
        secondary: (() -> Void)?, secondarySymbol: String = "", secondaryTint: NSColor = .secondaryLabelColor, secondaryTip: String = "",
        tertiary: (() -> Void)? = nil, tertiarySymbol: String = "", tertiaryTint: NSColor = .secondaryLabelColor, tertiaryTip: String = ""
    ) {
        action1 = primary
        action2 = secondary
        action3 = tertiary

        styleButton(btn1, symbol: primarySymbol, tint: primaryTint, tip: primaryTip, hidden: primary == nil)
        styleButton(btn2, symbol: secondarySymbol, tint: secondaryTint, tip: secondaryTip, hidden: secondary == nil)
        styleButton(btn3, symbol: tertiarySymbol, tint: tertiaryTint, tip: tertiaryTip, hidden: tertiary == nil)
    }

    private func styleButton(_ btn: NSButton, symbol: String, tint: NSColor, tip: String, hidden: Bool) {
        btn.isHidden = hidden
        guard !hidden else { return }
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        btn.contentTintColor = tint
        btn.toolTip = tip
    }

    @objc private func tap1() { action1?() }
    @objc private func tap2() { action2?() }
    @objc private func tap3() { action3?() }

    // MARK: - Helpers

    private func stateImage(_ status: DownloadStatus) -> NSImage? {
        let (sym, color): (String, NSColor) = {
            switch status {
            case .active:          return ("arrow.down.circle.fill", .systemBlue)
            case .paused:          return ("pause.circle.fill",      .systemOrange)
            case .waiting:         return ("clock.circle.fill",      .tertiaryLabelColor)
            case .complete:        return ("checkmark.circle.fill",  .systemGreen)
            case .error, .removed: return ("xmark.circle.fill",      .systemRed)
            }
        }()
        guard let base = NSImage(systemSymbolName: sym, accessibilityDescription: nil) else { return nil }
        return base.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))
    }

    private func detailString(_ dl: Download) -> String {
        switch dl.status {
        case .active:
            var parts: [String] = []
            let pct = Int(dl.progress * 100)
            parts.append("\(pct)%")
            if dl.downloadSpeed > 0 { parts.append("↓ \(formatBytes(dl.downloadSpeed))/s") }
            if dl.totalLength > 0 {
                parts.append("\(formatBytes(dl.completedLength)) / \(formatBytes(dl.totalLength))")
            }
            if let eta = etaString(dl) { parts.append("ETA \(eta)") }
            return parts.joined(separator: "  ·  ")
        case .paused:
            var parts = ["\(Int(dl.progress * 100))% paused"]
            if dl.totalLength > 0 { parts.append("\(formatBytes(dl.completedLength)) / \(formatBytes(dl.totalLength))") }
            return parts.joined(separator: "  ·  ")
        case .waiting:
            return dl.totalLength > 0 ? formatBytes(dl.totalLength) : "Queued"
        case .complete:
            return dl.totalLength > 0 ? formatBytes(dl.totalLength) : "Complete"
        case .error:
            return dl.errorMessage.flatMap { $0.isEmpty ? nil : $0 }
                ?? dl.errorCode.map { "Error \($0)" }
                ?? "Failed"
        case .removed:
            return "Removed"
        }
    }

    private func etaString(_ dl: Download) -> String? {
        guard dl.downloadSpeed > 0, dl.totalLength > dl.completedLength else { return nil }
        let s = (dl.totalLength - dl.completedLength) / dl.downloadSpeed
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }

    private static func makeIconButton() -> NSButton {
        let b = NSButton()
        b.isBordered = false
        b.imageScaling = .scaleProportionallyUpOrDown
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }
}
