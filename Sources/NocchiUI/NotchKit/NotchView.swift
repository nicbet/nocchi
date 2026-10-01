import NocchiCore
import SwiftUI

/// The notch itself, drawn at the top center of the (larger, transparent) panel.
struct NotchView: View {
    let model: NotchModel
    @Environment(\.nocchiReducesMotion) private var reduceMotion
    /// Set by snapshots; combined with morphing below rather than overridden by it.
    @Environment(\.facesRenderStill) private var renderStill

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
        .facesRenderStill(renderStill || model.isMorphing)
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
            CollapsedView(model: model)
                .transition(.blurReplace)
        case .expanded where model.isGreeting:
            GreetingView(model: model)
                .transition(.blurReplace)
        case .expanded:
            OverviewView(model: model)
                .transition(.blurReplace.combined(with: .scale(0.96, anchor: .top)))
        }
    }
}

