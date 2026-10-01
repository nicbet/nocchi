import NocchiCore

/// Decides when the notch opens on its own: when an agent *enters* a mood that wants attention
/// (needs you, failed, finished). Staying in that mood doesn't peek again; leaving and coming back
/// does. Moods present when tracking starts don't peek: the faces already show them.
struct PeekTracker {
    struct Peek: Equatable {
        var ref: AgentRef
        var mood: Mood
        var duration: Duration
    }

    private var moods: [AgentRef: Mood]?

    static func duration(for mood: Mood) -> Duration? {
        switch mood {
        case .waiting, .error: .seconds(6)
        case .done: .milliseconds(3500)
        default: nil
        }
    }

    /// Feed the current moods; returns every agent that just entered an attention mood, most
    /// urgent first. The notch peeks for the first; the ticker announces them all.
    mutating func update(_ current: [AgentRef: Mood]) -> [Peek] {
        defer { moods = current }
        guard let previous = moods else { return [] }
        let entered = current.compactMap { ref, mood -> Peek? in
            guard previous[ref] != mood, let duration = Self.duration(for: mood) else { return nil }
            return Peek(ref: ref, mood: mood, duration: duration)
        }
        return entered.sorted { (Self.rank($0.mood), $0.ref.localID) < (Self.rank($1.mood), $1.ref.localID) }
    }

    static func rank(_ mood: Mood) -> Int {
        switch mood {
        case .waiting: 0
        case .error: 1
        default: 2
        }
    }
}
