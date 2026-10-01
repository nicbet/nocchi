import NocchiCore
import SwiftUI

/// The notch itself, drawn at the top center of the (larger, transparent) panel.
struct NotchView: View {
    let model: NotchModel
    @Environment(\.nocchiReducesMotion) private var reduceMotion

    var body: some View {
        let size = model.shapeSize(for: model.mode)
        let shape = NotchShape(topRadius: model.topRadius, bottomRadius: model.bottomRadius)

        ZStack(alignment: .top) {
            // The shadow sits on its own layer: if it wrapped the animated faces it would be
            // re-rasterized every frame.
            shape
                .fill(.black)
                .frame(width: size.width, height: size.height)
                .shadow(color: .black.opacity(model.mode == .expanded ? 0.45 : 0), radius: 18, y: 8)
            content
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(shape)
                .overlay {
                    if model.showsHitArea {
                        Rectangle().strokeBorder(.red, lineWidth: 1).frame(width: size.width, height: size.height)
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .facesPaused(model.facesPaused)
        .facesRenderStill(model.isMorphing)
        .animation(model.mode == .expanded && !reduceMotion ? Self.expandSpring : Self.collapseSpring, value: model.mode)
    }

    /// Opening can overshoot: the bounce reads as playful.
    static let expandSpring = Animation.spring(duration: 0.45, bounce: 0.28)
    /// Closing must not overshoot, or the shape briefly shrinks past its collapsed size
    /// and is smaller than the content inside it.
    static let collapseSpring = Animation.spring(duration: 0.35, bounce: 0)

    @ViewBuilder
    private var content: some View {
        switch model.mode {
        case .collapsed:
            CollapsedPlaceholder(model: model)
                .transition(.blurReplace)
        case .expanded:
            ExpandedPlaceholder(model: model)
                .transition(.blurReplace.combined(with: .scale(0.96, anchor: .top)))
        }
    }
}

/// Collapsed: the primary face on the left, a 2×2 cluster of other agents on the right.
private struct CollapsedPlaceholder: View {
    let model: NotchModel

    var body: some View {
        let h = model.geometry.notchSize.height
        HStack(spacing: 0) {
            FaceView(mood: model.primaryMood, size: (h * 0.66).rounded(), seed: 0.37)
                .frame(width: model.earWidth, height: h)
            Spacer(minLength: model.geometry.notchSize.width)
            Grid(horizontalSpacing: h * 0.06, verticalSpacing: h * 0.06) {
                GridRow { face(0); face(1) }
                GridRow { face(2); face(3) }
            }
            .frame(width: model.earWidth, height: h)
        }
        .frame(width: model.bodySize(for: .collapsed).width, height: h)
    }

    private func face(_ slot: Int) -> some View {
        FaceView(mood: model.clusterMoods[slot], color: FacePalette.bot(slot),
                 size: (model.geometry.notchSize.height * 0.36).rounded(), seed: Double(slot + 1) * 0.29)
    }
}

/// Expanded: the primary face with its mood, and the other agents. (Real cards arrive in M3.)
private struct ExpandedPlaceholder: View {
    let model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.geometry.notchSize.height)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay {
                    HStack(spacing: 18) {
                        FaceView(mood: model.primaryMood, size: 64, seed: 0.37)
                            .frame(width: 96, height: 96)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("nocchi").font(.system(size: 15, weight: .semibold))
                            Text(model.primaryMood.rawValue.capitalized).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        ForEach(0..<4, id: \.self) { slot in
                            FaceView(mood: model.clusterMoods[slot], color: FacePalette.bot(slot), size: 30, seed: Double(slot + 1) * 0.29)
                                .frame(width: 48, height: 48)
                        }
                    }
                    .padding(.horizontal, 20)
                    .foregroundStyle(.white)
                }
                .padding(EdgeInsets(top: 10, leading: 18, bottom: 18, trailing: 18))
        }
        .frame(width: model.bodySize(for: .expanded).width, height: model.bodySize(for: .expanded).height)
        .environment(\.colorScheme, .dark)
    }
}
