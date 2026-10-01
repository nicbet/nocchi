import Foundation

/// What every `AgentAdapter` must do, as plain checks that return failure messages. Test targets
/// run them against each adapter (`MockAdapter` now, `HerdrAdapter` in M4).
public protocol AgentAdapterContractSubject: Sendable {
    func makeAdapter(capabilities: AdapterCapabilities) async throws -> AgentAdapter
    /// Makes an agent with `localID` appear in the adapter's source.
    func addAgent(_ localID: String, to adapter: AgentAdapter) async throws
    /// Makes it disappear.
    func removeAgent(_ localID: String, from adapter: AgentAdapter) async throws
    /// Makes the adapter lose and regain its connection to the source.
    func reconnect(_ adapter: AgentAdapter) async throws
}

public enum AgentAdapterContract {
    public static func check(_ subject: AgentAdapterContractSubject, timeout: Duration = .seconds(5)) async -> [String] {
        var failures: [String] = []
        do {
            failures += try await startsWithConnectionThenSnapshot(subject, timeout)
            failures += try await reportsAddedAndRemovedAgents(subject, timeout)
            failures += try await resnapshotsAfterReconnect(subject, timeout)
            failures += try await rejectsUnsupportedActions(subject)
        } catch {
            failures.append("threw: \(error)")
        }
        return failures
    }

    static func startsWithConnectionThenSnapshot(_ subject: AgentAdapterContractSubject, _ timeout: Duration) async throws -> [String] {
        let adapter = try await subject.makeAdapter(capabilities: .all)
        let recorder = EventRecorder(adapter.events())
        defer { recorder.stop() }
        let first = await recorder.wait(timeout) { $0.count >= 2 }
        guard first.count >= 2, case .connection = first[0], case .snapshot = first[1] else {
            return ["stream must start with .connection then .snapshot, got \(first.prefix(2))"]
        }
        return []
    }

    static func reportsAddedAndRemovedAgents(_ subject: AgentAdapterContractSubject, _ timeout: Duration) async throws -> [String] {
        let adapter = try await subject.makeAdapter(capabilities: .all)
        let ref = AgentRef(adapter: adapter.id, localID: "contract-agent")
        let recorder = EventRecorder(adapter.events())
        defer { recorder.stop() }
        @Sendable func state(_ events: [AgentEvent]) -> AgentsState {
            var state = AgentsState()
            for event in events { AgentReducer.reduce(&state, event, from: adapter.id, now: Date()) }
            return state
        }

        _ = await recorder.wait(timeout) { $0.count >= 2 }
        try await subject.addAgent(ref.localID, to: adapter)
        guard state(await recorder.wait(timeout) { state($0).agents[ref] != nil }).agents[ref] != nil else {
            return ["added agent never appeared"]
        }
        try await subject.removeAgent(ref.localID, from: adapter)
        guard state(await recorder.wait(timeout) { state($0).agents[ref] == nil }).agents[ref] == nil else {
            return ["removed agent never disappeared"]
        }
        return []
    }

    static func resnapshotsAfterReconnect(_ subject: AgentAdapterContractSubject, _ timeout: Duration) async throws -> [String] {
        let adapter = try await subject.makeAdapter(capabilities: .all)
        let recorder = EventRecorder(adapter.events())
        defer { recorder.stop() }
        let initial = await recorder.wait(timeout) { $0.count >= 2 }.count
        try await subject.reconnect(adapter)
        let after = await recorder.wait(timeout) { events in
            events.dropFirst(initial).contains { if case .snapshot = $0 { true } else { false } }
        }
        let resnapshotted = after.dropFirst(initial).contains { if case .snapshot = $0 { true } else { false } }
        return resnapshotted ? [] : ["no .snapshot after reconnect"]
    }

    static func rejectsUnsupportedActions(_ subject: AgentAdapterContractSubject) async throws -> [String] {
        let adapter = try await subject.makeAdapter(capabilities: [])
        let ref = AgentRef(adapter: adapter.id, localID: "anyone")
        var failures: [String] = []
        for action in [AgentAction.focus(ref), .prompt(ref, "hi"), .start(kind: .claude, cwd: URL(fileURLWithPath: "/tmp"))] {
            do {
                try await adapter.perform(action)
                failures.append("\(action) should throw .unsupported without the capability")
            } catch AgentActionError.unsupported {
            } catch {
                failures.append("\(action) threw \(error), expected .unsupported")
            }
        }
        return failures
    }
}

/// Consumes an event stream in the background so checks can wait on it with a deadline.
final class EventRecorder: Sendable {
    private let storage = Storage()
    private let task: Task<Void, Never>

    private actor Storage {
        var events: [AgentEvent] = []
        func append(_ event: AgentEvent) { events.append(event) }
    }

    init(_ stream: AsyncStream<AgentEvent>) {
        let storage = storage
        task = Task {
            for await event in stream { await storage.append(event) }
        }
    }

    /// Waits until `condition` holds or `timeout` passes; returns the events recorded so far.
    func wait(_ timeout: Duration, until condition: @Sendable ([AgentEvent]) -> Bool) async -> [AgentEvent] {
        let deadline = ContinuousClock.now + timeout
        while true {
            let events = await storage.events
            if condition(events) || ContinuousClock.now >= deadline { return events }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func stop() { task.cancel() }
}
