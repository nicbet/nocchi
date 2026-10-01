import CoreGraphics
import NocchiCore
import Testing
@testable import NocchiUI

@Suite struct NotchGeometryTests {
    // 14" MacBook Pro at default scaling: 1512×982, 32 pt notch, ~185 pt wide.
    let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func hardwareNotchFromAuxiliaryAreas() {
        let g = NotchGeometry.make(
            screenFrame: frame,
            safeAreaTop: 32,
            topLeftArea: CGRect(x: 0, y: 950, width: 663, height: 32),
            topRightArea: CGRect(x: 849, y: 950, width: 663, height: 32),
            menuBarHeight: 32
        )
        #expect(g.hasHardwareNotch)
        #expect(g.notchSize == CGSize(width: 186, height: 32))
        #expect(g.notchCenterX == 756)
    }

    @Test func fallbackNotchOnScreensWithoutOne() {
        let external = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
        let g = NotchGeometry.make(screenFrame: external, safeAreaTop: 0, topLeftArea: nil, topRightArea: nil, menuBarHeight: 25)
        #expect(!g.hasHardwareNotch)
        #expect(g.notchSize.height == 25)
        #expect(g.notchCenterX == external.midX)
    }

    @Test func fallbackHeightWhenMenuBarAutoHides() {
        let g = NotchGeometry.make(screenFrame: frame, safeAreaTop: 0, topLeftArea: nil, topRightArea: nil, menuBarHeight: 0)
        #expect(g.notchSize.height == NotchGeometry.fallbackNotchHeight)
    }

    @Test func rectHangsFromTopCenteredOnNotch() {
        let g = NotchGeometry.make(screenFrame: frame, safeAreaTop: 0, topLeftArea: nil, topRightArea: nil, menuBarHeight: 24)
        let r = g.rectHanging(CGSize(width: 200, height: 50))
        #expect(r == CGRect(x: 656, y: 932, width: 200, height: 50))
    }
}

@Suite struct NotchShapeTests {
    @Test(arguments: [(6.0, 12.0), (14.0, 32.0), (100.0, 100.0)])
    func pathFillsItsRect(top: Double, bottom: Double) {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 60)
        let path = NotchShape(topRadius: top, bottomRadius: bottom).path(in: rect)
        #expect(path.boundingRect.width.rounded() == rect.width)
        #expect(path.boundingRect.height.rounded() == rect.height)
    }
}

@MainActor
@Test func chipsCardSitsInTheRightOfTheExpandedNotch() {
    let geometry = NotchGeometry.make(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
                                      topLeftArea: CGRect(x: 0, y: 0, width: 663, height: 32),
                                      topRightArea: CGRect(x: 0, y: 0, width: 663, height: 32), menuBarHeight: 32)
    let model = NotchModel(geometry: geometry, store: AgentStore())
    model.mode = .expanded
    let chips = model.chipsScreenRect
    #expect(model.hitRect.contains(chips))
    #expect(chips.minX > geometry.notchCenterX)
    #expect(chips.maxY < geometry.screenFrame.maxY - geometry.notchSize.height, "below the notch")
}
