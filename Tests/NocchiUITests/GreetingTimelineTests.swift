import Testing
@testable import NocchiUI

@Suite struct GreetingTimelineTests {
    @Test func everythingFinishesBeforeTheNotchCollapses() {
        let lastSparkDies = GreetingTimeline.emitEnd + GreetingTimeline.pulseTravel
        #expect(lastSparkDies <= GreetingTimeline.duration)
        #expect(GreetingTimeline.settle.upperBound + GreetingTimeline.idleHold <= GreetingTimeline.duration)
        #expect(GreetingTimeline.home.upperBound + GreetingTimeline.idleHold <= GreetingTimeline.duration)
        #expect(GreetingTimeline.glowFade.upperBound <= GreetingTimeline.duration)
    }

    @Test func handsComeOutWaveGoodbyeAndTuckBeforeTheSettle() {
        #expect(GreetingTimeline.open.upperBound <= GreetingTimeline.handsIn.lowerBound)
        #expect(GreetingTimeline.handsIn.upperBound <= GreetingTimeline.goodbye.lowerBound)
        #expect(GreetingTimeline.goodbye.upperBound <= GreetingTimeline.tuck.lowerBound)
        #expect(GreetingTimeline.tuck.upperBound <= GreetingTimeline.settle.upperBound)
    }

    @Test func overshootStartsAtZeroAndSettlesAtOne() {
        #expect(abs(GreetingTimeline.overshoot(0, 1...2)) < 1e-9)
        #expect(GreetingTimeline.overshoot(1.7, 1...2) > 1)
        #expect(GreetingTimeline.overshoot(3, 1...2) == 1)
    }

    @Test func progressIsClampedAndEased() {
        #expect(GreetingTimeline.progress(0, 1...2) == 0)
        #expect(GreetingTimeline.progress(3, 1...2) == 1)
        #expect(GreetingTimeline.progress(1.5, 1...2) == 0.5)
    }

    @Test func hashIsUniformEnough() {
        let values = (0..<4000).map { hash01(1, UInt64($0), 2) }
        let inRange = values.allSatisfy { $0 >= 0 && $0 < 1 }
        let buckets = Dictionary(grouping: values) { Int($0 * 4) }.mapValues(\.count)
        #expect(inRange)
        #expect(buckets.values.allSatisfy { $0 > 850 && $0 < 1150 }, "\(buckets)")
    }
}
