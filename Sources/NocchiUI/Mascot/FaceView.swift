import NocchiCore
import SwiftUI

/// An animated face. Mood changes blend over `transitionDuration`; time-based motion (blinks,
/// nods, shakes) keeps running through the blend.
public struct FaceView: View {
    let mood: Mood
    let color: RGBA
    let size: CGFloat
    let seed: Double

    @Environment(\.pointerLocator) private var pointerLocator
    @Environment(\.facesPaused) private var paused
    @Environment(\.faceFrameRate) private var frameRate
    @Environment(\.faceAnimatesCalmMoods) private var animatesCalmMoods
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var previousMood: Mood?
    @State private var changedAt = 0.0
    @State private var center: CGPoint?

    static let transitionDuration = 0.35
    /// The canvas extends past the face so accessories aren't clipped.
    static let canvasScale: CGFloat = 1.8

    public init(mood: Mood, color: RGBA = FacePalette.primary, size: CGFloat, seed: Double = 0) {
        self.mood = mood
        self.color = color
        self.size = size
        self.seed = seed
    }

    /// Below this size a face is a colored blob: motion isn't visible, so it draws a still frame
    /// and only redraws when its mood changes.
    static let minimumAnimatedSize: CGFloat = 14

    static func isCalm(_ mood: Mood) -> Bool { mood == .idle || mood == .sleep }

    private var isAnimated: Bool {
        size >= Self.minimumAnimatedSize && (animatesCalmMoods || !Self.isCalm(mood))
    }

    public var body: some View {
        Group {
            if !isAnimated {
                still
            } else {
                animated
            }
        }
        .frame(width: size, height: size)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            center = CGPoint(x: frame.midX, y: frame.midY)
        }
        .onChange(of: mood) { old, _ in
            previousMood = old
            changedAt = Date.timeIntervalSinceReferenceDate
        }
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(Text("Face, \(mood.rawValue)"))
    }

    private var animated: some View {
        TimelineView(.animation(minimumInterval: 1.0 / frameRate, paused: paused)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let params = params(at: timeline.date.timeIntervalSinceReferenceDate, motionTime: t)
            canvas(params: params, gaze: gaze(for: params), t: t)
        }
    }

    /// t = 0 with seed 0 is a neutral pose: eyes open, no shake or bounce mid-swing.
    private var still: some View {
        let params = FaceParams.make(mood, t: 0, seed: 0)
        return canvas(params: params, gaze: params.gazeBias, t: 0)
    }

    private func canvas(params: FaceParams, gaze: CGVector, t: Double) -> some View {
        Canvas { context, canvas in
            FaceRenderer.draw(context, canvas: canvas, size: size, params: params, color: color, gaze: gaze, t: t)
        }
        .frame(width: size * Self.canvasScale, height: size * Self.canvasScale)
    }

    private func params(at now: Double, motionTime t: Double) -> FaceParams {
        let target = FaceParams.make(mood, t: t, seed: seed)
        guard let previousMood else { return target }
        let progress = min(1, max(0, (now - changedAt) / Self.transitionDuration))
        guard progress < 1 else { return target }
        let eased = progress * progress * (3 - 2 * progress)
        return .lerp(FaceParams.make(previousMood, t: t, seed: seed), target, eased)
    }

    /// Combines the mood's own gaze with a pull toward the pointer. Length is at most 1.
    private func gaze(for p: FaceParams) -> CGVector {
        var g = p.gazeBias
        if p.gazeWeight > 0, let center, let pointer = pointerLocator?.location() {
            let dx = pointer.x - center.x, dy = pointer.y - center.y
            let d = max(1, hypot(dx, dy))
            let pull = min(1, d / (size * 4)) * p.gazeWeight
            g.dx += dx / d * pull
            g.dy += dy / d * pull
        }
        let length = hypot(g.dx, g.dy)
        return length > 1 ? CGVector(dx: g.dx / length, dy: g.dy / length) : g
    }
}
