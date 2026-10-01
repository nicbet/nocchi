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

/// Four vertical streams of small dots drifting upward, like sparks.
private struct ParticleStreams: View {
    let t: Double
    static let streams: [CGFloat] = [0.12, 0.24, 0.76, 0.88]
    static let perStream = 70

    var body: some View {
        Canvas { context, size in
            for (s, x) in Self.streams.enumerated() {
                for i in 0..<Self.perStream {
                    // Deterministic pseudo-random per particle.
                    let seed = Double(s * 1000 + i)
                    func rand(_ k: Double) -> Double {
                        let v = sin(seed * 12.9898 + k * 78.233) * 43758.5453
                        return v - floor(v)
                    }
                    let speed = 18 + rand(1) * 30
                    let y = size.height - ((rand(2) * size.height + t * speed).truncatingRemainder(dividingBy: size.height + 10))
                    let jitter = sin(t * (1 + rand(3) * 2) + rand(4) * 6) * 10 + (rand(5) - 0.5) * 34
                    let px = x * size.width + jitter
                    let r = 0.6 + rand(6) * 1.2
                    let edgeFade = min(1, y / 30, (size.height - y) / 30)
                    context.fill(Path(ellipseIn: CGRect(x: px - r, y: y - r, width: 2 * r, height: 2 * r)),
                                 with: .color(.white.opacity((0.35 + rand(7) * 0.6) * max(0, edgeFade))))
                }
            }
        }
    }
}
