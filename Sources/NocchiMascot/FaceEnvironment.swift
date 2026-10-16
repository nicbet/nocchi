import SwiftUI

public extension EnvironmentValues {
    /// Whether nocchi reduces motion (faces stop shaking, swaying and breathing). nocchi resolves
    /// it from the system setting and its own preference; other hosts set it with `facesReduceMotion(_:)`.
    @Entry var nocchiReducesMotion: Bool = false
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
    func facesReduceMotion(_ reduce: Bool) -> some View { environment(\.nocchiReducesMotion, reduce) }
}
