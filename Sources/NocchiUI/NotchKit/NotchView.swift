import SwiftUI

/// The notch itself, drawn at the top center of the (larger, transparent) panel.
struct NotchView: View {
    let model: NotchModel

    var body: some View {
        let size = model.shapeSize(for: model.mode)
        let shape = NotchShape(topRadius: model.topRadius, bottomRadius: model.bottomRadius)

        ZStack(alignment: .top) {
            shape
                .fill(.black)
                .overlay(alignment: .top) { content }
                .clipShape(shape)
                .frame(width: size.width, height: size.height)
                .shadow(color: .black.opacity(model.mode == .expanded ? 0.45 : 0), radius: 18, y: 8)
                .overlay {
                    if model.showsHitArea {
                        Rectangle().strokeBorder(.red, lineWidth: 1).frame(width: size.width, height: size.height)
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(model.mode == .expanded ? Self.expandSpring : Self.collapseSpring, value: model.mode)
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

/// Stand-ins until the Mascot lands in M2: a face on the left, a 2×2 cluster on the right.
private struct CollapsedPlaceholder: View {
    let model: NotchModel

    var body: some View {
        let h = model.geometry.notchSize.height
        HStack(spacing: 0) {
            Circle().fill(.white.opacity(0.9))
                .frame(width: h * 0.62, height: h * 0.62)
                .frame(width: model.earWidth)
            Spacer(minLength: model.geometry.notchSize.width)
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow { dot(.red); dot(.purple) }
                GridRow { dot(.teal); dot(.orange) }
            }
            .frame(width: model.earWidth)
        }
        .frame(width: model.bodySize(for: .collapsed).width, height: h)
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: model.geometry.notchSize.height * 0.3)
    }
}

private struct ExpandedPlaceholder: View {
    let model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.geometry.notchSize.height)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay {
                    HStack(spacing: 14) {
                        Circle().fill(.white.opacity(0.9)).frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("nocchi").font(.system(size: 15, weight: .semibold))
                            Text("No agents yet").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .foregroundStyle(.white)
                }
                .padding(EdgeInsets(top: 10, leading: 18, bottom: 18, trailing: 18))
        }
        .frame(width: model.bodySize(for: .expanded).width, height: model.bodySize(for: .expanded).height)
        .environment(\.colorScheme, .dark)
    }
}
