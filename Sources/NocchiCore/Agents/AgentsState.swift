import Foundation

/// One agent as the UI sees it: what the adapter reported, plus what nocchi derives.
public struct AgentEntry: Hashable, Sendable {
    public var info: AgentInfo
    /// Recent steps, oldest first, at most `AgentsState.maxSteps`. Fed by `.step` events, or by
    /// title changes for adapters without steps.
    public var steps: [String]
    /// Show the `done` face until then, even if the status already went back to idle.
    public var celebratingUntil: Date?
    /// Stable position among the other agents, assigned on arrival.
    public var slot: Int
    /// The agent's latest message to the user, from `.message` events.
    public var lastMessage: String?

    public var ref: AgentRef { info.ref }

    public func mood(at now: Date) -> Mood {
        switch info.status {
        case .starting, .thinking: return .thinking
        case .working: return .working
        case .blocked: return .waiting
        case .done: return .done
        case .error: return .error
        case .idle:
            if let celebratingUntil, now < celebratingUntil { return .done }
            return now.timeIntervalSince(info.changedAt) >= AgentsState.sleepAfter ? .sleep : .idle
        }
    }

    /// Lower is more urgent. Used to pick the primary face and to order alerts.
    public func attention(at now: Date) -> Int {
        switch mood(at: now) {
        case .waiting: 0
        case .error: 1
        case .done: 2
        case .working: 3
        case .thinking: 4
        case .idle: 5
        case .sleep: 6
        }
    }

    public var needsAttention: Bool {
        switch info.status {
        case .blocked, .error, .done: true
        default: false
        }
    }
}

/// All agents from all adapters. A plain value: `AgentReducer` changes it, tests inspect it.
public struct AgentsState: Hashable, Sendable {
    public var agents: [AgentRef: AgentEntry] = [:]
    public var connections: [AdapterID: ConnectionState] = [:]
    var nextSlot = 0

    public init() {}

    static let maxSteps = 3
    /// Idle agents doze off after this long without a status change.
    public static let sleepAfter: TimeInterval = 10 * 60
    /// How long the `done` face shows after a turn finishes in a pane that's being looked at.
    public static let celebrationDuration: TimeInterval = 3

    /// The face on the left: the most urgent agent that needs attention, else the one selected in
    /// nocchi, else the focused one, else the one that changed most recently.
    public func primary(at now: Date, preferring selected: AgentRef? = nil) -> AgentEntry? {
        let all = Array(agents.values)
        if let urgent = all.filter(\.needsAttention).min(by: { order($0, $1, now) }) { return urgent }
        if let selected, let entry = agents[selected] { return entry }
        if let focused = all.first(where: \.info.isFocused) { return focused }
        return all.max { ($0.info.changedAt, -$0.slot) < ($1.info.changedAt, -$1.slot) }
    }

    /// Everyone but the primary, in stable slot order.
    public func others(at now: Date, preferring selected: AgentRef? = nil) -> [AgentEntry] {
        let primary = primary(at: now, preferring: selected)?.ref
        return agents.values.filter { $0.ref != primary }.sorted { $0.slot < $1.slot }
    }

    /// The others for a row of `spots` places. Without overflow that's everyone, in slot order.
    /// With overflow, the last spot is kept for a "+N" summary of `hidden`, and the shown spots go to
    /// agents that need attention first, so one that needs you is never hidden. Shown agents stay in
    /// slot order; `hidden` is in slot order too.
    public func others(at now: Date, fitting spots: Int, preferring selected: AgentRef? = nil) -> (shown: [AgentEntry], hidden: [AgentEntry]) {
        let all = others(at: now, preferring: selected)
        guard all.count > spots else { return (all, []) }
        let room = max(spots - 1, 0)
        let urgent = all.filter(\.needsAttention).sorted { order($0, $1, now) }
        let picked = Set((urgent + all.filter { !$0.needsAttention }).prefix(room).map(\.ref))
        return (all.filter { picked.contains($0.ref) }, all.filter { !picked.contains($0.ref) })
    }

    /// The most urgent of `entries`, e.g. to tint a "+N" summary.
    public func mostUrgent(_ entries: [AgentEntry], at now: Date) -> AgentEntry? {
        entries.min { order($0, $1, now) }
    }

    private func order(_ a: AgentEntry, _ b: AgentEntry, _ now: Date) -> Bool {
        let (x, y) = (a.attention(at: now), b.attention(at: now))
        return x != y ? x < y : a.info.changedAt > b.info.changedAt
    }
}

/// Applies adapter events to `AgentsState`. Pure and source-agnostic: adapter quirks are handled
/// inside the adapters.
public enum AgentReducer {
    public static func reduce(_ state: inout AgentsState, _ event: AgentEvent, from adapter: AdapterID, now: Date) {
        switch event {
        case .connection(let connection):
            state.connections[adapter] = connection

        case .snapshot(let infos):
            let incoming = Set(infos.map(\.ref))
            for ref in state.agents.keys where ref.adapter == adapter && !incoming.contains(ref) {
                state.agents[ref] = nil
            }
            for info in infos { upsert(&state, info) }

        case .upserted(let info):
            upsert(&state, info)

        case .removed(let ref):
            state.agents[ref] = nil

        case .turnFinished(let ref):
            state.agents[ref]?.celebratingUntil = now.addingTimeInterval(AgentsState.celebrationDuration)

        case .message(let ref, let text):
            state.agents[ref]?.lastMessage = text

        case .step(let ref, let step):
            guard var entry = state.agents[ref] else { return }
            push(step, onto: &entry.steps)
            state.agents[ref] = entry
        }
    }

    private static func upsert(_ state: inout AgentsState, _ info: AgentInfo) {
        guard var entry = state.agents[info.ref] else {
            var steps: [String] = []
            if let title = info.title { push(title, onto: &steps) }
            state.agents[info.ref] = AgentEntry(info: info, steps: steps, celebratingUntil: nil, slot: state.nextSlot)
            state.nextSlot += 1
            return
        }
        if let title = info.title, title != entry.info.title { push(title, onto: &entry.steps) }
        entry.info = info
        state.agents[info.ref] = entry
    }

    private static func push(_ step: String, onto steps: inout [String]) {
        guard steps.last != step else { return }
        steps.append(step)
        if steps.count > AgentsState.maxSteps { steps.removeFirst(steps.count - AgentsState.maxSteps) }
    }
}
