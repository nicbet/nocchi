import NocchiCore
import SwiftUI

/// A face. Live faces are a `FaceNSView` with its own display link; tiny faces and snapshots
/// are a still SwiftUI `Canvas` frame.
public struct FaceView: View {
    let mood: Mood
    let color: RGBA
    let size: CGFloat
    let seed: Double

    @Environment(\.facesPaused) private var paused
    @Environment(\.faceFrameRate) private var frameRate
    @Environment(\.facesRenderStill) private var renderStill
    @Environment(\.nocchiReducesMotion) private var reduceMotion

    /// The canvas extends past the face so accessories aren't clipped.
    static let canvasScale: CGFloat = 1.8
    /// Below this size a face is a colored blob: motion isn't visible, so it draws a still frame
    /// and only redraws when its mood changes.
    static let minimumAnimatedSize: CGFloat = 14

    public init(mood: Mood, color: RGBA = FacePalette.primary, size: CGFloat, seed: Double = 0) {
        self.mood = mood
        self.color = color
        self.size = size
        self.seed = seed
    }

    public var body: some View {
        Group {
            if renderStill || size < Self.minimumAnimatedSize {
                still
            } else {
                LiveFace(mood: mood, color: color, size: size, seed: seed,
                         frameRate: frameRate, paused: paused, reduceMotion: reduceMotion)
            }
        }
        .frame(width: size * Self.canvasScale, height: size * Self.canvasScale)
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(Text("Face, \(mood.rawValue)"))
    }

    /// t = 0 with seed 0 is a neutral pose: eyes open, no shake or bounce mid-swing.
    private var still: some View {
        let params = FaceParams.make(mood, t: 0, seed: 0)
        return Canvas { context, canvas in
            context.withCGContext { cg in
                FaceRenderer.draw(in: cg, canvas: canvas, size: size, params: params, color: color, gaze: params.gazeBias, t: 0)
            }
        }
    }
}

private struct LiveFace: NSViewRepresentable {
    let mood: Mood
    let color: RGBA
    let size: CGFloat
    let seed: Double
    let frameRate: Double
    let paused: Bool
    let reduceMotion: Bool

    func makeNSView(context: Context) -> FaceNSView {
        FaceNSView(mood: mood, color: color, size: size, seed: seed)
    }

    func updateNSView(_ view: FaceNSView, context: Context) {
        view.configure(mood: mood, color: color, size: size, seed: seed,
                       frameRate: frameRate, paused: paused, reduceMotion: reduceMotion)
    }
}
