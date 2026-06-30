import AppKit
import Foundation

if CLIHandler.shouldRunAsCLI() {
    CLIHandler.run()
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
