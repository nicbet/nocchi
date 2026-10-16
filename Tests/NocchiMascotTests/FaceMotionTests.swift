import CoreGraphics
import NocchiCore
import Testing
@testable import NocchiMascot

@Suite struct FaceMotionTests {
    @Test func moodChangeBlendsThenSettles() {
        var motion = FaceMotion(mood: .idle)
        motion.setMood(.done, at: 100)

        let start = motion.params(at: 100, motionTime: 1, seed: 0)
        let middle = motion.params(at: 100 + FaceMotion.transitionDuration / 2, motionTime: 1, seed: 0)
        let end = motion.params(at: 100 + FaceMotion.transitionDuration, motionTime: 1, seed: 0)

        #expect(start.caret == 0)
        #expect(middle.caret > 0 && middle.caret < 1)
        #expect(end == FaceParams.make(.done, t: 1, seed: 0))
        #expect(motion.isTransitioning(at: 100.1))
        #expect(!motion.isTransitioning(at: 101))
    }

    @Test func settingTheSameMoodDoesNotRestartTheTransition() {
        var motion = FaceMotion(mood: .idle)
        motion.setMood(.idle, at: 100)
        #expect(!motion.isTransitioning(at: 100))
    }

    @Test func gazeFollowsThePointerAndIsCapped() {
        let idle = FaceParams.make(.idle, t: 0, seed: 0)
        let right = FaceMotion.gaze(idle, pointer: CGVector(dx: 500, dy: 0), size: 20)
        #expect(right.dx > 0.99 && abs(right.dy) < 0.01)

        let near = FaceMotion.gaze(idle, pointer: CGVector(dx: 10, dy: 0), size: 20)
        #expect(near.dx > 0 && near.dx < 0.2, "gaze is weaker close to the face")

        let waiting = FaceMotion.gaze(FaceParams.make(.waiting, t: 0, seed: 0), pointer: CGVector(dx: 300, dy: 400), size: 20)
        #expect(hypot(waiting.dx, waiting.dy) <= 1.0001)
    }

    @Test func moodsWithoutGazeIgnoreThePointer() {
        let done = FaceParams.make(.done, t: 0, seed: 0)
        #expect(FaceMotion.gaze(done, pointer: CGVector(dx: 500, dy: 0), size: 20) == done.gazeBias)
        #expect(FaceMotion.gaze(FaceParams.make(.idle, t: 0, seed: 0), pointer: nil, size: 20) == .zero)
    }
}
