import NocchiCore
import SwiftUI

/// Small helpers shared by the notch views.
extension AgentEntry {
    /// Stable per-agent seed so faces blink out of sync.
    var faceSeed: Double { Double(abs(ref.localID.hashValue % 997)) / 997 }

    /// The step being worked on now: the latest step, else the title.
    var currentStep: String? { steps.last ?? info.title }
    /// For a chip: the live step while the agent is busy, else what it's about (its title).
    func chipText(_ mood: Mood) -> String {
        let busy = mood == .working || mood == .thinking || mood == .waiting
        return (busy ? currentStep : info.title ?? currentStep) ?? info.displayName
    }

    /// The step before it.
    var previousStep: String? { steps.count >= 2 ? steps[steps.count - 2] : nil }
}

extension Mood {
    /// The mood's face color, for tints and glows around the face.
    var tint: Color { FacePalette.body(for: self).color }

    /// Short words for the expanded card.
    var label: String {
        switch self {
        case .idle: "Ready"
        case .thinking: "Thinking"
        case .working: "Working"
        case .waiting: "Needs you"
        case .done: "Done"
        case .error: "Failed"
        case .sleep: "Asleep"
        }
    }

    var symbol: String {
        switch self {
        case .idle: "text.alignleft"
        case .thinking: "ellipsis"
        case .working: "terminal"
        case .waiting: "hand.raised"
        case .done: "checkmark"
        case .error: "exclamationmark.triangle"
        case .sleep: "moon.zzz"
        }
    }
}

extension AgentStore {
    /// The mood for the left face when there are no agents.
    var emptyMood: Mood {
        let connected = state.connections.values.contains { if case .connected = $0 { true } else { false } }
        return connected ? .idle : .sleep
    }

    /// The two most important of "1 needs you", "2 working", "1 done", or nil when nothing is
    /// going on. Two parts fit the middle of the notch without truncating.
    var statusSummary: String? {
        var needs = 0, working = 0, done = 0
        for entry in state.agents.values {
            switch mood(of: entry) {
            case .waiting, .error: needs += 1
            case .working, .thinking: working += 1
            case .done: done += 1
            case .idle, .sleep: break
            }
        }
        var parts: [String] = []
        if needs > 0 { parts.append(needs == 1 ? "1 needs you" : "\(needs) need you") }
        if working > 0 { parts.append("\(working) working") }
        if done > 0 { parts.append("\(done) done") }
        return parts.isEmpty ? nil : parts.prefix(2).joined(separator: " · ")
    }

    /// Why no source is connected ("Herdr isn't running"), if none is.
    var unavailableReason: String? {
        var reason: String?
        for connection in state.connections.values {
            switch connection {
            case .connected: return nil
            case .unavailable(let why): reason = why
            case .connecting: break
            }
        }
        return reason
    }
}

extension View {
    /// Makes the view a button with press feedback; `action` nil leaves it inert.
    func onAgentClick(help: String, _ action: (@MainActor () -> Void)?) -> some View {
        modifier(AgentClick(help: help, action: action))
    }
}

private struct AgentClick: ViewModifier {
    let help: String
    let action: (@MainActor () -> Void)?

    func body(content: Content) -> some View {
        if let action {
            Button(action: action) {
                content.contentShape(Rectangle())
            }
            .buttonStyle(PressScale())
            .help(help)
        } else {
            content
        }
    }
}

extension NotchModel {
    /// Clicking the primary agent: write to it when it's idle; otherwise jump to it in its
    /// terminal (it needs you, finished, failed, or you want to watch it work).
    func activatePrimary(_ entry: AgentEntry) {
        let mood = store.mood(of: entry)
        let capabilities = store.capabilities(of: entry.ref)
        if (mood == .idle || mood == .sleep), capabilities.contains(.prompt) {
            prompt = .composing(entry.ref)
        } else if capabilities.contains(.focus) {
            let store = store
            Task { try? await store.perform(.open(entry.ref)) }
        }
    }

    func primaryClickHelp(_ entry: AgentEntry) -> String {
        let mood = store.mood(of: entry)
        return mood == .idle || mood == .sleep ? "Message \(entry.info.displayName)" : "Open \(entry.info.displayName) in the terminal"
    }
}

/// Shrinks a little while pressed.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.3), value: configuration.isPressed)
    }
}
