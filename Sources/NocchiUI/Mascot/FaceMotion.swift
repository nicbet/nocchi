import CoreGraphics
import NocchiCore

/// Per-face animation state: mood transitions and gaze. Independent of how the face is drawn.
struct FaceMotion {
    static let transitionDuration = 0.35

    private(set) var mood: Mood
    private var previousMood: Mood?
    private var changedAt = 0.0

    init(mood: Mood) {
        self.mood = mood
    }

    mutating func setMood(_ new: Mood, at now: Double) {
        guard new != mood else { return }
        previousMood = mood
        mood = new
        changedAt = now
    }

    /// Parameters at wall-clock `now`. `motionTime` drives blinks and nods (0 under Reduce Motion).
    func params(at now: Double, motionTime t: Double, seed: Double) -> FaceParams {
        let target = FaceParams.make(mood, t: t, seed: seed)
        guard let previousMood else { return target }
        let progress = min(1, max(0, (now - changedAt) / Self.transitionDuration))
        guard progress < 1 else { return target }
        let eased = progress * progress * (3 - 2 * progress)
        return .lerp(FaceParams.make(previousMood, t: t, seed: seed), target, eased)
    }

    func isTransitioning(at now: Double) -> Bool {
        previousMood != nil && now - changedAt < Self.transitionDuration
    }

    /// The mood's own gaze plus a pull toward `pointer` (both relative to the face center, y down).
    /// The pull is full strength from four face-widths away. Length is at most 1.
    static func gaze(_ p: FaceParams, pointer: CGVector?, size: CGFloat) -> CGVector {
        var g = p.gazeBias
        if p.gazeWeight > 0, let pointer {
            let d = max(1, hypot(pointer.dx, pointer.dy))
            let pull = min(1, d / (size * 4)) * p.gazeWeight
            g.dx += pointer.dx / d * pull
            g.dy += pointer.dy / d * pull
        }
        let length = hypot(g.dx, g.dy)
        return length > 1 ? CGVector(dx: g.dx / length, dy: g.dy / length) : g
    }
}
