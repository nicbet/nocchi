import NocchiCore
import Observation
import SwiftUI

public enum NotchMode: Sendable, Equatable {
    case collapsed
    case expanded
}

/// Observable state of the notch: mode, hover, and the sizes derived from the screen geometry.
@MainActor
@Observable
public final class NotchModel {
    public var geometry: NotchGeometry
    public var mode: NotchMode = .collapsed {
        didSet { if mode != oldValue { beginMorph() } }
    }
    /// True while the shape animates between modes. Live faces are AppKit views, which SwiftUI
    /// can't clip to the notch shape or transition, so faces draw as still frames meanwhile.
    public private(set) var isMorphing = false
    @ObservationIgnored private var morphEnd: Task<Void, Never>?
    static let morphDuration: Duration = .milliseconds(550)
    public var isHovering = false
    /// Debug: stay expanded regardless of hover.
    public var isPinned = false
    /// Debug: outline the interactive area.
    public var showsHitArea = false

    public let store: AgentStore

    /// Faces stop animating while the displays sleep. (Window occlusion isn't used: for a
    /// transparent, always-on-top panel it can report "not visible" while the notch is on screen.)
    public var screensAsleep = false
    var facesPaused: Bool { screensAsleep }

    public init(geometry: NotchGeometry, store: AgentStore) {
        self.geometry = geometry
        self.store = store
    }

    private func beginMorph() {
        isMorphing = true
        morphEnd?.cancel()
        morphEnd = Task { [weak self] in
            try? await Task.sleep(for: Self.morphDuration)
            guard !Task.isCancelled else { return }
            self?.isMorphing = false
        }
    }

    // MARK: Metrics

    /// Width of each side slot next to the notch (left face, right cluster) when collapsed.
    var earWidth: CGFloat { (geometry.notchSize.height * 1.3).rounded() }

    var topRadius: CGFloat { mode == .expanded ? 14 : 6 }
    var bottomRadius: CGFloat { mode == .expanded ? 32 : 12 }

    /// Size of the body (excluding the shoulders) for a mode.
    func bodySize(for mode: NotchMode) -> CGSize {
        let notch = geometry.notchSize
        switch mode {
        case .collapsed:
            return CGSize(width: notch.width + 2 * earWidth, height: notch.height)
        case .expanded:
            return CGSize(width: max(notch.width + 2 * earWidth, 640), height: notch.height + 168)
        }
    }

    /// Full shape size for a mode, shoulders included.
    func shapeSize(for mode: NotchMode) -> CGSize {
        let body = bodySize(for: mode)
        let top: CGFloat = mode == .expanded ? 14 : 6
        return CGSize(width: body.width + 2 * top, height: body.height)
    }

    /// Screen rect that receives the mouse in the current mode.
    public var hitRect: CGRect {
        geometry.rectHanging(shapeSize(for: mode))
    }

    /// Size the panel must have so every mode (plus its shadow) fits.
    public var panelSize: CGSize {
        let expanded = shapeSize(for: .expanded)
        return CGSize(width: expanded.width + 2 * Self.shadowMargin, height: expanded.height + Self.shadowMargin)
    }

    static let shadowMargin: CGFloat = 40
}
