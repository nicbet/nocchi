import Foundation

/// Identifies an adapter ("herdr", "mock", later "claude", "codex").
public struct AdapterID: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public var description: String { rawValue }
}

/// Identifies one agent within one adapter (Herdr: the pane ID).
public struct AgentRef: Hashable, Sendable, CustomStringConvertible {
    public let adapter: AdapterID
    public let localID: String
    public init(adapter: AdapterID, localID: String) {
        self.adapter = adapter
        self.localID = localID
    }
    public var description: String { "\(adapter)/\(localID)" }
}

/// Which coding agent is running.
public enum AgentKind: Hashable, Sendable {
    case claude, codex, pi, opencode, copilot
    case other(String)

    public init(name: String) {
        switch name.lowercased() {
        case "claude", "claude-code": self = .claude
        case "codex": self = .codex
        case "pi": self = .pi
        case "opencode": self = .opencode
        case "copilot": self = .copilot
        default: self = .other(name)
        }
    }

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .pi: "pi"
        case .opencode: "OpenCode"
        case .copilot: "Copilot"
        case .other(let name): name
        }
    }
}

/// Normalized agent status. Every adapter maps its source's states onto these.
public enum AgentStatus: Hashable, Sendable {
    /// Launched, not ready for input yet.
    case starting
    /// Ready, nothing to report.
    case idle
    /// Working on a turn but not using tools (only adapters with `.thinking`).
    case thinking
    /// Working on a turn.
    case working
    /// Waiting for the user: an approval or a question.
    case blocked
    /// Finished a turn the user hasn't looked at yet.
    case done
    /// Failed (only adapters with `.errors`).
    case error(String?)
}

/// Everything the UI needs to know about one agent.
public struct AgentInfo: Hashable, Sendable {
    public var ref: AgentRef
    public var kind: AgentKind
    public var status: AgentStatus
    /// Short label for the agent, e.g. the project or tab name. See `displayName`.
    public var name: String?
    /// Short summary of the current task, shown in the step carousel.
    public var title: String?
    public var cwd: URL?
    /// Claude/Codex session ID, used to merge the same agent from several adapters.
    public var sessionID: String?
    public var isFocused: Bool
    /// When `status` last changed.
    public var changedAt: Date

    public init(
        ref: AgentRef, kind: AgentKind, status: AgentStatus, name: String? = nil, title: String? = nil,
        cwd: URL? = nil, sessionID: String? = nil, isFocused: Bool = false, changedAt: Date
    ) {
        self.ref = ref
        self.kind = kind
        self.status = status
        self.name = name
        self.title = title
        self.cwd = cwd
        self.sessionID = sessionID
        self.isFocused = isFocused
        self.changedAt = changedAt
    }

    /// The name, else the working folder's name, else the agent kind.
    public var displayName: String {
        if let name, !name.isEmpty { return name }
        if let folder = cwd?.lastPathComponent, !folder.isEmpty, folder != "/" { return folder }
        return kind.displayName
    }
}

public enum ConnectionState: Hashable, Sendable {
    case connecting
    case connected(version: String?)
    case unavailable(reason: String)
}

/// What an adapter reports. The stream must start with `.connection` then `.snapshot`, and
/// re-send `.snapshot` after every reconnect.
public enum AgentEvent: Hashable, Sendable {
    case connection(ConnectionState)
    /// Authoritative full set of this adapter's agents.
    case snapshot([AgentInfo])
    case upserted(AgentInfo)
    case removed(AgentRef)
    /// A turn finished. Drives the celebration even when the status skips `done`.
    case turnFinished(AgentRef)
    /// Fine-grained progress ("Editing Model.swift"), for adapters with `.steps`.
    case step(AgentRef, String)
    /// The agent's latest message to the user: its answer when a turn ends, or its question when
    /// it needs you (adapters with `.steps`).
    case message(AgentRef, String)
}

public enum AgentAction: Hashable, Sendable {
    /// Switch the source to this agent (Herdr: focus its pane).
    case focus(AgentRef)
    /// Focus the agent and bring the app it runs in to the front.
    case open(AgentRef)
    case prompt(AgentRef, String)
    /// Starts an agent in `cwd`, and gives it `prompt` as its first message when there is one.
    case start(kind: AgentKind, cwd: URL, prompt: String? = nil)

    public var requiredCapability: AdapterCapabilities {
        switch self {
        case .focus, .open: .focus
        case .prompt: .prompt
        case .start: .start
        }
    }
}

public struct AdapterCapabilities: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let focus = AdapterCapabilities(rawValue: 1 << 0)
    public static let prompt = AdapterCapabilities(rawValue: 1 << 1)
    public static let start = AdapterCapabilities(rawValue: 1 << 2)
    /// Emits `.step` events.
    public static let steps = AdapterCapabilities(rawValue: 1 << 3)
    /// Distinguishes `.thinking` from `.working`.
    public static let thinking = AdapterCapabilities(rawValue: 1 << 4)
    /// Reports `.error`.
    public static let errors = AdapterCapabilities(rawValue: 1 << 5)

    public static let all: AdapterCapabilities = [.focus, .prompt, .start, .steps, .thinking, .errors]
}

public enum AgentActionError: Error, Equatable {
    /// The adapter lacks the capability the action needs.
    case unsupported(AgentAction)
    /// The target agent isn't known to the adapter.
    case unknownAgent(AgentRef)
    case failed(String)
}

/// A source of agents: Herdr, a mock, later Claude Code or Codex directly.
/// Only adapters know about their source; the store and UI only see the types above.
public protocol AgentAdapter: AnyObject, Sendable {
    var id: AdapterID { get }
    var capabilities: AdapterCapabilities { get }

    /// Starts on first iteration, stops when the consumer cancels.
    func events() -> AsyncStream<AgentEvent>

    /// Throws `AgentActionError.unsupported` if the capability is missing. For `.start`, returns
    /// the new agent when the adapter knows it (it may not have reported it yet).
    @discardableResult
    func perform(_ action: AgentAction) async throws -> AgentRef?
}
