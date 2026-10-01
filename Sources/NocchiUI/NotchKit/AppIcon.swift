import AppKit
import NocchiCore
import SwiftUI

/// Nocchi's app icon, drawn with the same face renderer as the notch. `nocchi --render-icon <dir>`
/// writes the variants as 1024 px PNGs; `scripts/make-icon.sh` turns the chosen one into an .icns.
@MainActor
public enum AppIcon {
    public enum Variant: String, CaseIterable, Sendable {
        /// The face on a dark rounded square.
        case face
        /// A notch hanging from the top of a gradient, the face peeking out.
        case notch
        /// The happy "done" face with sparkles.
        case celebrate
        /// Waving hello, as in the launch greeting.
        case wave
        /// The happy face waving.
        case waveHappy = "wave-happy"
    }

    /// Renders `variant` at `pixels` × `pixels`.
    public static func png(_ variant: Variant, pixels: Int = 1024) -> Data? {
        let renderer = ImageRenderer(content: IconView(variant: variant).facesRenderStill())
        renderer.scale = CGFloat(pixels) / IconView.canvas
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

/// macOS icon grid: an 824 pt rounded square centered in 1024, with room for the shadow.
private struct IconView: View {
    let variant: AppIcon.Variant
    static let canvas: CGFloat = 1024
    static let tile: CGFloat = 824
    static let radius: CGFloat = 185

    var body: some View {
        ZStack {
            tile
                .frame(width: Self.tile, height: Self.tile)
                .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
                .overlay {
                    // A soft top highlight, like macOS icons.
                    RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 3)
                }
                .shadow(color: .black.opacity(0.35), radius: 18, y: 12)
        }
        .frame(width: Self.canvas, height: Self.canvas)
    }

    @ViewBuilder
    private var tile: some View {
        switch variant {
        case .face:
            ZStack {
                LinearGradient(colors: [Color(white: 0.16), Color(white: 0.03)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Mood.idle.tint.opacity(0.25), .clear], center: .center, startRadius: 40, endRadius: 360)
                FaceView(mood: .idle, size: 470, seed: 0.37)
                    .frame(width: 560, height: 560)
            }
        case .notch:
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.62, green: 0.36, blue: 0.95), Color(red: 0.30, green: 0.30, blue: 0.86)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                // The notch: black, hanging from the top edge, rounded at the bottom.
                UnevenRoundedRectangle(bottomLeadingRadius: 150, bottomTrailingRadius: 150, style: .continuous)
                    .fill(.black)
                    .frame(width: 640, height: 470)
                    .shadow(color: .black.opacity(0.35), radius: 30, y: 16)
                FaceView(mood: .working, size: 300, seed: 0.37)
                    .frame(width: 360, height: 360)
                    .padding(.top, 70)
            }
        case .wave, .waveHappy:
            let mood: Mood = variant == .wave ? .idle : .done
            let glow = variant == .wave ? Color(red: 1, green: 0.85, blue: 0.6) : Mood.done.tint
            ZStack {
                LinearGradient(colors: [Color(white: 0.14), Color(white: 0.02)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [glow.opacity(0.45), .clear], center: .center, startRadius: 60, endRadius: 400)
                Sparkles()
                WavingPose(mood: mood, size: 400)
                    .offset(x: -20, y: 30)
            }
        case .celebrate:
            ZStack {
                LinearGradient(colors: [Color(white: 0.14), Color(white: 0.02)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Mood.done.tint.opacity(0.45), .clear], center: .center, startRadius: 60, endRadius: 400)
                FaceView(mood: .done, size: 440, seed: 0.37)
                    .frame(width: 600, height: 600)
            }
        }
    }
}

/// A few gold four-pointed sparkles around the face, like the done face's.
private struct Sparkles: View {
    var body: some View {
        Canvas { context, size in
            let spots: [(x: Double, y: Double, r: Double)] = [
                (0.20, 0.24, 34), (0.82, 0.30, 26), (0.16, 0.72, 20), (0.86, 0.74, 30), (0.70, 0.14, 16),
            ]
            for spot in spots {
                let c = CGPoint(x: spot.x * size.width, y: spot.y * size.height)
                var star = Path()
                let r = spot.r, w = spot.r * 0.28
                star.move(to: CGPoint(x: c.x, y: c.y - r))
                star.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + w, y: c.y - w))
                star.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + w, y: c.y + w))
                star.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - w, y: c.y + w))
                star.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - w, y: c.y - w))
                context.fill(star, with: .color(Color(red: 1, green: 0.9, blue: 0.62)))
            }
        }
    }
}

/// The greeting's wave as one clear pose: the right hand raised beside the head with a couple of
/// motion arcs, the left hand down. (A frame of the animation reads as ears; the motion is what
/// made it a wave.)
private struct WavingPose: View {
    let mood: Mood
    let size: CGFloat

    var body: some View {
        let s = size
        let color = FacePalette.body(for: mood)
        ZStack {
            hand(color).offset(x: -s * 0.50, y: s * 0.30)
            hand(color).offset(x: s * 0.55, y: -s * 0.36)
            // Motion arcs beside the raised hand.
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .trim(from: 0.04, to: 0.2)
                    .stroke(.white.opacity(0.75), style: StrokeStyle(lineWidth: s * 0.03, lineCap: .round))
                    .frame(width: s * (0.42 + 0.22 * CGFloat(i)), height: s * (0.42 + 0.22 * CGFloat(i)))
                    .rotationEffect(.degrees(-60))
                    .offset(x: s * 0.55, y: -s * 0.36)
            }
            FaceView(mood: mood, size: s, seed: 0.37)
                .frame(width: s * 1.4, height: s * 1.4)
        }
    }

    private func hand(_ color: RGBA) -> some View {
        let d = size * 0.27
        return Circle()
            .fill(RadialGradient(colors: [color.lighter(0.3).color, color.darker(0.12).color],
                                 center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: d))
            .frame(width: d, height: d)
    }
}
