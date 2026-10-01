import NocchiCore
import Testing
@testable import NocchiUI

@Suite struct PeekTrackerTests {
    let a = AgentRef(adapter: "mock", localID: "a")
    let b = AgentRef(adapter: "mock", localID: "b")

    @Test func moodsAlreadyThereAtStartDontPeek() {
        var tracker = PeekTracker()
        #expect(tracker.update([a: .waiting, b: .done]) == nil)
        #expect(tracker.update([a: .waiting, b: .done]) == nil)
    }

    @Test func enteringAnAttentionMoodPeeksOnce() {
        var tracker = PeekTracker()
        _ = tracker.update([a: .working])
        #expect(tracker.update([a: .done]) == .init(ref: a, mood: .done, duration: .milliseconds(3500)))
        #expect(tracker.update([a: .done]) == nil)
        _ = tracker.update([a: .idle])
        #expect(tracker.update([a: .done])?.mood == .done, "a new turn finishing peeks again")
    }

    @Test func calmMoodsDontPeek() {
        var tracker = PeekTracker()
        _ = tracker.update([a: .idle])
        #expect(tracker.update([a: .working]) == nil)
        #expect(tracker.update([a: .sleep]) == nil)
        #expect(tracker.update([a: .thinking]) == nil)
    }

    @Test func newAgentsThatNeedYouPeek() {
        var tracker = PeekTracker()
        _ = tracker.update([:])
        #expect(tracker.update([a: .waiting])?.ref == a)
    }

    @Test func theMostUrgentWins() {
        var tracker = PeekTracker()
        _ = tracker.update([a: .working, b: .working])
        #expect(tracker.update([a: .done, b: .waiting]) == .init(ref: b, mood: .waiting, duration: .seconds(6)))
    }
}
