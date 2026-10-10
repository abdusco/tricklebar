import AppKit

// Draw semantic colors at display time so panels follow the current appearance.
final class SettingsPanel: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                 xRadius: 12, yRadius: 12)
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let fill = dark ? NSColor.white.withAlphaComponent(0.05) : NSColor.black.withAlphaComponent(0.035)
        fill.setFill()
        shape.fill()
    }
}

final class SettingsBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
    }
}

func interfaceSymbol(_ name: String, size: CGFloat = 16, description: String? = nil) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: description)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .medium))
}
