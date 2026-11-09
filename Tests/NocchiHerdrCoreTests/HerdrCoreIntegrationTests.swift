import Foundation
import NocchiCore
import Testing
@testable import NocchiHerdrCore

let hcInstalled = IsolatedHerdrCore.findHc() != nil

extension HerdrCoreAdapter.Timing {
    /// Fast reconnects so the tests don't wait on backoff.
    static var test: Self {
        var timing = Self()
        timing.minBackoff = .milliseconds(200)
        timing.maxBackoff = .seconds(1)
        return timing
    }
}

struct HerdrCoreContractSubject: AgentAdapterContractSubject {
    let core: IsolatedHerdrCore

    func makeAdapter(capabilities: AdapterCapabilities) async throws -> AgentAdapter {
        HerdrCoreAdapter(client: core.client, app: core.noWindow, capabilities: capabilities, timing: .test)
    }
    func addAgent(to adapter: AgentAdapter) async throws -> String {
        try await core.addAgent()
    }
    func removeAgent(_ localID: String, from adapter: AgentAdapter) async throws {
        try await core.kill(localID)
    }
    func reconnect(_ adapter: AgentAdapter) async throws {
        try core.restart()
    }
}

/// Against a real, isolated herdr-core (see `IsolatedHerdrCore`). Skipped when hc isn't installed.
@Suite(.serialized, .enabled(if: hcInstalled, "needs hc on PATH"))
struct HerdrCoreIntegrationTests {
    func withCore(_ body: (IsolatedHerdrCore) async throws -> Void) async throws {
        let core = try #require(try IsolatedHerdrCore.start())
        defer { core.stop() }
        try await body(core)
        // Whatever the adapter sent must still match hc's schema.
        if let schema = try HcSchema.installed() {
            for request in core.recorded.withLock({ $0 }) {
                #expect(schema.validate(request).isEmpty, "\(schema.validate(request))")
            }
        }
    }

    func state(_ events: [AgentEvent]) -> AgentsState {
        var state = AgentsState()
        for event in events { AgentReducer.reduce(&state, event, from: "hc", now: Date()) }
        return state
    }

    @Test func passesTheAdapterContract() async throws {
        try await withCore { core in
            let failures = await AgentAdapterContract.check(HerdrCoreContractSubject(core: core), timeout: .seconds(20))
            #expect(failures.isEmpty, "\(failures)")
        }
    }

    @Test func followsAnAgentThroughATurnAndPrompts() async throws {
        try await withCore { core in
            let terminal = try await core.addAgent()
            let adapter = HerdrCoreAdapter(client: core.client, app: core.noWindow, timing: .test)
            let recorder = EventRecorder(adapter.events())
            defer { recorder.stop() }
            let ref = AgentRef(adapter: "hc", localID: terminal)

            let start = await recorder.wait(.seconds(10)) { state($0).agents[ref] != nil }
            #expect(state(start).agents[ref]?.info.status == .idle)
            #expect(state(start).agents[ref]?.info.kind == .other("fake"))

            try await core.report(terminal, "working")
            _ = await recorder.wait(.seconds(10)) { state($0).agents[ref]?.info.status == .working }
            try await core.report(terminal, "done")
            let done = await recorder.wait(.seconds(10)) { state($0).agents[ref]?.info.status == .done }
            #expect(state(done).agents[ref]?.info.status == .done)
            #expect(done.contains(.turnFinished(ref)))

            // A prompt reaches the program: the fake agent reports whatever it's sent.
            try await adapter.perform(.prompt(ref, "state=blocked:app=fake"))
            let blocked = await recorder.wait(.seconds(10)) { state($0).agents[ref]?.info.status == .blocked }
            #expect(state(blocked).agents[ref]?.info.status == .blocked)
            await #expect(throws: AgentActionError.self) { try await adapter.perform(.prompt(ref, "hi")) }

            // Without the window, showing or starting fails cleanly.
            await #expect(throws: AgentActionError.self) { try await adapter.perform(.focus(ref)) }
            await #expect(throws: AgentActionError.failed("Open Herdr to start agents")) {
                try await adapter.perform(.start(kind: .claude, cwd: core.directory))
            }

            try await core.kill(terminal)
            let gone = await recorder.wait(.seconds(10)) { state($0).agents[ref] == nil }
            #expect(state(gone).agents[ref] == nil)
        }
    }

    @Test func reportsUnavailableWithoutACore() async throws {
        let adapter = HerdrCoreAdapter(client: HcClient(socketPath: "/tmp/nocchi-no-such-core.sock"), timing: .test)
        let recorder = EventRecorder(adapter.events())
        defer { recorder.stop() }
        let events = await recorder.wait(.seconds(5)) { $0.count >= 2 }
        #expect(events.first == .connection(.unavailable(reason: "herdr-core isn't running")))
        #expect(events.dropFirst().first == .snapshot([]))
    }
}

@Suite(.enabled(if: hcInstalled, "needs hc on PATH"))
struct HcSchemaDriftTests {
    @Test func everyRequestMatchesTheInstalledSchema() throws {
        let schema = try #require(try HcSchema.installed())
        for request in HcRequest.all {
            #expect(schema.validate(request).isEmpty, "\(schema.validate(request))")
        }
    }
}
