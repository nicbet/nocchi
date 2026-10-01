import CoreGraphics
import Testing
@testable import NocchiUI

@Suite struct GreetingTimelineTests {
    @Test func everythingFinishesBeforeTheNotchCollapses() {
        let lastSparkDies = GreetingTimeline.emitEnd + GreetingTimeline.pulseTravel
        #expect(lastSparkDies <= GreetingTimeline.duration)
        #expect(GreetingTimeline.glowFade.upperBound <= GreetingTimeline.duration)
    }

    @Test func theJumpTakesOffAsTheNotchCollapsesAndLandsWithIt() {
        #expect(GreetingTimeline.duration >= GreetingTimeline.launch.lowerBound)
        #expect(GreetingTimeline.duration <= GreetingTimeline.launch.upperBound)
        // The collapse spring (0.35 s) and the flight end together.
        #expect(abs(GreetingTimeline.flight.upperBound - (GreetingTimeline.duration + 0.35)) < 0.05)
        #expect(GreetingTimeline.tuck.upperBound <= GreetingTimeline.flight.upperBound)
        let landing = CGPoint(x: -110, y: -96)
        #expect(GreetingTimeline.jump(GreetingTimeline.flight.lowerBound, to: landing) == .zero)
        #expect(GreetingTimeline.jump(GreetingTimeline.flight.upperBound, to: landing) == landing)
    }

    @Test func handsComeOutWaveGoodbyeThenDropForTheJump() {
        #expect(GreetingTimeline.open.upperBound <= GreetingTimeline.handsIn.lowerBound)
        #expect(GreetingTimeline.handsIn.upperBound <= GreetingTimeline.goodbye.lowerBound)
        #expect(GreetingTimeline.goodbye.upperBound <= GreetingTimeline.armsDown.lowerBound)
        #expect(GreetingTimeline.armsDown.lowerBound <= GreetingTimeline.crouch.lowerBound)
        #expect(GreetingTimeline.crouch.upperBound <= GreetingTimeline.launch.lowerBound)
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
