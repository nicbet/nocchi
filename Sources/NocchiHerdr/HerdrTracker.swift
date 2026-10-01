import Foundation
import NocchiCore

/// Turns Herdr snapshots and events into clean `AgentEvent`s. Pure, so every Herdr quirk is
/// covered by fixture tests:
/// - `unknown` keeps the previous status (it doesn't mean finished).
/// - A pending launch (listed in `agents[]`, `agent` still empty) is `.starting`, not gone.
/// - A turn that finishes in the focused pane goes `working → idle` without `done`, so any
///   `working → done|idle` emits `.turnFinished`.
/// - An empty title keeps the previous one.
struct HerdrTracker {
    let adapter: AdapterID
    private(set) var agents: [String: AgentInfo] = [:]
    private var tabLabels: [String: String] = [:]
    private var paneTabs: [String: String] = [:]

    init(adapter: AdapterID) { self.adapter = adapter }

    /// The panes whose status changes we must subscribe to.
    var agentPanes: Set<String> { Set(agents.keys) }

    struct Output: Equatable {
        var events: [AgentEvent] = []
        /// The set of agents may have changed in a way only a fresh snapshot can tell.
        var needsReconcile = false
    }

    /// Replaces everything with `snapshot`. Returns `.snapshot` plus `.turnFinished` for turns
    /// that finished since the last state we saw (a missed event, or a reconnect).
    mutating func apply(_ snapshot: HerdrSnapshot, now: Date) -> [AgentEvent] {
        for tab in snapshot.tabs { tabLabels[tab.tabID] = tab.label }
        var next: [String: AgentInfo] = [:]
        var finished: [AgentEvent] = []
        for pane in snapshot.agents {
            let old = agents[pane.paneID]
            if let tab = pane.tabID { paneTabs[pane.paneID] = tab }
            var info = old ?? AgentInfo(ref: ref(pane.paneID), kind: .other("agent"), status: .starting, changedAt: now)
            update(&info, from: pane, now: now)
            info.isFocused = snapshot.focusedPaneID.map { $0 == pane.paneID } ?? pane.focused ?? false
            if Self.finishesTurn(old?.status, info.status) { finished.append(.turnFinished(info.ref)) }
            next[pane.paneID] = info
        }
        agents = next
        paneTabs = paneTabs.filter { next[$0.key] != nil }
        return [.snapshot(next.values.sorted { $0.ref.localID < $1.ref.localID })] + finished
    }

    mutating func apply(_ event: HerdrEvent, now: Date) -> Output {
        var out = Output()
        switch event {
        case .statusChanged(let pane, let agent, let status, let title):
            guard agents[pane] != nil, let agent, !agent.isEmpty else {
                // A new agent, or the agent left its pane: only a snapshot can tell.
                out.needsReconcile = true
                break
            }
            var info = agents[pane]!
            update(&info, from: HerdrPane(paneID: pane, agent: agent, agentStatus: status, title: title), now: now)
            out.events = commit(info)

        case .paneUpdated(let info):
            guard var agent = agents[info.paneID] else {
                if let kind = info.agent, !kind.isEmpty { out.needsReconcile = true }
                break
            }
            if let tab = info.tabID { paneTabs[info.paneID] = tab }
            update(&agent, from: info, now: now)
            out.events = commit(agent)

        case .paneCreated, .agentDetected:
            out.needsReconcile = true

        case .paneRemoved(let pane):
            guard let info = agents.removeValue(forKey: pane) else { break }
            paneTabs[pane] = nil
            out.events = [.removed(info.ref)]

        case .paneFocused(let pane):
            for var info in agents.values.sorted(by: { $0.ref.localID < $1.ref.localID }) {
                info.isFocused = info.ref.localID == pane
                out.events += commit(info)
            }

        case .tabRenamed(let tab, let label):
            tabLabels[tab] = label
            for (pane, paneTab) in paneTabs.sorted(by: { $0.key < $1.key }) where paneTab == tab {
                guard var info = agents[pane] else { continue }
                info.name = Self.name(fromTab: label)
                out.events += commit(info)
            }
        }
        return out
    }

    /// Stores an updated agent and reports the change, if any.
    private mutating func commit(_ info: AgentInfo) -> [AgentEvent] {
        guard let old = agents[info.ref.localID], info != old else { return [] }
        agents[info.ref.localID] = info
        var events: [AgentEvent] = [.upserted(info)]
        if Self.finishesTurn(old.status, info.status) { events.append(.turnFinished(info.ref)) }
        return events
    }

    private func update(_ info: inout AgentInfo, from pane: HerdrPane, now: Date) {
        if let agent = pane.agent, !agent.isEmpty { info.kind = AgentKind(name: agent) }
        let status = Self.status(pane.agentStatus, agent: pane.agent, previous: info.status)
        if status != info.status {
            info.status = status
            info.changedAt = now
        }
        if let title = pane.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty { info.title = title }
        if let cwd = pane.cwd, !cwd.isEmpty { info.cwd = URL(fileURLWithPath: cwd, isDirectory: true) }
        if let session = pane.sessionID, !session.isEmpty { info.sessionID = session }
        if let tab = pane.tabID ?? paneTabs[pane.paneID] { info.name = tabLabels[tab].flatMap(Self.name(fromTab:)) }
    }

    private func ref(_ pane: String) -> AgentRef { AgentRef(adapter: adapter, localID: pane) }

    /// `agent` is nil when the event doesn't say; empty while a launch is pending.
    static func status(_ raw: String?, agent: String?, previous: AgentStatus) -> AgentStatus {
        if agent?.isEmpty == true { return .starting }
        switch raw {
        case "working": return .working
        case "blocked": return .blocked
        case "done": return .done
        case "idle": return .idle
        default: return previous == .starting && agent != nil ? .idle : previous
        }
    }

    static func finishesTurn(_ old: AgentStatus?, _ new: AgentStatus) -> Bool {
        old == .working && (new == .done || new == .idle)
    }

    /// Herdr numbers unnamed tabs ("1", "2"); those aren't names.
    static func name(fromTab label: String) -> String? {
        let label = label.trimmingCharacters(in: .whitespaces)
        return label.isEmpty || label.allSatisfy(\.isNumber) ? nil : label
    }
}
