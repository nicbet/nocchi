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
}
