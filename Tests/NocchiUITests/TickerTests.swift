import NocchiCore
import Testing
@testable import NocchiUI

@MainActor
@Suite struct TickerTests {
    func message(_ id: String, _ mood: Mood) -> Ticker.Message {
        Ticker.Message(ref: AgentRef(adapter: "mock", localID: id), name: id, mood: mood)
    }

    @Test func textNamesTheAgentFirst() {
        #expect(message("Atlas", .waiting).text == "Atlas needs you")
        #expect(message("webapp", .error).text == "webapp failed")
        #expect(message("Nocchi", .done).text == "Nocchi finished")
    }

    @Test func showsMostUrgentFirstThenEmpties() async throws {
        let ticker = Ticker(hold: .milliseconds(80))
        ticker.announce(message("a", .done))     // shows right away
        ticker.announce(message("b", .done))
        ticker.announce(message("c", .waiting))  // jumps the queue, not the current message
        var seen: [String] = []
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            if let current = ticker.current, seen.last != current.ref.localID { seen.append(current.ref.localID) }
            if ticker.current == nil && !seen.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(seen == ["a", "c", "b"])
        #expect(ticker.current == nil)
    }

    @Test func newerStateOfTheSameAgentReplacesItsQueuedMessage() async throws {
        let ticker = Ticker(hold: .seconds(10))
        ticker.announce(message("a", .done))
        ticker.announce(message("b", .done))
        ticker.announce(message("b", .waiting))
        ticker.announce(message("a", .done))  // already showing: ignored
        #expect(ticker.current?.ref.localID == "a")
        ticker.stop()
        #expect(ticker.current == nil)
    }
}
