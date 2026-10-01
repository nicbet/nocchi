import Foundation
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
        didSet {
            guard mode != oldValue else { return }
            notchLog.info("mode: \(String(describing: self.mode), privacy: .public)")
            beginMorph()
        }
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
    /// Short messages for the middle of the collapsed notch on screens without a hardware notch.
    public let ticker = Ticker()
    /// The launch greeting is showing.
    public var isGreeting = false
    public var drop: DropState = .none
    /// Called with the folder when one is dropped on the notch.
    @ObservationIgnored var onDropFolder: ((URL) -> Void)?

    /// Stay open regardless of hover.
    var holdsOpen: Bool { isPinned || drop != .none }

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

/// Dragging a folder onto the notch starts an agent there.
public enum DropState: Equatable, Sendable {
    case none
    /// A file drag is near the notch; `isTargeted` while it's over it.
    case offering(isTargeted: Bool)
    case starting(folder: URL, since: Date)
    case started(folder: URL)
    case failed(folder: URL, message: String)

    /// The folder to start in for a dropped item: itself if it's a folder, else its parent.
    static func folder(for url: URL) -> URL {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? url.hasDirectoryPath
        return isDirectory ? url : url.deletingLastPathComponent()
    }

    /// The bar's position while an agent starts: eases toward 90 % and waits there for Herdr.
    static func progress(after seconds: TimeInterval) -> Double {
        0.9 * (1 - exp(-max(0, seconds) / 2.5))
    }
}
