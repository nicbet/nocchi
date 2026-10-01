import SwiftUI

extension EnvironmentValues {
    /// Stops every face's frame loop (window hidden, screens asleep).
    @Entry var facesPaused: Bool = false
    /// Frame rate cap for live faces.
    @Entry var faceFrameRate: Double = 30
    /// Draw faces as still SwiftUI frames. Needed for `ImageRenderer`, which can't draw AppKit views.
    @Entry var facesRenderStill: Bool = false
}

public extension View {
    func facesPaused(_ paused: Bool) -> some View { environment(\.facesPaused, paused) }
    func faceFrameRate(_ fps: Double) -> some View { environment(\.faceFrameRate, fps) }
    func facesRenderStill(_ still: Bool = true) -> some View { environment(\.facesRenderStill, still) }
}
