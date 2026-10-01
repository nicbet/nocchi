import NocchiCore
import Testing
@testable import NocchiUI

@Suite struct PeekPolicyTests {
    let a = AgentRef(adapter: "mock", localID: "a")
    let b = AgentRef(adapter: "mock", localID: "b")
    func peek(_ ref: AgentRef, _ mood: Mood) -> PeekTracker.Peek { .init(ref: ref, mood: mood, duration: .seconds(1)) }

    @Test func needsYouOpensFinishesGetABanner() {
        let policy = PeekPolicy(level: .everything, statusTextAnnounces: false)
        let actions = policy.actions(for: [peek(b, .waiting), peek(a, .done)]) { _ in true }
        #expect(actions == [.open(peek(b, .waiting)), .banner(peek(a, .done))])
        #expect(policy.actions(for: [peek(a, .error)]) { _ in true } == [.banner(peek(a, .error))])
    }

    @Test func whatYouAreLookingAtOnlyCelebrates() {
        let policy = PeekPolicy(level: .everything, statusTextAnnounces: false)
        #expect(policy.actions(for: [peek(a, .done)]) { _ in false }.isEmpty)
    }

    @Test func levelsAndTheStatusText() {
        #expect(PeekPolicy(level: .needsYou, statusTextAnnounces: false).actions(for: [peek(a, .done), peek(b, .waiting)]) { _ in true }
            == [.open(peek(b, .waiting))])
        #expect(PeekPolicy(level: .never, statusTextAnnounces: false).actions(for: [peek(b, .waiting)]) { _ in true }.isEmpty)
        #expect(PeekPolicy(level: .everything, statusTextAnnounces: true).actions(for: [peek(a, .done)]) { _ in true }.isEmpty,
                "the middle of the notch already says it")
    }

    @Test func bannersCountAndTurnRedOnFailure() {
        let c = AgentRef(adapter: "mock", localID: "c")
        var banner = PeekBanner(ref: a, name: "api", mood: .done)
        #expect(banner.text == "api finished")
        #expect(banner.mood == .done)
        banner = banner.adding(b, mood: .done)
        #expect(banner.text == "2 agents finished")
        banner = banner.adding(c, mood: .error)
        #expect(banner.text == "2 finished · 1 failed")
        #expect(banner.mood == .error)
        #expect(banner.adding(b, mood: .done).refs.count == 3, "no duplicates")
        #expect(PeekBanner(ref: a, name: "api", mood: .error).text == "api failed")
    }
}
