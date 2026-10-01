import NocchiCore
import SwiftUI

/// A color we can interpolate. SwiftUI `Color` can't be mixed directly in a Canvas.
public struct RGBA: Equatable, Sendable {
    public var r, g, b, a: Double

    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public static let white = RGBA(1, 1, 1)
    public static let black = RGBA(0, 0, 0)

    /// Weighted form so p == 0 and p == 1 return the endpoints exactly.
    public func mixed(with other: RGBA, _ p: Double) -> RGBA {
        RGBA(r * (1 - p) + other.r * p, g * (1 - p) + other.g * p, b * (1 - p) + other.b * p, a * (1 - p) + other.a * p)
    }

    public func lighter(_ p: Double) -> RGBA { mixed(with: .white, p) }
    public func darker(_ p: Double) -> RGBA { mixed(with: .black, p) }
    public func opacity(_ o: Double) -> RGBA { RGBA(r, g, b, a * o) }

    public var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    public var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

/// Face colors. **Color means state**: every face in a mood has the same body color, so the
/// collapsed notch reads at a glance (amber needs you, red failed, green finished). Agent identity
/// comes from position, name and kind, not color.
public enum FacePalette {
    public static func body(for mood: Mood) -> RGBA {
        switch mood {
        case .idle: RGBA(0.93, 0.94, 0.97)       // near-white
        case .thinking: RGBA(0.64, 0.54, 0.98)   // purple
        case .working: RGBA(0.36, 0.62, 0.98)    // blue
        case .waiting: RGBA(0.98, 0.73, 0.27)    // amber
        case .done: RGBA(0.40, 0.82, 0.54)       // green
        case .error: RGBA(0.93, 0.33, 0.34)      // red
        case .sleep: RGBA(0.52, 0.54, 0.60)      // gray
        }
    }

    static let eye = RGBA(0.07, 0.07, 0.09)
    static let ring = RGBA(0.99, 0.76, 0.30)
    /// Dark so it reads on every body color, including the blue working face.
    static let badge = RGBA(0.13, 0.14, 0.17)
    static let errorDot = RGBA(1.0, 0.62, 0.60)
    static let sparkle = RGBA(1.0, 0.94, 0.66)
}
