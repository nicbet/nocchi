import Foundation
import NocchiCore

/// One Claude Code hook call, parsed: what happened, to which session, and where it runs.
public struct ClaudeHookEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case sessionStart
        case promptSubmitted
        case toolUsed
        /// Claude asks for approval or an answer.
        case needsInput
        /// Claude has been waiting for input a while (`idle_prompt`).
        case idleReminder
        case stopped
        case failed(String?)
        case sessionEnd
        /// Ready for input with nothing to report (after an answered question or a declined request).
        case idle
        case other
    }

    public var kind: Kind
    public var sessionID: String
    public var cwd: String?
    public var transcriptPath: String?
    /// The `claude` process, when found.
    public var processID: Int32?
    /// The terminal app it runs in, and its tty.
    public var hostID: Int32?
    public var tty: String?
    /// Set when the session runs inside a Herdr pane.
    public var herdrPane: String?

    public init(
        kind: Kind, sessionID: String, cwd: String? = nil, transcriptPath: String? = nil,
        processID: Int32? = nil, hostID: Int32? = nil, tty: String? = nil, herdrPane: String? = nil
    ) {
        self.kind = kind
        self.sessionID = sessionID
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.processID = processID
        self.hostID = hostID
        self.tty = tty
        self.herdrPane = herdrPane
    }

    /// Parses a hook's JSON input. Nil when it has no session.
    public static func parse(_ input: Data) -> ClaudeHookEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
              let session = object["session_id"] as? String, !session.isEmpty else { return nil }
        let name = object["hook_event_name"] as? String ?? ""
        let kind: Kind
        switch name {
        case "SessionStart": kind = .sessionStart
        case "UserPromptSubmit": kind = .promptSubmitted
        case "PreToolUse", "PostToolUse", "PostToolUseFailure": kind = .toolUsed
        case "PermissionRequest": kind = .needsInput
        case "Notification":
            switch object["notification_type"] as? String {
            case "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input": kind = .needsInput
            case "idle_prompt": kind = .idleReminder
            default: kind = .other
            }
        case "Stop": kind = .stopped
        case "StopFailure":
            kind = .failed((object["error"] as? String) ?? (object["reason"] as? String) ?? (object["source"] as? String))
        case "SessionEnd": kind = .sessionEnd
        default: kind = .other
        }
        return ClaudeHookEvent(kind: kind, sessionID: session, cwd: object["cwd"] as? String,
                               transcriptPath: object["transcript_path"] as? String)
    }
}

/// Claude Code sessions as `AgentEvent`s, from two sources. Pure, so the lifecycle is covered by
/// tests.
/// - **Registry** (`~/.claude/sessions`, polled): which sessions run, where, busy or idle. Only its
///   *changes* count (busy → idle finishes a turn), so a poll never overwrites a hook's fresher news.
/// - **Hooks** (optional): prompt or tool use → working; a permission request or question → blocked;
///   `Stop` → done; `StopFailure` → error; `SessionEnd` → gone.
/// A finished turn stays done until seen (its terminal comes to the front). Sessions inside a Herdr
/// pane are left to the Herdr adapter when `leavesHerdrToHerdr` is set.
public struct ClaudeSessionTracker: Sendable {
    public let adapter: AdapterID
    public var leavesHerdrToHerdr: Bool
    public private(set) var agents: [String: AgentInfo] = [:]
    /// Per session: the `claude` process and the terminal app hosting it.
    public private(set) var processes: [String: Int32] = [:]
    public private(set) var hosts: [String: Int32] = [:]
    /// The registry status last seen per session, to act on changes only.
    private var registryStatus: [String: String] = [:]
    /// Sessions that have sent a hook: from then on hooks alone set their status (they're instant
    /// and exact), and registry polls only keep them present. One authority per session, so a
    /// late poll can't undo fresher news.
    public private(set) var hooked: Set<String> = []

    public init(adapter: AdapterID = "claude", leavesHerdrToHerdr: Bool = true) {
        self.adapter = adapter
        self.leavesHerdrToHerdr = leavesHerdrToHerdr
    }

    /// A hook call. Makes hooks the status authority for this session.
    public mutating func apply(_ event: ClaudeHookEvent, now: Date) -> [AgentEvent] {
        if leavesHerdrToHerdr, event.herdrPane != nil { return [] }
        hooked.insert(event.sessionID)
        return update(event, now: now)
    }

    private mutating func update(_ event: ClaudeHookEvent, now: Date) -> [AgentEvent] {
        let id = event.sessionID
        if event.kind == .sessionEnd {
            return remove(id)
        }
        var info = agents[id] ?? AgentInfo(
            ref: AgentRef(adapter: adapter, localID: id), kind: .claude, status: .idle,
            sessionID: id, changedAt: now
        )
        if let cwd = event.cwd, !cwd.isEmpty { info.cwd = URL(fileURLWithPath: cwd, isDirectory: true) }
        if let pid = event.processID { processes[id] = pid }
        if let host = event.hostID { hosts[id] = host }

        let old = agents[id]?.status
        var status = info.status
        switch event.kind {
        case .sessionStart: status = old ?? .idle
        case .promptSubmitted, .toolUsed: status = .working
        case .needsInput: status = .blocked
        case .stopped: status = .done
        case .failed(let reason): status = .error(reason)
        case .idle: status = .idle
        case .idleReminder, .other: break
        case .sessionEnd: break
        }
        if status != info.status || agents[id] == nil {
            info.status = status
            info.changedAt = now
        }
        guard info != agents[id] else { return [] }
        agents[id] = info
        var events: [AgentEvent] = [.upserted(info)]
        if old == .working, status == .done { events.append(.turnFinished(info.ref)) }
        return events
    }

    /// One poll of the registry. `context` says, per pid, whether it runs inside Herdr and which
    /// terminal app and tty host it (looked up by the caller; nil while unknown).
    public mutating func applyRegistry(
        _ entries: [ClaudeRegistryEntry], context: [Int32: (insideHerdr: Bool, host: Int32?, tty: String?)], now: Date
    ) -> [AgentEvent] {
        var events: [AgentEvent] = []
        var live: Set<String> = []
        for entry in entries {
            let where_ = context[entry.pid]
            if leavesHerdrToHerdr, where_?.insideHerdr == true { continue }
            live.insert(entry.sessionID)
            let previous = registryStatus[entry.sessionID]
            registryStatus[entry.sessionID] = entry.status
            var hook = ClaudeHookEvent(kind: .other, sessionID: entry.sessionID, cwd: entry.cwd,
                                       processID: entry.pid, hostID: where_?.host, tty: where_?.tty)
            // Claude's statuses: "busy", "shell" (running a command), "waiting" (a permission
            // prompt or a question, see `waitingFor`), "idle". Every change counts.
            if entry.status != previous, !hooked.contains(entry.sessionID) {
                switch entry.status {
                case "busy", "shell": hook.kind = .promptSubmitted
                case "waiting", "needs_input", "blocked": hook.kind = .needsInput
                case "idle" where previous == "busy" || previous == "shell": hook.kind = .stopped
                case "idle" where previous != nil: hook.kind = .idle
                default: break
                }
            }
            events += update(hook, now: now)
        }
        // Gone from the registry: the process exited.
        for id in agents.keys.sorted() where !live.contains(id) && processes[id] != nil {
            registryStatus[id] = nil
            events += remove(id)
        }
        return events
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

    /// Drops sessions whose process is gone (a crash or a closed terminal skips `SessionEnd`).
    public mutating func keepAlive(_ isAlive: (Int32) -> Bool) -> [AgentEvent] {
        processes.filter { !isAlive($0.value) }.keys.sorted().flatMap { remove($0) }
    }

    /// Everything, for a `.snapshot`.
    public var snapshot: [AgentInfo] { agents.values.sorted { $0.ref.localID < $1.ref.localID } }

    private mutating func remove(_ id: String) -> [AgentEvent] {
        processes[id] = nil
        registryStatus[id] = nil
        hooked.remove(id)
        hosts[id] = nil
        guard let info = agents.removeValue(forKey: id) else { return [] }
        return [.removed(info.ref)]
    }
}
