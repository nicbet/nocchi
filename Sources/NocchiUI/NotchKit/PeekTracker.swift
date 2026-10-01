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

/// How much the notch may interrupt.
public enum PeekLevel: String, CaseIterable, Sendable {
    /// Needs you: open the notch. Finished or failed: a one-line banner under the collapsed notch.
    case everything
    /// Only when an agent needs you; finishes just celebrate on the face.
    case needsYou
    case never

    public var title: String {
        switch self {
        case .everything: "Everything"
        case .needsYou: "Only When Needed"
        case .never: "Never"
        }
    }
}

/// What the notch does about agents that just entered an attention mood.
struct PeekPolicy {
    enum Action: Equatable {
        /// Open the notch: someone needs you.
        case open(PeekTracker.Peek)
        /// A one-line banner under the collapsed notch.
        case banner(PeekTracker.Peek)
    }

    var level: PeekLevel
    /// The middle of the collapsed notch already announces finishes (screens without a notch).
    var statusTextAnnounces: Bool

    /// `entered` is most urgent first. `isUnread(ref)` is false when the agent's status isn't
    /// actually done/blocked/failed: a turn finishing right where you look only celebrates.
    func actions(for entered: [PeekTracker.Peek], isUnread: (AgentRef) -> Bool) -> [Action] {
        guard level != .never else { return [] }
        var actions: [Action] = []
        for peek in entered where isUnread(peek.ref) {
            switch peek.mood {
            case .waiting:
                if !actions.contains(where: { if case .open = $0 { true } else { false } }) { actions.append(.open(peek)) }
            case .done, .error:
                if level == .everything && !statusTextAnnounces { actions.append(.banner(peek)) }
            default:
                break
            }
        }
        return actions
    }
}

/// The one-line mini peek under the collapsed notch: "Servaint finished", or counts when several
/// arrive together ("2 finished · 1 failed").
public struct PeekBanner: Equatable, Sendable {
    public var refs: [AgentRef]
    public var failed: Set<AgentRef>
    /// The first agent's name, for a single one.
    public var name: String

    init(ref: AgentRef, name: String, mood: Mood) {
        refs = [ref]
        failed = mood == .error ? [ref] : []
        self.name = name
    }

    /// Red when anything failed.
    public var mood: Mood { failed.isEmpty ? .done : .error }

    public var text: String {
        if refs.count == 1 { return "\(name) \(failed.isEmpty ? "finished" : "failed")" }
        let finished = refs.count - failed.count
        switch (finished, failed.count) {
        case (_, 0): return "\(finished) agents finished"
        case (0, _): return "\(failed.count) agents failed"
        default: return "\(finished) finished · \(failed.count) failed"
        }
    }

    public var symbol: String { failed.isEmpty ? "checkmark" : "exclamationmark.triangle.fill" }

    func adding(_ ref: AgentRef, mood: Mood) -> PeekBanner {
        guard !refs.contains(ref) else { return self }
        var banner = self
        banner.refs.append(ref)
        if mood == .error { banner.failed.insert(ref) }
        return banner
    }
}
