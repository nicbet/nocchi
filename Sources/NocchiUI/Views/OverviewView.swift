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
        let composing: (target: ComposeTarget, entry: AgentEntry?)? = switch model.prompt.target {
        case .agent(let ref)?: store.state.agents[ref].map { (.agent(ref), $0) }
        case .newAgent?: (.newAgent, nil)
        case nil: nil
        }
        VStack(spacing: 0) {
            TopBar(model: model)
            Group {
                if let composing {
                    // Removal must take time: the focus card shrinks back from the composer's
                    // frame only while the composer is still there.
                    Composer(model: model, target: composing.target, entry: composing.entry, card: card)
                        .transition(.asymmetric(insertion: .identity, removal: .opacity))
                } else if let alert {
                    AlertView(store: store, entry: alert, mood: store.mood(of: alert))
                        .transition(.blurReplace)
                } else {
                    // With nobody else, the focus card takes the whole width.
                    let hasOthers = !store.others.isEmpty
                    HStack(spacing: 10) {
                        FocusCard(model: model, card: card)
                            .frame(width: hasOthers ? (body.width - 2 * Self.gutter - 10) * 0.52 : body.width - 2 * Self.gutter)
                        if hasOthers {
                            ChipsCard(store: store, waits: model.composerJustClosed)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .animation(.spring(duration: 0.45, bounce: 0.15), value: hasOthers)
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

/// The strip beside the notch: Home and a new chat on the left; the agent sources and settings on
/// the right. The middle stays clear for the camera housing.
private struct TopBar: View {
    let model: NotchModel

    var body: some View {
        let notch = model.geometry.notchSize
        let newChat = model.prompt.target == .newAgent
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                TabButton(symbol: "house.fill", isSelected: !newChat, help: "Home") {
                    if model.prompt != .none { model.prompt = .none }
                }
                TabButton(symbol: "text.bubble.fill", isSelected: newChat, help: "Start a new agent") {
                    if !newChat { model.startNewChat() }
                }
                .disabled(!model.store.canStartAgents)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: notch.width)
            HStack(spacing: 12) {
                SourceBadges(store: model.store)
                Button {
                    model.onOpenSettings?()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScale())
                .help("Settings")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, OverviewView.gutter)
        .frame(height: notch.height)
    }
}

/// An icon tab: a dark pill when selected, a dim icon otherwise.
private struct TabButton: View {
    let symbol: String
    let isSelected: Bool
    let help: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(isSelected ? 0.95 : isEnabled ? 0.5 : 0.25))
                .frame(width: 38, height: 24)
                .background(Capsule().fill(.white.opacity(isSelected ? 0.14 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
        .help(help)
        .animation(.spring(duration: 0.3, bounce: 0.15), value: isSelected)
    }
}

/// One glyph per agent source, with a dot for its connection: green connected, amber connecting,
/// red unavailable.
private struct SourceBadges: View {
    let store: AgentStore

    var body: some View {
        HStack(spacing: 10) {
            ForEach(store.state.connections.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { id in
                let state = store.state.connections[id]
                let (symbol, name) = Self.describe(id)
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 20, height: 20)
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(Self.color(state))
                            .frame(width: 6, height: 6)
                            .overlay(Circle().stroke(.black, lineWidth: 1.5))
                            .offset(x: 2, y: 1)
                    }
                    .help(Self.help(name, state))
            }
        }
    }

    static func describe(_ id: AdapterID) -> (symbol: String, name: String) {
        switch id.rawValue {
        case "herdr": ("square.split.2x1.fill", "Herdr")
        case "claude": ("asterisk", "Claude Code")
        case "mock": ("theatermasks.fill", "Demo")
        default: ("circle.dashed", id.rawValue)
        }
    }

    static func color(_ state: ConnectionState?) -> Color {
        switch state {
        case .connected: Color(red: 0.3, green: 0.82, blue: 0.45)
        case .connecting, nil: Color(red: 0.98, green: 0.72, blue: 0.25)
        case .unavailable: Color(red: 0.95, green: 0.35, blue: 0.32)
        }
    }

    static func help(_ name: String, _ state: ConnectionState?) -> String {
        switch state {
        case .connected(let version): [name, version].compactMap { $0 }.joined(separator: " ") + ": connected"
        case .connecting, nil: "\(name): connecting…"
        case .unavailable(let reason): "\(name): \(reason)"
        }
    }
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
            if resting {
                // Project (secondary), task (primary), last message (secondary): one line each.
                let task = entry.info.title.flatMap { $0.isEmpty || $0 == entry.info.displayName ? nil : $0 }
                if task != nil {
                    row(entry.info.displayName, id: "project") {
                        Image(systemName: "folder").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
                }
                row(task ?? entry.info.displayName, id: "task") {
                    Image(systemName: mood.symbol).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(mood.tint)
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                if let said = entry.lastMessage {
                    row(said, id: "said") {
                        Image(systemName: "text.bubble").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
                }
            } else if mood.isBusy {
                // Agent and task (secondary), what it's doing now (primary), the step it just
                // finished (secondary): one line each.
                projectRow(lines: 1)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                row(entry.headline(mood), id: "now") {
                    Image(systemName: mood.symbol).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(mood.tint)
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                if let previous = entry.previousStep {
                    row(previous, id: "previous") {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
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

/// One chip per other agent, tinted by state: one column for up to three, two columns (up to 2×3)
/// beyond, the last chip "+N more" when they don't all fit.
private struct ChipsCard: View {
    let store: AgentStore
    /// Slide in only once the focus card is back in place, instead of overlapping it.
    @State private var shown: Bool
    static let maxChips = ChipLayout.maxChips

    init(store: AgentStore, waits: Bool) {
        self.store = store
        _shown = State(initialValue: !waits)
    }

    var body: some View {
        let others = store.others
        let (visible, hidden) = store.others(fitting: Self.maxChips)
        let overflow = hidden.count
        let layout = ChipLayout(count: visible.count + (overflow > 0 ? 1 : 0))
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(0..<layout.rows, id: \.self) { row in
                GridRow {
                    ForEach(0..<layout.columns, id: \.self) { column in
                        let index = row * layout.columns + column
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

/// Columns and rows for `count` chips (the overflow chip included).
struct ChipLayout: Equatable {
    static let maxChips = 6
    var columns: Int
    var rows: Int

    init(count: Int) {
        let count = max(1, min(count, Self.maxChips))
        columns = count <= 3 ? 1 : 2
        rows = (count + columns - 1) / columns
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
