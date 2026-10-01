import NocchiCore
import SwiftUI

/// Expanded: a focus card for the primary agent (face + step carousel) and chips for the others.
struct OverviewView: View {
    let model: NotchModel
    /// The focus card grows into the composer and shrinks back.
    @Namespace private var card

    /// When the primary agent is in one of these, the expanded notch shows an alert instead.
    static let alertMoods: Set<Mood> = [.waiting, .error, .done]

    var body: some View {
        let body = model.bodySize(for: .expanded)
        let store = model.store
        // While writing to an agent, keep its card: an alert would pull the field away.
        let alert = model.prompt != .none ? nil : store.primary.flatMap { entry in
            Self.alertMoods.contains(store.mood(of: entry)) ? entry : nil
        }
        VStack(spacing: 0) {
            Color.clear.frame(height: model.geometry.notchSize.height)
            Group {
                if let target = model.prompt.target, let entry = store.state.agents[target] {
                    // Removal must take time: the focus card shrinks back from the composer's
                    // frame only while the composer is still there.
                    Composer(model: model, entry: entry, card: card)
                        .transition(.asymmetric(insertion: .identity, removal: .opacity))
                } else if let alert {
                    AlertView(store: store, entry: alert, mood: store.mood(of: alert))
                        .transition(.blurReplace)
                } else {
                    HStack(spacing: 10) {
                        FocusCard(model: model, card: card)
                            .frame(width: (body.width - 36 - 10) * 0.52)
                        ChipsCard(store: store, waits: model.composerJustClosed)
                    }
                    .transition(.opacity)
                }
            }
            .padding(EdgeInsets(top: 8, leading: Self.gutter, bottom: 16, trailing: Self.gutter))
            .animation(.spring(duration: 0.45, bounce: 0.15), value: alert?.ref)
            // Opening takes its time; closing is quick.
            .animation(model.prompt.target == nil ? .spring(duration: 0.28, bounce: 0.05) : .spring(duration: 0.5, bounce: 0.2),
                       value: model.prompt.target)

            .animation(.spring(duration: 0.45, bounce: 0.15), value: alert.map(store.mood(of:)))
        }
        .frame(width: body.width, height: body.height)
        .environment(\.colorScheme, .dark)
    }
}

extension OverviewView {
    static let gutter: CGFloat = 18

    /// Center of the focus card's face, as an offset from the center of a body `bodyWidth` wide.
    static func focusFaceX(bodyWidth: CGFloat) -> CGFloat {
        gutter + FocusCard.padding + FocusCard.faceFrame / 2 - bodyWidth / 2
    }
    static var focusFaceSize: CGFloat { FocusCard.faceSize }
}

/// The primary agent (or the one being written to): big face with a glow in its mood color, and
/// what it's doing. Click it to open the agent; the bubble button writes to it.
private struct FocusCard: View {
    let model: NotchModel
    let card: Namespace.ID
    static let padding: CGFloat = 14
    static let faceSize: CGFloat = 64
    static let faceFrame: CGFloat = 92

    var body: some View {
        let store = model.store
        let entry = store.primary
        let mood = entry.map(store.mood(of:)) ?? store.emptyMood
        HStack(spacing: 14) {
            HStack(spacing: 14) {
                FaceView(mood: mood, size: Self.faceSize, seed: entry?.faceSeed ?? 0.37)
                    .frame(width: Self.faceFrame, height: Self.faceFrame)
                    .background {
                        RadialGradient(colors: [mood.tint.opacity(0.45), .clear], center: .center, startRadius: 10, endRadius: 70)
                            .frame(width: 150, height: 150)
                            .animation(.easeInOut(duration: 0.4), value: mood)
                    }
                if let entry {
                    StepCarousel(entry: entry, mood: mood)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.unavailableReason ?? "No agents running").font(.system(size: 14, weight: .semibold))
                        Text(store.unavailableReason != nil ? "Start it and your agents show up here."
                            : mood == .sleep ? "Waiting for an agent source…" : "Start an agent and it shows up here.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .onAgentClick(help: entry.map(model.primaryClickHelp) ?? "") {
                if let entry { model.activatePrimary(entry) }
            }
        }
        .padding(.horizontal, Self.padding)
        .frame(maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(0.06))
                .matchedGeometryEffect(id: "card", in: card)
        }
    }
}

/// Previous step (dim), current step (bright), and the agent's name and state (dim).
/// New steps slide up from below.
private struct StepCarousel: View {
    let entry: AgentEntry
    let mood: Mood

    var body: some View {
        // Busy: the live step, with the one before it above. Done or needs you: what it said,
        // above the project and task. Idle: the project and task first, what it last said below.
        // The face already shows the state.
        let resting = mood == .idle || mood == .sleep
        VStack(alignment: .leading, spacing: 6) {
            if mood.isBusy, let previous = entry.previousStep {
                row(previous, id: "previous") {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy))
                }
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.38))
                .lineLimit(1)
            }
            if resting {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "folder").font(.system(size: 10, weight: .semibold)).frame(width: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.info.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        if let task = entry.info.title, !task.isEmpty, task != entry.info.displayName {
                            Text(task)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.7))
                if let said = entry.lastMessage {
                    row(said, id: "said") {
                        Image(systemName: "text.bubble").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(2)
                }
            } else {
                row(entry.headline(mood), id: "headline") {
                    Image(systemName: mood.isBusy ? mood.symbol : "text.bubble").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(mood.tint)
                }
                // Live steps are short and bold; a message reads as prose.
                .font(.system(size: mood.isBusy ? 15 : 13.5, weight: mood.isBusy ? .semibold : .medium))
                .foregroundStyle(.white)
                .lineLimit(mood.isBusy ? 2 : 3)
                projectRow(lines: 1)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.15), value: entry.steps)
        .animation(.spring(duration: 0.4, bounce: 0.15), value: mood)
    }

    private func projectRow(lines: Int) -> some View {
        row(entry.projectAndTask, id: "project") {
            Image(systemName: "folder").font(.system(size: 10, weight: .semibold))
        }
        .lineLimit(lines)
    }

    /// Icon in a fixed column so the texts line up; new text pushes in from below.
    private func row(_ text: String, id: String, @ViewBuilder icon: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            icon().frame(width: 14)
            Text(text)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .id("\(id) \(text)")
                .transition(.push(from: .bottom).combined(with: .opacity))
        }
        .clipped()
    }
}

/// One chip per other agent, two columns, tinted by state.
private struct ChipsCard: View {
    let store: AgentStore
    /// Slide in only once the focus card is back in place, instead of overlapping it.
    @State private var shown: Bool
    static let maxChips = 4

    init(store: AgentStore, waits: Bool) {
        self.store = store
        _shown = State(initialValue: !waits)
    }

    var body: some View {
        let others = store.others
        let (visible, hidden) = store.others(fitting: Self.maxChips)
        let overflow = hidden.count
        Group {
            if others.isEmpty {
                Text("No other agents").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    ForEach(0..<2, id: \.self) { row in
                        GridRow {
                            ForEach(0..<2, id: \.self) { column in
                                let index = row * 2 + column
                                if index < visible.count {
                                    AgentChip(entry: visible[index], mood: store.mood(of: visible[index]))
                                        .onAgentClick(help: "Show \(visible[index].info.displayName)") {
                                            store.select(visible[index].ref)
                                        }
                                } else if index == visible.count, overflow > 0 {
                                    OverflowChip(count: overflow, mood: store.summaryMood(of: hidden) ?? .idle)
                                } else {
                                    Color.clear.frame(height: 34)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white.opacity(0.06)))
        .animation(.spring(duration: 0.4, bounce: 0.15), value: others.map(\.ref))
        .opacity(shown ? 1 : 0)
        .offset(x: shown ? 0 : 16)
        .onAppear {
            guard !shown else { return }
            withAnimation(.spring(duration: 0.3, bounce: 0.15).delay(0.18)) { shown = true }
        }
    }
}

private struct AgentChip: View {
    let entry: AgentEntry
    let mood: Mood

    var body: some View {
        HStack(spacing: 7) {
            FaceView(mood: mood, size: 20, seed: entry.faceSeed)
                .frame(width: 22, height: 22)
            Text(entry.chipText(mood))
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(mood.tint)
            Spacer(minLength: 0)
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .frame(height: 34)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(mood.tint.opacity(0.14)))
        .overlay(Capsule().strokeBorder(mood.tint.opacity(0.35), lineWidth: 1))
        .animation(.easeInOut(duration: 0.3), value: mood)
        .help("\(entry.info.displayName): \(mood.label)")
    }
}

/// Tinted by the most urgent hidden agent.
private struct OverflowChip: View {
    let count: Int
    let mood: Mood

    var body: some View {
        Text("+\(count) more")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(mood.tint)
            .frame(height: 34)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(mood.tint.opacity(0.1)))
            .overlay(Capsule().strokeBorder(mood.tint.opacity(0.3), lineWidth: 1))
    }
}
