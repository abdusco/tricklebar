import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    let manager = DownloadManager()
    private var popoverController: PopoverController!

    // URLs received via the tricklebar:// scheme before the daemon is ready are held
    // here and flushed once the first poll confirms aria2c is up.
    private var pendingURLs: [(url: String, onDone: String?)] = []
    private var isReady = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Register early so a cold launch triggered by a tricklebar:// URL is caught.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Enforce single instance. If LaunchServices spawned us for a tricklebar://
        // URL while another instance owns the daemon, give the GetURL event a beat
        // to arrive, forward it straight to the shared daemon, then quit — otherwise
        // the URL would die with this duplicate instance.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.abdus.tricklebar")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                if let self, !self.pendingURLs.isEmpty, let cfg = DownloadManager.readConfig() {
                    let rpc = Aria2RPC(port: cfg.port, secret: cfg.secret)
                    for item in self.pendingURLs {
                        guard let gid = try? rpc.addUriSync(urls: [item.url]) else { continue }
                        // This process is about to quit and never polls, so it can't run
                        // the script itself — hand the mapping off to the owning instance
                        // via DownloadManager.onDoneFile instead of its in-memory dict.
                        if let onDone = item.onDone {
                            DownloadManager.registerOnDoneScript(gid: gid, script: onDone)
                        }
                    }
                }
                NSApp.terminate(nil)
            }
            return
        }

        setupMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        popoverController = PopoverController(manager: manager, statusItem: statusItem)

        manager.onUpdate = { [weak self] in
            guard let self else { return }
            self.popoverController.rebuild(with: self.manager.downloads)
            // The first update means a poll succeeded, so the daemon is reachable.
            if !self.isReady {
                self.isReady = true
                let queued = self.pendingURLs
                self.pendingURLs = []
                queued.forEach { item in
                    self.manager.addDownload(urls: [item.url], onDone: item.onDone) { _, _ in }
                }
            }
        }
        manager.onScriptFailure = { [weak self] name, output in
            self?.showScriptFailure(name: name, output: output)
        }
        manager.start()
    }

    // MARK: - URL scheme: tricklebar://add-download?url=<encoded>&on_done=<path>

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let str = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let comps = URLComponents(string: str),
              comps.scheme == "tricklebar",
              comps.host == "add-download"
        else { return }

        // Support one or more ?url= params; queryItems decodes percent-encoding.
        let urls = comps.queryItems?
            .filter { $0.name == "url" }
            .compactMap { $0.value }
            .filter { !$0.isEmpty } ?? []
        guard !urls.isEmpty else { return }

        // Run when each download finishes (or fails); applies to every url in this event.
        let onDone = comps.queryItems?.first { $0.name == "on_done" }?.value
            .flatMap { $0.isEmpty ? nil : $0 }

        if isReady {
            urls.forEach { manager.addDownload(urls: [$0], onDone: onDone) { _, _ in } }
        } else {
            pendingURLs.append(contentsOf: urls.map { (url: $0, onDone: onDone) })
        }
    }

    private func showScriptFailure(name: String, output: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "on_done script failed for \"\(name)\""
        alert.informativeText = "The script exited with an error. Output below:"

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 160))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let tv = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        tv.isEditable = false
        tv.isSelectable = true
        tv.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.string = output
        tv.autoresizingMask = .width
        scroll.documentView = tv
        alert.accessoryView = scroll

        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.stop()
    }

    // An accessory (LSUIElement) app has no main menu by default, so standard
    // editing shortcuts (Cmd+V/C/X/A) never reach the focused text view. Install
    // an Edit menu with nil targets so the key equivalents travel the responder chain.
    private func setupMainMenu() {
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let editItem = NSMenuItem()
        editItem.submenu = editMenu

        let mainMenu = NSMenu()
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }
}
