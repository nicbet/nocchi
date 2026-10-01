import NocchiCore
import SwiftUI

/// The greeting's choreography. Everything finishes before `duration`, when the notch collapses.
enum GreetingTimeline {
    /// The card grows open from the middle as the first pulse goes out.
    static let open = 0.0...0.35
    /// The face sends pulses through a field of glitter, one every `pulsePeriod`, until `emitEnd`.
    static let pulsePeriod = 0.3
    static let emitEnd = 0.9
    static let pulseSpeed = 230.0                      // pt/s
    /// How long the last pulse takes to cross the card; the field is dark after `emitEnd` + this.
    static let pulseTravel = 1.3
    static let sparkCount = 5000
    /// Confetti pieces thrown out with the first pulses.
    static let confettiCount = 24

    /// Glow strength: a steady glow that fades out at the end.
    static func glow(_ t: Double) -> Double {
        0.8 * (1 - progress(t, glowFade))
    }
    /// The hands pop out from below the face, then wave.
    static let handsIn = 1.0...1.3
    /// The wave speeds up into a goodbye, then the hands tuck into the face.
    static let goodbye = 2.0...2.4
    static let tuck = 2.4...2.8
    /// The face settles into idle with a small hop, then the notch collapses to its idle pill.
    static let settle = 2.7...3.2
    /// Meanwhile it slides left and shrinks a little, to where the face sits in the overview.
    static let home = 2.7...3.2
    static let glowFade = 2.8...3.4
    /// How long the face rests in idle after settling, before the notch collapses.
    static let idleHold = 1.0
    /// When the notch collapses.
    static let duration = settle.upperBound + idleHold
    /// The frame shown when motion is reduced: hands out, sparks gone.
    static let stillPose = 2.1

    /// 0 before `range`, 1 after, linear in between.
    static func linear(_ t: Double, _ range: ClosedRange<Double>) -> Double {
        min(1, max(0, (t - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }

    /// 0 before `range`, 1 after, eased in between.
    static func progress(_ t: Double, _ range: ClosedRange<Double>) -> Double {
        let x = linear(t, range)
        return x * x * (3 - 2 * x)
    }

    /// 0 before `range`, 1 after, overshooting a little before settling.
    static func overshoot(_ t: Double, _ range: ClosedRange<Double>) -> Double {
        let x = linear(t, range) - 1
        return 1 + 2.7 * x * x * x + 1.7 * x * x
    }
}

/// Shown for a few seconds at launch: Nocchi appears amid a burst of sparks, pops its hands out
/// to wave hello, waves goodbye, tucks its hands in and settles into idle.
struct GreetingView: View {
    let model: NotchModel
    @Environment(\.nocchiReducesMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        let body = model.bodySize(for: .expanded)
        VStack(spacing: 0) {
            Color.clear.frame(height: model.geometry.notchSize.height)
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                GreetingScene(t: reduceMotion ? GreetingTimeline.stillPose : timeline.date.timeIntervalSince(start),
                              homeX: OverviewView.focusFaceX(bodyWidth: body.width))
            }
            .padding(EdgeInsets(top: 8, leading: OverviewView.gutter, bottom: 16, trailing: OverviewView.gutter))
        }
        .frame(width: body.width, height: body.height)
    }
}

/// One frame of the greeting at time `t`. Separate from the clock so snapshots can render any moment.
struct GreetingScene: View {
    let t: Double
    /// Where the face ends up, as an offset from the card's center: its spot in the overview.
    var homeX: CGFloat = 0

    var body: some View {
        let glow = GreetingTimeline.glow(t)
        // A gentle float and tilt throughout, so the face looks alive.
        let float = CGSize(width: sin(t * 2 * .pi * 0.45) * 3, height: sin(t * 2 * .pi * 0.9) * 3)
        let tilt = sin(t * 2 * .pi * 0.6 + 1) * 4
        let homing = CGFloat(GreetingTimeline.progress(t, GreetingTimeline.home))
        let home = homeX * homing
        let shrink: CGFloat = 1 + (OverviewView.focusFaceSize / WavingFace.size - 1) * homing
        let card = CardShape(open: 0.3 + 0.7 * GreetingTimeline.progress(t, GreetingTimeline.open))
        ZStack {
            // Rendered offscreen at full size: drawn directly, the live notch clipped the sparks
            // to a corner of the card.
            Sparks(t: t).drawingGroup().allowsHitTesting(false)
            // The glow is a background so its size doesn't stretch the card.
            WavingFace(t: t)
                .scaleEffect(shrink)
                .rotationEffect(.degrees(tilt))
                .background {
                    RadialGradient(colors: [Color(red: 1, green: 0.85, blue: 0.6).opacity(0.45 * glow), .clear],
                                   center: .center, startRadius: 10, endRadius: 130)
                        .frame(width: 280, height: 280)
                }
                .offset(x: home + float.width, y: float.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(card.fill(.white.opacity(0.04)))
        .clipShape(card)
    }
}

/// The card, `open` of its full width, centered.
private struct CardShape: Shape {
    var open: Double

    func path(in rect: CGRect) -> Path {
        let inset = rect.width * (1 - open) / 2
        return RoundedRectangle(cornerRadius: 22, style: .continuous).path(in: rect.insetBy(dx: inset, dy: 0))
    }
}

/// The face with two small hands. The hands pop out from below (the face squashes as they do),
/// the right one waves (faster for the goodbye) and the left bobs; then both tuck into the face
/// and it hops into idle.
struct WavingFace: View {
    let t: Double
    static let size: CGFloat = 70

    var body: some View {
        let s = Self.size
        let handsIn = GreetingTimeline.overshoot(t, GreetingTimeline.handsIn)
        let goodbye = GreetingTimeline.progress(t, GreetingTimeline.goodbye)
        let tuck = GreetingTimeline.progress(t, GreetingTimeline.tuck)
        let handsOut = min(1, handsIn) * (1 - tuck)
        let waveSpeed = 2.2 + 1.6 * goodbye                  // Hz
        let wave = sin((t - GreetingTimeline.handsIn.lowerBound) * 2 * .pi * waveSpeed) * 28 * handsOut
        let bob = sin(t * 2 * .pi * 1.1) * 6 * handsOut
        // Hands rise from under the face, then slide into it.
        let handsY = s * 0.35 * (1 - min(1, handsIn))
        let handsX = 1 - 0.6 * tuck
        let handScale = max(0, handsIn) * (1 - tuck)
        let handOpacity = min(1, GreetingTimeline.linear(t, GreetingTimeline.handsIn) * 3) * (1 - tuck)
        // A squash as the hands pop out, and a hop when settling.
        let squash = sin(GreetingTimeline.linear(t, GreetingTimeline.handsIn) * .pi) * 0.07
        let hop = sin(GreetingTimeline.linear(t, GreetingTimeline.settle) * .pi) * 6
        ZStack {
            hand.rotationEffect(.degrees(-20 + bob), anchor: .bottomTrailing)
                .offset(x: -s * 0.55 * handsX, y: s * 0.12 + handsY)
                .scaleEffect(handScale)
                .opacity(handOpacity)
            hand.rotationEffect(.degrees(20 + wave), anchor: .bottomLeading)
                .offset(x: s * 0.55 * handsX, y: -s * 0.05 + handsY)
                .scaleEffect(handScale)
                .opacity(handOpacity)
            FaceView(mood: .idle, size: s, seed: 0.37)
                .frame(width: s * 1.4, height: s * 1.4)
                .scaleEffect(x: 1 + squash, y: 1 - squash, anchor: .bottom)
                .offset(y: -hop)
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

/// A celebration: pulses rippling outward from the face through a field of glitter, plus confetti.
/// The glitter stays put (drifting slightly); each pulse lights up the sparks it passes, so the card
/// shows bright bands moving outward — a ring around the face, and vertical bands further out where
/// the card is too short to show the whole ring. A pulse reaching a side edge makes it flash.
private struct Sparks: View {
    let t: Double
    /// Pulses start just outside the face (radius 35).
    static let startRadius = 40.0
    static let brightnessLevels = 12
    static let confettiColors: [Color] = [
        Color(red: 0.95, green: 0.33, blue: 0.36), Color(red: 0.32, green: 0.80, blue: 0.72),
        Color(red: 1.00, green: 0.78, blue: 0.30), Color(red: 0.38, green: 0.58, blue: 0.98),
        Color(red: 0.96, green: 0.48, blue: 0.70),
    ]

    /// How lit a spark at `distance` from the face is: 0 between pulses, 1 on a crest.
    /// `sharpness` narrows the bands.
    static func pulse(_ t: Double, distance: Double, sharpness: Double) -> Double {
        // When the wave now at this distance left the face.
        let emitted = t - (distance - startRadius) / GreetingTimeline.pulseSpeed
        let end = GreetingTimeline.emitEnd
        guard emitted >= 0, emitted <= end else { return 0 }
        let wave = 0.5 - 0.5 * cos(emitted / GreetingTimeline.pulsePeriod * 2 * .pi)
        // The first and last pulses are softer, so the train starts and ends smoothly.
        let envelope = 0.6 + 0.4 * sin(emitted / end * .pi)
        return pow(wave, sharpness) * envelope
    }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let far = Double(hypot(size.width, size.height) / 2)
            // Thousands of separate fills are slow and the live renderer drops some, so sparks are
            // gathered into a few paths by brightness and each path is filled once.
            var glitter = [Path](repeating: Path(), count: Self.brightnessLevels)
            func spark(at x: CGFloat, _ y: CGFloat, radius dot: CGFloat, opacity: Double) {
                let level = min(Self.brightnessLevels - 1, Int(opacity * Double(Self.brightnessLevels)))
                glitter[level].addRect(CGRect(x: x - dot, y: y - dot, width: 2 * dot, height: 2 * dot))
            }

            for i in 0..<GreetingTimeline.sparkCount {
                let h = { (k: UInt64) in hash01(9, UInt64(i), k) }
                // A spot on the card, drifting slowly away from the face.
                let base = CGPoint(x: h(1) * size.width, y: h(2) * size.height)
                let dx = Double(base.x - center.x), dy = Double(base.y - center.y)
                let d0 = hypot(dx, dy)
                guard d0 > Self.startRadius else { continue }
                let distance = d0 + 8 * t
                // Bands are tight near the face and spread as they travel.
                let lit = Self.pulse(t, distance: distance, sharpness: 6 - 4 * min(1, distance / far))
                guard lit > 0.02 else { continue }
                let x = center.x + CGFloat(dx / d0 * distance)
                let y = center.y + CGFloat(dy / d0 * distance)
                let dot = CGFloat(0.5 + h(3) * 0.9)
                // Each spark twinkles on its own as well.
                let twinkle = 0.55 + 0.45 * sin(t * (9 + h(4) * 9) + h(5) * 2 * .pi)
                spark(at: x, y, radius: dot, opacity: lit * twinkle * (0.35 + 0.65 * h(6)))
            }

            // Edge flashes: a thin glittering streak down each side as a pulse reaches it.
            let flash = Self.pulse(t, distance: Double(center.x), sharpness: 10)
            if flash > 0.02 {
                for side in 0..<2 {
                    var y: CGFloat = 12
                    var i: UInt64 = 0
                    while y < size.height - 12 {
                        let h = { (k: UInt64) in hash01(UInt64(100 + side), i, k) }
                        let inset = 3 + CGFloat(h(1)) * 3
                        let x = side == 0 ? inset : size.width - inset
                        let dot = CGFloat(0.5 + h(2) * 0.7)
                        spark(at: x, y, radius: dot, opacity: flash * (0.4 + 0.6 * h(3)))
                        y += 1.2 + CGFloat(h(4)) * 1.2
                        i += 1
                    }
                }
            }

            for (level, path) in glitter.enumerated() where !path.isEmpty {
                let opacity = (Double(level) + 0.5) / Double(Self.brightnessLevels)
                context.fill(path, with: .color(.white.opacity(opacity)))
            }

            // Confetti: a few colored pieces tumbling outward with the first pulses.
            for i in 0..<GreetingTimeline.confettiCount {
                let h = { (k: UInt64) in hash01(77, UInt64(i), k) }
                let birth = h(1) * 0.6
                let life = 1.2 + h(2) * 0.4
                guard t >= birth, t - birth < life else { continue }
                let age = t - birth
                let angle = h(3) * 2 * .pi
                let distance = Self.startRadius + (120 + h(4) * 160) * (1 - exp(-1.2 * age)) / 1.2
                let fall = CGFloat(age * age * 10)       // a touch of gravity
                var piece = context
                piece.translateBy(x: center.x + CGFloat(cos(angle) * distance),
                                  y: center.y + CGFloat(sin(angle) * distance) + fall)
                piece.rotate(by: .radians(age * (4 + h(5) * 8) * (h(6) < 0.5 ? -1 : 1)))
                let fade = min(1, age / 0.15) * (1 - pow(age / life, 3))
                let color = Self.confettiColors[Int(h(7) * Double(Self.confettiColors.count))]
                piece.fill(Path(roundedRect: CGRect(x: -4, y: -1.6, width: 8, height: 3.2), cornerRadius: 1.4),
                           with: .color(color.opacity(fade)))
            }
        }
    }
}

/// Uniform pseudo-random value in [0, 1) from three integers (SplitMix64 mixing).
func hash01(_ a: UInt64, _ b: UInt64, _ c: UInt64) -> Double {
    var z = a &* 0x9E37_79B9_7F4A_7C15 &+ b &* 0xBF58_476D_1CE4_E5B9 &+ c &* 0x94D0_49BB_1331_11EB &+ 0x2545_F491_4F6C_DD1D
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    z ^= z >> 31
    return Double(z >> 11) / Double(1 << 53)
}
