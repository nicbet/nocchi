import AppKit
import SwiftUI

/// Finds the pointer in a window's SwiftUI global coordinate space, so faces can look at it.
@MainActor
public final class PointerLocator {
    public weak var window: NSWindow?

    public init(window: NSWindow? = nil) {
        self.window = window
    }

    func location() -> CGPoint? {
        guard let window, let view = window.contentView else { return nil }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let local = view.convert(inWindow, from: nil)
        return view.isFlipped ? local : CGPoint(x: local.x, y: view.bounds.height - local.y)
    }
}

extension EnvironmentValues {
    /// Where faces should look. `nil`: no pointer tracking.
    @Entry var pointerLocator: PointerLocator? = nil
    /// Stops every face's frame loop (window hidden, screens asleep).
    @Entry var facesPaused: Bool = false
    /// Frame rate cap for faces. Small collapsed faces don't need 30 fps.
    @Entry var faceFrameRate: Double = 30
    /// Whether calm moods (idle, sleep) animate. Off in the collapsed notch: every animated frame
    /// re-lays out the panel, and a blinking idle face isn't worth that all day long.
    @Entry var faceAnimatesCalmMoods: Bool = true
}

public extension View {
    func pointerLocator(_ locator: PointerLocator?) -> some View { environment(\.pointerLocator, locator) }
    func facesPaused(_ paused: Bool) -> some View { environment(\.facesPaused, paused) }
    func faceFrameRate(_ fps: Double) -> some View { environment(\.faceFrameRate, fps) }
    func faceAnimatesCalmMoods(_ animates: Bool) -> some View { environment(\.faceAnimatesCalmMoods, animates) }
}
