import CoreGraphics
import Testing
@testable import NocchiUI

@Suite struct ClusterLayoutTests {
    let h: CGFloat = 32

    @Test func nobodyElseMeansNoRightSide() {
        #expect(ClusterLayout.make(count: 0, height: h) == nil)
    }

    @Test func columnsAndRowsGrowWithTheCount() {
        let shapes = (1...8).map { ClusterLayout.make(count: $0, height: h).map { "\($0.columns)x\($0.rows)" } }
        #expect(shapes == ["1x1", "1x2", "2x2", "2x2", "2x3", "2x3", "2x3", "2x3"])
    }

    @Test func facesShrinkOnlyAsNeeded() throws {
        let one = try #require(ClusterLayout.make(count: 1, height: h))
        let four = try #require(ClusterLayout.make(count: 4, height: h))
        let six = try #require(ClusterLayout.make(count: 6, height: h))
        #expect(one.faceSize > four.faceSize)
        #expect(four.faceSize > six.faceSize)
        // Three rows still fit the notch's height.
        #expect(3 * six.faceSize + 2 * six.gap <= h)
        #expect(one.width < four.width, "one column is narrower")
    }

    @Test func spotsFillRowsLeftToRightAroundTheCenter() throws {
        let six = try #require(ClusterLayout.make(count: 6, height: h))
        #expect(six.offset(0).width < 0 && six.offset(0).height < 0)
        #expect(six.offset(1).width > 0 && six.offset(1).height < 0)
        #expect(six.offset(2).height == 0)
        #expect(six.offset(5).width > 0 && six.offset(5).height > 0)
        let two = try #require(ClusterLayout.make(count: 2, height: h))
        #expect(two.offset(0).width == 0 && two.offset(1).width == 0)
        #expect(two.offset(0).height == -two.offset(1).height)
    }
}
