import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    let manager = DownloadManager()
    private var popoverController: PopoverController!

    // URLs received via the tricklebar:// scheme before the daemon is ready are held
    // here and flushed once the first poll confirms aria2c is up.
    private var pendingURLs: [String] = []
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
                    self.pendingURLs.forEach { _ = try? rpc.addUriSync(urls: [$0]) }
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
                queued.forEach { self.manager.addDownload(urls: [$0]) { _, _ in } }
            }
        }
        manager.start()
    }

    // MARK: - URL scheme: tricklebar://add-download?url=<encoded>

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

        if isReady {
            urls.forEach { manager.addDownload(urls: [$0]) { _, _ in } }
        } else {
            pendingURLs.append(contentsOf: urls)
        }
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
