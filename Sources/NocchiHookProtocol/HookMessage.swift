import Foundation

/// One hook invocation, as `nocchi-hook` forwards it to the app over a Unix socket: a single JSON
/// line per connection, no reply.
public struct HookMessage: Codable, Hashable, Sendable {
    /// Bumped on incompatible changes; the app ignores versions it doesn't know.
    public static let currentVersion = 1

    public var version: Int
    /// "claude" or "codex": which agent's hook ran.
    public var agent: String
    /// The process that ran the hook (the agent itself, or a shell it started).
    public var parentPID: Int32
    /// Environment the agent runs in, as far as nocchi cares: `HERDR_PANE_ID`, `TERM_PROGRAM`,
    /// `ITERM_SESSION_ID`, `TERM_SESSION_ID`, `TMUX`.
    public var environment: [String: String]
    /// The hook's JSON input, as the agent wrote it to stdin (large tool payloads removed).
    public var input: Data

    public init(agent: String, parentPID: Int32, environment: [String: String], input: Data) {
        version = Self.currentVersion
        self.agent = agent
        self.parentPID = parentPID
        self.environment = environment
        self.input = input
    }

    /// The environment variables worth forwarding.
    public static let environmentKeys = ["HERDR_PANE_ID", "HERDR_ENV", "TERM_PROGRAM", "ITERM_SESSION_ID", "TERM_SESSION_ID", "TMUX"]

    /// Where the app listens. Short enough for the 104-byte socket path limit.
    public static func socketPath(home: String = NSHomeDirectory()) -> String {
        home + "/Library/Application Support/nocchi/hook.sock"
    }

    /// Hook inputs bigger than this lose their tool payloads (a `Write` carries the whole file).
    public static let maxInputBytes = 64 * 1024
}
