import AppKit

/// Where the notch is on a screen, in global screen coordinates (origin bottom-left).
public struct NotchGeometry: Equatable, Sendable {
    public var screenFrame: CGRect
    public var notchSize: CGSize
    public var notchCenterX: CGFloat
    /// False when we draw a notch on a screen without one (external display, clamshell).
    public var hasHardwareNotch: Bool

    /// Size of the drawn notch on screens without a hardware notch.
    static let fallbackNotchWidth: CGFloat = 185
    static let fallbackNotchHeight: CGFloat = 24

    public static func make(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        topLeftArea: CGRect?,
        topRightArea: CGRect?,
        menuBarHeight: CGFloat
    ) -> NotchGeometry {
        if safeAreaTop > 0, let left = topLeftArea, let right = topRightArea {
            let width = screenFrame.width - left.width - right.width
            return NotchGeometry(
                screenFrame: screenFrame,
                notchSize: CGSize(width: width, height: safeAreaTop),
                notchCenterX: screenFrame.minX + left.width + width / 2,
                hasHardwareNotch: true
            )
        }
        let height = menuBarHeight > 0 ? menuBarHeight : fallbackNotchHeight
        return NotchGeometry(
            screenFrame: screenFrame,
            notchSize: CGSize(width: fallbackNotchWidth, height: height),
            notchCenterX: screenFrame.midX,
            hasHardwareNotch: false
        )
    }

    @MainActor
    public init(screen: NSScreen) {
        self = Self.make(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            topLeftArea: screen.auxiliaryTopLeftArea,
            topRightArea: screen.auxiliaryTopRightArea,
            menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY
        )
    }

    init(screenFrame: CGRect, notchSize: CGSize, notchCenterX: CGFloat, hasHardwareNotch: Bool) {
        self.screenFrame = screenFrame
        self.notchSize = notchSize
        self.notchCenterX = notchCenterX
        self.hasHardwareNotch = hasHardwareNotch
    }

    /// A rect of `size` hanging from the top of the screen, centered on the notch.
    public func rectHanging(_ size: CGSize) -> CGRect {
        CGRect(
            x: notchCenterX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// The screen nocchi lives on: the one named `name` if it's connected, else the one with a
    /// hardware notch, else the main screen.
    @MainActor
    public static func preferredScreen(named name: String? = nil) -> NSScreen? {
        if let name, let screen = NSScreen.screens.first(where: { $0.localizedName == name }) { return screen }
        return NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }
}
