import AppKit

/// Transparent, borderless, non-activating panel above the menu bar on every Space,
/// including next to fullscreen apps.
final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
    }

    /// Only while writing to an agent. Being a non-activating panel, it takes the keyboard without
    /// activating nocchi, so the user's app stays frontmost.
    var acceptsKeyboard = false
    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }
}
