import Foundation
import NocchiCore

/// A running Codex CLI session, as discovery found it.
public struct CodexSession: Equatable, Sendable {
    public var pid: Int32
    public var sessionID: String
    public var rollout: URL
    public var cwd: String?
    /// Codex's name for the thread (`session_index.jsonl`).
    public var title: String?
    /// The terminal app it runs in.
    public var hostID: Int32?

    public init(pid: Int32, sessionID: String, rollout: URL, cwd: String? = nil, title: String? = nil, hostID: Int32? = nil) {
        self.pid = pid
        self.sessionID = sessionID
        self.rollout = rollout
        self.cwd = cwd
        self.title = title
        self.hostID = hostID
    }
}

/// Codex sessions as `AgentEvent`s. Pure, so the lifecycle is covered by tests:
/// - discovery says which sessions run (a process writing a rollout); gone ones are removed;
/// - the rollout says what happens: a turn starts → working; completes → done until seen (its
///   terminal comes to the front), with its final message; aborted → idle; tool calls → steps;
/// - hooks, when installed, add what the rollout can't: a permission request → blocked.
/// When a session is first found, its recent rollout is replayed quietly: the latest state, no
/// celebration for turns that ended before nocchi was looking.
public struct CodexSessionTracker: Sendable {
    public let adapter: AdapterID
    public private(set) var agents: [String: AgentInfo] = [:]
    public private(set) var hosts: [String: Int32] = [:]

    public init(adapter: AdapterID = "codex") {
        self.adapter = adapter
    }

    /// The sessions running now. New ones appear (idle until their rollout says otherwise);
    /// missing ones are removed.
    public mutating func update(live: [CodexSession], now: Date) -> [AgentEvent] {
        var events: [AgentEvent] = []
        let ids = Set(live.map(\.sessionID))
        for id in agents.keys.sorted() where !ids.contains(id) {
            hosts[id] = nil
            if let info = agents.removeValue(forKey: id) { events.append(.removed(info.ref)) }
        }
        for session in live {
            if let host = session.hostID { hosts[session.sessionID] = host }
            var info = agents[session.sessionID] ?? AgentInfo(
                ref: AgentRef(adapter: adapter, localID: session.sessionID), kind: .codex, status: .idle,
                sessionID: session.sessionID, changedAt: now
            )
            if let cwd = session.cwd, !cwd.isEmpty { info.cwd = URL(fileURLWithPath: cwd, isDirectory: true) }
            if let title = session.title, !title.isEmpty { info.title = title }
            if info != agents[session.sessionID] {
                agents[session.sessionID] = info
                events.append(.upserted(info))
            }
        }
        return events
    }

    /// Rollout lines for `session`. `replay` for the first read of an existing rollout.
    public mutating func apply(_ rollout: [CodexRolloutEvent], to session: String, replay: Bool = false, now: Date) -> [AgentEvent] {
        guard var info = agents[session] else { return [] }
        let old = info.status
        var steps: [String] = []
        var message: String?
        for event in rollout {
            switch event {
            case .turnStarted: info.status = .working
            case .turnCompleted(let last):
                info.status = replay ? .idle : .done
                if let last { message = last }
            case .turnAborted: info.status = .idle
            case .step(let step): steps.append(step)
            case .message(let text): message = text
            case .session: break
            }
        }
        var events: [AgentEvent] = []
        if info.status != old { info.changedAt = now }
        if info != agents[session] {
            agents[session] = info
            events.append(.upserted(info))
        }
        if !replay, old == .working, info.status == .done { events.append(.turnFinished(info.ref)) }
        // A replay only needs the latest couple of steps.
        events += (replay ? Array(steps.suffix(2)) : steps).map { .step(info.ref, $0) }
        if let message { events.append(.message(info.ref, message)) }
        return events
    }

    /// From Codex hooks: a permission request blocks; anything after it means work goes on.
    public mutating func applyHook(_ name: String, session: String, now: Date) -> [AgentEvent] {
        guard var info = agents[session] else { return [] }
        switch name {
        case "PermissionRequest": info.status = .blocked
        case "PreToolUse", "PostToolUse", "UserPromptSubmit": info.status = .working
        default: return []
        }
        guard info.status != agents[session]?.status else { return [] }
        info.changedAt = now
        agents[session] = info
        return [.upserted(info)]
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

    public var snapshot: [AgentInfo] { agents.values.sorted { $0.ref.localID < $1.ref.localID } }
}
