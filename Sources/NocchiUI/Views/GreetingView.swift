import NocchiCore
import SwiftUI

/// The greeting's choreography. Everything finishes before `duration`, when the notch collapses.
enum GreetingTimeline {
    /// Shockwave rings of sparks, fired from the face every 0.3 s until `emitEnd`.
    static let bursts: [Double] = Array(stride(from: 0, through: 1.8, by: 0.3))
    static let sparksPerRing = 900
    static let emitEnd = 1.8
    /// How long a ring lives; it has left the card by then.
    static let sparkLifetime = 1.6...1.8
    /// Confetti pieces thrown out with the first rings.
    static let confettiCount = 24

    /// Glow strength: a base level plus a flare after each burst.
    static func glow(_ t: Double) -> Double {
        let flare = bursts.reduce(0) { sum, burst in t >= burst ? sum + exp(-(t - burst) * 8) : sum }
        return (0.6 + 0.4 * min(1, flare)) * (1 - progress(t, glowFade))
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

/// A celebration: shockwave rings of tiny sparks expanding out of the face, plus confetti.
/// The card is wide and short, so mostly the left and right arcs of each ring are visible,
/// moving outward as bands.
private struct Sparks: View {
    let t: Double
    /// Rings start just outside the face (radius 35) and its hands.
    static let startRadius: CGFloat = 46
    static let ringSpeed: CGFloat = 190            // pt/s
    static let confettiColors: [Color] = [
        Color(red: 0.95, green: 0.33, blue: 0.36), Color(red: 0.32, green: 0.80, blue: 0.72),
        Color(red: 1.00, green: 0.78, blue: 0.30), Color(red: 0.38, green: 0.58, blue: 0.98),
        Color(red: 0.96, green: 0.48, blue: 0.70),
    ]

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let count = GreetingTimeline.sparksPerRing
            let lifetime = GreetingTimeline.sparkLifetime.upperBound

            for (ring, birth) in GreetingTimeline.bursts.enumerated() where t >= birth && t - birth < lifetime {
                let age = t - birth
                let progress = age / lifetime
                let radius = Self.startRadius + Self.ringSpeed * CGFloat(age)
                let thickness = 18 + 40 * CGFloat(progress)       // the band spreads as it travels
                let ringFade = min(1, age / 0.12) * (1 - progress * progress)
                for i in 0..<count {
                    let h = { (k: UInt64) in hash01(UInt64(ring), UInt64(i), k) }
                    let angle = (Double(i) + h(1)) / Double(count) * 2 * .pi
                    // Two random numbers averaged: denser in the middle of the band.
                    let offset = CGFloat((h(2) + h(3)) / 2 - 0.5) * thickness
                    let r = radius + offset
                    let x = center.x + cos(angle) * r
                    let y = center.y + sin(angle) * r
                    let dot = CGFloat(0.4 + h(4) * 0.8)
                    let opacity = ringFade * (0.3 + 0.7 * h(5))
                    context.fill(Path(CGRect(x: x - dot, y: y - dot, width: 2 * dot, height: 2 * dot)),
                                 with: .color(.white.opacity(opacity)))
                }
            }

            // Confetti: a few colored pieces tumbling outward with the first rings.
            for i in 0..<GreetingTimeline.confettiCount {
                let h = { (k: UInt64) in hash01(77, UInt64(i), k) }
                let birth = h(1) * 0.9
                let life = 1.8 + h(2) * 0.6
                guard t >= birth, t - birth < life else { continue }
                let age = t - birth
                let angle = h(3) * 2 * .pi
                let distance = Self.startRadius + CGFloat(120 + h(4) * 160) * CGFloat(1 - exp(-1.2 * age)) / 1.2
                let fall = CGFloat(age * age * 10)       // a touch of gravity
                var piece = context
                piece.translateBy(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance + fall)
                piece.rotate(by: .radians(age * (4 + h(5) * 8) * (h(6) < 0.5 ? -1 : 1)))
                let fade = min(1, age / 0.15) * (1 - pow(age / life, 3))
                let color = Self.confettiColors[Int(h(7) * Double(Self.confettiColors.count))]
                piece.fill(Path(roundedRect: CGRect(x: -4, y: -1.6, width: 8, height: 3.2), cornerRadius: 1.4),
                           with: .color(color.opacity(fade)))
            }
        }
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
