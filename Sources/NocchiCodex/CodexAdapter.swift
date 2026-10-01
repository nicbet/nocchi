import AppKit
import Foundation
import NocchiCore
import NocchiHookProtocol
import NocchiHooks
import NocchiTerminals
import OSLog
import Synchronization

let codexLog = Logger(subsystem: "com.github.nicbet.nocchi", category: "codex")

/// Codex CLI sessions running outside Herdr: found from `codex` processes and the rollout log
/// each one writes, followed by tailing that log (status, steps, final messages), refined by
/// Codex hooks when installed. Sessions inside Herdr panes are left to the Herdr adapter.
public final class CodexAdapter: AgentAdapter {
    public let id: AdapterID = "codex"
    public let capabilities: AdapterCapabilities = [.focus, .steps]

    private let hooks: HookServer?
    private let home: URL
    private let leavesHerdrToHerdr: Bool
    private let hosts = Mutex<[String: pid_t]>([:])

    public init(hooks: HookServer? = nil, home: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex"),
                leavesHerdrToHerdr: Bool = true) {
        self.hooks = hooks
        self.home = home
        self.leavesHerdrToHerdr = leavesHerdrToHerdr
    }

    private enum Signal: Sendable {
        case tick(Int)
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
        var tracker = CodexSessionTracker(adapter: id)
        var discovery = CodexDiscovery(home: home, leavesHerdrToHerdr: leavesHerdrToHerdr)
        var tails = RolloutTails()
        out.yield(.connection(.connected(version: nil)))

        func refresh(now: Date) async -> [AgentEvent] {
            let live = await discovery.sessions()
            var events = tracker.update(live: live, now: now)
            for session in live where !tails.follows(session.sessionID) {
                let replayed = tails.start(session.sessionID, at: session.rollout)
                events += tracker.apply(replayed, to: session.sessionID, replay: true, now: now)
            }
            tails.keep(only: Set(live.map(\.sessionID)))
            hosts.withLock { $0 = tracker.hosts }
            return events
        }

        // The snapshot first, then what the replayed rollouts say each agent did last.
        let initial = await refresh(now: Date())
        out.yield(.snapshot(tracker.snapshot))
        for event in initial {
            switch event {
            case .step, .message: out.yield(event)
            default: break
            }
        }

        let (signals, sink) = AsyncStream.makeStream(of: Signal.self)
        let ticker = Task {
            var n = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                n += 1
                sink.yield(.tick(n))
            }
        }
        let hookTask = Task { [hooks] in
            guard let hooks else { return }
            for await message in hooks.messages(for: "codex") { sink.yield(.hook(message)) }
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
            var events: [AgentEvent] = []
            switch signal {
            case .tick(let n):
                // New and finished sessions every 3 s (a process scan); their logs every second.
                if n % 3 == 0 { events += await refresh(now: now) }
                for (session, lines) in tails.read() {
                    events += tracker.apply(lines, to: session, now: now)
                }
            case .hook(let message):
                guard let object = try? JSONSerialization.jsonObject(with: message.input) as? [String: Any],
                      let session = object["session_id"] as? String, let name = object["hook_event_name"] as? String else { continue }
                // Codex runs hooks in its app-server daemon, so their environment is the daemon's
                // (it may well say HERDR_PANE_ID from wherever it was first started). Ownership
                // comes from discovery instead: hooks only apply to sessions found outside Herdr.
                events = tracker.applyHook(name, session: session, now: now)
                if tracker.agents[session] == nil {
                    codexLog.info("hook \(name, privacy: .public) for unknown session \(session, privacy: .public); known: \(tracker.agents.keys.sorted().joined(separator: ","), privacy: .public)")
                }
            case .frontmost(let pid):
                events = tracker.hostBecameFrontmost(pid, now: now)
            }
            for event in events { out.yield(event) }
        }
        out.finish()
    }

    public func perform(_ action: AgentAction) async throws {
        guard capabilities.contains(action.requiredCapability) else { throw AgentActionError.unsupported(action) }
        switch action {
        case .focus(let ref), .open(let ref):
            guard ref.adapter == id else { throw AgentActionError.unknownAgent(ref) }
            guard let host = hosts.withLock({ $0[ref.localID] }) else {
                throw AgentActionError.failed("Couldn't find the terminal running this session")
            }
            let found = await MainActor.run { NSRunningApplication(processIdentifier: host) }
            guard let app = found, await TerminalApps.bringToFront(app) else {
                throw AgentActionError.failed("Couldn't bring the terminal forward")
            }
        case .prompt, .start:
            throw AgentActionError.unsupported(action)
        }
    }
}

/// Finds running Codex CLI sessions: `codex` processes (not the app server, not the desktop
/// app's helpers), the rollout each writes, and the terminal it runs in. Codex creates its rollout
/// only with the first prompt, so processes without one are looked up again on every scan; found
/// sessions are remembered. Codex doesn't keep the rollout open, so it's matched by folder.
struct CodexDiscovery {
    let home: URL
    let leavesHerdrToHerdr: Bool
    private var found: [Int32: CodexSession] = [:]
    /// Processes left to Herdr: no need to look again.
    private var skipped: Set<Int32> = []

    init(home: URL, leavesHerdrToHerdr: Bool) {
        self.home = home
        self.leavesHerdrToHerdr = leavesHerdrToHerdr
    }

    mutating func sessions() async -> [CodexSession] {
        let table = await ProcessTable.current()
        let processes = table.entries.values.filter(Self.isCLI)
        let pids = Set(processes.map(\.pid))
        found = found.filter { pids.contains($0.key) }
        skipped.formIntersection(pids)
        for process in processes where found[process.pid] == nil && !skipped.contains(process.pid) {
            switch await lookup(process, in: table) {
            case .session(let session): found[process.pid] = session
            case .insideHerdr: skipped.insert(process.pid)
            case .notYet: break
            }
        }
        return found.values.sorted { $0.pid < $1.pid }
    }

    /// The interactive CLI: `codex` or `codex resume …`, not `codex app-server`, `codex exec` or
    /// anything inside an app bundle.
    static func isCLI(_ entry: ProcessTable.Entry) -> Bool {
        guard entry.command == "codex", !entry.args.contains(".app/") else { return false }
        let words = entry.args.split(separator: " ").dropFirst()
        return !words.contains { ["app-server", "exec", "mcp", "mcp-server", "login", "proto"].contains($0) }
    }

    private enum Lookup {
        case session(CodexSession)
        case insideHerdr
        /// No rollout yet (no prompt so far).
        case notYet
    }

    private func lookup(_ process: ProcessTable.Entry, in table: ProcessTable) async -> Lookup {
        let chain = [process] + table.ancestors(of: process.pid)
        if leavesHerdrToHerdr, chain.contains(where: { $0.command == "herdr" }) { return .insideHerdr }
        let files = await Self.openFiles(of: process.pid)
        let rollout = files.paths.first { $0.contains("/.codex/sessions/") && $0.hasSuffix(".jsonl") }.map(URL.init(fileURLWithPath:))
            ?? newestRollout(in: files.cwd)
        guard let rollout, let meta = Self.sessionMeta(rollout) else { return .notYet }
        let host = await MainActor.run { TerminalApps.host(of: process.pid, in: table)?.processIdentifier }
        return .session(CodexSession(pid: process.pid, sessionID: meta.id, rollout: rollout, cwd: meta.cwd ?? files.cwd,
                                     title: threadName(meta.id), hostID: host))
    }

    /// When the process doesn't keep its rollout open: the newest rollout of the last two days
    /// started in the same folder.
    private func newestRollout(in cwd: String?) -> URL? {
        guard let cwd else { return nil }
        let calendar = Calendar.current
        let days = [Date(), Date().addingTimeInterval(-86_400)].map {
            home.appending(path: String(format: "sessions/%04d/%02d/%02d", calendar.component(.year, from: $0),
                                        calendar.component(.month, from: $0), calendar.component(.day, from: $0)))
        }
        let files = days.flatMap { (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] }
            .filter { $0.pathExtension == "jsonl" }
        let dated = files.compactMap { url -> (URL, Date)? in
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return nil }
            return (url, date)
        }
        return dated.sorted { $0.1 > $1.1 }.first { Self.sessionMeta($0.0)?.cwd == cwd }?.0
    }

    /// The `session_meta` line at the top of a rollout.
    static func sessionMeta(_ rollout: URL) -> (id: String, cwd: String?)? {
        guard let handle = try? FileHandle(forReadingFrom: rollout) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 256 * 1024),  // session_meta carries instructions: ~50 KB
              let line = head.split(separator: 0x0A).first,
              case .session(let id, let cwd) = CodexRolloutEvent.parse(Data(line)) else { return nil }
        return (id, cwd)
    }

    /// Codex's name for a thread, from `session_index.jsonl`.
    private func threadName(_ id: String) -> String? {
        guard let data = try? Data(contentsOf: home.appending(path: "session_index.jsonl")) else { return nil }
        for line in data.split(separator: 0x0A).reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["id"] as? String == id else { continue }
            return object["thread_name"] as? String
        }
        return nil
    }

    /// The process's working directory and open files, from `lsof`.
    static func openFiles(of pid: Int32) async -> (cwd: String?, paths: [String]) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let lsof = Process()
                lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
                lsof.arguments = ["-n", "-P", "-p", String(pid), "-Ffn"]
                let pipe = Pipe()
                lsof.standardOutput = pipe
                lsof.standardError = FileHandle.nullDevice
                guard (try? lsof.run()) != nil else { return continuation.resume(returning: (nil, [])) }
                let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                lsof.waitUntilExit()
                continuation.resume(returning: parseLsof(output))
            }
        }
    }

    /// `lsof -F fn` output: `f<descriptor>` then `n<path>` lines.
    static func parseLsof(_ output: String) -> (cwd: String?, paths: [String]) {
        var cwd: String?
        var paths: [String] = []
        var descriptor = ""
        for line in output.split(separator: "\n") {
            if line.hasPrefix("f") { descriptor = String(line.dropFirst()) }
            if line.hasPrefix("n") {
                let path = String(line.dropFirst())
                if descriptor == "cwd" { cwd = path } else { paths.append(path) }
            }
        }
        return (cwd, paths)
    }
}

/// Follows each session's rollout from where it was last read, complete lines only.
struct RolloutTails {
    private var tails: [String: (url: URL, offset: UInt64)] = [:]

    func follows(_ session: String) -> Bool { tails[session] != nil }

    /// Starts following; returns the recent events (the last 256 KB) to replay.
    mutating func start(_ session: String, at url: URL) -> [CodexRolloutEvent] {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        let start = size > 256 * 1024 ? size - 256 * 1024 : 0
        tails[session] = (url, start)
        let events = read(session, skippingFirstLine: start > 0)
        return events
    }

    mutating func keep(only sessions: Set<String>) {
        tails = tails.filter { sessions.contains($0.key) }
    }

    /// New events per session since the last read.
    mutating func read() -> [(String, [CodexRolloutEvent])] {
        tails.keys.sorted().compactMap { session in
            let events = read(session)
            return events.isEmpty ? nil : (session, events)
        }
    }

    private mutating func read(_ session: String, skippingFirstLine: Bool = false) -> [CodexRolloutEvent] {
        guard let tail = tails[session], let handle = try? FileHandle(forReadingFrom: tail.url) else { return [] }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > tail.offset,
              (try? handle.seek(toOffset: tail.offset)) != nil,
              let data = try? handle.read(upToCount: Int(size - tail.offset)),
              let lastNewline = data.lastIndex(of: 0x0A) else { return [] }
        tails[session]?.offset = tail.offset + UInt64(data.distance(from: data.startIndex, to: lastNewline) + 1)
        var lines = data[data.startIndex...lastNewline].split(separator: 0x0A)
        if skippingFirstLine, !lines.isEmpty { lines.removeFirst() }
        return lines.compactMap { CodexRolloutEvent.parse(Data($0)) }
    }
}
