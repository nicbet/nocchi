import Foundation
import NocchiCore
import OSLog
import Synchronization

let herdrLog = Logger(subsystem: "com.github.nicbet.nocchi", category: "herdr")

/// Agents from Herdr. Each `events()` stream runs its own sync loop:
/// snapshot → subscribe to the agent panes → apply events; re-snapshot every 30 s and whenever
/// the set of agents may have changed (opening the new subscription before closing the old one);
/// reconnect with 1 s → 10 s backoff, and only clear the agents after 3 failed attempts in a row.
public final class HerdrAdapter: AgentAdapter {
    public let id: AdapterID
    public let capabilities: AdapterCapabilities
    public let client: HerdrClient

    public struct Timing: Sendable {
        public var reconcile: Duration = .seconds(30)
        public var minBackoff: Duration = .seconds(1)
        public var maxBackoff: Duration = .seconds(10)
        public var missesBeforeClearing = 3
        /// How long a first message retries `agent_not_ready` while a new agent starts (kinds
        /// whose command doesn't take the message as an argument).
        public var startRetryWindow: Duration = .seconds(15)
        public var retryInterval: Duration = .milliseconds(250)
        public init() {}
    }
    public let timing: Timing
    /// Watch whether the terminal hosting Herdr is frontmost, so a turn that ends while it's
    /// behind other apps stays done until seen. Off in tests: plain Herdr behavior.
    public let watchesTerminal: Bool

    /// Last known status per pane, for refusing prompts to blocked agents.
    private let statuses = Mutex<[String: AgentStatus]>([:])
    /// Per pane: what finds its terminal window (see `HerdrTracker.windowHints`).
    private let windowHints = Mutex<[String: [String]]>([:])
    /// The command that runs an agent kind. Tests swap in a script.
    let agentCommand: @Sendable (AgentKind) -> String

    public init(
        client: HerdrClient, id: AdapterID = "herdr",
        capabilities: AdapterCapabilities = [.focus, .prompt, .start], timing: Timing = Timing(),
        watchesTerminal: Bool = false, agentCommand: @escaping @Sendable (AgentKind) -> String = HerdrAdapter.command(for:)
    ) {
        self.client = client
        self.agentCommand = agentCommand
        self.id = id
        self.capabilities = capabilities
        self.timing = timing
        self.watchesTerminal = watchesTerminal
    }

    public convenience init(socketPath: String = Herdr.socketPath(), watchesTerminal: Bool = false) {
        self.init(client: HerdrClient(socketPath: socketPath), watchesTerminal: watchesTerminal)
    }

    // MARK: Events

    public func events() -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            let task = Task { await self.sync(continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private enum Signal: Sendable {
        case event(HerdrEvent)
        case ended(generation: Int)
        case reconcile
        case terminal(frontmost: Bool)
    }

    private func sync(_ out: AsyncStream<AgentEvent>.Continuation) async {
        var tracker = HerdrTracker(adapter: id)
        var connected = false   // last reported connection state
        var reported = false    // reported any connection state yet
        var misses = 0
        var backoff = timing.minBackoff

        while !Task.isCancelled {
            do {
                let pong = try await client.ping()
                let snapshot = try await client.snapshot()
                if !connected {
                    out.yield(.connection(.connected(version: pong.version)))
                    connected = true
                    reported = true
                }
                misses = 0
                backoff = timing.minBackoff
                publish(tracker.apply(snapshot, now: Date()), tracker, to: out)
                try await follow(&tracker, to: out)
            } catch {
                if Task.isCancelled { break }
                misses += 1
                // At launch there's nothing to keep, so say so right away. Once agents are on
                // screen, ride out short hiccups (a Herdr restart) without flicker.
                if !reported || (connected && misses >= timing.missesBeforeClearing) {
                    out.yield(.connection(.unavailable(reason: Self.reason(error))))
                    tracker = HerdrTracker(adapter: id)
                    publish([.snapshot([])], tracker, to: out)
                    connected = false
                    reported = true
                }
                try? await Task.sleep(for: backoff)
                backoff = min(backoff * 2, timing.maxBackoff)
            }
        }
        out.finish()
    }

    private func publish(_ events: [AgentEvent], _ tracker: HerdrTracker, to out: AsyncStream<AgentEvent>.Continuation) {
        let before = statuses.withLock { $0 }
        for event in events { out.yield(event) }
        // Status changes are logged, to trace states that look wrong (`log stream --predicate
        // 'subsystem == "com.github.nicbet.nocchi"'`).
        for (pane, info) in tracker.agents where before[pane] != info.status {
            herdrLog.info("status \(pane, privacy: .public): \(String(describing: before[pane]), privacy: .public) → \(String(describing: info.status), privacy: .public) via \(Self.describe(events), privacy: .public)")
        }
        statuses.withLock { $0 = tracker.agents.mapValues(\.status) }
        windowHints.withLock { hints in hints = Dictionary(uniqueKeysWithValues: tracker.agents.keys.map { ($0, tracker.windowHints(for: $0)) }) }
    }

    /// Follows events until the stream drops (throws) or the task is cancelled (returns).
    private func follow(_ tracker: inout HerdrTracker, to out: AsyncStream<AgentEvent>.Continuation) async throws {
        let (signals, sink) = AsyncStream.makeStream(of: Signal.self)
        var generation = 0
        var subscribed = tracker.agentPanes
        var stream = try await subscribe(&tracker, to: out, &subscribed)
        pump(stream, generation, into: sink)
        // Anything that changed while subscribing went unseen.
        sink.yield(.reconcile)

        let reconcileEvery = timing.reconcile
        let ticker = Task {
            while !Task.isCancelled {
                try await Task.sleep(for: reconcileEvery)
                sink.yield(.reconcile)
            }
        }
        let presence = Task { [watchesTerminal] in
            guard watchesTerminal else { return }
            for await frontmost in await HerdrTerminal.frontmostUpdates() { sink.yield(.terminal(frontmost: frontmost)) }
        }
        defer {
            presence.cancel()
            ticker.cancel()
            stream.close()
            sink.finish()
        }

        for await signal in signals {
            switch signal {
            case .event(let event):
                let output = tracker.apply(event, now: Date())
                publish(output.events, tracker, to: out)
                guard output.needsReconcile else { continue }
            case .ended(let ended):
                guard ended == generation else { continue }
                throw HerdrError.unavailable("event stream closed")
            case .reconcile:
                break
            case .terminal(let frontmost):
                herdrLog.info("terminal frontmost: \(frontmost, privacy: .public)")
                publish(tracker.setTerminalFrontmost(frontmost, now: Date()), tracker, to: out)
                continue
            }
            var snapshot = try await client.snapshot()
            publish(tracker.apply(snapshot, now: Date()), tracker, to: out)
            while tracker.agentPanes != subscribed {
                // Make before break: events keep flowing while we switch. Then look again, since
                // a new agent's status changes only arrive once its subscription is in place.
                let next = try await subscribe(&tracker, to: out, &subscribed)
                generation += 1
                pump(next, generation, into: sink)
                stream.close()
                stream = next
                snapshot = try await client.snapshot()
                publish(tracker.apply(snapshot, now: Date()), tracker, to: out)
            }
        }
    }

    /// Subscribes to the tracker's agent panes. A pane can vanish between the snapshot and the
    /// subscription (Herdr then rejects it), so re-snapshot and retry a few times.
    private func subscribe(
        _ tracker: inout HerdrTracker, to out: AsyncStream<AgentEvent>.Continuation, _ subscribed: inout Set<String>
    ) async throws -> HerdrEventStream {
        var attempt = 0
        while true {
            do {
                let stream = try await client.subscribe(agentPanes: tracker.agentPanes)
                subscribed = tracker.agentPanes
                return stream
            } catch let error as HerdrError where error.code == "pane_not_found" && attempt < 3 {
                attempt += 1
                let snapshot = try await client.snapshot()
                publish(tracker.apply(snapshot, now: Date()), tracker, to: out)
            }
        }
    }

    private func pump(_ stream: HerdrEventStream, _ generation: Int, into sink: AsyncStream<Signal>.Continuation) {
        Task {
            for await event in stream.events { sink.yield(.event(event)) }
            sink.yield(.ended(generation: generation))
        }
    }

    private static func describe(_ events: [AgentEvent]) -> String {
        events.map { event in
            switch event {
            case .snapshot: "snapshot"
            case .upserted: "event"
            case .removed: "removed"
            case .turnFinished: "turnFinished"
            default: "other"
            }
        }.joined(separator: ",")
    }

    private static func reason(_ error: Error) -> String {
        if case HerdrError.unavailable(let reason) = error { return reason }
        return "\(error)"
    }

    // MARK: Actions

    @discardableResult
    public func perform(_ action: AgentAction) async throws -> AgentRef? {
        guard capabilities.contains(action.requiredCapability) else { throw AgentActionError.unsupported(action) }
        switch action {
        case .focus(let ref):
            try check(ref)
            try await translating(ref) { _ = try await client.send(.focus(pane: ref.localID)) }

        case .open(let ref):
            try check(ref)
            try await translating(ref) { _ = try await client.send(.focus(pane: ref.localID)) }
            // Herdr retitles its window for the new workspace a moment after switching.
            try? await Task.sleep(for: .milliseconds(200))
            let hints = windowHints.withLock { $0[ref.localID] } ?? []
            if await !HerdrTerminal.bringToFront(raising: hints) { throw AgentActionError.failed("Couldn't find the terminal running Herdr") }

        case .prompt(let ref, let text):
            try check(ref)
            if statuses.withLock({ $0[ref.localID] }) == .blocked {
                throw AgentActionError.failed("\(ref.localID) is waiting for you; answer it in Herdr first")
            }
            // `agent_not_ready` is refused before anything is typed, so retrying is safe.
            try await translating(ref) {
                try await retrying(code: "agent_not_ready", for: .seconds(5)) {
                    try await client.send(.prompt(pane: ref.localID, text: text))
                }
            }

        case .start(let kind, let cwd, let prompt):
            return try await start(kind: kind, cwd: cwd, prompt: prompt)
        }
        return nil
    }

    /// Starts the agent as the process of a new pane (nothing is typed into a shell, so shell
    /// startup can't swallow the command), in a new tab of the workspace already open in `cwd`,
    /// else of a new workspace there. The message goes along as an argument where the agent's
    /// command takes one, so it waits through anything the agent asks first (Claude: trust this
    /// folder?). When the agent exits, its pane closes.
    private func start(kind: AgentKind, cwd: URL, prompt: String?) async throws -> AgentRef {
        struct Panes: Decodable, Sendable {
            var panes: [Pane]
            struct Pane: Decodable, Sendable { var workspace_id: String; var cwd: String?; var foreground_cwd: String? }
        }
        struct Created: Decodable, Sendable {
            var workspace: Workspace
            var root_pane: Pane
            struct Workspace: Decodable, Sendable { var workspace_id: String }
            struct Pane: Decodable, Sendable { var pane_id: String }
        }
        struct Applied: Decodable, Sendable {
            var layout: Layout
            struct Layout: Decodable, Sendable { var root: Root }
            struct Root: Decodable, Sendable { var pane_id: String }
        }
        let folder = Self.canonical(cwd.path)
        let takesPrompt = kind == .claude || kind == .codex
        let command = [agentCommand(kind)] + (takesPrompt ? [prompt].compactMap { $0 } : [])

        let panes = try await translating(nil) { try await client.call(.listPanes, as: Panes.self).panes }
        let open = panes.first { pane in [pane.cwd, pane.foreground_cwd].contains { $0.map(Self.canonical) == folder } }
        let workspace: String
        var shell: String?   // the new workspace's own shell pane, closed once the agent's tab is up
        if let open {
            workspace = open.workspace_id
        } else {
            let created = try await translating(nil) {
                try await client.call(.createWorkspace(cwd: cwd.path, label: cwd.lastPathComponent), as: Created.self)
            }
            workspace = created.workspace.workspace_id
            shell = created.root_pane.pane_id
        }
        let pane: String
        do {
            pane = try await translating(nil) {
                try await client.call(.applyLayout(workspace: workspace, cwd: cwd.path, command: command,
                                                   tabLabel: Self.tabLabel(prompt, kind: kind)), as: Applied.self).layout.root.pane_id
            }
        } catch {
            if let shell { _ = try? await client.send(.closePane(shell)) }
            throw error
        }
        if let shell { _ = try? await client.send(.closePane(shell)) }
        // Herdr's agent ID is its pane.
        let ref = AgentRef(adapter: id, localID: pane)

        guard let prompt, !takesPrompt else { return ref }
        // The agent stays either way: it's running, only the first message didn't arrive.
        do {
            try await translating(nil) {
                try await retrying(code: "agent_not_ready", for: timing.startRetryWindow) {
                    try await client.send(.prompt(pane: pane, text: prompt))
                }
            }
        } catch {
            throw AgentActionError.failed("Started \(kind.displayName), but couldn't send it the message")
        }
        return ref
    }

    /// A folder path as Herdr reports it (`/tmp` is `/private/tmp`).
    static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// The new tab's name: the start of the message, cut at a word, else the agent's name.
    static func tabLabel(_ prompt: String?, kind: AgentKind, limit: Int = 24) -> String {
        let words = (prompt ?? "").split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return kind.displayName }
        var label = ""
        for word in words {
            let next = label.isEmpty ? String(word) : label + " " + word
            if next.count > limit {
                return (label.isEmpty ? String(next.prefix(limit - 1)) : label) + "…"
            }
            label = next
        }
        return label
    }

    private func check(_ ref: AgentRef) throws {
        guard ref.adapter == id else { throw AgentActionError.unknownAgent(ref) }
    }

    /// Retries `body` while Herdr answers `code`, every `timing.retryInterval`, for up to `window`.
    private func retrying(code: String, for window: Duration, _ body: () async throws -> Data) async throws {
        let deadline = ContinuousClock.now + window
        while true {
            do {
                _ = try await body()
                return
            } catch let error as HerdrError where error.code == code && ContinuousClock.now < deadline {
                try await Task.sleep(for: timing.retryInterval)
            }
        }
    }

    /// Maps Herdr errors to `AgentActionError`.
    private func translating<T>(_ ref: AgentRef?, _ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as HerdrError {
            if let ref, error.code == "agent_not_found" || error.code == "pane_not_found" {
                throw AgentActionError.unknownAgent(ref)
            }
            throw AgentActionError.failed(error.description)
        }
    }

    /// The command that runs `kind`.
    public static func command(for kind: AgentKind) -> String {
        switch kind {
        case .claude: "claude"
        case .codex: "codex"
        case .pi: "pi"
        case .opencode: "opencode"
        case .copilot: "copilot"
        case .other(let name): name
        }
    }
}
