import NocchiCore
import SwiftUI

/// Expanded: a focus card for the primary agent (face + step carousel) and chips for the others.
struct OverviewView: View {
    let model: NotchModel

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
                if let alert {
                    AlertView(store: store, entry: alert, mood: store.mood(of: alert))
                        .transition(.blurReplace)
                } else {
                    HStack(spacing: 10) {
                        FocusCard(model: model)
                            .frame(width: (body.width - 36 - 10) * 0.52)
                        ChipsCard(store: store)
                    }
                    .transition(.blurReplace)
                }
            }
            .padding(EdgeInsets(top: 8, leading: Self.gutter, bottom: 16, trailing: Self.gutter))
            .animation(.spring(duration: 0.45, bounce: 0.15), value: alert?.ref)
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
    static let padding: CGFloat = 14
    static let faceSize: CGFloat = 64
    static let faceFrame: CGFloat = 92

    var body: some View {
        let store = model.store
        let entry = model.prompt.target.flatMap { store.state.agents[$0] } ?? store.primary
        let mood = entry.map(store.mood(of:)) ?? store.emptyMood
        let composing = entry != nil && model.prompt.target == entry?.ref
        HStack(spacing: 14) {
            HStack(spacing: 14) {
                FaceView(mood: mood, size: Self.faceSize, seed: entry?.faceSeed ?? 0.37)
                    .frame(width: Self.faceFrame, height: Self.faceFrame)
                    .background {
                        RadialGradient(colors: [mood.tint.opacity(0.45), .clear], center: .center, startRadius: 10, endRadius: 70)
                            .frame(width: 150, height: 150)
                            .animation(.easeInOut(duration: 0.4), value: mood)
                    }
                if let entry, composing {
                    PromptField(model: model, entry: entry)
                } else if let entry {
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
            .focusesAgent(composing ? nil : entry, in: store)
            if let entry, !composing, store.capabilities(of: entry.ref).contains(.prompt) {
                MessageButton(model: model, entry: entry, blocked: entry.info.status == .blocked)
            }
        }
        .padding(.horizontal, Self.padding)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white.opacity(0.06)))
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

/// Write to an agent: Return sends, Escape cancels.
private struct PromptField: View {
    let model: NotchModel
    let entry: AgentEntry
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Message \(entry.info.displayName)")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
            HStack(spacing: 8) {
                TextField("What next?", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .focused($focused)
                    .onSubmit { model.sendPrompt(text) }
                    .onExitCommand { model.prompt = .none }
                    .disabled(model.prompt == .sending(entry.ref))
                Button {
                    model.sendPrompt(text)
                } label: {
                    Image(systemName: model.prompt == .sending(entry.ref) ? "ellipsis.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(text.isEmpty ? .white.opacity(0.25) : Mood.working.tint)
                }
                .buttonStyle(.plain)
                .disabled(text.isEmpty)
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .frame(height: 34)
            .background(Capsule().fill(.white.opacity(0.1)))
            if case .failed(_, let message) = model.prompt {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(FacePalette.body(for: .error).lighter(0.2).color)
                    .lineLimit(1)
            } else {
                Button("Cancel") { model.prompt = .none }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .task {
            // The panel becomes key as composing starts; focus once it has.
            try? await Task.sleep(for: .milliseconds(60))
            focused = true
        }
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
                                        .focusesAgent(visible[index], in: store)
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
