import Testing
@testable import NocchiUI

@Suite struct GreetingTimelineTests {
    @Test func everythingFinishesBeforeTheNotchCollapses() {
        let lastSparkDies = GreetingTimeline.emitEnd + GreetingTimeline.sparkLifetime.upperBound
        #expect(lastSparkDies <= GreetingTimeline.duration)
        #expect(GreetingTimeline.bow.upperBound <= GreetingTimeline.duration)
        #expect(GreetingTimeline.glowFade.upperBound <= GreetingTimeline.duration)
    }

    @Test func handsTuckBeforeTheBowEnds() {
        #expect(GreetingTimeline.tuck.upperBound <= GreetingTimeline.bow.upperBound)
        #expect(GreetingTimeline.goodbye.upperBound <= GreetingTimeline.tuck.lowerBound)
    }

    @Test func progressIsClampedAndEased() {
        #expect(GreetingTimeline.progress(0, 1...2) == 0)
        #expect(GreetingTimeline.progress(3, 1...2) == 1)
        #expect(GreetingTimeline.progress(1.5, 1...2) == 0.5)
    }
}
