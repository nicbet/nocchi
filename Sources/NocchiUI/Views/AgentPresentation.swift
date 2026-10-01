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
}
