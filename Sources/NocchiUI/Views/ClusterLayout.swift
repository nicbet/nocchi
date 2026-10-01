import CoreGraphics

/// How the other agents sit on the right of the collapsed notch. Counting the primary on the left:
/// 1 agent, no right side; 2–4, one column of 1–3; 5–7, two columns (2×2 or 2×3); more, 2×3 with
/// the last spot a "+N" badge. Fewer rows, larger faces.
struct ClusterLayout: Equatable {
    var columns: Int
    var rows: Int
    var faceSize: CGFloat
    var gap: CGFloat
    /// Width of the right ear holding the faces.
    var width: CGFloat

    static let maxSpots = 6

    /// The layout for `count` spots (faces plus a "+N" badge) in a notch `height` tall; nil for none.
    static func make(count: Int, height h: CGFloat) -> ClusterLayout? {
        guard count > 0 else { return nil }
        let count = min(count, maxSpots)
        let columns = count <= 3 ? 1 : 2
        let rows = (count + columns - 1) / columns
        let gap = (h * 0.06).rounded()
        let faceSize: CGFloat = switch rows {
        case 1: (h * 0.5).rounded()
        case 2: (h * 0.36).rounded()
        default: ((h - 2 * gap) / 3 * 0.95).rounded(.down)
        }
        let width = columns == 1 ? (h * 0.9).rounded() : (h * 1.3).rounded()
        return ClusterLayout(columns: columns, rows: rows, faceSize: faceSize, gap: gap, width: width)
    }

    /// Offset of spot `index` from the ear's center, filling rows left to right.
    func offset(_ index: Int) -> CGSize {
        let column = index % columns, row = index / columns
        let step = faceSize + gap
        return CGSize(width: (CGFloat(column) - CGFloat(columns - 1) / 2) * step,
                      height: (CGFloat(row) - CGFloat(rows - 1) / 2) * step)
    }
}
