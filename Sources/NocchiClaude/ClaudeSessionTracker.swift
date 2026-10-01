import Foundation
import NocchiCore

/// Claude Code sessions as `AgentEvent`s, from Claude's session registry (`~/.claude/sessions`,
/// polled). Pure, so the lifecycle is covered by tests. Only status *changes* count:
/// - `busy` or `shell` (running a command) → working;
/// - `waiting` (a permission prompt or a question, see `waitingFor`) → blocked;
/// - `idle` after work → done (a finished turn), until seen: its terminal comes to the front;
/// - `idle` after waiting → idle (you answered or declined);
/// - gone from the registry → removed.
/// Sessions inside a Herdr pane are left to the Herdr adapter when `leavesHerdrToHerdr` is set.
public struct ClaudeSessionTracker: Sendable {
    public let adapter: AdapterID
    public var leavesHerdrToHerdr: Bool
    public private(set) var agents: [String: AgentInfo] = [:]
    /// Per session: the terminal app hosting it.
    public private(set) var hosts: [String: Int32] = [:]
    /// The registry status last seen per session, to act on changes only.
    private var registryStatus: [String: String] = [:]

    public init(adapter: AdapterID = "claude", leavesHerdrToHerdr: Bool = true) {
        self.adapter = adapter
        self.leavesHerdrToHerdr = leavesHerdrToHerdr
    }

    /// One poll of the registry. `context` says, per pid, whether it runs inside Herdr and which
    /// terminal app and tty host it (looked up by the caller; nil while unknown).
    public mutating func applyRegistry(
        _ entries: [ClaudeRegistryEntry], context: [Int32: (insideHerdr: Bool, host: Int32?, tty: String?)], now: Date
    ) -> [AgentEvent] {
        var events: [AgentEvent] = []
        var live: Set<String> = []
        for entry in entries {
            let place = context[entry.pid]
            if leavesHerdrToHerdr, place?.insideHerdr == true { continue }
            let id = entry.sessionID
            live.insert(id)
            if let host = place?.host { hosts[id] = host }
            let previous = registryStatus[id]
            registryStatus[id] = entry.status

            var info = agents[id] ?? AgentInfo(
                ref: AgentRef(adapter: adapter, localID: id), kind: .claude, status: .idle, sessionID: id, changedAt: now
            )
            if let cwd = entry.cwd, !cwd.isEmpty { info.cwd = URL(fileURLWithPath: cwd, isDirectory: true) }
            let old = agents[id]?.status
            if entry.status != previous, let status = Self.status(entry.status, after: previous) {
                if status != info.status { info.changedAt = now }
                info.status = status
            }
            guard info != agents[id] else { continue }
            agents[id] = info
            events.append(.upserted(info))
            if old == .working, info.status == .done { events.append(.turnFinished(info.ref)) }
        }
        for id in agents.keys.sorted() where !live.contains(id) {
            events += remove(id)
        }
        return events
    }

    /// What a registry status change means; nil for no change (a first sighting, or a status
    /// this version doesn't know).
    static func status(_ status: String?, after previous: String?) -> AgentStatus? {
        switch status {
        case "busy", "shell": .working
        case "waiting": .blocked
        case "idle" where previous == "busy" || previous == "shell": .done
        case "idle" where previous != nil: .idle
        default: nil
        }
    }

    /// The terminal app `host` came to the front: its finished sessions are seen.
    public mutating func hostBecameFrontmost(_ host: Int32, now: Date) -> [AgentEvent] {
        var events: [AgentEvent] = []
        for (id, var info) in agents.sorted(by: { $0.key < $1.key }) where hosts[id] == host && info.status == .done {
            info.status = .idle
            info.changedAt = now
            agents[id] = info
            events.append(.upserted(info))
        }
        return events
    }

    /// Everything, for a `.snapshot`.
    public var snapshot: [AgentInfo] { agents.values.sorted { $0.ref.localID < $1.ref.localID } }

    private mutating func remove(_ id: String) -> [AgentEvent] {
        hosts[id] = nil
        registryStatus[id] = nil
        guard let info = agents.removeValue(forKey: id) else { return [] }
        return [.removed(info.ref)]
    }
}
