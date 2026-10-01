import NocchiCore
import Testing
@testable import NocchiUI

@Suite struct PeekTrackerTests {
    let a = AgentRef(adapter: "mock", localID: "a")
    let b = AgentRef(adapter: "mock", localID: "b")

    @Test func moodsAlreadyThereAtStartDontPeek() {
        var tracker = PeekTracker()
        #expect(tracker.update([a: .waiting, b: .done]).isEmpty)
        #expect(tracker.update([a: .waiting, b: .done]).isEmpty)
    }

    @Test func enteringAnAttentionMoodPeeksOnce() {
        var tracker = PeekTracker()
        _ = tracker.update([a: .working])
        #expect(tracker.update([a: .done]) == [.init(ref: a, mood: .done, duration: .milliseconds(3500))])
        #expect(tracker.update([a: .done]).isEmpty)
        _ = tracker.update([a: .idle])
        #expect(tracker.update([a: .done]).first?.mood == .done, "a new turn finishing peeks again")
    }

    @Test func calmMoodsDontPeek() {
        var tracker = PeekTracker()
        _ = tracker.update([a: .idle])
        #expect(tracker.update([a: .working]).isEmpty)
        #expect(tracker.update([a: .sleep]).isEmpty)
        #expect(tracker.update([a: .thinking]).isEmpty)
    }

    @Test func newAgentsThatNeedYouPeek() {
        var tracker = PeekTracker()
        _ = tracker.update([:])
        #expect(tracker.update([a: .waiting]).first?.ref == a)
    }

    @Test func theMostUrgentWins() {
        var tracker = PeekTracker()
        _ = tracker.update([a: .working, b: .working])
        #expect(tracker.update([a: .done, b: .waiting]).map(\.ref) == [b, a])
    }
}
