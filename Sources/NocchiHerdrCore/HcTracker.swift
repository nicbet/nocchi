import Foundation
import NocchiCore

/// Turns herdr-core snapshots and events into clean `AgentEvent`s. Pure, so every rule is
/// covered by fixture tests:
/// - An agent is a live terminal whose program reports a status (OSC 7501). Status null (the
///   agent exited back to the shell), `finished` or `removed` → gone.
/// - `done` is unread until herdr-app has shown that turn (`herdr.seen` label ≥ `turn`), then
///   `idle`. Without herdr-app (no label) it stays `done`.
/// - `working → done|idle` emits `.turnFinished`.
/// - An empty title keeps the previous one.
/// - Names come from herdr-app's layout: the space's name, else a tab name that isn't a number.
/// - A Claude agent's session ID (for its steps and messages) comes from Claude's session
///   registry, by the foreground process: `sessionID(pid)`.
struct HcTracker {
    let adapter: AdapterID
    let sessionID: @Sendable (Int32) -> String?
    /// Every live terminal: a plain shell may start an agent later.
    private(set) var terminals: [String: HcTerminal] = [:]
    private(set) var agents: [String: AgentInfo] = [:]
    private var names: [String: String] = [:]

    init(adapter: AdapterID, sessionID: @escaping @Sendable (Int32) -> String? = { _ in nil }) {
        self.adapter = adapter
        self.sessionID = sessionID
    }

    /// Replaces everything with `snapshot`. Returns `.snapshot` plus `.turnFinished` for turns
    /// that finished since the last state we saw (a missed event, or a reconnect).
    mutating func apply(_ snapshot: [HcTerminal], now: Date) -> [AgentEvent] {
        terminals = Dictionary(snapshot.filter { $0.state == "live" }.map { ($0.address, $0) }, uniquingKeysWith: { $1 })
        var next: [String: AgentInfo] = [:]
        var finished: [AgentEvent] = []
        for terminal in terminals.values {
            guard let info = info(for: terminal, previous: agents[terminal.address], now: now) else { continue }
            if Self.finishesTurn(agents[terminal.address]?.status, info.status) { finished.append(.turnFinished(info.ref)) }
            next[terminal.address] = info
        }
        agents = next
        return [.snapshot(next.values.sorted { $0.ref.localID < $1.ref.localID })] + finished
    }

    mutating func apply(_ event: HcEvent, now: Date) -> [AgentEvent] {
        switch event {
        case .created(let terminal):
            terminals[terminal.address] = terminal
            return refresh(terminal.address, now: now)
        case .status(let address, let status):
            return change(address, now: now) { terminal in
                // Leaving `working` bumps the turn, but that event comes right after this one.
                // Bump it now, or the finished turn would count as seen for a moment.
                if terminal.status?.state == "working", let status, status.state != "working" { terminal.turn += 1 }
                terminal.status = status
            }
        case .turn(let address, let turn):
            return change(address, now: now) { $0.turn = turn }
        case .title(let address, let title):
            return change(address, now: now) { $0.title = title }
        case .labels(let address, let labels):
            return change(address, now: now) { $0.labels.merge(labels) { $1 } }
        case .foreground(let address, let cwd, let pid):
            return change(address, now: now) {
                $0.foregroundCwd = cwd
                $0.foregroundPID = pid
            }
        case .lost(let address):
            return change(address, now: now) { $0.status = nil }
        case .finished(let address), .removed(let address):
            terminals[address] = nil
            return refresh(address, now: now)
        case .doc, .heartbeat, .missed:
            return []
        }
    }

    /// herdr-app's layout changed: names follow.
    mutating func setLayout(_ layout: HerdrAppLayout?, now: Date) -> [AgentEvent] {
        names = layout?.names ?? [:]
        return agents.keys.sorted().flatMap { refresh($0, now: now) }
    }

    private mutating func change(_ address: String, now: Date, _ body: (inout HcTerminal) -> Void) -> [AgentEvent] {
        guard var terminal = terminals[address] else { return [] }
        body(&terminal)
        terminals[address] = terminal
        return refresh(address, now: now)
    }

    /// Recomputes one agent from its terminal and reports the difference.
    private mutating func refresh(_ address: String, now: Date) -> [AgentEvent] {
        let old = agents[address]
        let new = terminals[address].flatMap { info(for: $0, previous: old, now: now) }
        agents[address] = new
        switch (old, new) {
        case (nil, nil):
            return []
        case (let old?, nil):
            return [.removed(old.ref)]
        case (let old, let new?):
            guard new != old else { return [] }
            return [.upserted(new)] + (Self.finishesTurn(old?.status, new.status) ? [.turnFinished(new.ref)] : [])
        }
    }

    private func info(for terminal: HcTerminal, previous: AgentInfo?, now: Date) -> AgentInfo? {
        guard terminal.state == "live", let report = terminal.status else { return nil }
        var info = previous ?? AgentInfo(
            ref: AgentRef(adapter: adapter, localID: terminal.address), kind: .other("agent"), status: .starting, changedAt: now
        )
        if let app = report.app, !app.isEmpty { info.kind = AgentKind(name: app) }
        let status = Self.status(report, turn: terminal.turn, seen: terminal.seenTurn, previous: info.status)
        if status != info.status {
            info.status = status
            info.changedAt = now
        }
        if let title = terminal.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty { info.title = title }
        if let cwd = terminal.foregroundCwd ?? terminal.cwd, !cwd.isEmpty { info.cwd = URL(fileURLWithPath: cwd, isDirectory: true) }
        info.name = names[terminal.address]
        if info.kind == .claude, let pid = terminal.foregroundPID, let session = sessionID(pid) { info.sessionID = session }
        return info
    }

    static func status(_ report: HcStatus, turn: Int, seen: Int?, previous: AgentStatus) -> AgentStatus {
        switch report.state {
        case "working": return .working
        case "blocked": return .blocked
        case "idle": return .idle
        case "error": return .error(report.msg.flatMap { $0.isEmpty ? nil : $0 })
        case "done":
            if let seen, seen >= turn { return .idle }
            return .done
        default: return previous == .starting ? .idle : previous
        }
    }

    static func finishesTurn(_ old: AgentStatus?, _ new: AgentStatus) -> Bool {
        old == .working && (new == .done || new == .idle)
    }
}
