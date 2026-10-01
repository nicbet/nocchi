import AppKit
import NocchiCore
import SwiftUI

/// Nocchi's app icon: the face waving hello, as in the launch greeting, with a warm glow and gold
/// sparkles, drawn with the notch's own face renderer. `scripts/make-icon.sh` renders every size
/// (`nocchi --render-iconset <dir>`) and builds `Resources/AppIcon.icns`.
@MainActor
public enum AppIcon {
    /// The icon at `pixels` × `pixels`, drawn at that size (not scaled down).
    public static func png(pixels: Int = 1024) -> Data? {
        let renderer = ImageRenderer(content: IconView().facesRenderStill())
        renderer.scale = CGFloat(pixels) / IconView.canvas
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// Writes an `.iconset` folder (every size macOS wants) for `iconutil`.
    public static func writeIconset(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
                try png(pixels: points * scale)?.write(to: directory.appending(path: name))
            }
        }
    }
}

/// macOS icon grid: an 824 pt rounded square centered in 1024, with room for the shadow.
private struct IconView: View {
    static let canvas: CGFloat = 1024
    static let tile: CGFloat = 824
    static let radius: CGFloat = 185

    var body: some View {
        ZStack {
            ZStack {
                LinearGradient(colors: [Color(white: 0.14), Color(white: 0.02)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(red: 1, green: 0.85, blue: 0.6).opacity(0.45), .clear],
                               center: .center, startRadius: 60, endRadius: 400)
                Sparkles()
                WavingPose(mood: .idle, size: 400)
                    .offset(x: -20, y: 30)
            }
            .frame(width: Self.tile, height: Self.tile)
            .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
            .overlay {
                // A soft edge highlight, like macOS icons.
                RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 3)
            }
            .shadow(color: .black.opacity(0.35), radius: 18, y: 12)
        }
        .frame(width: Self.canvas, height: Self.canvas)
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
