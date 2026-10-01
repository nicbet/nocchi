import CoreGraphics
import NocchiCore
import Testing
@testable import NocchiUI

@Suite struct FaceParamsTests {
    @Test func blinkStaysInRangeAndIsMostlyOpen() {
        let samples = stride(from: 0.0, to: 60, by: 0.01).map { FaceParams.blink($0, seed: 0.42) }
        let inRange = samples.allSatisfy { $0 >= 0.08 - 1e-9 && $0 <= 1 }
        let openShare = Double(samples.filter { $0 == 1 }.count) / Double(samples.count)
        let blinked = samples.contains { $0 < 0.2 }
        #expect(inRange)
        #expect(openShare > 0.9)
        #expect(blinked, "blinks at least once a minute")
    }

    @Test func facesWithDifferentSeedsBlinkAtDifferentTimes() {
        let a = stride(from: 0.0, to: 30, by: 0.02).map { FaceParams.blink($0, seed: 0.1) }
        let b = stride(from: 0.0, to: 30, by: 0.02).map { FaceParams.blink($0, seed: 0.6) }
        #expect(a != b)
    }

    @Test(arguments: Mood.allCases)
    func everyMoodProducesFiniteParams(mood: Mood) {
        for t in stride(from: 0.0, to: 10, by: 0.37) {
            let p = FaceParams.make(mood, t: t, seed: 0.3)
            let values = [p.offset.dx, p.offset.dy, p.rotation, p.scale, p.eyeWidth, p.eyeHeight, p.ring]
            let finite = values.allSatisfy(\.isFinite)
            #expect(finite)
            #expect(p.eyeHeight > 0)
        }
    }

    @Test func lerpHitsBothEnds() {
        let a = FaceParams.make(.idle, t: 1, seed: 0)
        let b = FaceParams.make(.done, t: 1, seed: 0)
        #expect(FaceParams.lerp(a, b, 0) == a)
        #expect(FaceParams.lerp(a, b, 1) == b)
        #expect(FaceParams.lerp(a, b, 0.5).caret == 0.5)
    }

    @Test func accessoriesBelongToTheirMoods() {
        #expect(FaceParams.make(.working, t: 0, seed: 0).badge == 1)
        #expect(FaceParams.make(.waiting, t: 0, seed: 0).ring > 0)
        #expect(FaceParams.make(.done, t: 0, seed: 0).sparkles == 1)
        #expect(FaceParams.make(.sleep, t: 0, seed: 0).zzz == 1)
        #expect(FaceParams.make(.error, t: 0, seed: 0).errorDot == 1)
        #expect(FaceParams.make(.idle, t: 0, seed: 0).badge == 0)
    }
}
