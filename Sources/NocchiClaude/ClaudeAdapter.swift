import AppKit
import Foundation
import NocchiCore
import NocchiTerminals
import Synchronization

/// Claude Code sessions running outside Herdr (a plain terminal tab, an IDE's terminal), seen
/// natively with no setup: Claude's own session registry (which sessions run, and whether they're
/// busy, running a command, waiting for you or idle) and their transcripts (steps and messages,
/// through `ClaudeActivityFeed`). Sessions inside Herdr panes are left to the Herdr adapter.
public final class ClaudeAdapter: AgentAdapter {
    public let id: AdapterID = "claude"
    /// `.start` opens a terminal tab running `claude`; the registry then reports the session.
    public let capabilities: AdapterCapabilities = [.focus, .start, .errors]

    private let registry: URL
    private let pollInterval: Duration
    private let leavesHerdrToHerdr: Bool
    /// Where each session's terminal is, for "open".
    private let hosts = Mutex<[String: pid_t]>([:])
    /// Per session: its folder name, a fallback for finding its window.
    private let folders = Mutex<[String: String]>([:])

    public init(
        registry: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/sessions"),
        pollInterval: Duration = .seconds(1),
        leavesHerdrToHerdr: Bool = true
    ) {
        self.registry = registry
        self.pollInterval = pollInterval
        self.leavesHerdrToHerdr = leavesHerdrToHerdr
    }

    private enum Signal: Sendable {
        case poll
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
        let frontTask = Task {
            for await pid in await TerminalApps.frontmostAppUpdates() { sink.yield(.frontmost(pid)) }
        }
        defer {
            ticker.cancel()
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
        folders.withLock { folders in folders = tracker.agents.compactMapValues { $0.cwd?.lastPathComponent } }
    }

    /// A started session isn't known until Claude registers it, so `.start` returns nil.
    @discardableResult
    public func perform(_ action: AgentAction) async throws -> AgentRef? {
        guard capabilities.contains(action.requiredCapability) else { throw AgentActionError.unsupported(action) }
        switch action {
        case .focus(let ref), .open(let ref):
            guard ref.adapter == id else { throw AgentActionError.unknownAgent(ref) }
            guard let host = hosts.withLock({ $0[ref.localID] }) else {
                throw AgentActionError.failed("Couldn't find the terminal running this session")
            }
            let opened = await MainActor.run { NSRunningApplication(processIdentifier: host) }
            // Claude titles its terminal with the session's title; the folder is the fallback.
            let hints = [ClaudeActivity.latestTitle(session: ref.localID), folders.withLock { $0[ref.localID] }].compactMap { $0 }
            guard let app = opened, await TerminalApps.bringToFront(app, raising: hints) else {
                throw AgentActionError.failed("Couldn't bring the terminal forward")
            }
        case .start(let kind, let cwd, let prompt):
            guard kind == .claude else { throw AgentActionError.unsupported(action) }
            do {
                try await TerminalLauncher.run(["claude"] + (prompt.map { [$0] } ?? []), in: cwd)
            } catch {
                throw AgentActionError.failed("\(error)")
            }
        case .prompt:
            throw AgentActionError.unsupported(action)
        }
        return nil
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
