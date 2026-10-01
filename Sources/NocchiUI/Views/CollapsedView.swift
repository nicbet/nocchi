import NocchiCore
import SwiftUI

/// Collapsed: the primary agent's face on the left, a 2×2 cluster of the others on the right.
/// When the others are all idle or asleep the cluster folds into a pill, and the faces fly back
/// out one by one as soon as one of them does something.
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

/// The others: a 2×2 grid, or folded into a pill of overlapping faces while they're all calm.
struct Cluster: View {
    let model: NotchModel
    let others: [AgentEntry]
    let hidden: [AgentEntry]
    @Environment(\.nocchiReducesMotion) private var reduceMotion

    /// Fold when there are at least two others and none of them is doing anything.
    nonisolated static func folds(_ moods: [Mood]) -> Bool {
        moods.count >= 2 && moods.allSatisfy { $0 == .idle || $0 == .sleep }
    }

    var body: some View {
        let store = model.store
        let everyone = others + hidden
        let folded = Self.folds(everyone.map(store.mood(of:)))
        // Folded, the pill shows everyone in slot order (up to four); unfolded, the grid's spots.
        let faces = folded ? Array(store.others.prefix(4)) : others
        let size = (model.geometry.notchSize.height * 0.36).rounded()
        let gap = (model.geometry.notchSize.height * 0.06).rounded()
        let step = (size * 0.72).rounded()
        let pillWidth = size + step * CGFloat(max(faces.count - 1, 0))

        ZStack {
            Capsule()
                .fill(.white.opacity(0.12))
                .frame(width: pillWidth + gap * 2, height: size + gap * 2)
                .opacity(folded ? 1 : 0)
                .scaleEffect(folded ? 1 : 0.6)
                .animation(animation(delay: folded ? 0.12 : 0), value: folded)
            ForEach(Array(faces.enumerated()), id: \.element.ref) { index, entry in
                FaceView(mood: store.mood(of: entry), size: size, seed: entry.faceSeed)
                    .frame(width: size, height: size)
                    .zIndex(Double(index))
                    .offset(folded
                            ? CGSize(width: -pillWidth / 2 + size / 2 + step * CGFloat(index), height: 0)
                            : Self.gridOffset(index, size: size, gap: gap))
                    // Fly out one by one; fold back in the reverse order.
                    .animation(animation(delay: folded ? Double(faces.count - 1 - index) * 0.05 : Double(index) * 0.07), value: folded)
            }
            if !folded, !hidden.isEmpty {
                OverflowBadge(count: hidden.count, mood: store.summaryMood(of: hidden) ?? .idle, size: size)
                    .offset(Self.gridOffset(3, size: size, gap: gap))
                    .transition(.opacity)
            }
        }
    }

    static func gridOffset(_ index: Int, size: CGFloat, gap: CGFloat) -> CGSize {
        let half = (size + gap) / 2
        return CGSize(width: index % 2 == 0 ? -half : half, height: index < 2 ? -half : half)
    }

    private func animation(delay: Double) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.45, bounce: 0.3).delay(delay)
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
