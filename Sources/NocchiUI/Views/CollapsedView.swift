import NocchiCore
import SwiftUI

/// Collapsed: the primary agent's face on the left, the others on the right in one or two columns
/// (`ClusterLayout`), or no right side at all when there's nobody else.
struct CollapsedView: View {
    let model: NotchModel

    var body: some View {
        let h = model.geometry.notchSize.height
        let store = model.store
        let (others, hidden) = store.others(fitting: ClusterLayout.maxSpots)
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
            if let layout = model.cluster {
                Cluster(model: model, layout: layout, others: others, hidden: hidden)
                    .frame(width: layout.width, height: h)
                    .transition(.opacity)
            }
        }
        .frame(width: model.bodySize(for: .collapsed).width, height: h)
    }

}

/// The others, laid out by `ClusterLayout`; with more than fit, the last spot is a "+N" badge.
/// Faces glide to their new spots when the layout changes.
struct Cluster: View {
    let model: NotchModel
    let layout: ClusterLayout
    let others: [AgentEntry]
    let hidden: [AgentEntry]

    var body: some View {
        let store = model.store
        let spring = Animation.spring(duration: 0.45, bounce: 0.2)
        ZStack {
            ForEach(Array(others.enumerated()), id: \.element.ref) { index, entry in
                FaceView(mood: store.mood(of: entry), size: layout.faceSize, seed: entry.faceSeed)
                    .frame(width: layout.faceSize, height: layout.faceSize)
                    .offset(layout.offset(index))
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
            if !hidden.isEmpty {
                OverflowBadge(count: hidden.count, mood: store.summaryMood(of: hidden) ?? .idle, size: layout.faceSize)
                    .offset(layout.offset(others.count))
                    .transition(.opacity)
            }
        }
        .animation(spring, value: layout)
        .animation(spring, value: others.map(\.ref))
        .animation(spring, value: hidden.count)
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
