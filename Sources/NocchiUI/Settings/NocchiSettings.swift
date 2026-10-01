import Foundation
import Observation
import SwiftUI

/// User preferences, persisted in `UserDefaults`.
@MainActor
@Observable
public final class NocchiSettings {
    public static let shared = NocchiSettings()

    private let defaults: UserDefaults

    /// Animate fully even when the system's Reduce Motion is on. Some people turn Reduce Motion
    /// on for faster Space switching but still want lively faces.
    public var ignoresReduceMotion: Bool {
        didSet { defaults.set(ignoresReduceMotion, forKey: Keys.ignoresReduceMotion) }
    }

    /// A named Herdr session to watch instead of the default one.
    public var herdrSession: String? {
        didSet { defaults.set(herdrSession, forKey: Keys.herdrSession) }
    }

    /// An explicit Herdr socket path; wins over `herdrSession`.
    public var herdrSocketPath: String? {
        didSet { defaults.set(herdrSocketPath, forKey: Keys.herdrSocketPath) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ignoresReduceMotion = defaults.bool(forKey: Keys.ignoresReduceMotion)
        herdrSession = defaults.string(forKey: Keys.herdrSession)
        herdrSocketPath = defaults.string(forKey: Keys.herdrSocketPath)
    }

    private enum Keys {
        static let ignoresReduceMotion = "ignoresReduceMotion"
        static let herdrSession = "herdrSession"
        static let herdrSocketPath = "herdrSocketPath"
    }
}

extension EnvironmentValues {
    /// Whether nocchi reduces motion: the system setting, unless the user chose to ignore it.
    @Entry var nocchiReducesMotion: Bool = false
}

/// Resolves `nocchiReducesMotion` from the system setting and `NocchiSettings`.
private struct ReduceMotionResolver: ViewModifier {
    let settings: NocchiSettings
    @Environment(\.accessibilityReduceMotion) private var systemReducesMotion

    func body(content: Content) -> some View {
        content.environment(\.nocchiReducesMotion, systemReducesMotion && !settings.ignoresReduceMotion)
    }
}

extension View {
    func resolvesReduceMotion(_ settings: NocchiSettings = .shared) -> some View {
        modifier(ReduceMotionResolver(settings: settings))
    }
}
