import NocchiCore
import SwiftUI

/// The greeting's choreography. Everything finishes before `duration`, when the notch collapses.
enum GreetingTimeline {
    /// No new sparks after this; the ones in flight finish their lives.
    static let emitEnd = 2.0
    static let sparkLifetime = 1.0...1.8
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
        let glow = 1 - GreetingTimeline.progress(t, GreetingTimeline.glowFade)
        ZStack {
            ParticleStreams(t: t).allowsHitTesting(false)
            // The glow is a background so its size doesn't stretch the card.
            WavingFace(t: t)
                .background {
                    RadialGradient(colors: [Color(red: 1, green: 0.85, blue: 0.6).opacity(0.35 * glow), .clear],
                                   center: .center, startRadius: 10, endRadius: 110)
                        .frame(width: 240, height: 240)
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

/// Small sparks radiating outward from the face. Each spark slot is reborn on its own cycle until
/// `emitEnd`; sparks born after that never appear, so the burst winds down on its own.
private struct ParticleStreams: View {
    let t: Double
    static let count = 220
    /// Sparks start just outside the face (radius 35) and its hands.
    static let startRadius: CGFloat = 44

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let lifetimes = GreetingTimeline.sparkLifetime
            for i in 0..<Self.count {
                // Deterministic pseudo-random per spark slot.
                let seed = Double(i)
                func rand(_ k: Double) -> Double {
                    let v = sin(seed * 12.9898 + k * 78.233) * 43758.5453
                    return v - floor(v)
                }
                let lifetime = lifetimes.lowerBound + rand(3) * (lifetimes.upperBound - lifetimes.lowerBound)
                let phase = rand(4) * lifetime
                let cycle = floor((t + phase) / lifetime)
                let birth = cycle * lifetime - phase
                guard birth >= 0, birth <= GreetingTimeline.emitEnd else { continue }
                let age = t - birth
                let progress = age / lifetime

                // A new direction and speed every cycle, so the burst doesn't repeat visibly.
                func r(_ k: Double) -> Double { rand(k + cycle * 17.3).truncatingRemainder(dividingBy: 1) }
                let angle = r(1) * 2 * .pi
                let speed = 40 + r(2) * 80

                // Outward along the angle, with a slight sideways drift so paths aren't ruler-straight.
                let distance = Self.startRadius + CGFloat(speed * age)
                let drift = CGFloat(sin(age * 3 + r(5) * 6) * 6 * progress)
                let x = center.x + cos(angle) * distance - sin(angle) * drift
                let y = center.y + sin(angle) * distance + cos(angle) * drift

                let fadeIn = min(1, age / 0.2)
                let opacity = (0.4 + r(6) * 0.6) * fadeIn * (1 - progress)
                let radius = (0.7 + r(7) * 1.3) * (1 - 0.4 * progress)
                context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius)),
                             with: .color(.white.opacity(opacity)))
            }
        }
    }
}
