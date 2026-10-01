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
        .animation(model.mode == .expanded && !reduceMotion ? (model.isPeeking ? Self.peekSpring : Self.expandSpring) : Self.collapseSpring,
                   value: model.mode)
        .animation(.easeOut(duration: 0.25), value: model.banner)
        .animation(.spring(duration: 0.4, bounce: 0.15), value: model.drop)
    }

    /// Opening by itself (a peek) doesn't bounce: it shouldn't pull at your eye more than needed.
    static let peekSpring = Animation.spring(duration: 0.4, bounce: 0)
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
        case .expanded where model.drop != .none:
            DropView(model: model)
                .transition(.blurReplace)
        case .expanded where model.isGreeting:
            GreetingView(model: model)
                .transition(.asymmetric(insertion: AnyTransition(.blurReplace), removal: GreetingView.removal))
        case .expanded:
            OverviewView(model: model)
                .transition(.blurReplace.combined(with: .scale(0.96, anchor: .top)))
        }
    }
}


extension View {
    /// Folders dropped on the notch go to `model.onDropFolder`. Applied by the live panel only:
    /// `ImageRenderer` draws drop targets as placeholders.
    func acceptsFolderDrops(_ model: NotchModel) -> some View {
        modifier(FolderDrop(model: model))
    }
}

private struct FolderDrop: ViewModifier {
    let model: NotchModel

    func body(content: Content) -> some View {
        content.onDrop(of: [.fileURL], isTargeted: isTargeted) { providers in
            guard case .offering = model.drop, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.onDropFolder?(url) }
            }
            return true
        }
    }

    /// Drives the drop zone's highlight while a drag hovers over the notch.
    private var isTargeted: Binding<Bool> {
        Binding {
            if case .offering(let targeted) = model.drop { targeted } else { false }
        } set: { targeted in
            if case .offering = model.drop { model.drop = .offering(isTargeted: targeted) }
        }
    }
}
