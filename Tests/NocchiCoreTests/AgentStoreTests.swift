import Foundation
import Testing
@testable import NocchiCore

@MainActor
@Suite struct AgentStoreTests {
    /// Herdr and a launcher-only source (Claude Code) both running, both connected.
    private func storeWithTwoStarters() async throws -> AgentStore {
        let store = AgentStore()
        store.run(MockAdapter(id: "herdr", timeScale: 0))
        store.run(MockAdapter(id: "claude", capabilities: [.focus, .start], timeScale: 0))
        let deadline = ContinuousClock.now + .seconds(2)
        while store.state.connections.count < 2, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(store.state.connections.count == 2)
        return store
    }

    @Test func newAgentsGoToASourceNocchiCanTalkTo() async throws {
        let store = try await storeWithTwoStarters()
        #expect(store.starter == "herdr")
    }

    @Test func newAgentsFallBackWhileHerdrIsDown() async throws {
        let store = try await storeWithTwoStarters()
        store.apply(.connection(.unavailable(reason: "not running")), from: "herdr")
        #expect(store.starter == "claude")
        store.apply(.connection(.connected(version: nil)), from: "herdr")
        #expect(store.starter == "herdr")
    }

    @Test func nobodyStartsAgentsWithoutTheCapability() {
        let store = AgentStore()
        store.run(MockAdapter(id: "claude", capabilities: [.focus], timeScale: 0))
        #expect(store.starter == nil)
        #expect(!store.canStartAgents)
    }

    @Test func startReportsTheNewAgentAndSelectingItMakesItPrimary() async throws {
        let store = AgentStore()
        let mock = MockAdapter(scenario: MockScenario(name: "one", agents: [MockAgent("a", status: .idle, focused: true)]), timeScale: 0)
        store.run(mock)
        try await wait { store.state.agents.count == 1 }
        let started = try #require(try await store.perform(.start(kind: .claude, cwd: URL(fileURLWithPath: "/tmp/x"), prompt: "hi")))
        store.select(started, yieldsToAnyUrgent: true)
        try await wait { store.state.agents[started] != nil }
        #expect(store.primary?.ref == started)

        // Another agent needs you: it wins, and the new one is back once it's answered.
        let other = AgentRef(adapter: "mock", localID: "a")
        await mock.add(AgentInfo(ref: other, kind: .claude, status: .blocked, changedAt: Date()))
        try await wait { store.state.agents[other]?.info.status == .blocked }
        #expect(store.primary?.ref == other)
        await mock.add(AgentInfo(ref: other, kind: .claude, status: .idle, changedAt: Date()))
        try await wait { store.state.agents[other]?.info.status == .idle }
        #expect(store.primary?.ref == started)
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(condition())
    }
}
