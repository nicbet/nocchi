import NocchiCore
import SwiftUI

/// Collapsed: the primary agent's face on the left, a 2×2 cluster of the others on the right.
/// No text: the faces do the talking.
struct CollapsedView: View {
    let model: NotchModel

    var body: some View {
        let h = model.geometry.notchSize.height
        let store = model.store
        let (others, hidden) = store.others(fitting: 4)
        HStack(spacing: 0) {
            FaceView(mood: store.primary.map(store.mood(of:)) ?? store.emptyMood,
                     size: (h * 0.66).rounded(), seed: store.primary?.faceSeed ?? 0.37)
                .frame(width: model.earWidth, height: h)
            Spacer(minLength: model.geometry.notchSize.width)
            Grid(horizontalSpacing: h * 0.06, verticalSpacing: h * 0.06) {
                GridRow { face(others, 0); face(others, 1) }
                GridRow { face(others, 2); face(others, 3, hidden: hidden) }
            }
            .frame(width: model.earWidth, height: h)
        }
        .frame(width: model.bodySize(for: .collapsed).width, height: h)
    }

    @ViewBuilder
    private func face(_ others: [AgentEntry], _ index: Int, hidden: [AgentEntry] = []) -> some View {
        let size = (model.geometry.notchSize.height * 0.36).rounded()
        if !hidden.isEmpty {
            OverflowBadge(count: hidden.count, mood: model.store.summaryMood(of: hidden) ?? .idle, size: size)
        } else if index < others.count {
            FaceView(mood: model.store.mood(of: others[index]), size: size, seed: others[index].faceSeed)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
}

/// "+N" in place of the last face when there are more agents than spots, tinted by the most
/// urgent hidden agent so a hidden one that needs you still shows its color.
struct OverflowBadge: View {
    let count: Int
    let mood: Mood
    let size: CGFloat

    var body: some View {
        Text("+\(count)")
            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .foregroundStyle(mood.tint)
            .frame(width: size, height: size)
            .background(Circle().fill(mood.tint.opacity(0.22)))
            .overlay(Circle().strokeBorder(mood.tint.opacity(0.5), lineWidth: 1))
            .help("\(count) more agents")
    }
}
