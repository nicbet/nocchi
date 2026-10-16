import Foundation
import Testing
@testable import NocchiTerminals

/// The matching behind `WindowRaiser.windowID(in:matching:)`, on stand-in windows and tabs.
@Suite struct WindowRaiserTests {
    typealias Candidate = WindowRaiser.Candidate<String>

    func window(_ id: String, _ title: String) -> Candidate { Candidate(element: id, window: id, title: title, isTab: false) }
    func tab(_ id: String, in window: String, _ title: String) -> Candidate { Candidate(element: id, window: window, title: title, isTab: true) }

    var terminal: [Candidate] {
        [window("w1", "✳ Fix the login bug"), tab("w1.t1", in: "w1", "✳ Fix the login bug"), tab("w1.t2", in: "w1", "nocchi"),
         window("w2", "zsh"), tab("w2.t1", in: "w2", "zsh"), tab("w2.t2", in: "w2", "✳ Write the README")]
    }

    @Test func aMatchingTabResolvesToItsWindow() {
        let match = WindowRaiser.bestCandidate(terminal, hints: ["Write the README", "agentspaces"])
        #expect(match?.isTab == true)
        #expect(match?.element == "w2.t2")
        #expect(match?.window == "w2", "a background tab's window")
    }

    @Test func aMatchingWindowResolvesToItself() {
        let match = WindowRaiser.bestCandidate(terminal, hints: ["fix the login BUG"])
        #expect(match?.window == "w1")
        #expect(match?.isTab == false, "the window comes first")
    }

    @Test func theEarliestHintWins() {
        #expect(WindowRaiser.bestCandidate(terminal, hints: ["nocchi", "zsh"])?.window == "w1")
        #expect(WindowRaiser.bestCandidate(terminal, hints: ["missing", "zsh"])?.window == "w2", "falls back to a later hint")
    }

    @Test func noMatchIsNil() {
        #expect(WindowRaiser.bestCandidate(terminal, hints: ["agentspaces"]) == nil)
        #expect(WindowRaiser.bestCandidate(terminal, hints: []) == nil)
        #expect(WindowRaiser.bestCandidate(terminal, hints: ["x"]) == nil, "one-letter hints don't count")
        #expect(WindowRaiser.bestCandidate([Candidate](), hints: ["zsh"]) == nil)
    }

    @Test func aBatchMatchesEachAgentInOrder() {
        let hints = [["Write the README"], ["agentspaces"], ["fix the login bug"], [], ["missing", "nocchi"]]
        let matches = WindowRaiser.bestCandidates(terminal, hints: hints)
        #expect(matches.map { $0?.window } == ["w2", nil, "w1", nil, "w1"])
        #expect(matches.map { $0?.isTab } == [true, nil, false, nil, true])
        #expect(WindowRaiser.bestCandidates(terminal, hints: []).isEmpty)
    }

    @Test func runsOffTheMainActor() async {
        // Compiles only while the resolver is nonisolated; one result per list, whatever the access.
        let ids = await Task.detached { WindowRaiser.windowIDs(in: getpid(), matching: [["no such window title"], []]) }.value
        #expect(ids == [nil, nil])
    }
}
