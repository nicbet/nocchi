import Foundation
import NocchiCore

/// Turns Herdr snapshots and events into clean `AgentEvent`s. Pure, so every Herdr quirk is
/// covered by fixture tests:
/// - `unknown` keeps the previous status (it doesn't mean finished).
/// - A pending launch (listed in `agents[]`, `agent` still empty) is `.starting`, not gone.
/// - A turn that finishes in the focused pane goes `working → idle` without `done`, so any
///   `working → done|idle` emits `.turnFinished`.
/// - An empty title keeps the previous one.
/// - Herdr counts a focused pane as seen even when its terminal is behind other apps. A turn that
///   finishes then, or a `done` cleared then, stays `.done` here ("unread") until the user can
///   actually have seen it: see `unread`.
struct HerdrTracker {
    let adapter: AdapterID
    private(set) var agents: [String: AgentInfo] = [:]
    /// Whether the terminal app running Herdr is frontmost. Assumed true when unknown, which is
    /// plain Herdr behavior.
    private(set) var terminalFrontmost = true
    /// Panes Herdr reports `idle` that nocchi still shows `.done`: their turn ended (or their
    /// `done` was cleared) while the terminal was in the background. A narrow overlay on Herdr:
    /// it only turns `idle` into `.done`, and ends when the user looks at the pane (terminal
    /// frontmost with the pane focused), when Herdr reports any other state, or when the pane goes.
    private(set) var unread: Set<String> = []
    private var tabLabels: [String: String] = [:]
    private var workspaceLabels: [String: String] = [:]
    private var paneWorkspaces: [String: String] = [:]
    private var paneTabs: [String: String] = [:]
    /// The terminal app running the Herdr client, when looked up (see `setHost`).
    private(set) var hostPID: Int32?

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
        for workspace in snapshot.workspaces { workspaceLabels[workspace.workspaceID] = workspace.label }
        var next: [String: AgentInfo] = [:]
        var finished: [AgentEvent] = []
        for pane in snapshot.agents {
            let old = agents[pane.paneID]
            if let tab = pane.tabID { paneTabs[pane.paneID] = tab }
            if let workspace = pane.workspaceID { paneWorkspaces[pane.paneID] = workspace }
            var info = old ?? AgentInfo(ref: ref(pane.paneID), kind: .other("agent"), status: .starting, changedAt: now)
            info.isFocused = snapshot.focusedPaneID.map { $0 == pane.paneID } ?? pane.focused ?? false
            update(&info, from: pane, now: now)
            info = withHost(info)
            if Self.finishesTurn(old?.status, info.status) { finished.append(.turnFinished(info.ref)) }
            next[pane.paneID] = info
        }
        agents = next
        paneTabs = paneTabs.filter { next[$0.key] != nil }
        unread.formIntersection(next.keys)
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
            out.events = commit(withHost(info))

        case .paneUpdated(let info):
            guard var agent = agents[info.paneID] else {
                if let kind = info.agent, !kind.isEmpty { out.needsReconcile = true }
                break
            }
            if let tab = info.tabID { paneTabs[info.paneID] = tab }
            if let workspace = info.workspaceID { paneWorkspaces[info.paneID] = workspace }
            update(&agent, from: info, now: now)
            out.events = commit(withHost(agent))

        case .paneCreated, .agentDetected:
            out.needsReconcile = true

        case .paneRemoved(let pane):
            guard let info = agents.removeValue(forKey: pane) else { break }
            paneTabs[pane] = nil
            unread.remove(pane)
            out.events = [.removed(info.ref)]

        case .paneFocused(let pane):
            for var info in agents.values.sorted(by: { $0.ref.localID < $1.ref.localID }) {
                info.isFocused = info.ref.localID == pane
                if info.isFocused { markSeen(&info, now: now) }
                out.events += commit(info)
            }

        case .tabRenamed(let tab, let label):
            tabLabels[tab] = label
            for (pane, paneTab) in paneTabs.sorted(by: { $0.key < $1.key }) where paneTab == tab {
                guard var info = agents[pane] else { continue }
                info.name = Self.name(fromTab: label)
                out.events += commit(withHost(info))
            }
        }
        return out
    }

    /// The terminal app running Herdr's client was found (nil: none, e.g. inside tmux or over
    /// SSH). Every agent's `host` follows.
    mutating func setHost(_ pid: Int32?) -> [AgentEvent] {
        hostPID = pid
        var events: [AgentEvent] = []
        for info in agents.values.sorted(by: { $0.ref.localID < $1.ref.localID }) {
            events += commit(withHost(info))
        }
        return events
    }

    /// `info` with its host brought up to date: Herdr's terminal, and the pane's window hints
    /// (its title, tab or workspace may have just changed).
    private func withHost(_ info: AgentInfo) -> AgentInfo {
        var info = info
        info.host = hostPID.map { AgentHost(pid: $0, windowHints: windowHints(for: info.ref.localID, title: info.title)) }
        return info
    }

    /// The terminal running Herdr came to the front or went behind another app. Coming to the
    /// front, the focused pane is now really seen.
    mutating func setTerminalFrontmost(_ frontmost: Bool, now: Date) -> [AgentEvent] {
        terminalFrontmost = frontmost
        guard frontmost else { return [] }
        var events: [AgentEvent] = []
        for var info in agents.values.sorted(by: { $0.ref.localID < $1.ref.localID }) where info.isFocused {
            markSeen(&info, now: now)
            events += commit(info)
        }
        return events
    }

    /// Clears the unread overlay when the user can see the pane.
    private mutating func markSeen(_ info: inout AgentInfo, now: Date) {
        guard terminalFrontmost, unread.remove(info.ref.localID) != nil, info.status == .done else { return }
        info.status = .idle
        info.changedAt = now
    }

    /// Applies the unread overlay to the status Herdr reports. Only ever turns `idle` into `.done`.
    private mutating func overlay(_ pane: String, from old: AgentStatus, to new: AgentStatus) -> AgentStatus {
        guard new == .idle else {
            // Herdr knows better about every other state, including its own `done`.
            unread.remove(pane)
            return new
        }
        if unread.contains(pane) { return .done }
        // Finished, or marked seen, while the terminal is behind another app: not really seen.
        if !terminalFrontmost, old == .working || old == .done {
            unread.insert(pane)
            return .done
        }
        return new
    }

    /// Stores an updated agent and reports the change, if any.
    private mutating func commit(_ info: AgentInfo) -> [AgentEvent] {
        guard let old = agents[info.ref.localID], info != old else { return [] }
        agents[info.ref.localID] = info
        var events: [AgentEvent] = [.upserted(info)]
        if Self.finishesTurn(old.status, info.status) { events.append(.turnFinished(info.ref)) }
        return events
    }

    private mutating func update(_ info: inout AgentInfo, from pane: HerdrPane, now: Date) {
        if let agent = pane.agent, !agent.isEmpty { info.kind = AgentKind(name: agent) }
        let reported = Self.status(pane.agentStatus, agent: pane.agent, previous: info.status)
        var status = overlay(pane.paneID, from: info.status, to: reported)
        // Unread, but the user is looking at it right now.
        if status == .done, reported == .idle, info.isFocused, terminalFrontmost {
            unread.remove(pane.paneID)
            status = .idle
        }
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
    /// What finds the agent's terminal window: Herdr titles it "host: workspace", so the workspace
    /// label first, then the tab and the agent's title.
    func windowHints(for pane: String) -> [String] {
        windowHints(for: pane, title: agents[pane]?.title)
    }

    private func windowHints(for pane: String, title: String?) -> [String] {
        [paneWorkspaces[pane].flatMap { workspaceLabels[$0] },
         paneTabs[pane].flatMap { tabLabels[$0] },
         title].compactMap { $0 }.filter { !$0.isEmpty }
    }

    static func name(fromTab label: String) -> String? {
        let label = label.trimmingCharacters(in: .whitespaces)
        return label.isEmpty || label.allSatisfy(\.isNumber) ? nil : label
    }
}
