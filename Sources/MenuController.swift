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

    private func buildMenu(_ downloads: [Download]) {
        let active = downloads.filter { $0.status == .active }
        let waiting = downloads.filter { $0.status == .waiting }
        let paused = downloads.filter { $0.status == .paused }
        let completed = downloads.filter { $0.status == .complete }
        let failed = downloads.filter { $0.status == .error }

        // Update status item
        if let btn = statusItem?.button {
            btn.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "dlwatch")
            btn.image?.isTemplate = true
            btn.imagePosition = active.isEmpty ? .imageOnly : .imageLeft
            btn.title = active.isEmpty ? "" : " \(active.count)"
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        func sep() { menu.addItem(.separator()) }

        if !active.isEmpty {
            addHeader("Downloading (\(active.count))", to: menu)
            active.forEach { addActive($0, to: menu) }
            sep()
        }
        if !paused.isEmpty {
            addHeader("Paused (\(paused.count))", to: menu)
            paused.forEach { addPaused($0, to: menu) }
            sep()
        }
        if !waiting.isEmpty {
            addHeader("Queued (\(waiting.count))", to: menu)
            waiting.forEach { addWaiting($0, to: menu) }
            sep()
        }
        if !completed.isEmpty {
            addHeader("Completed (\(completed.count))", to: menu)
            completed.forEach { addCompleted($0, to: menu) }
            sep()
        }
        if !failed.isEmpty {
            addHeader("Failed (\(failed.count))", to: menu)
            failed.forEach { addFailed($0, to: menu) }
            sep()
        }

        let addItem = menuItem("Add Download…", action: #selector(addDownload), key: "n")
        menu.addItem(addItem)
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit", action: #selector(NSApplication.terminate(_:)), key: "q"))

        statusItem?.menu = menu
    }

    // MARK: - Section builders

    private func addHeader(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem()
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        menu.addItem(item)
    }

    private func addActive(_ dl: Download, to menu: NSMenu) {
        let pct = Int(dl.progress * 100)
        let speed = dl.downloadSpeed > 0 ? "↓ \(formatBytes(dl.downloadSpeed))/s" : ""
        let title = "  \(dl.displayName)   \(pct)%\(speed.isEmpty ? "" : "  \(speed)")"
        let item = menuItem(title, action: nil, key: "")
        item.submenu = subMenu([
            actionItem("Pause",  #selector(pauseAction(_:)),  gid: dl.gid),
            actionItem("Cancel", #selector(cancelAction(_:)), gid: dl.gid),
        ])
        menu.addItem(item)
    }

    private func addPaused(_ dl: Download, to menu: NSMenu) {
        let pct = Int(dl.progress * 100)
        let item = menuItem("  \(dl.displayName)   \(pct)% (paused)", action: nil, key: "")
        item.submenu = subMenu([
            actionItem("Resume", #selector(resumeAction(_:)), gid: dl.gid),
            actionItem("Cancel", #selector(cancelAction(_:)), gid: dl.gid),
        ])
        menu.addItem(item)
    }

    private func addWaiting(_ dl: Download, to menu: NSMenu) {
        let item = menuItem("  \(dl.displayName)", action: nil, key: "")
        item.submenu = subMenu([
            actionItem("Remove", #selector(cancelAction(_:)), gid: dl.gid),
        ])
        menu.addItem(item)
    }

    private func addCompleted(_ dl: Download, to menu: NSMenu) {
        let item = menuItem("  \(dl.displayName)", action: #selector(revealAction(_:)), key: "")
        item.target = self
        item.representedObject = dl.gid
        // Folder icon
        item.image = folderIcon()
        item.submenu = subMenu([
            actionItem("Reveal in Finder",   #selector(revealAction(_:)),       gid: dl.gid),
            actionItem("Remove from list",   #selector(removeResultAction(_:)), gid: dl.gid),
        ])
        menu.addItem(item)
    }

    private func addFailed(_ dl: Download, to menu: NSMenu) {
        let item = menuItem("  \(dl.displayName)  ✗", action: nil, key: "")
        item.submenu = subMenu([
            actionItem("Show Error", #selector(showErrorAction(_:)), gid: dl.gid),
            actionItem("Show Log",   #selector(showLogAction(_:)),   gid: dl.gid),
            .separator(),
            actionItem("Retry",  #selector(retryAction(_:)),  gid: dl.gid),
            actionItem("Remove", #selector(removeResultAction(_:)), gid: dl.gid),
        ])
        menu.addItem(item)
    }

    // MARK: - Helpers

    private func menuItem(_ title: String, action: Selector?, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = action != nil
        return item
    }

    private func actionItem(_ title: String, _ sel: Selector, gid: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        item.target = self
        item.representedObject = gid
        item.isEnabled = true
        return item
    }

    private func subMenu(_ items: [NSMenuItem]) -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false
        items.forEach { m.addItem($0) }
        return m
    }

    private func folderIcon() -> NSImage? {
        let img = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
        img?.isTemplate = false
        return img
    }

    private func download(for gid: String) -> Download? {
        manager?.downloads.first { $0.gid == gid }
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) { menuIsOpen = true }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        if let pending = pendingDownloads {
            pendingDownloads = nil
            DispatchQueue.main.async { self.buildMenu(pending) }
        }
    }

    // MARK: - Actions

    @objc func addDownload() {
        let alert = NSAlert()
        alert.messageText = "Add Download"
        alert.informativeText = "Enter URL(s), one per line:"
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Cancel")

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 80))
        let tf = NSTextView(frame: scroll.bounds)
        tf.isEditable = true
        tf.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        scroll.documentView = tf
        scroll.hasVerticalScroller = true
        alert.accessoryView = scroll

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let raw = tf.string.components(separatedBy: .newlines)
        let urls = raw.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for url in urls {
            manager?.addDownload(urls: [url]) { _, err in
                if let err {
                    DispatchQueue.main.async { self.showAlert("Failed to add download", detail: err.localizedDescription) }
                }
            }
        }
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
              let path = download(for: gid)?.primaryFilePath
        else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @objc private func removeResultAction(_ sender: NSMenuItem) {
        guard let gid = sender.representedObject as? String else { return }
        manager?.removeResult(gid: gid)
    }

    @objc private func retryAction(_ sender: NSMenuItem) {
        guard let gid = sender.representedObject as? String,
              let dl = download(for: gid)
        else { return }
        manager?.retry(download: dl)
    }

    @objc private func showErrorAction(_ sender: NSMenuItem) {
        guard let gid = sender.representedObject as? String,
              let dl = download(for: gid)
        else { return }
        let code = dl.errorCode ?? "unknown"
        let msg = dl.errorMessage ?? "No details available."
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Download Failed (error \(code))"
        alert.informativeText = msg
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Show Log")
        if alert.runModal() == .alertSecondButtonReturn { openLog() }
    }

    @objc private func showLogAction(_ sender: NSMenuItem) { openLog() }

    private func openLog() {
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
