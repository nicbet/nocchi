import NocchiCore
import SwiftUI

/// Shown for a few seconds at launch: Nocchi waving hello between streams of drifting particles.
struct GreetingView: View {
    let model: NotchModel
    @Environment(\.nocchiReducesMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        let body = model.bodySize(for: .expanded)
        VStack(spacing: 0) {
            Color.clear.frame(height: model.geometry.notchSize.height)
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSince(start)
                ZStack {
                    ParticleStreams(t: t).allowsHitTesting(false)
                    // The glow is a background so its size doesn't stretch the card.
                    WavingFace(t: t)
                        .background {
                            RadialGradient(colors: [Color(red: 1, green: 0.85, blue: 0.6).opacity(0.35), .clear],
                                           center: .center, startRadius: 10, endRadius: 110)
                                .frame(width: 240, height: 240)
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white.opacity(0.04)))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 16, trailing: 18))
        }
        .frame(width: body.width, height: body.height)
    }
}

/// The face with two small hands. The right hand waves; the left one bobs a little.
private struct WavingFace: View {
    let t: Double
    static let size: CGFloat = 70

    var body: some View {
        let s = Self.size
        let wave = sin(t * 2 * .pi * 2.2) * 28        // degrees
        let bob = sin(t * 2 * .pi * 1.1) * 6
        ZStack {
            hand.rotationEffect(.degrees(-20 + bob), anchor: .bottomTrailing)
                .offset(x: -s * 0.55, y: s * 0.12)
            hand.rotationEffect(.degrees(20 + wave), anchor: .bottomLeading)
                .offset(x: s * 0.55, y: -s * 0.05)
            FaceView(mood: .idle, size: s, seed: 0.37)
                .frame(width: s * 1.4, height: s * 1.4)
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

/// Small sparks radiating outward from the face, each on its own angle, speed and lifetime.
private struct ParticleStreams: View {
    let t: Double
    static let count = 260
    /// Sparks start just outside the face (radius 35) and its hands.
    static let startRadius: CGFloat = 44

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for i in 0..<Self.count {
                // Deterministic pseudo-random per particle.
                let seed = Double(i)
                func rand(_ k: Double) -> Double {
                    let v = sin(seed * 12.9898 + k * 78.233) * 43758.5453
                    return v - floor(v)
                }
                let angle = rand(1) * 2 * .pi
                let speed = 28 + rand(2) * 70
                let lifetime = 1.8 + rand(3) * 2.2
                let age = (t + rand(4) * lifetime).truncatingRemainder(dividingBy: lifetime)
                let progress = age / lifetime

                // Outward along the angle, with a slight sideways drift so paths aren't ruler-straight.
                let distance = Self.startRadius + CGFloat(speed * age)
                let drift = CGFloat(sin(age * 3 + rand(5) * 6) * 6 * progress)
                let x = center.x + cos(angle) * distance - sin(angle) * drift
                let y = center.y + sin(angle) * distance + cos(angle) * drift

                let fadeIn = min(1, age / 0.25)
                let opacity = (0.4 + rand(6) * 0.6) * fadeIn * (1 - progress)
                let r = (0.7 + rand(7) * 1.3) * (1 - 0.4 * progress)
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                             with: .color(.white.opacity(opacity)))
            }
        }
    }
}
