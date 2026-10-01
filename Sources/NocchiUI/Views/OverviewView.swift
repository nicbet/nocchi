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
                        ChipsCard(store: store)
                    }
                    .transition(.opacity)
                }
            }
            .padding(EdgeInsets(top: 8, leading: Self.gutter, bottom: 16, trailing: Self.gutter))
            .animation(.spring(duration: 0.45, bounce: 0.15), value: alert?.ref)
            .animation(.spring(duration: 0.5, bounce: 0.2), value: model.prompt.target)
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
            if let entry, store.capabilities(of: entry.ref).contains(.prompt) {
                MessageButton(model: model, entry: entry, blocked: entry.info.status == .blocked)
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

private struct MessageButton: View {
    let model: NotchModel
    let entry: AgentEntry
    let blocked: Bool

    var body: some View {
        Button {
            model.prompt = .composing(entry.ref)
        } label: {
            Image(systemName: "text.bubble")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(Circle().fill(.white.opacity(0.1)))
        }
        .buttonStyle(PressScale())
        .disabled(blocked)
        .opacity(blocked ? 0.35 : 1)
        .help(blocked ? "\(entry.info.displayName) is waiting for you: answer it in the terminal" : "Message \(entry.info.displayName)")
    }
}

/// Previous step (dim), current step (bright), and the agent's name and state (dim).
/// New steps slide up from below.
private struct StepCarousel: View {
    let entry: AgentEntry
    let mood: Mood

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            line(entry.previousStep, symbol: "checkmark", size: 12, opacity: 0.4)
            line(entry.currentStep ?? mood.label, symbol: mood.symbol, size: 15, opacity: 1, weight: .semibold)
            line("\(entry.info.displayName) · \(mood.label)", symbol: "person.crop.circle", size: 12, opacity: 0.4)
        }
        .animation(.spring(duration: 0.4, bounce: 0.15), value: entry.steps)
        .animation(.spring(duration: 0.4, bounce: 0.15), value: mood)
    }

    @ViewBuilder
    private func line(_ text: String?, symbol: String, size: CGFloat, opacity: Double, weight: Font.Weight = .regular) -> some View {
        ZStack(alignment: .leading) {
            if let text {
                Label {
                    Text(text).lineLimit(1).truncationMode(.tail)
                } icon: {
                    Image(systemName: symbol).frame(width: size + 4)
                }
                .font(.system(size: size, weight: weight))
                .foregroundStyle(.white.opacity(opacity))
                .id(text)
                .transition(.asymmetric(
                    insertion: .push(from: .bottom).combined(with: .opacity),
                    removal: .push(from: .bottom).combined(with: .opacity)
                ))
            }
        }
        .frame(height: size + 6, alignment: .leading)
        .clipped()
    }
}

/// One chip per other agent, two columns, tinted by state.
private struct ChipsCard: View {
    let store: AgentStore
    static let maxChips = 4

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
    }
}

private struct AgentChip: View {
    let entry: AgentEntry
    let mood: Mood

    var body: some View {
        HStack(spacing: 7) {
            FaceView(mood: mood, size: 20, seed: entry.faceSeed)
                .frame(width: 22, height: 22)
            Text(entry.currentStep ?? entry.info.displayName)
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
