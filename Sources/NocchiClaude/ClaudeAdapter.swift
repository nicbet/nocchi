import AppKit
import Foundation
import NocchiCore
import NocchiHookProtocol
import NocchiHooks
import NocchiTerminals
import OSLog
import Synchronization

let claudeLog = Logger(subsystem: "com.github.nicbet.nocchi", category: "claude")

/// Claude Code sessions running outside Herdr (a plain terminal tab, an IDE's terminal), seen
/// natively: Claude's session registry (no setup needed), its hooks when installed, and its
/// transcripts (steps and messages, through `ClaudeActivityFeed`). Sessions inside Herdr panes
/// are left to the Herdr adapter.
public final class ClaudeAdapter: AgentAdapter {
    public let id: AdapterID = "claude"
    public let capabilities: AdapterCapabilities = [.focus, .errors]

    private let hooks: HookServer?
    private let registry: URL
    private let pollInterval: Duration
    private let leavesHerdrToHerdr: Bool
    /// Where each session's terminal is, for "open".
    private let hosts = Mutex<[String: pid_t]>([:])

    public init(
        hooks: HookServer? = nil,
        registry: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/sessions"),
        pollInterval: Duration = .seconds(1),
        leavesHerdrToHerdr: Bool = true
    ) {
        self.hooks = hooks
        self.registry = registry
        self.pollInterval = pollInterval
        self.leavesHerdrToHerdr = leavesHerdrToHerdr
    }

    private enum Signal: Sendable {
        case poll
        case hook(HookMessage)
        case frontmost(pid_t)
    }

    public func events() -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            let task = Task { await self.run(continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ out: AsyncStream<AgentEvent>.Continuation) async {
        var tracker = ClaudeSessionTracker(adapter: id, leavesHerdrToHerdr: leavesHerdrToHerdr)
        var context = ProcessContext()
        out.yield(.connection(.connected(version: nil)))
        let entries = ClaudeRegistryEntry.read(registry)
        _ = tracker.applyRegistry(entries, context: await context.lookup(entries.map(\.pid)), now: Date())
        out.yield(.snapshot(tracker.snapshot))
        publishHosts(tracker)

        let (signals, sink) = AsyncStream.makeStream(of: Signal.self)
        let interval = pollInterval
        let ticker = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                sink.yield(.poll)
            }
        }
        let hookTask = Task { [hooks] in
            guard let hooks else { return }
            for await message in hooks.messages(for: "claude") { sink.yield(.hook(message)) }
        }
        let frontTask = Task {
            for await pid in await TerminalApps.frontmostAppUpdates() { sink.yield(.frontmost(pid)) }
        }
        defer {
            ticker.cancel()
            hookTask.cancel()
            frontTask.cancel()
            sink.finish()
        }

        for await signal in signals {
            let now = Date()
            var events: [AgentEvent]
            switch signal {
            case .poll:
                let entries = ClaudeRegistryEntry.read(registry)
                events = tracker.applyRegistry(entries, context: await context.lookup(entries.map(\.pid)), now: now)
            case .hook(let message):
                guard var event = ClaudeHookEvent.parse(message.input) else { continue }
                event.herdrPane = message.environment["HERDR_PANE_ID"]
                claudeLog.info("hook \(String(describing: event.kind), privacy: .public) \(event.sessionID, privacy: .public)")
                events = tracker.apply(event, now: now)
            case .frontmost(let pid):
                events = tracker.hostBecameFrontmost(pid, now: now)
            }
            for event in events { out.yield(event) }
            if !events.isEmpty { publishHosts(tracker) }
        }
        out.finish()
    }

    private func publishHosts(_ tracker: ClaudeSessionTracker) {
        hosts.withLock { $0 = tracker.hosts }
    }

    public func perform(_ action: AgentAction) async throws {
        guard capabilities.contains(action.requiredCapability) else { throw AgentActionError.unsupported(action) }
        switch action {
        case .focus(let ref), .open(let ref):
            guard ref.adapter == id else { throw AgentActionError.unknownAgent(ref) }
            guard let host = hosts.withLock({ $0[ref.localID] }) else {
                throw AgentActionError.failed("Couldn't find the terminal running this session")
            }
            let opened = await MainActor.run { NSRunningApplication(processIdentifier: host) }
            guard let app = opened, await TerminalApps.bringToFront(app) else {
                throw AgentActionError.failed("Couldn't bring the terminal forward")
            }
        case .prompt, .start:
            throw AgentActionError.unsupported(action)
        }
    }
}

/// Where each `claude` process runs: inside Herdr or not, and its terminal app and tty. Looked
/// up once per process (the process table is only read when a new one appears).
private struct ProcessContext {
    private var known: [Int32: (insideHerdr: Bool, host: Int32?, tty: String?)] = [:]

    mutating func lookup(_ pids: [Int32]) async -> [Int32: (insideHerdr: Bool, host: Int32?, tty: String?)] {
        let missing = pids.filter { known[$0] == nil }
        if !missing.isEmpty {
            let table = await ProcessTable.current()
            for pid in missing {
                let chain = [table[pid]].compactMap { $0 } + table.ancestors(of: pid)
                let insideHerdr = chain.contains { $0.command == "herdr" }
                let host = await MainActor.run { TerminalApps.host(of: pid, in: table)?.processIdentifier }
                known[pid] = (insideHerdr, host, table[pid]?.tty)
            }
        }
        known = known.filter { pids.contains($0.key) }
        return known
    }
}
