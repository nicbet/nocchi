import NocchiCore
import SwiftUI

/// Collapsed: the primary agent's face on the left, a 2×2 cluster of the others on the right.
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
            if !model.geometry.hasHardwareNotch && NocchiSettings.shared.showsStatusText {
                StatusText(model: model)
                    .frame(width: model.geometry.notchSize.width, height: h)
            } else {
                Spacer(minLength: model.geometry.notchSize.width)
            }
            Cluster(model: model, others: others, hidden: hidden)
                .frame(width: model.earWidth, height: h)
        }
        .frame(width: model.bodySize(for: .collapsed).width, height: h)
    }

}

/// The others in a 2×2 grid; with more than four, the last spot is a "+N" badge.
struct Cluster: View {
    let model: NotchModel
    let others: [AgentEntry]
    let hidden: [AgentEntry]

    var body: some View {
        let h = model.geometry.notchSize.height
        let size = (h * 0.36).rounded()
        Grid(horizontalSpacing: h * 0.06, verticalSpacing: h * 0.06) {
            GridRow { face(0, size); face(1, size) }
            GridRow { face(2, size); face(3, size) }
        }
        .animation(.spring(duration: 0.4, bounce: 0.2), value: others.map(\.ref))
        .animation(.spring(duration: 0.4, bounce: 0.2), value: hidden.count)
    }

    @ViewBuilder
    private func face(_ index: Int, _ size: CGFloat) -> some View {
        let store = model.store
        if index == 3, !hidden.isEmpty {
            OverflowBadge(count: hidden.count, mood: store.summaryMood(of: hidden) ?? .idle, size: size)
        } else if index < others.count {
            FaceView(mood: store.mood(of: others[index]), size: size, seed: others[index].faceSeed)
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

/// The middle of the collapsed notch on screens without a hardware notch: the ticker's current
/// message, else a dim summary. Never widens the notch; long text is truncated.
private struct StatusText: View {
    let model: NotchModel
    @Environment(\.nocchiReducesMotion) private var reduceMotion

    var body: some View {
        let message = model.ticker.current
        let summary = model.store.statusSummary
        ZStack {
            if let message {
                Text(message.text)
                    .foregroundStyle(message.mood.tint)
                    .id("message \(message.text)")
                    .transition(transition)
            } else if let summary {
                Text(summary)
                    .foregroundStyle(.white.opacity(0.45))
                    .id("summary \(summary)")
                    .transition(transition)
            }
        }
        .font(.system(size: (model.geometry.notchSize.height * 0.46).rounded(), weight: .semibold, design: .rounded))
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.4, bounce: 0.2), value: message?.text ?? summary)
    }

    private var transition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        )
    }
}
