import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    let manager = DownloadManager()
    private var menuController: MenuController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Enforce single instance — if another copy is already running, bail out.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.abdus.dlwatch")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            NSApp.terminate(nil)
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        menuController = MenuController(manager: manager, statusItem: statusItem)
        menuController.rebuild(with: [])

        manager.onUpdate = { [weak self] in
            guard let self else { return }
            self.menuController.rebuild(with: self.manager.downloads)
        }
        manager.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.stop()
    }
}
