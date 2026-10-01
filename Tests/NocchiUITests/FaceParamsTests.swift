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

    @Test(arguments: Mood.allCases)
    func reduceMotionRemovesTravelButKeepsBlinksAndPulses(mood: Mood) {
        let samples = stride(from: 0.0, to: 20, by: 0.05).map { FaceParams.make(mood, t: $0, seed: 0.4, reduceMotion: true) }
        let still = samples.allSatisfy { $0.offset == .zero && $0.scale == 1 }
        let fixedTilt = Set(samples.map(\.rotation)).count == 1
        #expect(still)
        #expect(fixedTilt)
    }

    @Test func reduceMotionStillBlinksAndPulses() {
        let idle = stride(from: 0.0, to: 20, by: 0.01).map { FaceParams.make(.idle, t: $0, seed: 0.4, reduceMotion: true).eyeHeight }
        let waiting = stride(from: 0.0, to: 5, by: 0.05).map { FaceParams.make(.waiting, t: $0, seed: 0.4, reduceMotion: true).ring }
        #expect(Set(idle).count > 1, "blinks")
        #expect(Set(waiting).count > 1, "ring pulses")
        #expect(FaceParams.make(.waiting, t: 3, seed: 0, reduceMotion: true).rotation > 0, "keeps the head-tilt pose")
    }
}

@Suite struct FacePaletteTests {
    @Test func everyMoodHasItsOwnColor() {
        let colors = Mood.allCases.map(FacePalette.body(for:))
        for (i, a) in colors.enumerated() {
            for b in colors[(i + 1)...] {
                let distance = abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
                #expect(distance > 0.25, "\(a) and \(b) are too close to tell apart")
            }
        }
    }

    @Test func moodChangeBlendsTheColor() {
        var motion = FaceMotion(mood: .working)
        motion.setMood(.done, at: 10)
        let middle = motion.params(at: 10 + FaceMotion.transitionDuration / 2, motionTime: 0, seed: 0).body
        let blue = FacePalette.body(for: .working), green = FacePalette.body(for: .done)
        #expect(middle != blue && middle != green)
        #expect(motion.params(at: 11, motionTime: 0, seed: 0).body == green)
    }
}

@Suite struct FaceCalmnessTests {
    /// Faces don't bob up and down; accessories carry the motion. Only the error shake moves the face.
    @Test(arguments: Mood.allCases.filter { $0 != .error })
    func facesStayInPlace(mood: Mood) {
        let moves = stride(from: 0.0, to: 10, by: 0.05).contains { FaceParams.make(mood, t: $0, seed: 0.3).offset != .zero }
        #expect(!moves)
    }
}
