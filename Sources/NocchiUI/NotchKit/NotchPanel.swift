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

    // Never steal focus from the user's app. (Revisit for the prompt field in M5.)
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
