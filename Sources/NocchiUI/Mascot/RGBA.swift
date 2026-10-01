import SwiftUI

/// A color we can interpolate. SwiftUI `Color` can't be mixed directly in a Canvas.
public struct RGBA: Equatable, Sendable {
    public var r, g, b, a: Double

    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public static let white = RGBA(1, 1, 1)
    public static let black = RGBA(0, 0, 0)

    public func mixed(with other: RGBA, _ p: Double) -> RGBA {
        RGBA(r + (other.r - r) * p, g + (other.g - g) * p, b + (other.b - b) * p, a + (other.a - a) * p)
    }

    public func lighter(_ p: Double) -> RGBA { mixed(with: .white, p) }
    public func darker(_ p: Double) -> RGBA { mixed(with: .black, p) }
    public func opacity(_ o: Double) -> RGBA { RGBA(r, g, b, a * o) }

    public var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    public var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

/// Face colors. The primary face is near-white; other agents get a stable slot color.
public enum FacePalette {
    public static let primary = RGBA(0.93, 0.94, 0.97)
    public static let bots: [RGBA] = [
        RGBA(0.93, 0.36, 0.33),  // red
        RGBA(0.56, 0.45, 0.96),  // purple
        RGBA(0.38, 0.79, 0.69),  // teal
        RGBA(0.96, 0.71, 0.28),  // amber
        RGBA(0.95, 0.46, 0.67),  // pink
        RGBA(0.36, 0.61, 0.97),  // blue
        RGBA(0.62, 0.84, 0.36),  // lime
    ]

    public static func bot(_ slot: Int) -> RGBA { bots[((slot % bots.count) + bots.count) % bots.count] }

    static let eye = RGBA(0.07, 0.07, 0.09)
    static let error = RGBA(0.90, 0.25, 0.28)
    static let ring = RGBA(0.98, 0.70, 0.22)
    static let badge = RGBA(0.25, 0.56, 0.98)
    static let sparkle = RGBA(1.0, 0.92, 0.62)
}
