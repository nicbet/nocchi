import Foundation

/// A pane as Herdr reports it, in `session.snapshot` (`panes[]`, `agents[]`) and pane events.
/// Only the fields nocchi uses.
public struct HerdrPane: Decodable, Hashable, Sendable {
    public var paneID: String
    public var workspaceID: String?
    public var tabID: String?
    /// The agent kind ("claude", "codex", …). Empty while a launch is pending.
    public var agent: String?
    /// "idle", "working", "blocked", "done" or "unknown".
    public var agentStatus: String?
    public var cwd: String?
    public var title: String?
    public var sessionID: String?
    public var focused: Bool?

    public init(
        paneID: String, workspaceID: String? = nil, tabID: String? = nil, agent: String? = nil, agentStatus: String? = nil,
        cwd: String? = nil, title: String? = nil, sessionID: String? = nil, focused: Bool? = nil
    ) {
        self.paneID = paneID
        self.workspaceID = workspaceID
        self.tabID = tabID
        self.agent = agent
        self.agentStatus = agentStatus
        self.cwd = cwd
        self.title = title
        self.sessionID = sessionID
        self.focused = focused
    }

    private enum CodingKeys: String, CodingKey {
        case paneID = "pane_id", workspaceID = "workspace_id", tabID = "tab_id", agent
        case agentStatus = "agent_status", cwd, title = "terminal_title_stripped", session = "agent_session", focused
    }

    private struct Session: Decodable { var value: String? }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        paneID = try c.decode(String.self, forKey: .paneID)
        workspaceID = try c.decodeIfPresent(String.self, forKey: .workspaceID)
        tabID = try c.decodeIfPresent(String.self, forKey: .tabID)
        agent = try c.decodeIfPresent(String.self, forKey: .agent)
        agentStatus = try c.decodeIfPresent(String.self, forKey: .agentStatus)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        sessionID = try c.decodeIfPresent(Session.self, forKey: .session)?.value
        focused = try c.decodeIfPresent(Bool.self, forKey: .focused)
    }
}

/// `session.snapshot` → `result.snapshot`.
public struct HerdrSnapshot: Decodable, Hashable, Sendable {
    public var focusedPaneID: String?
    /// Every pane that runs, or is launching, an agent. A pending launch is listed here before
    /// its `agent` is known.
    public var agents: [HerdrPane]
    public var tabs: [Tab]
    /// Workspace labels: Herdr's window title is "host: workspace", so they find the window.
    public var workspaces: [Workspace]

    public struct Workspace: Decodable, Hashable, Sendable {
        public var workspaceID: String
        public var label: String?
        private enum CodingKeys: String, CodingKey { case workspaceID = "workspace_id", label }
        public init(workspaceID: String, label: String?) {
            self.workspaceID = workspaceID
            self.label = label
        }
    }

    public struct Tab: Decodable, Hashable, Sendable {
        public var tabID: String
        public var label: String?
        private enum CodingKeys: String, CodingKey { case tabID = "tab_id", label }
        public init(tabID: String, label: String?) {
            self.tabID = tabID
            self.label = label
        }
    }

    public init(focusedPaneID: String? = nil, agents: [HerdrPane], tabs: [Tab] = [], workspaces: [Workspace] = []) {
        self.focusedPaneID = focusedPaneID
        self.agents = agents
        self.tabs = tabs
        self.workspaces = workspaces
    }

    private enum CodingKeys: String, CodingKey { case focusedPaneID = "focused_pane_id", agents, tabs, workspaces }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        focusedPaneID = try c.decodeIfPresent(String.self, forKey: .focusedPaneID)
        agents = try c.decodeIfPresent([HerdrPane].self, forKey: .agents) ?? []
        tabs = try c.decodeIfPresent([Tab].self, forKey: .tabs) ?? []
        workspaces = try c.decodeIfPresent([Workspace].self, forKey: .workspaces) ?? []
    }
}

/// A Herdr event nocchi cares about.
public enum HerdrEvent: Hashable, Sendable {
    case statusChanged(pane: String, agent: String?, status: String, title: String?)
    case paneCreated(HerdrPane)
    /// Title, cwd or status changed.
    case paneUpdated(HerdrPane)
    /// Closed or exited.
    case paneRemoved(String)
    case agentDetected(pane: String, agent: String?)
    case paneFocused(String)
    case tabRenamed(tab: String, label: String)

    /// Decodes one `{"event", "data"}` line. Per-pane subscriptions use dotted names with flat
    /// data (`pane.agent_status_changed`); global ones use underscored names, with pane info
    /// either flat or nested under `data.pane`. Both shapes are accepted for every event.
    /// Returns `nil` for acks, unknown events and malformed lines.
    public static func decode(_ line: Data) -> HerdrEvent? {
        struct Envelope: Decodable { var event: String; var data: Payload }
        struct Payload: Decodable {
            var pane_id: String?
            var agent: String?
            var agent_status: String?
            var title: String?
            var tab_id: String?
            var label: String?
            var pane: HerdrPane?
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: line) else { return nil }
        let data = envelope.data
        let paneID = data.pane_id ?? data.pane?.paneID
        switch envelope.event.replacingOccurrences(of: ".", with: "_") {
        case "pane_agent_status_changed":
            guard let paneID, let status = data.agent_status ?? data.pane?.agentStatus else { return nil }
            return .statusChanged(pane: paneID, agent: data.agent ?? data.pane?.agent, status: status, title: data.title ?? data.pane?.title)
        case "pane_created":
            guard let paneID else { return nil }
            return .paneCreated(data.pane ?? HerdrPane(paneID: paneID))
        case "pane_updated":
            guard let paneID else { return nil }
            return .paneUpdated(data.pane ?? HerdrPane(paneID: paneID, agent: data.agent, agentStatus: data.agent_status, title: data.title))
        case "pane_closed", "pane_exited":
            return paneID.map(HerdrEvent.paneRemoved)
        case "pane_agent_detected":
            return paneID.map { .agentDetected(pane: $0, agent: data.agent ?? data.pane?.agent) }
        case "pane_focused":
            return paneID.map(HerdrEvent.paneFocused)
        case "tab_renamed":
            guard let tab = data.tab_id, let label = data.label else { return nil }
            return .tabRenamed(tab: tab, label: label)
        default:
            return nil
        }
    }
}
