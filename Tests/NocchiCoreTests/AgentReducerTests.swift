import Foundation
import Testing
@testable import NocchiCore

let mock: AdapterID = "mock"
let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

func agent(_ id: String, _ status: AgentStatus, title: String? = nil, focused: Bool = false,
           changed: TimeInterval = 0, adapter: AdapterID = mock) -> AgentInfo {
    AgentInfo(ref: AgentRef(adapter: adapter, localID: id), kind: .claude, status: status, title: title,
              cwd: URL(fileURLWithPath: "/work/\(id)"), isFocused: focused, changedAt: t0.addingTimeInterval(changed))
}

func ref(_ id: String, adapter: AdapterID = mock) -> AgentRef { AgentRef(adapter: adapter, localID: id) }

func reduce(_ events: [AgentEvent], from adapter: AdapterID = mock, into state: AgentsState = AgentsState(), now: Date = t0) -> AgentsState {
    var state = state
    for event in events { AgentReducer.reduce(&state, event, from: adapter, now: now) }
    return state
}

@Suite struct AgentReducerTests {
    @Test func snapshotReplacesOnlyThatAdaptersAgents() {
        var state = reduce([.snapshot([agent("a", .idle), agent("b", .working)])])
        state = reduce([.snapshot([agent("x", .idle, adapter: "other")])], from: "other", into: state)
        state = reduce([.snapshot([agent("b", .done)])], into: state)

        #expect(Set(state.agents.keys) == [ref("b"), ref("x", adapter: "other")])
        #expect(state.agents[ref("b")]?.info.status == .done)
    }

    @Test func slotsAreStableAndAssignedOnArrival() {
        var state = reduce([.upserted(agent("a", .idle)), .upserted(agent("b", .idle)), .upserted(agent("c", .idle))])
        state = reduce([.removed(ref("b")), .upserted(agent("a", .working)), .upserted(agent("d", .idle))], into: state)
        #expect(state.agents[ref("a")]?.slot == 0)
        #expect(state.agents[ref("c")]?.slot == 2)
        #expect(state.agents[ref("d")]?.slot == 3)
    }

    @Test func stepsComeFromStepEventsAndTitleChanges() {
        let state = reduce([
            .upserted(agent("a", .working, title: "Fix login")),
            .step(ref("a"), "Reading Auth.swift"),
            .step(ref("a"), "Reading Auth.swift"),
            .upserted(agent("a", .working, title: "Fix login")),
            .upserted(agent("a", .working, title: "Run tests")),
            .step(ref("a"), "Editing Auth.swift"),
        ])
        #expect(state.agents[ref("a")]?.steps == ["Reading Auth.swift", "Run tests", "Editing Auth.swift"])
    }

    @Test func eventsForUnknownAgentsAreIgnored() {
        let state = reduce([.step(ref("ghost"), "boo"), .turnFinished(ref("ghost"))])
        #expect(state.agents.isEmpty)
    }

    @Test func connectionStateIsTrackedPerAdapter() {
        let state = reduce([.connection(.connected(version: "0.9.0"))])
        #expect(state.connections[mock] == .connected(version: "0.9.0"))
    }
}

@Suite struct MoodTests {
    @Test(arguments: [
        (AgentStatus.starting, Mood.thinking), (.thinking, .thinking), (.working, .working),
        (.blocked, .waiting), (.done, .done), (.error("boom"), .error), (.idle, .idle),
    ])
    func statusMapsToMood(status: AgentStatus, mood: Mood) {
        let state = reduce([.upserted(agent("a", status))])
        #expect(state.agents[ref("a")]?.mood(at: t0) == mood)
    }

    @Test func idleAgentsFallAsleep() {
        let entry = reduce([.upserted(agent("a", .idle))]).agents[ref("a")]!
        #expect(entry.mood(at: t0.addingTimeInterval(AgentsState.sleepAfter - 1)) == .idle)
        #expect(entry.mood(at: t0.addingTimeInterval(AgentsState.sleepAfter)) == .sleep)
    }

    @Test func turnFinishedCelebratesBrieflyEvenWhenStatusIsIdle() {
        let state = reduce([.upserted(agent("a", .idle)), .turnFinished(ref("a"))])
        let entry = state.agents[ref("a")]!
        #expect(entry.mood(at: t0.addingTimeInterval(1)) == .done)
        #expect(entry.mood(at: t0.addingTimeInterval(AgentsState.celebrationDuration + 0.1)) == .idle)
    }
}

@Suite struct PrimaryTests {
    @Test func mostUrgentAgentIsPrimary() {
        let state = reduce([.snapshot([
            agent("working", .working, focused: true),
            agent("done", .done, changed: 5),
            agent("blocked", .blocked, changed: 1),
            agent("error", .error(nil), changed: 9),
        ])])
        #expect(state.primary(at: t0)?.ref == ref("blocked"))
    }

    @Test func amongEquallyUrgentTheNewestWins() {
        let state = reduce([.snapshot([agent("old", .done, changed: 1), agent("new", .done, changed: 2)])])
        #expect(state.primary(at: t0)?.ref == ref("new"))
    }

    @Test func withoutUrgencyTheFocusedAgentIsPrimary() {
        let state = reduce([.snapshot([agent("a", .working, changed: 9), agent("b", .idle, focused: true)])])
        #expect(state.primary(at: t0)?.ref == ref("b"))
    }

    @Test func otherwiseTheMostRecentlyChanged() {
        let state = reduce([.snapshot([agent("a", .working, changed: 1), agent("b", .idle, changed: 7)])])
        #expect(state.primary(at: t0)?.ref == ref("b"))
    }

    @Test func othersExcludePrimaryInSlotOrder() {
        let state = reduce([.snapshot([agent("a", .idle), agent("b", .blocked), agent("c", .working)])])
        #expect(state.others(at: t0).map(\.ref) == [ref("a"), ref("c")])
    }

    @Test func withoutOverflowEveryoneShowsInSlotOrder() {
        let state = reduce([.snapshot([agent("p", .blocked), agent("a", .idle), agent("b", .working), agent("c", .idle)])])
        let (shown, hidden) = state.others(at: t0, fitting: 4)
        #expect(shown.map(\.ref) == [ref("a"), ref("b"), ref("c")])
        #expect(hidden.isEmpty)
    }

    @Test func withOverflowAgentsThatNeedYouAreNeverHidden() {
        // p is primary (most urgent). Slots 1–4 are calm; e (slot 5) and f (slot 6) need you.
        let state = reduce([.snapshot([
            agent("p", .blocked, changed: 9), agent("a", .idle), agent("b", .working), agent("c", .idle),
            agent("d", .idle), agent("e", .done), agent("f", .blocked),
        ])])
        let (shown, hidden) = state.others(at: t0, fitting: 4)
        #expect(shown.map(\.ref) == [ref("a"), ref("e"), ref("f")], "3 spots + the +N spot; urgent first, shown in slot order")
        #expect(hidden.map(\.ref) == [ref("b"), ref("c"), ref("d")])
        #expect(state.mostUrgent(hidden, at: t0)?.ref == ref("b"), "working beats idle")
    }

    @Test func noAgentsNoPrimary() {
        #expect(AgentsState().primary(at: t0) == nil)
    }
}
