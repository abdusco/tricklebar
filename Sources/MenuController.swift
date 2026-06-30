import AppKit
import Foundation

final class MenuController: NSObject, NSMenuDelegate {
    private weak var manager: DownloadManager?
    private weak var statusItem: NSStatusItem?
    private var menuIsOpen = false
    private var pendingDownloads: [Download]?

    init(manager: DownloadManager, statusItem: NSStatusItem) {
        self.manager = manager
        self.statusItem = statusItem
    }

    // MARK: - Rebuild

    func rebuild(with downloads: [Download]) {
        guard !menuIsOpen else { pendingDownloads = downloads; return }
        buildMenu(downloads)
    }

    // MARK: - Build

    private func buildMenu(_ downloads: [Download]) {
        let active    = downloads.filter { $0.status == .active }
        let paused    = downloads.filter { $0.status == .paused }
        let waiting   = downloads.filter { $0.status == .waiting }
        let completed = downloads.filter { $0.status == .complete }
        let failed    = downloads.filter { $0.status == .error }

        updateButton(activeCount: active.count,
                     totalSpeed: active.reduce(0) { $0 + $1.downloadSpeed })

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        var didAddSection = false
        func section(_ title: String, count: Int, _ body: () -> Void) {
            guard count > 0 else { return }
            if didAddSection { menu.addItem(.separator()) }
            menu.addItem(sectionHeader("\(title)  ·  \(count)"))
            body()
            didAddSection = true
        }

        section("DOWNLOADING", count: active.count)    { active.forEach    { addActive($0,    to: menu) } }
        section("PAUSED",      count: paused.count)    { paused.forEach    { addPaused($0,    to: menu) } }
        section("QUEUED",      count: waiting.count)   { waiting.forEach   { addWaiting($0,   to: menu) } }
        section("COMPLETED",   count: completed.count) { completed.forEach { addCompleted($0, to: menu) } }
        section("FAILED",      count: failed.count)    { failed.forEach    { addFailed($0,    to: menu) } }

        if !didAddSection {
            let empty = NSMenuItem()
            empty.isEnabled = false
            empty.attributedTitle = attr("No active downloads",
                font: .systemFont(ofSize: 12), color: .tertiaryLabelColor)
            menu.addItem(empty)
        }

        menu.addItem(.separator())

        let addItem = makeItem("Add Download…", action: #selector(addDownloadAction), key: "n",
                               symbol: "plus.circle.fill")
        menu.addItem(addItem)

        let openFolder = makeItem("Open Downloads Folder", action: #selector(openDownloadsFolderAction),
                                  symbol: "folder.fill")
        menu.addItem(openFolder)

        menu.addItem(.separator())

        // target intentionally nil so terminate: travels the responder chain to NSApp
        let quit = NSMenuItem(title: "Quit dlwatch", action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)

        statusItem?.menu = menu
    }

    // MARK: - Status button

    private func updateButton(activeCount: Int, totalSpeed: Int64) {
        guard let btn = statusItem?.button else { return }
        let img = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "dlwatch")
        img?.isTemplate = true
        btn.image = img
        if activeCount > 0 {
            btn.imagePosition = .imageLeft
            let speedStr = totalSpeed > 0 ? "  \(formatBytes(totalSpeed))/s" : "  \(activeCount)"
            btn.title = speedStr
        } else {
            btn.imagePosition = .imageOnly
            btn.title = ""
        }
    }

    // MARK: - Row builders

    private func addActive(_ dl: Download, to menu: NSMenu) {
        let item = NSMenuItem()
        item.isEnabled = true
        item.image = stateImage(.active)
        item.attributedTitle = activeTitle(dl)
        item.submenu = rowMenu([
            rowItem("Pause",  #selector(pauseAction(_:)),  dl.gid),
            rowItem("Cancel", #selector(cancelAction(_:)), dl.gid),
        ])
        menu.addItem(item)
    }

    private func addPaused(_ dl: Download, to menu: NSMenu) {
        let pct = Int(dl.progress * 100)
        let detail = "\(progressBar(dl.progress))  \(pct)%\(sizeDetail(dl))"
        let item = NSMenuItem()
        item.isEnabled = true
        item.image = stateImage(.paused)
        item.attributedTitle = twoLine(dl.displayName, detail)
        item.submenu = rowMenu([
            rowItem("Resume", #selector(resumeAction(_:)), dl.gid),
            rowItem("Cancel", #selector(cancelAction(_:)), dl.gid),
        ])
        menu.addItem(item)
    }

    private func addWaiting(_ dl: Download, to menu: NSMenu) {
        let size = dl.totalLength > 0 ? formatBytes(dl.totalLength) : "queued"
        let item = NSMenuItem()
        item.isEnabled = true
        item.image = stateImage(.waiting)
        item.attributedTitle = twoLine(dl.displayName, size)
        item.submenu = rowMenu([rowItem("Remove", #selector(cancelAction(_:)), dl.gid)])
        menu.addItem(item)
    }

    private func addCompleted(_ dl: Download, to menu: NSMenu) {
        let size = dl.totalLength > 0 ? formatBytes(dl.totalLength) : ""
        let item = NSMenuItem()
        item.isEnabled = true
        item.image = stateImage(.complete)
        item.attributedTitle = twoLine(dl.displayName, size)
        item.action = #selector(revealAction(_:))
        item.target = self
        item.representedObject = dl.gid
        item.submenu = rowMenu([
            rowItem("Reveal in Finder",  #selector(revealAction(_:)),       dl.gid),
            rowItem("Remove from list",  #selector(removeResultAction(_:)), dl.gid),
        ])
        menu.addItem(item)
    }

    private func addFailed(_ dl: Download, to menu: NSMenu) {
        let errStr = dl.errorMessage.flatMap { $0.isEmpty ? nil : $0 }
            ?? (dl.errorCode.map { "Error \($0)" })
            ?? "Unknown error"
        let item = NSMenuItem()
        item.isEnabled = true
        item.image = stateImage(.error)
        item.attributedTitle = twoLine(dl.displayName, errStr,
                                       secondaryColor: .systemRed.withAlphaComponent(0.8))
        item.submenu = rowMenu([
            rowItem("Show Error",    #selector(showErrorAction(_:)),    dl.gid),
            rowItem("Show Log",      #selector(showLogAction(_:)),      dl.gid),
            .separator(),
            rowItem("Retry",         #selector(retryAction(_:)),        dl.gid),
            rowItem("Remove",        #selector(removeResultAction(_:)), dl.gid),
        ])
        menu.addItem(item)
    }

    // MARK: - Title helpers

    private func activeTitle(_ dl: Download) -> NSAttributedString {
        let pct = Int(dl.progress * 100)
        var parts: [String] = ["\(progressBar(dl.progress))  \(pct)%"]
        if dl.downloadSpeed > 0 { parts.append("↓ \(formatBytes(dl.downloadSpeed))/s") }
        if let e = etaString(dl) { parts.append("ETA \(e)") }
        let sz = sizeDetail(dl)
        if !sz.isEmpty { parts.append(sz.trimmingCharacters(in: .init(charactersIn: "  ·  "))) }
        return twoLine(dl.displayName, parts.joined(separator: "   "))
    }

    private func twoLine(_ primary: String, _ secondary: String,
                         secondaryColor: NSColor = .secondaryLabelColor) -> NSAttributedString {
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: primary, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ]))
        if !secondary.isEmpty {
            s.append(NSAttributedString(string: "\n" + secondary, attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: secondaryColor,
            ]))
        }
        return s
    }

    private func progressBar(_ p: Double, width: Int = 10) -> String {
        let n = min(width, max(0, Int(p * Double(width))))
        return String(repeating: "▓", count: n) + String(repeating: "░", count: width - n)
    }

    private func sizeDetail(_ dl: Download) -> String {
        guard dl.totalLength > 0 else { return "" }
        return "  ·  \(formatBytes(dl.completedLength)) / \(formatBytes(dl.totalLength))"
    }

    private func etaString(_ dl: Download) -> String? {
        guard dl.downloadSpeed > 0, dl.totalLength > dl.completedLength else { return nil }
        let secs = (dl.totalLength - dl.completedLength) / dl.downloadSpeed
        if secs < 60    { return "\(secs)s" }
        if secs < 3600  { return "\(secs / 60)m" }
        return "\(secs / 3600)h \((secs % 3600) / 60)m"
    }

    // MARK: - Item & menu factories

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .kern: 1.2,
        ])
        return item
    }

    private func makeItem(_ title: String, action: Selector, key: String = "",
                          symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = true
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    private func rowItem(_ title: String, _ sel: Selector, _ gid: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        item.target = self
        item.representedObject = gid
        item.isEnabled = true
        return item
    }

    private func rowMenu(_ items: [NSMenuItem]) -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false
        items.forEach { m.addItem($0) }
        return m
    }

    private func attr(_ s: String, font: NSFont, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
    }

    // MARK: - State images

    private func stateImage(_ status: DownloadStatus) -> NSImage? {
        let (symbol, color): (String, NSColor) = {
            switch status {
            case .active:   return ("arrow.down.circle.fill", .systemBlue)
            case .paused:   return ("pause.circle.fill",      .systemOrange)
            case .waiting:  return ("clock.circle.fill",      .systemGray)
            case .complete: return ("checkmark.circle.fill",  .systemGreen)
            case .error, .removed: return ("xmark.circle.fill", .systemRed)
            }
        }()
        guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else { return nil }
        let cfg = NSImage.SymbolConfiguration(paletteColors: [color])
        return base.withSymbolConfiguration(cfg)
    }

    // MARK: - Delegate

    func menuWillOpen(_ menu: NSMenu) { menuIsOpen = true }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        if let pending = pendingDownloads {
            pendingDownloads = nil
            DispatchQueue.main.async { self.buildMenu(pending) }
        }
    }

    // MARK: - Actions

    @objc func addDownloadAction() {
        let alert = NSAlert()
        alert.messageText = "Add Download"
        alert.informativeText = "Enter URL(s), one per line:"
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Cancel")

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 440, height: 90))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .bezelBorder

        let contentSize = scroll.contentSize
        let tf = NSTextView(frame: NSRect(origin: .zero, size: contentSize))
        tf.minSize = NSSize(width: 0, height: contentSize.height)
        tf.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tf.isVerticallyResizable = true
        tf.isHorizontallyResizable = false
        tf.autoresizingMask = .width
        tf.textContainer?.containerSize = NSSize(width: contentSize.width,
                                                  height: CGFloat.greatestFiniteMagnitude)
        tf.textContainer?.widthTracksTextView = true
        tf.isEditable = true
        tf.isSelectable = true
        tf.allowsUndo = true
        tf.isRichText = false
        tf.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tf.textContainerInset = NSSize(width: 2, height: 4)
        scroll.documentView = tf
        alert.accessoryView = scroll
        alert.window.initialFirstResponder = tf

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let urls = tf.string.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for url in urls {
            manager?.addDownload(urls: [url]) { _, err in
                if let err {
                    DispatchQueue.main.async {
                        self.showAlert("Failed to add download", detail: err.localizedDescription)
                    }
                }
            }
        }
    }

    @objc private func openDownloadsFolderAction() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        NSWorkspace.shared.open(dir)
    }

    @objc private func pauseAction(_ sender: NSMenuItem) {
        guard let gid = sender.representedObject as? String else { return }
        manager?.pause(gid: gid)
    }

    @objc private func resumeAction(_ sender: NSMenuItem) {
        guard let gid = sender.representedObject as? String else { return }
        manager?.resume(gid: gid)
    }

    @objc private func cancelAction(_ sender: NSMenuItem) {
        guard let gid = sender.representedObject as? String else { return }
        manager?.cancel(gid: gid)
    }

    @objc private func revealAction(_ sender: NSMenuItem) {
        guard let gid = sender.representedObject as? String,
              let path = manager?.downloads.first(where: { $0.gid == gid })?.primaryFilePath
        else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @objc private func removeResultAction(_ sender: NSMenuItem) {
        guard let gid = sender.representedObject as? String else { return }
        manager?.removeResult(gid: gid)
    }

    @objc private func retryAction(_ sender: NSMenuItem) {
        guard let gid = sender.representedObject as? String,
              let dl = manager?.downloads.first(where: { $0.gid == gid })
        else { return }
        manager?.retry(download: dl)
    }

    @objc private func showErrorAction(_ sender: NSMenuItem) {
        guard let gid = sender.representedObject as? String,
              let dl = manager?.downloads.first(where: { $0.gid == gid })
        else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Download Failed"
        alert.informativeText = "Error \(dl.errorCode ?? "?"): \(dl.errorMessage ?? "No details.")"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Show Log")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(DownloadManager.logFile)
        }
    }

    @objc private func showLogAction(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(DownloadManager.logFile)
    }

    private func showAlert(_ msg: String, detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = msg
        a.informativeText = detail
        a.runModal()
    }
}
