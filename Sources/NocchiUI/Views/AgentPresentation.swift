import NocchiCore
import SwiftUI

/// Small helpers shared by the notch views.
extension AgentEntry {
    /// Stable per-agent seed so faces blink out of sync.
    var faceSeed: Double { Double(abs(ref.localID.hashValue % 997)) / 997 }

    /// The step being worked on now: the latest step, else the title.
    var currentStep: String? { steps.last ?? info.title }
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
        case .idle: "circle"
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
    /// Clicking focuses `entry`'s agent (and its terminal), if its adapter can.
    func focusesAgent(_ entry: AgentEntry?, in store: AgentStore) -> some View {
        modifier(FocusOnClick(entry: entry, store: store))
    }
}

private struct FocusOnClick: ViewModifier {
    let entry: AgentEntry?
    let store: AgentStore

    func body(content: Content) -> some View {
        if let entry, store.capabilities(of: entry.ref).contains(.focus) {
            Button {
                Task { try? await store.perform(.focus(entry.ref)) }
            } label: {
                content.contentShape(Rectangle())
            }
            .buttonStyle(PressScale())
            .help("Open \(entry.info.displayName)")
        } else {
            content
        }
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
