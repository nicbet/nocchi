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
