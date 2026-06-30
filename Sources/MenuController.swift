import AppKit
import Foundation

// MARK: - PopoverController

final class PopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let contentVC: DownloadsViewController
    private weak var statusItem: NSStatusItem?

    init(manager: DownloadManager, statusItem: NSStatusItem) {
        self.contentVC = DownloadsViewController(manager: manager)
        self.statusItem = statusItem
        super.init()

        popover.contentViewController = contentVC
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        contentVC.popoverRef = popover

        // Force viewDidLoad now so preferredContentSize is valid before first click.
        _ = contentVC.view
        popover.contentSize = contentVC.preferredContentSize

        if let btn = statusItem.button {
            btn.action = #selector(togglePopover(_:))
            btn.target = self
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateButton(active: 0, totalSpeed: 0)
    }

    // Called by AppDelegate on every manager update — no isOpen guard; view updates live.
    func rebuild(with downloads: [Download]) {
        let active = downloads.filter { $0.status == .active }
        updateButton(active: active.count, totalSpeed: active.reduce(0) { $0 + $1.downloadSpeed })
        contentVC.update(with: downloads)
        popover.contentSize = contentVC.preferredContentSize
    }

    private func updateButton(active: Int, totalSpeed: Int64) {
        guard let btn = statusItem?.button else { return }
        let img = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "dlwatch")
        img?.isTemplate = true
        btn.image = img
        if active > 0 {
            btn.imagePosition = .imageLeft
            btn.title = totalSpeed > 0 ? "  \(formatBytes(totalSpeed))/s" : "  \(active)"
        } else {
            btn.imagePosition = .imageOnly
            btn.title = ""
        }
    }

    @objc private func togglePopover(_ sender: NSButton) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            let menu = NSMenu()
            let quit = NSMenuItem(title: "Quit dlwatch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
            menu.addItem(quit)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
            return
        }
        if popover.isShown {
            popover.close()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.contentSize = contentVC.preferredContentSize
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }
}

// MARK: - DownloadsViewController

private enum ListItem {
    case sectionHeader(String)
    case download(Download)
}

private let kRowHeight: CGFloat   = 62
private let kHeaderHeight: CGFloat = 26
private let kTopBarHeight: CGFloat  = 52
private let kBottomBarHeight: CGFloat = 44
private let kPopoverWidth: CGFloat  = 390
private let kMaxTableHeight: CGFloat = 360

final class DownloadsViewController: NSViewController {
    private weak var manager: DownloadManager?
    private var tableView: NSTableView!
    private var items: [ListItem] = []
    weak var popoverRef: NSPopover?

    init(manager: DownloadManager) {
        self.manager = manager
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: kPopoverWidth, height: 180)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let vfx = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: kPopoverWidth, height: 180))
        vfx.autoresizingMask = [.width, .height]
        vfx.material = .popover
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        view = vfx
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
        update(with: manager?.downloads ?? [])
    }

    // MARK: - Update (called on every poll; works while popover is open)

    func update(with downloads: [Download]) {
        items = buildItems(from: downloads)
        if isViewLoaded { tableView.reloadData() }
        recalcSize()
    }

    private func buildItems(from downloads: [Download]) -> [ListItem] {
        var out: [ListItem] = []
        let order: [(String, DownloadStatus)] = [
            ("DOWNLOADING", .active),
            ("PAUSED",      .paused),
            ("QUEUED",      .waiting),
            ("COMPLETED",   .complete),
            ("FAILED",      .error),
        ]
        for (title, status) in order {
            let group = downloads.filter { $0.status == status }
            guard !group.isEmpty else { continue }
            out.append(.sectionHeader(title))
            group.forEach { out.append(.download($0)) }
        }
        return out
    }

    private func recalcSize() {
        let tableH = items.reduce(CGFloat(0)) { sum, item in
            sum + (item.isSectionHeader ? kHeaderHeight : kRowHeight)
        }.clamped(to: 40...kMaxTableHeight)
        let emptyH: CGFloat = items.isEmpty ? 44 : 0
        let total = kTopBarHeight + tableH + emptyH + kBottomBarHeight
        preferredContentSize = NSSize(width: kPopoverWidth, height: total)
    }

    // MARK: - Layout

    private func buildLayout() {
        // ─── Top bar ───────────────────────────────────────────────────────
        let topBar = NSView()
        topBar.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "Downloads")
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let addBtn = NSButton()
        addBtn.image = NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: "Add Download")
        addBtn.contentTintColor = .systemBlue
        addBtn.isBordered = false
        addBtn.toolTip = "Add Download"
        addBtn.target = self
        addBtn.action = #selector(addDownloadAction)
        addBtn.translatesAutoresizingMaskIntoConstraints = false

        topBar.addSubview(titleLabel)
        topBar.addSubview(addBtn)

        let topSep = separator()
        topBar.addSubview(topSep)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor, constant: -1),
            addBtn.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -14),
            addBtn.centerYAnchor.constraint(equalTo: topBar.centerYAnchor, constant: -1),
            addBtn.widthAnchor.constraint(equalToConstant: 22),
            addBtn.heightAnchor.constraint(equalToConstant: 22),
            topSep.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            topSep.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            topSep.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),
            topSep.heightAnchor.constraint(equalToConstant: 1),
        ])

        // ─── Table ─────────────────────────────────────────────────────────
        tableView = NSTableView()
        tableView.style = .plain
        tableView.headerView = nil
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        // ─── Bottom bar ────────────────────────────────────────────────────
        let botBar = NSView()
        botBar.translatesAutoresizingMaskIntoConstraints = false

        let botSep = separator()
        botBar.addSubview(botSep)

        let openBtn = textButton("Open Downloads Folder", action: #selector(openFolderAction))
        let quitBtn = textButton("Quit", action: #selector(quitAction))
        botBar.addSubview(openBtn)
        botBar.addSubview(quitBtn)

        NSLayoutConstraint.activate([
            botSep.topAnchor.constraint(equalTo: botBar.topAnchor),
            botSep.leadingAnchor.constraint(equalTo: botBar.leadingAnchor),
            botSep.trailingAnchor.constraint(equalTo: botBar.trailingAnchor),
            botSep.heightAnchor.constraint(equalToConstant: 1),
            openBtn.leadingAnchor.constraint(equalTo: botBar.leadingAnchor, constant: 12),
            openBtn.centerYAnchor.constraint(equalTo: botBar.centerYAnchor, constant: 2),
            quitBtn.trailingAnchor.constraint(equalTo: botBar.trailingAnchor, constant: -12),
            quitBtn.centerYAnchor.constraint(equalTo: botBar.centerYAnchor, constant: 2),
        ])

        // ─── Assemble ──────────────────────────────────────────────────────
        view.addSubview(topBar)
        view.addSubview(scroll)
        view.addSubview(botBar)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: kTopBarHeight),

            botBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            botBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            botBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            botBar.heightAnchor.constraint(equalToConstant: kBottomBarHeight),

            scroll.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: botBar.topAnchor),
        ])
    }

    // MARK: - Actions

    @objc private func addDownloadAction() {
        popoverRef?.close()
        let alert = NSAlert()
        alert.messageText = "Add Download"
        alert.informativeText = "Enter URL(s), one per line:"
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Cancel")

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 440, height: 90))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let cs = scroll.contentSize
        let tf = NSTextView(frame: NSRect(origin: .zero, size: cs))
        tf.minSize = NSSize(width: 0, height: cs.height)
        tf.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tf.isVerticallyResizable = true
        tf.isHorizontallyResizable = false
        tf.autoresizingMask = .width
        tf.textContainer?.containerSize = NSSize(width: cs.width, height: CGFloat.greatestFiniteMagnitude)
        tf.textContainer?.widthTracksTextView = true
        tf.isEditable = true; tf.isSelectable = true; tf.allowsUndo = true; tf.isRichText = false
        tf.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tf.textContainerInset = NSSize(width: 2, height: 4)
        scroll.documentView = tf
        alert.accessoryView = scroll
        alert.window.initialFirstResponder = tf

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let urls = tf.string.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for url in urls {
            manager?.addDownload(urls: [url]) { _, err in
                if let err {
                    DispatchQueue.main.async { self.alert("Failed", err.localizedDescription) }
                }
            }
        }
    }

    @objc private func openFolderAction() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        NSWorkspace.shared.open(dir)
    }

    @objc private func quitAction() { NSApp.terminate(nil) }

    func showError(for dl: Download) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Download Failed"
        a.informativeText = "Error \(dl.errorCode ?? "?"): \(dl.errorMessage ?? "No details.")"
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Show Log")
        if a.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(DownloadManager.logFile)
        }
    }

    private func alert(_ msg: String, _ detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = msg; a.informativeText = detail; a.runModal()
    }

    // MARK: - View factories

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }

    private func textButton(_ title: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.controlSize = .small
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }
}

// MARK: - NSTableViewDataSource / Delegate

extension DownloadsViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        items[row].isSectionHeader ? kHeaderHeight : kRowHeight
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch items[row] {
        case .sectionHeader(let title):
            let id = NSUserInterfaceItemIdentifier("hdr")
            let v = (tableView.makeView(withIdentifier: id, owner: nil) as? SectionHeaderView)
                    ?? SectionHeaderView()
            v.identifier = id
            v.configure(title: title)
            return v
        case .download(let dl):
            let id = NSUserInterfaceItemIdentifier("row")
            let v = (tableView.makeView(withIdentifier: id, owner: nil) as? DownloadRowView)
                    ?? DownloadRowView()
            v.identifier = id
            v.configure(with: dl)
            wireActions(v, dl: dl)
            return v
        }
    }

    private func wireActions(_ v: DownloadRowView, dl: Download) {
        let gid = dl.gid
        switch dl.status {
        case .active:
            v.setActions(
                primary:   { [weak self] in self?.manager?.pause(gid: gid) },
                primarySymbol: "pause.circle.fill", primaryTint: .systemOrange, primaryTip: "Pause",
                secondary: { [weak self] in self?.manager?.cancel(gid: gid) },
                secondarySymbol: "xmark.circle.fill", secondaryTint: .systemRed, secondaryTip: "Cancel"
            )
        case .paused:
            v.setActions(
                primary:   { [weak self] in self?.manager?.resume(gid: gid) },
                primarySymbol: "play.circle.fill", primaryTint: .systemGreen, primaryTip: "Resume",
                secondary: { [weak self] in self?.manager?.cancel(gid: gid) },
                secondarySymbol: "xmark.circle.fill", secondaryTint: .systemRed, secondaryTip: "Cancel"
            )
        case .waiting:
            v.setActions(
                primary:   { [weak self] in self?.manager?.cancel(gid: gid) },
                primarySymbol: "xmark.circle.fill", primaryTint: .systemRed, primaryTip: "Remove",
                secondary: nil, secondarySymbol: "", secondaryTint: .clear, secondaryTip: ""
            )
        case .complete:
            v.setActions(
                primary: { [weak self] in
                    guard let path = self?.manager?.downloads.first(where: { $0.gid == gid })?.primaryFilePath
                    else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                },
                primarySymbol: "folder.fill", primaryTint: .systemBlue, primaryTip: "Reveal in Finder",
                secondary: { [weak self] in self?.manager?.removeResult(gid: gid) },
                secondarySymbol: "trash.fill", secondaryTint: .systemRed, secondaryTip: "Remove from list"
            )
        case .error:
            v.setActions(
                primary: { [weak self] in
                    guard let dl = self?.manager?.downloads.first(where: { $0.gid == gid }) else { return }
                    self?.manager?.retry(download: dl)
                },
                primarySymbol: "arrow.clockwise.circle.fill", primaryTint: .systemBlue, primaryTip: "Retry",
                secondary: { [weak self] in self?.manager?.removeResult(gid: gid) },
                secondarySymbol: "trash.fill", secondaryTint: .systemRed, secondaryTip: "Remove",
                tertiary: { [weak self] in
                    guard let dl = self?.manager?.downloads.first(where: { $0.gid == gid }) else { return }
                    self?.showError(for: dl)
                },
                tertiarySymbol: "exclamationmark.circle.fill",
                tertiaryTint: .systemOrange,
                tertiaryTip: "Show Error"
            )
        case .removed:
            v.setActions(primary: nil, primarySymbol: "", primaryTint: .clear, primaryTip: "",
                         secondary: nil)
        }
    }
}

// MARK: - Helpers

private extension ListItem {
    var isSectionHeader: Bool {
        if case .sectionHeader = self { return true }
        return false
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
