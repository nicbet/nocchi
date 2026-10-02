import Foundation
import Testing
@testable import NocchiUI

@MainActor
@Suite struct NocchiSettingsTests {
    @Test func ignoreReduceMotionDefaultsOffAndPersists() {
        let suite = "nocchi.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = NocchiSettings(defaults: defaults)
        #expect(!settings.ignoresReduceMotion)

        settings.ignoresReduceMotion = true
        #expect(NocchiSettings(defaults: defaults).ignoresReduceMotion)
    }

    @Test func remembersRecentChatFoldersMostRecentFirst() {
        let suite = "nocchi.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = NocchiSettings(defaults: defaults)
        for name in ["a", "b", "c", "d", "e", "f", "b"] { settings.rememberChatFolder(URL(fileURLWithPath: "/p/\(name)")) }
        #expect(settings.recentChatFolders == ["/p/b", "/p/f", "/p/e", "/p/d", "/p/c"])
        #expect(NocchiSettings(defaults: defaults).recentChatFolders == ["/p/b", "/p/f", "/p/e", "/p/d", "/p/c"])
    }
}
