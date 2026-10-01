import Foundation
import NocchiCore
import Testing
@testable import NocchiHerdr

let herdrInstalled = IsolatedHerdr.findHerdr() != nil

extension HerdrAdapter.Timing {
    /// Fast reconnects so the tests don't wait on backoff.
    static var test: Self {
        var timing = Self()
        timing.minBackoff = .milliseconds(200)
        timing.maxBackoff = .seconds(1)
        return timing
    }
}

struct HerdrContractSubject: AgentAdapterContractSubject {
    let herdr: IsolatedHerdr

    func makeAdapter(capabilities: AdapterCapabilities) async throws -> AgentAdapter {
        HerdrAdapter(client: herdr.client, capabilities: capabilities, timing: .test)
    }
    func addAgent(to adapter: AgentAdapter) async throws -> String {
        try await herdr.addAgent(label: "contract")
    }
    func removeAgent(_ localID: String, from adapter: AgentAdapter) async throws {
        try await herdr.close(localID)
    }
    func reconnect(_ adapter: AgentAdapter) async throws {
        herdr.halt()
        try herdr.launch()
    }
}

/// Against a real, isolated Herdr (see `IsolatedHerdr`). Skipped when Herdr isn't installed.
@Suite(.serialized, .enabled(if: herdrInstalled, "needs herdr on PATH"))
struct HerdrIntegrationTests {
    func withHerdr(_ body: (IsolatedHerdr) async throws -> Void) async throws {
        let herdr = try #require(try IsolatedHerdr.start())
        defer { herdr.stop() }
        try await body(herdr)
        // Whatever the adapter sent must still match Herdr's schema.
        if let schema = try HerdrSchema.installed() {
            for request in herdr.recorded.withLock({ $0 }) {
                #expect(schema.validate(request).isEmpty, "\(schema.validate(request))")
            }
        }
    }

    func state(_ events: [AgentEvent]) -> AgentsState {
        var state = AgentsState()
        for event in events { AgentReducer.reduce(&state, event, from: "herdr", now: Date()) }
        return state
    }

    @Test func passesTheAdapterContract() async throws {
        try await withHerdr { herdr in
            let failures = await AgentAdapterContract.check(HerdrContractSubject(herdr: herdr), timeout: .seconds(20))
            #expect(failures.isEmpty, "\(failures)")
        }
    }

    @Test func followsAgentsThroughATurn() async throws {
        try await withHerdr { herdr in
            let watched = try await herdr.addAgent(label: "Watched", focus: false)
            let adapter = HerdrAdapter(client: herdr.client, timing: .test)
            let recorder = EventRecorder(adapter.events())
            defer { recorder.stop() }
            let ref = AgentRef(adapter: "herdr", localID: watched)

            let start = await recorder.wait(.seconds(5)) { $0.count >= 2 }
            guard case .connection(.connected) = start.first else { Issue.record("not connected: \(start)"); return }
            #expect(state(start).agents[ref]?.info.status == .idle)

            // A second workspace takes focus, so the first one's turn ends in `done`.
            let other = try await herdr.addAgent(label: "Other")
            try await herdr.driver.send(.focus(pane: other))
            try await herdr.report(watched, "working")
            _ = await recorder.wait(.seconds(5)) { state($0).agents[ref]?.info.status == .working }
            try await herdr.report(watched, "idle")
            let finished = await recorder.wait(.seconds(5)) { $0.contains(.turnFinished(ref)) }
            #expect(finished.contains(.turnFinished(ref)))
            #expect(state(finished).agents[ref]?.info.status == .done)

            // The focused pane goes straight to idle and is celebrated all the same.
            let otherRef = AgentRef(adapter: "herdr", localID: other)
            try await herdr.report(other, "working")
            _ = await recorder.wait(.seconds(5)) { state($0).agents[otherRef]?.info.status == .working }
            try await herdr.report(other, "idle")
            let focused = await recorder.wait(.seconds(5)) { $0.contains(.turnFinished(otherRef)) }
            #expect(focused.contains(.turnFinished(otherRef)))
            #expect(state(focused).agents[otherRef]?.info.status == .idle)
            #expect(state(focused).agents[otherRef]?.info.isFocused == true)

            try await herdr.report(watched, "blocked")
            let blocked = await recorder.wait(.seconds(5)) { state($0).agents[ref]?.info.status == .blocked }
            #expect(state(blocked).agents[ref]?.info.status == .blocked)
            await #expect(throws: AgentActionError.self) { try await adapter.perform(.prompt(ref, "hello")) }

            try await herdr.close(watched)
            let closed = await recorder.wait(.seconds(5)) { state($0).agents[ref] == nil }
            #expect(state(closed).agents[ref] == nil)
            #expect(state(closed).agents[otherRef] != nil)
        }
    }

    @Test func picksUpAgentsThatAppearLater() async throws {
        try await withHerdr { herdr in
            let adapter = HerdrAdapter(client: herdr.client, timing: .test)
            let recorder = EventRecorder(adapter.events())
            defer { recorder.stop() }
            _ = await recorder.wait(.seconds(5)) { $0.count >= 2 }

            let pane = try await herdr.addAgent(label: "Late")
            let ref = AgentRef(adapter: "herdr", localID: pane)
            _ = await recorder.wait(.seconds(5)) { state($0).agents[ref] != nil }
            // Its status changes arrive only through the new per-pane subscription.
            try await herdr.report(pane, "working")
            let events = await recorder.wait(.seconds(5)) { state($0).agents[ref]?.info.status == .working }
            #expect(state(events).agents[ref]?.info.status == .working)
            #expect(state(events).agents[ref]?.info.name == "Late" || state(events).agents[ref]?.info.name == nil)
        }
    }

    @Test func ridesOutARestartWithoutDroppingAgents() async throws {
        try await withHerdr { herdr in
            _ = try await herdr.addAgent(label: "Steady", state: "working")
            // Production timing tolerates ~7 s; this tolerates 1 s + 2 s.
            var timing = HerdrAdapter.Timing()
            timing.maxBackoff = .seconds(2)
            let adapter = HerdrAdapter(client: herdr.client, timing: timing)
            let recorder = EventRecorder(adapter.events())
            defer { recorder.stop() }
            let before = await recorder.wait(.seconds(5)) { $0.count >= 2 }.count

            herdr.halt()
            try await Task.sleep(for: .milliseconds(500))
            try herdr.launch()
            let events = await recorder.wait(.seconds(10)) { events in
                events.dropFirst(before).contains { if case .snapshot = $0 { true } else { false } }
            }
            let after = events.dropFirst(before)
            #expect(after.contains { if case .snapshot = $0 { true } else { false } }, "re-snapshots after reconnecting")
            // Clearing always comes with `.unavailable`. (The restarted server itself may come back
            // without the simulated agent, so an empty snapshot afterwards is fine.)
            #expect(!after.contains { if case .connection(.unavailable) = $0 { true } else { false } }, "a short restart isn't reported")
        }
    }

    @Test func focusAndUnknownAgents() async throws {
        try await withHerdr { herdr in
            let a = try await herdr.addAgent(label: "A")
            let b = try await herdr.addAgent(label: "B")
            let adapter = HerdrAdapter(client: herdr.client, timing: .test)
            let recorder = EventRecorder(adapter.events())
            defer { recorder.stop() }
            _ = await recorder.wait(.seconds(5)) { $0.count >= 2 }

            for pane in [b, a] {
                let ref = AgentRef(adapter: "herdr", localID: pane)
                try await adapter.perform(.focus(ref))
                let events = await recorder.wait(.seconds(5)) { state($0).agents[ref]?.info.isFocused == true }
                #expect(state(events).agents.values.filter(\.info.isFocused).map(\.ref) == [ref])
            }

            let ghost = AgentRef(adapter: "herdr", localID: "w99:p99")
            await #expect(throws: AgentActionError.unknownAgent(ghost)) { try await adapter.perform(.focus(ghost)) }
        }
    }
}

@Suite(.enabled(if: herdrInstalled, "needs herdr on PATH"))
struct HerdrSchemaDriftTests {
    @Test func installedHerdrSpeaksOurProtocol() throws {
        let schema = try #require(try HerdrSchema.installed())
        #expect(schema.protocolVersion == Herdr.supportedProtocol)
    }

    @Test(arguments: HerdrRequest.all)
    func requestMatchesTheSchema(_ request: HerdrRequest) throws {
        let schema = try #require(try HerdrSchema.installed())
        let problems = schema.validate(request)
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test func validatorCatchesDrift() throws {
        let schema = try #require(try HerdrSchema.installed())
        #expect(!schema.validate(HerdrRequest(method: "agent.focus", params: ["pane": "w1:p1"])).isEmpty, "renamed parameter")
        #expect(!schema.validate(HerdrRequest(method: "agent.wiggle", params: [:])).isEmpty, "unknown method")
        #expect(!schema.validate(HerdrRequest(method: "agent.start", params: ["name": "x", "kind": "claude", "pane_id": 3])).isEmpty, "wrong type")
    }
}
