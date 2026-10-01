import Foundation
import Testing
@testable import NocchiCore

struct MockContractSubject: AgentAdapterContractSubject {
    func makeAdapter(capabilities: AdapterCapabilities) async throws -> AgentAdapter {
        MockAdapter(capabilities: capabilities, timeScale: 0)
    }
    func addAgent(to adapter: AgentAdapter) async throws -> String {
        let mock = adapter as! MockAdapter
        await mock.add(AgentInfo(ref: AgentRef(adapter: mock.id, localID: "contract-agent"), kind: .claude, status: .idle, changedAt: Date()))
        return "contract-agent"
    }
    func removeAgent(_ localID: String, from adapter: AgentAdapter) async throws {
        await (adapter as! MockAdapter).remove(localID)
    }
    func reconnect(_ adapter: AgentAdapter) async throws {
        await (adapter as! MockAdapter).simulateReconnect()
    }
}

@Suite struct MockAdapterTests {
    @Test func passesTheAdapterContract() async {
        let failures = await AgentAdapterContract.check(MockContractSubject())
        #expect(failures.isEmpty, "\(failures)")
    }

    @Test func snapshotHasTheScenarioAgents() async {
        let adapter = MockAdapter(scenario: .needsYou, timeScale: 0)
        let recorder = EventRecorder(adapter.events())
        defer { recorder.stop() }
        let events = await recorder.wait(.seconds(2)) { $0.count >= 2 }
        guard case .snapshot(let agents) = events[1] else { Issue.record("no snapshot"); return }
        #expect(agents.map(\.ref.localID) == ["deploy", "api", "web"])
    }

    @Test func scriptPlaysThroughTheReducer() async {
        let scenario = MockScenario(name: "t", agents: [MockAgent("a", status: .working, title: "Build")], script: [
            MockStep(after: 1, .step("a", "Compiling")),
            MockStep(after: 1, .finish("a")),
        ])
        let adapter = MockAdapter(scenario: scenario, timeScale: 0)
        let recorder = EventRecorder(adapter.events())
        defer { recorder.stop() }
        let events = await recorder.wait(.seconds(2)) { $0.contains(.turnFinished(AgentRef(adapter: "mock", localID: "a"))) }

        var state = AgentsState()
        for event in events { AgentReducer.reduce(&state, event, from: "mock", now: Date()) }
        let entry = state.agents[AgentRef(adapter: "mock", localID: "a")]
        #expect(entry?.info.status == .done)
        #expect(entry?.steps == ["Build", "Compiling"])
        #expect(entry?.celebratingUntil != nil)
    }

    @Test func focusMovesFocus() async throws {
        let adapter = MockAdapter(scenario: .needsYou, timeScale: 0)
        let recorder = EventRecorder(adapter.events())
        defer { recorder.stop() }
        _ = await recorder.wait(.seconds(2)) { $0.count >= 2 }
        try await adapter.perform(.focus(AgentRef(adapter: "mock", localID: "api")))
        let events = await recorder.wait(.seconds(2)) { events in
            events.contains { if case .upserted(let info) = $0 { info.ref.localID == "api" && info.isFocused } else { false } }
        }
        var state = AgentsState()
        for event in events { AgentReducer.reduce(&state, event, from: "mock", now: Date()) }
        #expect(state.agents.values.filter(\.info.isFocused).map(\.ref.localID) == ["api"])
    }

    @Test func unknownAgentsAreRejected() async {
        let adapter = MockAdapter(timeScale: 0)
        await #expect(throws: AgentActionError.unknownAgent(AgentRef(adapter: "mock", localID: "nobody"))) {
            try await adapter.perform(.focus(AgentRef(adapter: "mock", localID: "nobody")))
        }
    }

    @Test(arguments: MockScenario.all.map(\.name))
    func builtInScenariosStartCleanly(name: String) async {
        let scenario = MockScenario.all.first { $0.name == name }!
        let adapter = MockAdapter(scenario: scenario, timeScale: 0)
        let recorder = EventRecorder(adapter.events())
        defer { recorder.stop() }
        let events = await recorder.wait(.seconds(2)) { $0.count >= 2 }
        guard case .snapshot(let agents) = events[1] else { Issue.record("no snapshot"); return }
        #expect(agents.count == scenario.agents.count)
    }
}
