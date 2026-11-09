import AppKit
import Foundation
import NocchiCore
import NocchiHerdr
import NocchiTerminals
import OSLog
import Synchronization

let herdrCoreLog = Logger(subsystem: "com.github.nicbet.nocchi", category: "herdr-core")

/// Agents from the Herdr GUI. herdr-core (`hc`) is the source of truth: each `events()` stream
/// subscribes (a snapshot, then every change in order) and re-subscribes after a drop, a
/// `missed` notice or silence past the heartbeat. herdr-app, the window, is only asked to show
/// things (focus, start); its layout names the agents, read from herdr-core's shared document.
/// Reconnects with 1 s → 10 s backoff, and only clears the agents after 3 failed attempts in a row.
public final class HerdrCoreAdapter: AgentAdapter {
    public let id: AdapterID
    public let capabilities: AdapterCapabilities
    public let client: HcClient
    public let app: HerdrAppClient

    public struct Timing: Sendable {
        public var minBackoff: Duration = .seconds(1)
        public var maxBackoff: Duration = .seconds(10)
        public var missesBeforeClearing = 3
        /// herdr-core sends a heartbeat every 15 s; this much silence means the line is dead.
        public var silence: Duration = .seconds(45)
        /// How long `.start` waits for the window to show the new terminal.
        public var startWindow: Duration = .seconds(10)
        public var pollInterval: Duration = .milliseconds(200)
        public init() {}
    }
    public let timing: Timing

    /// Last known status per terminal, for refusing prompts to blocked agents.
    private let statuses = Mutex<[String: AgentStatus]>([:])
    /// The command that runs an agent kind. Tests swap in a script.
    let agentCommand: @Sendable (AgentKind) -> String
    /// A Claude process's session ID. Tests swap in a fixture.
    let sessionID: @Sendable (Int32) -> String?

    public init(
        client: HcClient = HcClient(), app: HerdrAppClient = HerdrAppClient(), id: AdapterID = "hc",
        capabilities: AdapterCapabilities = [.focus, .prompt, .start, .errors], timing: Timing = Timing(),
        agentCommand: @escaping @Sendable (AgentKind) -> String = HerdrAdapter.command(for:),
        sessionID: @escaping @Sendable (Int32) -> String? = HerdrCoreAdapter.claudeSession(pid:)
    ) {
        self.sessionID = sessionID
        self.client = client
        self.app = app
        self.id = id
        self.capabilities = capabilities
        self.timing = timing
        self.agentCommand = agentCommand
    }

    // MARK: Events

    public func events() -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            let task = Task { await self.sync(continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func sync(_ out: AsyncStream<AgentEvent>.Continuation) async {
        var tracker = HcTracker(adapter: id, sessionID: sessionID)
        var connected = false   // last reported connection state
        var reported = false    // reported any connection state yet
        var misses = 0
        var backoff = timing.minBackoff

        while !Task.isCancelled {
            do {
                let hello = try await client.hello()
                let (subscription, stream) = try await client.subscribe()
                defer { stream.close() }
                let layout = try? await client.appLayout()
                if !connected {
                    out.yield(.connection(.connected(version: hello.version)))
                    connected = true
                    reported = true
                }
                misses = 0
                backoff = timing.minBackoff
                _ = tracker.setLayout(layout, now: Date())
                publish(tracker.apply(subscription.terminals, now: Date()), tracker, to: out)
                try await follow(stream, &tracker, to: out)
            } catch {
                if Task.isCancelled { break }
                if case HcResubscribe.missed = error {
                    // Not a failure: just take a fresh snapshot.
                    continue
                }
                misses += 1
                // At launch there's nothing to keep, so say so right away. Once agents are on
                // screen, ride out short hiccups (a core restart) without flicker.
                if !reported || (connected && misses >= timing.missesBeforeClearing) {
                    out.yield(.connection(.unavailable(reason: Self.reason(error))))
                    tracker = HcTracker(adapter: id, sessionID: sessionID)
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

    private enum HcResubscribe: Error { case missed, silent, closed }

    private enum Signal: Sendable {
        case event(HcEvent)
        case ended
        case tick
    }

    /// Follows events until the stream drops or falls behind (throws) or the task is cancelled.
    private func follow(_ stream: HcEventStream, _ tracker: inout HcTracker, to out: AsyncStream<AgentEvent>.Continuation) async throws {
        let (signals, sink) = AsyncStream.makeStream(of: Signal.self)
        let pump = Task {
            for await event in stream.events { sink.yield(.event(event)) }
            sink.yield(.ended)
        }
        let silence = timing.silence
        let ticker = Task {
            while !Task.isCancelled {
                try await Task.sleep(for: silence / 3)
                sink.yield(.tick)
            }
        }
        defer {
            pump.cancel()
            ticker.cancel()
            sink.finish()
        }

        var heard = ContinuousClock.now
        for await signal in signals {
            switch signal {
            case .event(let event):
                heard = .now
                switch event {
                case .missed:
                    throw HcResubscribe.missed
                case .doc(let name) where name == "herdr-app":
                    let layout = try? await client.appLayout()
                    publish(tracker.setLayout(layout, now: Date()), tracker, to: out)
                default:
                    publish(tracker.apply(event, now: Date()), tracker, to: out)
                }
            case .ended:
                throw HcResubscribe.closed
            case .tick:
                if ContinuousClock.now - heard > silence { throw HcResubscribe.silent }
            }
        }
    }

    private func publish(_ events: [AgentEvent], _ tracker: HcTracker, to out: AsyncStream<AgentEvent>.Continuation) {
        let before = statuses.withLock { $0 }
        for event in events { out.yield(event) }
        for (terminal, info) in tracker.agents where before[terminal] != info.status {
            herdrCoreLog.info("status \(terminal, privacy: .public): \(String(describing: before[terminal]), privacy: .public) → \(String(describing: info.status), privacy: .public)")
        }
        statuses.withLock { $0 = tracker.agents.mapValues(\.status) }
    }

    private static func reason(_ error: Error) -> String {
        switch error {
        case HerdrError.unavailable(let reason): reason
        case HcResubscribe.closed: "herdr-core closed the event stream"
        case HcResubscribe.silent: "herdr-core stopped answering"
        default: "\(error)"
        }
    }

    // MARK: Actions

    @discardableResult
    public func perform(_ action: AgentAction) async throws -> AgentRef? {
        guard capabilities.contains(action.requiredCapability) else { throw AgentActionError.unsupported(action) }
        switch action {
        case .focus(let ref):
            try check(ref)
            try await show(ref)

        case .open(let ref):
            try check(ref)
            try await show(ref)
            guard let window = await MainActor.run(body: { NSRunningApplication.runningApplications(withBundleIdentifier: HerdrCore.appBundleID).first }),
                  await TerminalApps.bringToFront(window) else {
                throw AgentActionError.failed("Couldn't bring Herdr to the front")
            }

        case .prompt(let ref, let text):
            try check(ref)
            if statuses.withLock({ $0[ref.localID] }) == .blocked {
                throw AgentActionError.failed("\(ref.localID) is waiting for you; answer it in Herdr first")
            }
            do {
                // herdr-core types once nobody has typed for ~3 s, so allow for that.
                try await client.send(.send(terminal: ref.localID, text: text), timeout: .seconds(20))
            } catch {
                switch HerdrCore.kind(error) {
                case "blocked": throw AgentActionError.failed("\(ref.localID) is waiting for you; answer it in Herdr first")
                case "not_found", "finished": throw AgentActionError.unknownAgent(ref)
                default: throw AgentActionError.failed("\(error)")
                }
            }

        case .start(let kind, let cwd, let prompt):
            return try await start(kind: kind, cwd: cwd, prompt: prompt)
        }
        return nil
    }

    /// Shows the agent's pane in herdr-app.
    private func show(_ ref: AgentRef) async throws {
        do {
            try await app.run("agent.focus", ["terminal": .string(ref.localID)])
        } catch {
            throw AgentActionError.failed(Self.reason(error))
        }
    }

    /// Starts the agent in a new tab of the space already open in `cwd`, else in a new space
    /// there. herdr-app hands the message over once the agent is ready, so it waits through
    /// anything the agent asks first. Needs the window: without a pane nobody could see the agent.
    private func start(kind: AgentKind, cwd: URL, prompt: String?) async throws -> AgentRef? {
        let before: HerdrAppClient.Tree
        do {
            before = try await app.ls()
        } catch HerdrError.unavailable {
            throw AgentActionError.failed("Open Herdr to start agents")
        } catch {
            throw AgentActionError.failed(Self.reason(error))
        }
        let folder = Self.canonical(cwd.path)
        var args: [String: JSONValue] = ["folder": .string(cwd.path), "argv": [.string(agentCommand(kind))]]
        if let prompt, !prompt.isEmpty { args["task"] = .string(prompt) }
        let command: String
        if let space = before.spaces.first(where: { $0.machine == nil && $0.folder.map(Self.canonical) == folder }) {
            command = "tab.new"
            args["space"] = .string(space.id)
            args["name"] = .string(HerdrAdapter.tabLabel(prompt, kind: kind))
        } else {
            command = "space.new"
            args["name"] = .string(cwd.lastPathComponent)
            args["machine"] = ""
        }
        do {
            try await app.run(command, args)
        } catch {
            throw AgentActionError.failed(Self.reason(error))
        }

        // The window names the new terminal once it has a pane.
        let known = before.terminals
        let deadline = ContinuousClock.now + timing.startWindow
        while ContinuousClock.now < deadline {
            if let tree = try? await app.ls(), let new = tree.terminals.subtracting(known).sorted().first {
                return AgentRef(adapter: id, localID: new)
            }
            try await Task.sleep(for: timing.pollInterval)
        }
        // It's starting; it'll show up once herdr-core reports it.
        return nil
    }

    /// The session a Claude process runs, from Claude's session registry
    /// (`~/.claude/sessions/<pid>.json`, `sessionId`). Read on each change, since `/clear` starts a
    /// new session in the same process.
    public static func claudeSession(pid: Int32) -> String? {
        let file = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/sessions/\(pid).json")
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (object["sessionId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// A folder path as Herdr reports it (`/tmp` is `/private/tmp`).
    static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func check(_ ref: AgentRef) throws {
        guard ref.adapter == id else { throw AgentActionError.unknownAgent(ref) }
    }
}
