import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    let manager = DownloadManager()
    private var menuController: MenuController!

    func applicationDidFinishLaunching(_ notification: Notification) {
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
