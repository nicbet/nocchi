import AppKit
import NocchiMascot
import SwiftUI

/// Window hosting the gallery. Faces follow the pointer inside it.
@MainActor
public final class MoodGalleryWindow {
    private var window: NSWindow?

    public init() {}

    public func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 760, height: 900),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered, defer: false
            )
            window.title = "nocchi — Mood Gallery"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: MoodGallery().resolvesReduceMotion())
            window.center()
            self.window = window
        }
        // nocchi is a background (accessory) app, so plain activation can leave the window
        // behind the frontmost app's windows. Order it front regardless, then make it key.
        window?.orderFrontRegardless()
        window?.makeKey()
        NSApp.activate()
    }
}
