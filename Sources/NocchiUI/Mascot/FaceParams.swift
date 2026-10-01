import CoreGraphics
import Foundation
import NocchiCore

/// Everything that describes a face at one instant. Lengths are fractions of the face diameter.
/// Moods are just different parameter sets, so changing mood is a plain interpolation.
struct FaceParams: Equatable {
    var offset = CGVector.zero      // nod, bounce, shake
    var rotation = 0.0              // radians, head tilt
    var scale = 1.0                 // breathing
    var redness = 0.0               // body tint toward error red
    var dim = 0.0                   // body tint toward dark (asleep)

    var eyeWidth = 0.095
    var eyeHeight = 0.26
    var eyeY = 0.02                 // eye center below the face center
    var eyeSpacing = 0.25           // distance between eye centers
    var caret = 0.0                 // 0 = capsule eyes, 1 = `^ ^` eyes

    var gazeBias = CGVector.zero    // where the eyes look on their own (-1…1)
    var gazeWeight = 1.0            // how much the pointer pulls the eyes

    var ring = 0.0                  // accessory opacities
    var badge = 0.0
    var sparkles = 0.0
    var zzz = 0.0
    var errorDot = 0.0

    static func lerp(_ a: Self, _ b: Self, _ p: Double) -> Self {
        // Weighted form so p == 0 and p == 1 return the endpoints exactly.
        func m(_ x: Double, _ y: Double) -> Double { x * (1 - p) + y * p }
        func v(_ x: CGVector, _ y: CGVector) -> CGVector { CGVector(dx: m(x.dx, y.dx), dy: m(x.dy, y.dy)) }
        return FaceParams(
            offset: v(a.offset, b.offset), rotation: m(a.rotation, b.rotation), scale: m(a.scale, b.scale),
            redness: m(a.redness, b.redness), dim: m(a.dim, b.dim),
            eyeWidth: m(a.eyeWidth, b.eyeWidth), eyeHeight: m(a.eyeHeight, b.eyeHeight),
            eyeY: m(a.eyeY, b.eyeY), eyeSpacing: m(a.eyeSpacing, b.eyeSpacing), caret: m(a.caret, b.caret),
            gazeBias: v(a.gazeBias, b.gazeBias), gazeWeight: m(a.gazeWeight, b.gazeWeight),
            ring: m(a.ring, b.ring), badge: m(a.badge, b.badge), sparkles: m(a.sparkles, b.sparkles),
            zzz: m(a.zzz, b.zzz), errorDot: m(a.errorDot, b.errorDot)
        )
    }

    /// Parameters for `mood` at time `t` (seconds). `seed` desynchronizes faces from each other.
    /// With `reduceMotion`, motion that moves the face (nod, bounce, shake, sway, breathing) is
    /// removed; blinks, gaze, pulses and twinkles stay.
    static func make(_ mood: Mood, t: Double, seed: Double, reduceMotion: Bool = false) -> Self {
        var p = makeAnimated(mood, t: t, seed: seed)
        if reduceMotion {
            let pose = makeAnimated(mood, t: 0, seed: 0)
            p.offset = .zero
            p.rotation = pose.rotation
            p.scale = 1
        }
        return p
    }

    private static func makeAnimated(_ mood: Mood, t: Double, seed: Double) -> Self {
        let tt = t + seed * 13.7
        let tau = 2 * Double.pi
        var p = FaceParams()
        let breathe = 1 + 0.015 * sin(tt * tau / 3.5)

        switch mood {
        case .idle:
            p.scale = breathe
            p.eyeHeight *= blink(t, seed: seed)

        case .thinking:
            p.scale = breathe
            p.eyeHeight = 0.2 * blink(t, seed: seed)
            p.gazeBias = CGVector(dx: 0.8 * sin(tt * 0.9), dy: -0.6 + 0.25 * sin(tt * 1.3))
            p.gazeWeight = 0

        case .working:
            p.offset.dy = 0.035 * abs(sin(tt * .pi * 1.6))
            p.eyeHeight = 0.2 * blink(t, seed: seed + 0.5)
            p.gazeBias = CGVector(dx: 0.3 * sin(tt * 1.2), dy: 0.55)
            p.gazeWeight = 0.2
            p.badge = 1

        case .waiting:
            p.scale = breathe
            p.rotation = 0.2 + 0.04 * sin(tt * 1.5)
            p.eyeHeight *= blink(t, seed: seed)
            p.gazeWeight = 1.4
            p.ring = 0.6 + 0.4 * sin(tt * tau * 0.9)

        case .done:
            p.offset.dy = -0.05 * abs(sin(tt * .pi * 1.4))
            p.eyeY = -0.01
            p.eyeWidth = 0.11
            p.eyeHeight = 0.09
            p.caret = 1
            p.gazeWeight = 0
            p.sparkles = 1

        case .error:
            let phase = tt.truncatingRemainder(dividingBy: 2.4)
            let burst = max(0, 1 - phase / 0.6)
            p.offset.dx = 0.05 * sin(tt * tau * 7) * burst
            p.redness = 0.8
            p.eyeWidth = 0.17
            p.eyeHeight = 0.055
            p.gazeWeight = 0
            p.errorDot = 1

        case .sleep:
            p.scale = 1 + 0.025 * sin(tt * tau / 5)
            p.dim = 0.25
            p.eyeWidth = 0.13
            p.eyeHeight = 0.03
            p.eyeY = 0.06
            p.gazeWeight = 0
            p.zzz = 1
        }
        return p
    }

    /// Eye openness multiplier: 1 when open, dips toward 0.08 during a blink.
    /// Each face blinks every 3.6–5.8 s, with an occasional double blink.
    static func blink(_ t: Double, seed: Double) -> Double {
        let fraction = seed - floor(seed)
        let period = 3.6 + fraction * 2.2
        let shifted = t + seed * 7.3
        let cycle = floor(shifted / period)
        let local = shifted - cycle * period

        let h = abs(sin(cycle * 12.9898 + seed * 78.233) * 43758.5453)
        let isDouble = h - floor(h) < 0.25

        func closure(_ x: Double) -> Double { x >= 0 && x < 0.16 ? sin(.pi * x / 0.16) : 0 }
        var c = closure(local)
        if isDouble { c = max(c, closure(local - 0.28)) }
        return 1 - 0.92 * c
    }
}
