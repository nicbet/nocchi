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
}
