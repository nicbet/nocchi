import NocchiCore
import SwiftUI

/// The greeting's choreography. Everything finishes before `duration`, when the notch collapses.
enum GreetingTimeline {
    /// Rings of sparks fired outward from the face.
    static let bursts: [Double] = [0, 0.55, 1.1, 1.65]
    static let sparksPerBurst = 170
    /// Steady sparkle between the bursts. No new sparks after `emitEnd`; the ones in flight
    /// finish their lives.
    static let emitEnd = 2.0
    static let sparkLifetime = 1.2...1.9

    /// Glow strength: a base level plus a flare after each burst.
    static func glow(_ t: Double) -> Double {
        let flare = bursts.reduce(0) { sum, burst in t >= burst ? sum + exp(-(t - burst) * 5) : sum }
        return (0.6 + 0.5 * min(1, flare)) * (1 - progress(t, glowFade))
    }
    /// The wave speeds up into a goodbye, then the hands tuck into the face.
    static let goodbye = 2.2...2.6
    static let tuck = 2.6...3.0
    /// The final action: a small bow.
    static let bow = 2.9...3.5
    static let glowFade = 3.2...3.8
    /// When the notch collapses.
    static let duration = 4.0

    /// 0 before `range`, 1 after, eased in between.
    static func progress(_ t: Double, _ range: ClosedRange<Double>) -> Double {
        let x = min(1, max(0, (t - range.lowerBound) / (range.upperBound - range.lowerBound)))
        return x * x * (3 - 2 * x)
    }
}

/// Shown for a few seconds at launch: Nocchi waves hello amid a burst of sparks, waves goodbye,
/// tucks its hands in and bows.
struct GreetingView: View {
    let model: NotchModel
    @Environment(\.nocchiReducesMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        let body = model.bodySize(for: .expanded)
        VStack(spacing: 0) {
            Color.clear.frame(height: model.geometry.notchSize.height)
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                GreetingScene(t: reduceMotion ? 0 : timeline.date.timeIntervalSince(start))
            }
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 16, trailing: 18))
        }
        .frame(width: body.width, height: body.height)
    }
}

/// One frame of the greeting at time `t`. Separate from the clock so snapshots can render any moment.
struct GreetingScene: View {
    let t: Double

    var body: some View {
        let glow = GreetingTimeline.glow(t)
        ZStack {
            Sparks(t: t).allowsHitTesting(false)
            // The glow is a background so its size doesn't stretch the card.
            WavingFace(t: t)
                .background {
                    RadialGradient(colors: [Color(red: 1, green: 0.85, blue: 0.6).opacity(0.45 * glow), .clear],
                                   center: .center, startRadius: 10, endRadius: 130)
                        .frame(width: 280, height: 280)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white.opacity(0.04)))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// The face with two small hands. The right hand waves (faster for the goodbye), the left bobs;
/// then both tuck into the face and the face bows.
private struct WavingFace: View {
    let t: Double
    static let size: CGFloat = 70

    var body: some View {
        let s = Self.size
        let goodbye = GreetingTimeline.progress(t, GreetingTimeline.goodbye)
        let tuck = GreetingTimeline.progress(t, GreetingTimeline.tuck)
        let waveSpeed = 2.2 + 1.6 * goodbye                  // Hz
        let wave = sin(t * 2 * .pi * waveSpeed) * 28 * (1 - tuck)
        let bob = sin(t * 2 * .pi * 1.1) * 6 * (1 - tuck)
        // A bow: tilt forward and come back up.
        let bowPhase = GreetingTimeline.progress(t, GreetingTimeline.bow)
        let bow = sin(bowPhase * .pi) * 10                   // degrees, and points down
        ZStack {
            hand.rotationEffect(.degrees(-20 + bob), anchor: .bottomTrailing)
                .offset(x: -s * 0.55 * (1 - 0.6 * tuck), y: s * 0.12)
                .scaleEffect(1 - tuck)
                .opacity(1 - tuck)
            hand.rotationEffect(.degrees(20 + wave), anchor: .bottomLeading)
                .offset(x: s * 0.55 * (1 - 0.6 * tuck), y: -s * 0.05)
                .scaleEffect(1 - tuck)
                .opacity(1 - tuck)
            FaceView(mood: .idle, size: s, seed: 0.37)
                .frame(width: s * 1.4, height: s * 1.4)
                .rotation3DEffect(.degrees(bow * 2), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
                .offset(y: bow * 0.4)
        }
    }

    private var hand: some View {
        let d = Self.size * 0.26
        let color = FacePalette.body(for: .idle)
        return Circle()
            .fill(RadialGradient(colors: [color.lighter(0.3).color, color.darker(0.12).color],
                                 center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: d))
            .frame(width: d, height: d)
    }
}

/// A celebration: rings of sparks bursting out of the face, plus a steady sparkle in between.
private struct Sparks: View {
    let t: Double
    /// Sparks start just outside the face (radius 35) and its hands.
    static let startRadius: CGFloat = 42
    static let trickleSlots = 120
    static let colors: [Color] = [
        .white, .white, .white,
        Color(red: 1.0, green: 0.88, blue: 0.58),   // warm gold
        Color(red: 1.0, green: 0.94, blue: 0.80),   // cream
    ]

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            // Bursts: a full ring each, angles spread evenly with a little jitter.
            for (b, burst) in GreetingTimeline.bursts.enumerated() where t >= burst {
                let count = GreetingTimeline.sparksPerBurst
                for i in 0..<count {
                    let h = { (k: UInt64) in hash01(UInt64(b), UInt64(i), k) }
                    let lifetime = lerp(GreetingTimeline.sparkLifetime, h(1))
                    let age = t - burst
                    guard age < lifetime else { continue }
                    let angle = (Double(i) + h(2) * 0.8) / Double(count) * 2 * .pi
                    let speed = 140 + h(3) * 260          // initial speed, pt/s
                    draw(&context, center: center, angle: angle, speed: speed, age: age, lifetime: lifetime,
                         size: 1.0 + h(4) * 1.8, color: Self.colors[Int(h(5) * Double(Self.colors.count))], twinkle: h(6))
                }
            }

            // Trickle: each slot re-fires on its own cycle until emitEnd.
            for i in 0..<Self.trickleSlots {
                let slot = { (k: UInt64) in hash01(99, UInt64(i), k) }
                let lifetime = lerp(GreetingTimeline.sparkLifetime, slot(1))
                let phase = slot(2) * lifetime
                let cycle = floor((t + phase) / lifetime)
                let birth = cycle * lifetime - phase
                guard birth >= 0, birth <= GreetingTimeline.emitEnd else { continue }
                let h = { (k: UInt64) in hash01(UInt64(i), UInt64(cycle + 1000), k) }
                draw(&context, center: center, angle: h(3) * 2 * .pi, speed: 60 + h(4) * 140, age: t - birth,
                     lifetime: lifetime, size: 0.7 + h(5) * 1.2, color: Self.colors[Int(h(6) * Double(Self.colors.count))], twinkle: h(7))
            }
        }
    }

    /// One spark: flies out fast and slows down (ease-out), twinkles, shrinks and fades.
    private func draw(_ context: inout GraphicsContext, center: CGPoint, angle: Double, speed: Double, age: Double,
                      lifetime: Double, size: Double, color: Color, twinkle: Double) {
        let progress = age / lifetime
        let drag = 1.6
        let distance = Self.startRadius + CGFloat(speed * (1 - exp(-drag * age)) / drag)
        let x = center.x + cos(angle) * distance
        let y = center.y + sin(angle) * distance
        let flicker = 0.75 + 0.25 * sin(age * 18 + twinkle * 6.3)
        let opacity = min(1, age / 0.08) * (1 - progress * progress) * flicker
        let r = size * (1 - 0.5 * progress)
        context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(color.opacity(opacity)))
    }
}

private func lerp(_ range: ClosedRange<Double>, _ x: Double) -> Double {
    range.lowerBound + x * (range.upperBound - range.lowerBound)
}

/// Uniform pseudo-random value in [0, 1) from three integers (SplitMix64 mixing).
func hash01(_ a: UInt64, _ b: UInt64, _ c: UInt64) -> Double {
    var z = a &* 0x9E37_79B9_7F4A_7C15 &+ b &* 0xBF58_476D_1CE4_E5B9 &+ c &* 0x94D0_49BB_1331_11EB &+ 0x2545_F491_4F6C_DD1D
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    z ^= z >> 31
    return Double(z >> 11) / Double(1 << 53)
}
