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
}
