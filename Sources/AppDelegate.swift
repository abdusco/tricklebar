import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    let manager = DownloadManager()
    private var popoverController: PopoverController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Enforce single instance
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.abdus.dlwatch")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty { NSApp.terminate(nil); return }

        setupMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        popoverController = PopoverController(manager: manager, statusItem: statusItem)

        manager.onUpdate = { [weak self] in
            guard let self else { return }
            self.popoverController.rebuild(with: self.manager.downloads)
        }
        manager.start()
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
