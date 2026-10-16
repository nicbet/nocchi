import Foundation
import NocchiMascot
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

    /// How much the notch may interrupt: open for "needs you", a banner for finished or failed.
    public var peekLevel: PeekLevel {
        didSet { defaults.set(peekLevel.rawValue, forKey: Keys.peekLevel) }
    }

    /// Show messages and a summary in the middle of the collapsed notch on screens without a
    /// hardware notch.
    public var showsStatusText: Bool {
        didSet { defaults.set(showsStatusText, forKey: Keys.showsStatusText) }
    }

    /// Play a short system sound when an agent needs you, failed or finished.
    public var playsSounds: Bool {
        didSet { defaults.set(playsSounds, forKey: Keys.playsSounds) }
    }

    /// The screen to show the notch on, by name; nil picks the one with a notch, else the main one.
    public var screenName: String? {
        didSet { defaults.set(screenName, forKey: Keys.screenName) }
    }

    /// Agent sources. Herdr: agents in Herdr panes. Claude Code: Claude sessions anywhere else
    /// (read from Claude's own session registry; no setup).
    public var usesHerdr: Bool {
        didSet { defaults.set(usesHerdr, forKey: Keys.usesHerdr) }
    }
    public var watchesClaude: Bool {
        didSet { defaults.set(watchesClaude, forKey: Keys.watchesClaude) }
    }


    /// A named Herdr session to watch instead of the default one.
    public var herdrSession: String? {
        didSet { defaults.set(herdrSession, forKey: Keys.herdrSession) }
    }

    /// An explicit Herdr socket path; wins over `herdrSession`.
    public var herdrSocketPath: String? {
        didSet { defaults.set(herdrSocketPath, forKey: Keys.herdrSocketPath) }
    }

    /// Folders new chats started in, most recent first.
    public var recentChatFolders: [String] {
        didSet { defaults.set(recentChatFolders, forKey: Keys.recentChatFolders) }
    }

    func rememberChatFolder(_ folder: URL) {
        recentChatFolders = Array(([folder.path] + recentChatFolders.filter { $0 != folder.path }).prefix(5))
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ignoresReduceMotion = defaults.bool(forKey: Keys.ignoresReduceMotion)
        // Earlier versions stored an on/off `autoPeek`.
        peekLevel = defaults.string(forKey: Keys.peekLevel).flatMap(PeekLevel.init(rawValue:))
            ?? (defaults.object(forKey: Keys.autoPeek) as? Bool == false ? .never : .everything)
        showsStatusText = defaults.object(forKey: Keys.showsStatusText) as? Bool ?? true
        playsSounds = defaults.bool(forKey: Keys.playsSounds)
        screenName = defaults.string(forKey: Keys.screenName)
        usesHerdr = defaults.object(forKey: Keys.usesHerdr) as? Bool ?? true
        watchesClaude = defaults.object(forKey: Keys.watchesClaude) as? Bool ?? true
        herdrSession = defaults.string(forKey: Keys.herdrSession)
        herdrSocketPath = defaults.string(forKey: Keys.herdrSocketPath)
        recentChatFolders = defaults.stringArray(forKey: Keys.recentChatFolders) ?? []
    }

    private enum Keys {
        static let ignoresReduceMotion = "ignoresReduceMotion"
        static let autoPeek = "autoPeek"
        static let peekLevel = "peekLevel"
        static let showsStatusText = "showsStatusText"
        static let playsSounds = "playsSounds"
        static let screenName = "screenName"
        static let usesHerdr = "usesHerdr"
        static let watchesClaude = "watchesClaude"
        static let herdrSession = "herdrSession"
        static let herdrSocketPath = "herdrSocketPath"
        static let recentChatFolders = "recentChatFolders"
    }
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
