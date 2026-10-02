import Foundation

/// A scripted adapter: plays a `MockScenario` and fakes actions. Used for the demo mode, for
/// building UI states before Herdr is wired up, and as the first adapter to pass the contract.
public actor MockAdapter: AgentAdapter {
    public nonisolated let id: AdapterID
    public nonisolated let capabilities: AdapterCapabilities

    private let scenario: MockScenario
    /// Multiplies scenario delays. 0 plays everything immediately (tests).
    private let timeScale: Double

    private var agents: [String: AgentInfo] = [:]
    private var order: [String] = []
    private var subscribers: [UUID: AsyncStream<AgentEvent>.Continuation] = [:]
    private var playback: Task<Void, Never>?
    public private(set) var performed: [AgentAction] = []

    public init(id: AdapterID = "mock", scenario: MockScenario = .empty, capabilities: AdapterCapabilities = .all, timeScale: Double = 1) {
        self.id = id
        self.scenario = scenario
        self.capabilities = capabilities
        self.timeScale = timeScale
        for spec in scenario.agents {
            agents[spec.id] = spec.info(adapter: id, at: Date())
            order.append(spec.id)
        }
    }

    public nonisolated func events() -> AsyncStream<AgentEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: AgentEvent.self)
        let token = UUID()
        Task { await self.subscribe(token, continuation) }
        continuation.onTermination = { _ in Task { await self.unsubscribe(token) } }
        return stream
    }

    public func perform(_ action: AgentAction) async throws {
        guard capabilities.contains(action.requiredCapability) else { throw AgentActionError.unsupported(action) }
        performed.append(action)
        switch action {
        case .focus(let ref), .open(let ref):
            guard agents[ref.localID] != nil, ref.adapter == id else { throw AgentActionError.unknownAgent(ref) }
            for key in order {
                let focused = key == ref.localID
                if agents[key]?.isFocused != focused { update(key) { $0.isFocused = focused } }
            }
        case .prompt(let ref, let text):
            guard agents[ref.localID] != nil, ref.adapter == id else { throw AgentActionError.unknownAgent(ref) }
            update(ref.localID) { $0.status = .working; $0.title = String(text.prefix(60)) }
        case .start(let kind, let cwd, let prompt):
            let key = "started-\(order.count + 1)"
            var info = MockAgent(key, kind: kind, name: cwd.lastPathComponent, status: .starting).info(adapter: id, at: Date())
            if let prompt {
                info.status = .working
                info.title = String(prompt.prefix(60))
            }
            add(info)
        }
    }

    // MARK: Test and demo hooks

    public func add(_ info: AgentInfo) {
        if agents[info.ref.localID] == nil { order.append(info.ref.localID) }
        agents[info.ref.localID] = info
        broadcast(.upserted(info))
    }

    public func remove(_ localID: String) {
        guard agents.removeValue(forKey: localID) != nil else { return }
        order.removeAll { $0 == localID }
        broadcast(.removed(AgentRef(adapter: id, localID: localID)))
    }

    /// Drops and restores the "connection": subscribers see connecting → connected → snapshot.
    public func simulateReconnect() {
        broadcast(.connection(.connecting))
        broadcast(.connection(.connected(version: "mock")))
        broadcast(.snapshot(currentAgents))
    }

    // MARK: Streaming

    private var currentAgents: [AgentInfo] { order.compactMap { agents[$0] } }

    private func subscribe(_ token: UUID, _ continuation: AsyncStream<AgentEvent>.Continuation) {
        subscribers[token] = continuation
        continuation.yield(.connection(.connected(version: "mock")))
        continuation.yield(.snapshot(currentAgents))
        if playback == nil, !scenario.script.isEmpty {
            playback = Task { await self.play() }
        }
    }

    private func unsubscribe(_ token: UUID) {
        subscribers[token] = nil
        if subscribers.isEmpty {
            playback?.cancel()
            playback = nil
        }
    }

    private func broadcast(_ event: AgentEvent) {
        for continuation in subscribers.values { continuation.yield(event) }
    }

    private func play() async {
        repeat {
            for step in scenario.script {
                if step.after > 0, timeScale > 0 {
                    try? await Task.sleep(for: .seconds(step.after * timeScale))
                } else {
                    // Always suspend, so a looping scenario at time scale 0 can still be cancelled.
                    await Task.yield()
                }
                guard !Task.isCancelled else { return }
                apply(step.change)
            }
        } while scenario.loops && !Task.isCancelled
    }

    private func apply(_ change: MockChange) {
        switch change {
        case .add(let spec): add(spec.info(adapter: id, at: Date()))
        case .remove(let key): remove(key)
        case .status(let key, let status, let title):
            update(key) { info in
                info.status = status
                if let title { info.title = title }
            }
        case .step(let key, let text):
            guard agents[key] != nil else { return }
            broadcast(.step(AgentRef(adapter: id, localID: key), text))
        case .finish(let key, let status):
            guard agents[key] != nil else { return }
            update(key) { $0.status = status }
            broadcast(.turnFinished(AgentRef(adapter: id, localID: key)))
        case .focus(let key):
            for other in order where (agents[other]?.isFocused ?? false) != (other == key) {
                update(other) { $0.isFocused = other == key }
            }
        }
    }

    private func update(_ key: String, _ change: (inout AgentInfo) -> Void) {
        guard var info = agents[key] else { return }
        let before = info.status
        change(&info)
        if info.status != before { info.changedAt = Date() }
        agents[key] = info
        broadcast(.upserted(info))
    }
}

/// An agent in a scenario.
public struct MockAgent: Sendable {
    public var id: String
    public var kind: AgentKind
    public var status: AgentStatus
    public var name: String?
    public var title: String?
    public var focused: Bool

    public init(_ id: String, kind: AgentKind = .claude, name: String? = nil, status: AgentStatus = .idle, title: String? = nil, focused: Bool = false) {
        self.id = id
        self.kind = kind
        self.status = status
        self.name = name
        self.title = title
        self.focused = focused
    }

    func info(adapter: AdapterID, at date: Date) -> AgentInfo {
        AgentInfo(ref: AgentRef(adapter: adapter, localID: id), kind: kind, status: status, name: name, title: title,
                  sessionID: "mock-\(id)", isFocused: focused, changedAt: date)
    }
}

public enum MockChange: Sendable {
    case add(MockAgent)
    case remove(String)
    case status(String, AgentStatus, title: String? = nil)
    case step(String, String)
    /// Sets the status and reports `turnFinished`.
    case finish(String, AgentStatus = .done)
    case focus(String)
}

public struct MockStep: Sendable {
    /// Seconds after the previous step.
    public var after: TimeInterval
    public var change: MockChange
    public init(after: TimeInterval, _ change: MockChange) {
        self.after = after
        self.change = change
    }
}
